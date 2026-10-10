import SwiftUI
import WebKit

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
    @State private var games: [MiniGame] = []
    @State private var playing: MiniGame?

    private let pageBg = Color.dyn(0x111111, 0x141419)
    private let cardBg = Color(hex: 0x1B1B1D)
    private let ink = Color.white
    private let subInk = Color(hex: 0x929292)

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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(list) { g in
                        Button { playing = g } label: { card(g) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)

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
            GameWebPage(game: g)
        }
        .task {
            let items = (try? await API.shared.games()) ?? []
            games = items
            loading = false
        }
    }

    private var list: [MiniGame] { games.filter { ($0.enabled ?? true) } }

    private func card(_ g: MiniGame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(g.icon ?? "🎮").font(.system(size: 34))
            Text(g.label ?? "").font(pf(15, .medium)).foregroundColor(ink)
            Text(g.desc ?? "").font(pf(12.5)).foregroundColor(subInk).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }
}
/* ---------------------------------------------------------- 内置浏览器玩小游戏 */

/// 小游戏页面：**全屏 + 内置浏览器**（WKWebView）。
/// 左上角一颗「✕」退出，页面本身就是 canvas 全屏，不做别的栏，免得挡着玩。
struct GameWebPage: View {
    let game: MiniGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(game.label ?? Tr("游戏"))
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
                }
            }
            .frame(height: L.navH)
            .background(Color(hex: 0x111318))

            GameWebView(url: gameURL)
        }
        .background(Color(hex: 0x0B0E17).ignoresSafeArea())
        .statusBarHidden(true)
    }

    /// 服务器上的那套网页小游戏（后台 data/games.json 里配的 url）
    private var gameURL: URL? {
        let path = (game.url ?? "").trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return API.shared.assetURL(path)
    }
}

/// WKWebView 包一层：禁掉滚动/回弹，全屏铺满，画布自己吃手势
struct GameWebView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.09, alpha: 1)
        v.scrollView.bounces = false
        v.scrollView.isScrollEnabled = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        if let url { v.load(URLRequest(url: url)) }
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { }
}
