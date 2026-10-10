import SwiftUI
import WebKit

/// 分享出去那张小游戏卡片的 body（收端按这段 JSON 画卡片、点开直接进游戏）
func miniAppSharePayload(_ g: MiniApp) -> String {
    var d: [String: Any] = ["id": g.id, "name": g.name, "kind": g.kind ?? "game", "url": g.url]
    if let v = g.desc, !v.isEmpty { d["desc"] = v }
    if let v = g.icon, !v.isEmpty { d["icon"] = v }
    if let v = g.cover, !v.isEmpty { d["cover"] = v }
    if let v = g.action, !v.isEmpty { d["action"] = v }
    guard let data = try? JSONSerialization.data(withJSONObject: d),
          let s = String(data: data, encoding: .utf8) else { return "" }
    return s
}

/* ============================================================
   游戏（发现 → 游戏）
   四款小游戏都是**网页小游戏**（服务器 /games/ 下面那几套，后台能改 data/games.json）：
      · 跳一跳 / 2048 / 飞机大战 / 贪吃蛇
   点一下就在 App **内置的浏览器**里全屏玩（左上角一颗关闭）。
   ⚠ 以前「掷骰子 / 石头剪刀布 / 抽签 / 大转盘」那 4 个原生小游戏已经删掉了（用户要求换成这 4 款）。
   ============================================================ */

struct GamesPageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var games: [MiniApp] = []
    @State private var playing: MiniApp?
    /// 分享给好友：选人页在最外层弹（在游戏页里弹会闪退，见 GameWebPage 里的说明）
    @State private var shareApp: MiniApp?
    /// 换图标（只有 ops 账号看得到那张小按钮）
    @State private var iconPickFor = ""
    @State private var showIconPick = false

    /* 用户要求：游戏页的底色**跟着系统走**——白天白的、晚上深色。
       以前写死深色，白天看着像另一个 App。 */
    private let pageBg = Color.dyn(0xEDEDED, 0x111114)
    private let cardBg = Color.dyn(0xFFFFFF, 0x1B1B1D)
    private let ink = C.label
    private let subInk = C.subLabel

    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(Tr("游戏")).font(pf(17, .semibold)).foregroundColor(ink)
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(ink)
                            .frame(width: 44, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: L.navH)
            .background(pageBg)

            ScrollView {
                /* 照微信那个「小游戏」：一节一节的小标题 + 一张张卡片
                   （封面 / 名字 / 说明 / 立即玩），后台能加、能分组 */
                ForEach(groups, id: \.0) { g in
                    HStack(spacing: 6) {
                        Text(g.0).font(pf(15.5, .semibold)).foregroundColor(ink)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(subInk)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

                    VStack(spacing: 10) {
                        ForEach(g.1) { g2 in
                            Button { playing = g2 } label: { card(g2) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if loading {
                    HStack(spacing: 10) {
                        ProgressView().tint(subInk)
                        Text(Tr("正在加载…")).font(pf(14)).foregroundColor(subInk)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                } else if list.isEmpty {
                    Text(Tr("游戏加载失败，检查一下网络"))
                        .font(pf(14)).foregroundColor(subInk)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
        }
        .background(pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .swipeBack { dismiss() }
        /* 点开一款：**内置浏览器全屏**玩（网页小游戏在服务器上） */
        .fullScreenCover(item: $playing) { g in
            GameWebPage(game: g).environmentObject(app)
        }
        /* 有管理权限：在小游戏列表里直接点一下就能换图标 */
        .sheet(isPresented: $showIconPick) {
            PhotoPicker { img in
                let id = iconPickFor
                Task {
                    if let url = try? await API.shared.upload(image: img) {
                        try? await API.shared.manageSetIcon(kind: "miniapp", id: id, cover: url)
                        games = await API.shared.miniApps(kind: "game")
                    }
                }
            }
        }
        /* 分享给好友：选一个聊天 → 发一张小游戏卡片（收端在聊天里点开直接玩） */
        .sheet(item: $shareApp) { g in
            ForwardPickerView(items: [ForwardItem(kind: "miniapp", content: miniAppSharePayload(g))]) { shareApp = nil }
                .environmentObject(app)
        }
        .task {
            /* 和「发现 → 小程序」同一个源：后台「小程序 / 小游戏」里 kind=小游戏 的那些。
               这样后台加一款游戏，App 不用出包。 */
            games = await API.shared.miniApps(kind: "game")
            loading = false
        }
    }

    private var list: [MiniApp] { games }

    /// 按分组合起来（后台没填分组的都归到「推荐小游戏」）
    private var groups: [(String, [MiniApp])] {
        var order: [String] = []
        var map: [String: [MiniApp]] = [:]
        for g in list {
            let k = g.groupText
            if map[k] == nil { map[k] = []; order.append(k) }
            map[k]?.append(g)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func card(_ g: MiniApp) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(g.iconText).font(.system(size: 30))
                if let cv = g.cover, !cv.isEmpty {
                    RemoteImage(path: cv)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(g.name).font(pf(16, .medium)).foregroundColor(ink).lineLimit(1)
                Text(g.desc ?? "").font(pf(12.5)).foregroundColor(subInk)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            /* ops 账号：卡片右下角多一颗「换图标」 */
            if app.me?.ops == true {
                Button {
                    iconPickFor = g.id
                    showIconPick = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(C.green)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            /* 分享给好友（谁都能用） */
            Button { shareApp = g } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .foregroundColor(subInk)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(g.actionText)
                .font(pf(13.5, .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x3ED37F), Color(hex: 0x12A05A)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }
}
/* ---------------------------------------------------------- 内置浏览器玩小游戏 */

/// 小游戏页面：**全屏 + 内置浏览器**（WKWebView）。
/// 左上角一颗「✕」退出，页面本身就是 canvas 全屏，不做别的栏，免得挡着玩。
struct GameWebPage: View {
    let game: MiniApp
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 下到本机的那份 index.html（见 prepare()）
    @State private var localIndex: URL?
    @State private var localDir: URL?
    @State private var loading = true
    @State private var errorText = ""
    /// 顶栏那颗 🏆（好友排名面板）要往里打 JS
    @StateObject private var box = WebBox()
    /// 「分享给好友」那个选人页
    @State private var share = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(game.name)
                    .font(pf(16.5, .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    /* 好友排名：点了在游戏上盖一层「我 + 我的好友」的榜单 */
                    Button {
                        box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()")
                    } label: {
                        Text("🏆").font(.system(size: 18))
                            .frame(width: 48, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    /* 分享给好友挪到**列表页**那颗按钮上了 ——
                       在这里弹选人页会闪退（用户反馈的「分享出去会没法选择哪个人还闪退」），
                       列表页（普通的 NavigationStack 页面）里弹就没事。 */
                }
            }
            .frame(height: L.navH)
            .background(Color(hex: 0x111318))

            if let localIndex {
                GameWebView(index: localIndex, dir: localDir,
                            rankJs: chrisRankJs(game: game.id, token: API.shared.token, base: API.shared.base),
                            box: box,
                            onScore: { g, s in Task { await API.shared.gameScore(g, s) } },
                            onRank: { g, done in Task { done(await API.shared.gameRankJSONWithAvatars(g)) } })
            } else if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(Tr("正在准备游戏…")).font(pf(13.5)).foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Text(errorText.isEmpty ? Tr("游戏打不开") : errorText)
                        .font(pf(14)).foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                    Button { Task { await prepare(force: true) } } label: {
                        Text(Tr("重试"))
                            .font(pf(15, .medium)).foregroundColor(.white)
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

    /// 一款小游戏要的那几个文件（服务器上 /games/xxx/ 下面就是这套）
    private var gameFiles: [String] {
        ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    }

    /// ⚠ 关键：**不要**让内置浏览器自己去连服务器 ——
    /// App 默认连的是 IP（https://43.242.194.89），那个证书 App 自己的网络层是放过的，
    /// 但 WKWebView 不认，页面会直接加载失败（用户看到的「游戏都打不开」就是这个）。
    /// 所以这里用 App 自己的通道把文件下到本机，再从本地文件跑；顺带离线也能玩。
    private func prepare(force: Bool = false) async {
        loading = true
        errorText = ""
        let path = game.url
        guard !path.isEmpty, let remoteIndex = API.shared.assetURL(path) else {
            loading = false
            errorText = Tr("这款游戏还没配地址（后台「游戏」里填 url）")
            return
        }
        let remoteDir = remoteIndex.deletingLastPathComponent()
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            loading = false
            return
        }
        let root = caches.appendingPathComponent("games/\(game.id)", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            /* 文件清单问服务器（每套游戏目录里那份 files.json），没有才用默认那 5 个 */
            let list = await miniAppFileList(baseDir: remoteDir)
            for f in list {
                let dst = root.appendingPathComponent(f)
                if !force, let sz = try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 0 { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try await API.shared.assetData(remoteDir.appendingPathComponent(f))
                try data.write(to: dst, options: .atomic)
            }
            localDir = root
            localIndex = root.appendingPathComponent("index.html")
        } catch {
            errorText = Tr("游戏下载失败：") + error.localizedDescription
        }
        loading = false
    }
}

/// WKWebView 包一层：禁掉滚动/回弹，全屏铺满，画布自己吃手势
struct GameWebView: UIViewRepresentable {
    let index: URL
    /// 允许读取的目录（游戏自己那几个 js 就在这里面）
    let dir: URL?
    /// 好友排名那一层（自动报分 + 🏆 面板）
    var rankJs: String = ""
    var box: WebBox? = nil
    /// 报分：由**原生**替网页发（网页是本地 file://，直连服务器会被证书/CORS 拦掉 ——
    /// 这就是以前排行榜一直不生效的原因）
    var onScore: ((String, Int) -> Void)? = nil
    /// 拉榜单：拿到 JSON 字符串后回填到网页里画
    var onRank: ((String, @escaping (String) -> Void) -> Void)? = nil

    func makeCoordinator() -> RankBridge { RankBridge() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        if !rankJs.isEmpty {
            cfg.userContentController.addUserScript(
                WKUserScript(source: rankJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            /* 网页 → 原生 的那根线：报分 / 拉榜都走它 */
            let b = context.coordinator
            b.onScore = onScore
            b.onRank = onRank
            cfg.userContentController.add(b, name: "chrisRank")
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.09, alpha: 1)
        v.scrollView.bounces = false
        v.scrollView.isScrollEnabled = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.loadFileURL(index, allowingReadAccessTo: dir ?? index.deletingLastPathComponent())
        box?.web = v
        context.coordinator.web = v
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { }
}
