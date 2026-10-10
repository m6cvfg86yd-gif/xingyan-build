import SwiftUI
import WebKit
import UIKit

/* ============================================================
   小程序 / 小游戏运行时（发现 → 小程序）

   · 小程序由**后台加**（后台「小程序 / 小游戏」页：名字 / 图标 / 说明 / 类型 / 入口地址）
     —— 加新的、改名字图标都不用重新出包。
   · App 这一页就是个**运行时**：内置浏览器（WKWebView）+ 一层 `wx.*` JS 桥
     （setNavigationBarTitle / showToast / showModal / 存储 / request / 震动 / 分享 / 退出…），
     所以按小程序 API 写的页面直接能跑。
   · 文件先下到本机再跑（App 默认连的是 IP，证书 App 自己放过、WKWebView 不认，
     直连必然加载失败；下到本地顺带离线也能用）。
   ⚠ 小游戏（kind = game）**不注入** wx 桥 —— 它们自己那份 adapter.js 在浏览器模式下走 canvas。
   ============================================================ */

struct MiniApp: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var desc: String?
    var icon: String?
    var kind: String?
    var url: String
    var color: String?
    /// 封面图（后台填，可空 —— 空就用图标那块渐变）
    var cover: String?
    /// 分组名（微信那边是「发现新游 / 动作对抗游戏」这种小标题）
    var group: String?
    /// 卡片上那颗按钮的文字（立即玩 / 预约 …）
    var action: String?

    var isGame: Bool { (kind ?? "") == "game" }
    var iconText: String { (icon?.isEmpty == false) ? icon! : (isGame ? "🕹️" : "🧩") }
    var actionText: String { (action?.isEmpty == false) ? action! : "立即玩" }
    var groupText: String { (group?.isEmpty == false) ? group! : "推荐小游戏" }
}

/* ---------------------------------------------------------- 列表页（发现 → 小程序） */

struct MiniAppsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MiniApp] = []
    @State private var loading = true
    @State private var run: MiniApp?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("小程序"), back: { dismiss() })

            ScrollView {
                if loading {
                    HStack(spacing: 10) { ProgressView(); Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel) }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else if items.isEmpty {
                    Text(Tr("后台还没加小程序（后台「小程序 / 小游戏」里加一个）"))
                        .font(pf(14)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(items) { it in
                            Button { run = it } label: { tile(it) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    Spacer().frame(height: 24)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            items = await API.shared.miniApps()
            loading = false
        }
        .fullScreenCover(item: $run) { it in
            MiniAppRuntimeView(app: it)
                .environmentObject(app)
        }
    }

    private func tile(_ it: MiniApp) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x1B1F27)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(it.iconText).font(.system(size: 30))
            }
            .frame(width: 62, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))

            Text(it.name)
                .font(pf(13))
                .foregroundColor(C.label)
                .lineLimit(1)
        }
    }
}

/* ---------------------------------------------------------- 运行时页 */

struct MiniAppRuntimeView: View {
    let app: MiniApp
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var localIndex: URL?
    @State private var localDir: URL?
    @State private var loading = true
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 0) {
            /* 顶栏：✕ / 标题（wx.setNavigationBarTitle 会改它）/ ⋯（刷新） */
            ZStack {
                Text(title.isEmpty ? app.name : title)
                    .font(pf(16.5, .semibold)).foregroundColor(.white).lineLimit(1)
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white).frame(width: 48, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button { Task { await prepare(force: true) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white).frame(width: 48, height: L.navH)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: L.navH)
            .background(Color(hex: 0x111318))

            if let localIndex {
                MiniAppWebView(index: localIndex, dir: localDir,
                               injectBridge: !app.isGame,
                               onMessage: handle)
            } else if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(Tr("正在准备…")).font(pf(13.5)).foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Text(errorText.isEmpty ? Tr("打不开") : errorText)
                        .font(pf(14)).foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                    Button { Task { await prepare(force: true) } } label: {
                        Text(Tr("重试")).font(pf(15, .medium)).foregroundColor(.white)
                            .padding(.horizontal, 22).frame(height: 40)
                            .background(Capsule().fill(C.green))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(hex: 0x0B0E17).ignoresSafeArea())
        .statusBarHidden(true)
        .task { await prepare() }
    }

    /// 小程序/小游戏那一套文件（约定：入口同目录下的 index.html + js/*.js）
    private var files: [String] {
        ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    }

    private func prepare(force: Bool = false) async {
        loading = true
        errorText = ""
        guard let remote = API.shared.assetURL(app.url) else {
            loading = false
            errorText = Tr("这个入口地址不对（后台「小程序」里看看）")
            return
        }
        let remoteDir = remote.deletingLastPathComponent()
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            loading = false
            return
        }
        let root = caches.appendingPathComponent("miniapps/\(app.id)", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for f in files {
                let dst = root.appendingPathComponent(f)
                if !force, let sz = try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 0 { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try await API.shared.assetData(remoteDir.appendingPathComponent(f))
                try data.write(to: dst, options: .atomic)
            }
            localDir = root
            localIndex = root.appendingPathComponent("index.html")
        } catch {
            errorText = Tr("下载失败：") + error.localizedDescription
        }
        loading = false
    }

    /// JS 桥回传的消息（wx.showToast / wx.setNavigationBarTitle / wx.vibrateShort / wx.exitMiniProgram…）
    private func handle(_ dict: [String: Any]) {
        let fn = (dict["fn"] as? String) ?? ""
        switch fn {
        case "title":
            title = (dict["title"] as? String) ?? ""
        case "toast":
            appState.show((dict["title"] as? String) ?? "")
        case "vibrate":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "share":
            appState.show(Tr("已分享"))
        case "exit":
            dismiss()
        default:
            break
        }
    }
}

/// 内置浏览器 + （小程序才注入的）wx.* JS 桥
struct MiniAppWebView: UIViewRepresentable {
    let index: URL
    let dir: URL?
    let injectBridge: Bool
    let onMessage: ([String: Any]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        if injectBridge {
            cfg.userContentController.add(context.coordinator, name: "wx")
            let js = miniAppWxBridge(token: API.shared.token, base: API.shared.base)
            cfg.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.09, alpha: 1)
        v.scrollView.bounces = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.loadFileURL(index, allowingReadAccessTo: dir ?? index.deletingLastPathComponent())
        context.coordinator.web = v
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { }

    func makeCoordinator() -> Coord { Coord(onMessage: onMessage) }

    final class Coord: NSObject, WKScriptMessageHandler {
        let onMessage: ([String: Any]) -> Void
        weak var web: WKWebView?
        init(onMessage: @escaping ([String: Any]) -> Void) { self.onMessage = onMessage }
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if let d = message.body as? [String: Any] { onMessage(d) }
            else if let s = message.body as? String { onMessage(["fn": s]) }
        }
    }
}

/* ---------------------------------------------------------- wx.* 桥（注入到小程序页面里） */

/// 一层很薄的 wx 兼容层：够大多数「小程序」页面直接跑。
/// 原生那边只接 4 件事（改标题 / toast / 震动 / 退出 / 分享），其余都在 JS 里自己搞定。
func miniAppWxBridge(token: String, base: String) -> String {
    let t = token.replacingOccurrences(of: "\"", with: "\\\"")
    let b = base.replacingOccurrences(of: "\"", with: "\\\"")
    return """
    (function () {
      if (window.wx && window.wx.__chris) return;
      var TOKEN = "\(t)", BASE = "\(b)";
      function post(o) { try { window.webkit.messageHandlers.wx.postMessage(o); } catch (e) { } }
      function abs(u) { return /^https?:/i.test(u) ? u : (BASE + (u.charAt(0) === '/' ? u : '/' + u)); }
      var api = {
        __chris: true,
        setNavigationBarTitle: function (o) { post({ fn: 'title', title: (o && o.title) || '' }); },
        setNavigationBarColor: function () { },
        showToast: function (o) { post({ fn: 'toast', title: (o && o.title) || '' }); },
        hideToast: function () { },
        showLoading: function (o) { post({ fn: 'toast', title: (o && o.title) || '加载中' }); },
        hideLoading: function () { },
        showModal: function (o) {
          o = o || {};
          var ok = window.confirm(((o.title || '') + '\\n' + (o.content || '')).trim());
          if (ok && o.success) o.success({ confirm: true, cancel: false });
          else if (!ok && o.fail) o.fail({ confirm: false, cancel: true });
        },
        vibrateShort: function () { post({ fn: 'vibrate' }); },
        vibrateLong: function () { post({ fn: 'vibrate' }); },
        setStorageSync: function (k, v) { try { localStorage.setItem('wx_' + k, JSON.stringify(v)); } catch (e) { } },
        getStorageSync: function (k) { try { var s = localStorage.getItem('wx_' + k); return s == null ? '' : JSON.parse(s); } catch (e) { return ''; } },
        removeStorageSync: function (k) { try { localStorage.removeItem('wx_' + k); } catch (e) { } },
        clearStorageSync: function () { try { Object.keys(localStorage).forEach(function (k) { if (k.indexOf('wx_') === 0) localStorage.removeItem(k); }); } catch (e) { } },
        request: function (o) {
          o = o || {};
          var h = {}; var hh = o.header || {};
          for (var k in hh) h[k] = hh[k];
          if (TOKEN) h['Authorization'] = 'Bearer ' + TOKEN;
          if (o.data && (o.method || 'GET').toUpperCase() !== 'GET') h['Content-Type'] = 'application/json';
          fetch(abs(o.url), { method: o.method || 'GET', headers: h,
            body: (o.data && (o.method || 'GET').toUpperCase() !== 'GET') ? JSON.stringify(o.data) : undefined })
            .then(function (r) { return r.json(); })
            .then(function (j) { if (o.success) o.success({ statusCode: 200, data: j }); })
            .catch(function (e) { if (o.fail) o.fail({ errMsg: String(e) }); });
        },
        getSystemInfoSync: function () {
          return { platform: 'ios', brand: 'Apple', model: 'iPhone', system: 'iOS',
                   windowWidth: window.innerWidth, windowHeight: window.innerHeight,
                   pixelRatio: window.devicePixelRatio || 2, statusBarHeight: 0,
                   screenWidth: window.innerWidth, screenHeight: window.innerHeight,
                   safeArea: { top: 0, bottom: 0, left: 0, right: 0 } };
        },
        getLaunchOptionsSync: function () { return { scene: 1001, query: {}, path: '' }; },
        showShareMenu: function () { }, hideShareMenu: function () { },
        onShareAppMessage: function () { }, onShow: function () { }, onHide: function () { },
        onError: function () { }, onUnhandledRejection: function () { },
        shareAppMessage: function () { post({ fn: 'share' }); },
        exitMiniProgram: function () { post({ fn: 'exit' }); },
        navigateBack: function () { post({ fn: 'exit' }); },
        navigateTo: function () { post({ fn: 'exit' }); }
      };
      window.wx = api;
    })();
    """
}
