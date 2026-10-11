import SwiftUI
import WebKit

/// 分享出去那张小游戏卡片的 body（收端按这段 JSON 画卡片、点开直接进游戏）
/* ---------- 棋牌大厅的模型（一桌 = 4 个位） ---------- */

struct GameTableSeat: Decodable {
    var id: String?
    var name: String?
    var avatar: String?
    var mine: Bool?
}

struct GameTable: Decodable, Identifiable {
    var code: String
    var id: String { code }
    var game: String?
    var host: String?
    var started: Bool?
    var seated: Int?
    var seats: [GameTableSeat?]?

    var seatNames: [String?] { (seats ?? []).map { $0?.name } }
}

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
    /// 一段字符串的稳定指纹（djb2）：用来给游戏缓存目录命名 ——
    /// Swift 自带的 hashValue 每次启动都不一样，不能用来当目录名。
    static func stableKey(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h, radix: 16)
    }

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
    /// 右上角胶囊里的「···」菜单
    @State private var capsuleMenu = false
    /* ---- 棋牌大厅（四国军棋这类要凑桌的） ---- */
    /// 是不是"要凑桌"的游戏。
    /// ⚠ 现在**关掉**了：四国军棋用的是项目里那套 11-junqi（自带「好友联机 / 快速匹配」，
    /// 走 wss://aa.x8iu.com/junqi 的房间服务器），不用我们这层原生大厅了。
    /// 以后要新加"凑桌"游戏，把 id 写进来就能用原生大厅。
    private var isRoomGame: Bool { false }
    @State private var tables: [GameTable] = []
    @State private var myRoom: String = ""
    @State private var mySeat: Int = 0
    @State private var roomNames: [String?] = []
    @State private var roomStarted = false
    @State private var lobbyMsg = ""
    @State private var moveSeq = 0
    @State private var pollTask: Task<Void, Never>? = nil

    var body: some View {
        /* 微信小程序那样：**不占顶栏，整屏都是游戏**，只有右上角那个胶囊 */
        ZStack(alignment: .topTrailing) {
            Group {
                if isRoomGame && !roomStarted {
                    lobby
                } else if let localIndex {
                    GameWebView(index: localIndex, dir: localDir,
                                rankJs: chrisRankJs(game: game.id, token: API.shared.token, base: API.shared.base),
                                box: box,
                                onScore: { g, s in Task { await API.shared.gameScore(g, s) } },
                                onRank: { g, done in Task { done(await API.shared.gameRankJSONWithAvatars(g)) } },
                                roomJs: roomJs,
                                onMove: { mv in Task { await API.shared.gameTableMove(myRoom, mv) } })
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
            /* 右上角那颗胶囊：左边 ···（菜单）右边 ⊙（关掉）—— 微信小程序就是这一颗 */
            miniCapsule
                .padding(.top, 8)
                .padding(.trailing, 10)
        }
        .background(Color(hex: 0x0B0E17).ignoresSafeArea())
        .statusBarHidden(true)
        .task {
            if isRoomGame { await loadTables() }
            await prepare()
        }
        .confirmationDialog(game.name, isPresented: $capsuleMenu, titleVisibility: .visible) {
            Button(Tr("好友排名")) { box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()") }
            if isRoomGame && !myRoom.isEmpty {
                Button(Tr("复制桌号邀请")) {
                    UIPasteboard.general.string = Tr("四国军棋 桌号 ") + myRoom
                    lobbyMsg = Tr("桌号已复制")
                }
            }
            Button(Tr("重新进入")) { Task { await prepare(force: true) } }
            Button(Tr("关闭"), role: .destructive) { dismiss() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .onDisappear {
            pollTask?.cancel()
            if !myRoom.isEmpty { Task { await API.shared.gameTableLeave(myRoom) } }
        }
    }

    /* ============================================================
       棋牌大厅：一张张桌子摆着（用户要求"进门要做摆放一张张的桌子"）
       ============================================================ */

    /// 微信小程序右上角那颗胶囊：[ ··· | ⊙ ]
    private var miniCapsule: some View {
        HStack(spacing: 0) {
            Button { capsuleMenu = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 0.5, height: 18)
            Button { dismiss() } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 1.6).frame(width: 15, height: 15)
                    Circle().fill(Color.white).frame(width: 5.5, height: 5.5)
                }
                .frame(width: 46, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }

    private var lobby: some View {
        ZStack {
            Color(hex: 0x0B0E17).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    Text(Tr("四国军棋 · 棋牌大厅")).font(pf(17, .semibold)).foregroundColor(.white)
                    Text(myRoom.isEmpty ? Tr("点一张桌子坐下，缺的位置由电脑顶上")
                                        : (Tr("你在 ") + myRoom + Tr(" 号桌（") + "\(mySeat + 1)" + Tr(" 号位）")))
                        .font(pf(12.5)).foregroundColor(.white.opacity(0.6))

                    if !myRoom.isEmpty {
                        roomCard
                    } else {
                        Button { Task { await createTable() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text(Tr("自己开一桌"))
                            }
                            .font(pf(15, .medium)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(tables) { t in tableCard(t) }
                        }
                        if tables.isEmpty {
                            Text(Tr("还没有人开桌，你可以先开一桌等好友"))
                                .font(pf(13)).foregroundColor(.white.opacity(0.5))
                                .padding(.top, 20)
                        }
                    }
                    if !lobbyMsg.isEmpty {
                        Text(lobbyMsg).font(pf(12.5)).foregroundColor(.white.opacity(0.7))
                    }
                    Spacer().frame(height: 20)
                }
                .padding(16)
            }
        }
    }

    /// 大厅里的一张桌子：四个座位（有人显示名字 + 头像，没人显示"空"）
    private func tableCard(_ t: GameTable) -> some View {
        Button { Task { await sit(t.code) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Tr("桌 ") + t.code).font(pf(14, .semibold)).foregroundColor(.white)
                    Spacer(minLength: 0)
                    Text("\(t.seated ?? 0)/4").font(pf(11.5)).foregroundColor(.white.opacity(0.55))
                }
                let names = t.seatNames
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(i < names.count && names[i] != nil ? C.green : Color.white.opacity(0.12))
                            .frame(width: 7, height: 7)
                        Text(i < names.count ? (names[i] ?? Tr("空位")) : Tr("空位"))
                            .font(pf(12))
                            .foregroundColor(i < names.count && names[i] != nil ? .white : .white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Text((t.started == true) ? Tr("已开局") : Tr("点一下坐下"))
                    .font(pf(11.5)).foregroundColor(C.green)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1B1B1D)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var roomCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Tr("桌号 ") + myRoom).font(pf(19, .semibold)).foregroundColor(.white)
                Spacer(minLength: 0)
                /* ⚠ 这里不能弹选人页（在游戏整页里弹 sheet 会闪退，之前踩过），
                   所以改成「复制桌号」——好友进同一款游戏的大厅就能看到这张桌、坐下 ✅ */
                Button {
                    UIPasteboard.general.string = Tr("来打四国军棋，桌号 ") + myRoom + Tr("（进「游戏 → 四国军棋」大厅点这张桌坐下）")
                    lobbyMsg = Tr("桌号已复制，去聊天里发给好友就行")
                } label: {
                    Text(Tr("复制桌号邀请")).font(pf(13)).foregroundColor(C.green)
                }
                .buttonStyle(.plain)
            }
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(pf(12)).foregroundColor(.white.opacity(0.5)).frame(width: 14)
                    Text(i < roomNames.count ? (roomNames[i] ?? Tr("空位（电脑）")) : Tr("空位（电脑）"))
                        .font(pf(14))
                        .foregroundColor(i == mySeat ? C.green : .white)
                    Spacer(minLength: 0)
                    if i == mySeat { Text(Tr("我")).font(pf(11.5)).foregroundColor(C.green) }
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(i == mySeat ? 0.10 : 0.05)))
            }
            Button { startRoom() } label: {
                Text(roomStarted ? Tr("开局啦") : Tr("开始（缺的人电脑顶上）"))
                    .font(pf(15, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(C.green))
            }
            .buttonStyle(.plain)
            Button { Task { await API.shared.gameTableLeave(myRoom); myRoom = ""; roomStarted = false; await loadTables() } } label: {
                Text(Tr("离开这桌")).font(pf(13)).foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1B1B1D)))
    }

    private func loadTables() async {
        tables = await API.shared.gameTables(game.id)
    }

    private func createTable() async {
        guard let r = await API.shared.gameTableCreate(game.id) else { lobbyMsg = Tr("开桌失败，再试一次"); return }
        myRoom = r.code
        mySeat = r.seat
        await refreshRoom()
    }

    private func sit(_ code: String) async {
        guard let r = await API.shared.gameTableSit(code) else { lobbyMsg = Tr("坐不进去，换一桌试试"); return }
        myRoom = code
        mySeat = r.seat
        roomNames = r.players
        if r.started { startRoom() }
    }

    private func refreshRoom() async {
        let list = await API.shared.gameTables(game.id)
        if let t = list.first(where: { $0.code == myRoom }) {
            roomNames = t.seatNames
            if t.started == true { roomStarted = true }
        }
    }

    /// 开局：告诉服务器开始，然后真的把网页游戏加载起来（带上桌号/座位）
    private func startRoom() {
        roomStarted = true
        moveSeq = 0
        Task {
            await API.shared.gameTableStart(myRoom)
            await prepare(force: true)
        }
        /* 每 1.5 秒拉一次别人的棋 */
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                let r = await API.shared.gameTableMoves(myRoom, since: moveSeq)
                moveSeq = r.n
                if !r.list.isEmpty,
                   let data = try? JSONSerialization.data(withJSONObject: r.list),
                   let s = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        box.web?.evaluateJavaScript("window.chrisOnMoves && window.chrisOnMoves(\(s));")
                    }
                }
            }
        }
    }

    /// 注进网页的那段：桌号、我的座位、同桌的人，以及"我走了一步"怎么告诉原生
    private var roomJs: String {
        let names = roomNames.map { $0 ?? "" }
        var arr = "[]"
        if let d = try? JSONSerialization.data(withJSONObject: names.map { ["name": $0.isEmpty ? "电脑" : $0] }),
           let s = String(data: d, encoding: .utf8) { arr = s }
        return """
        window.chrisRoom = { code: "\(myRoom)", seat: \(mySeat), players: \(arr) };
        window.chrisMove = function (mv) {
          try { window.webkit.messageHandlers.chrisRoom.postMessage({ action: 'move', move: mv }); } catch (e) {}
        };
        """
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
        /* ⚠ 缓存目录要带上**地址的指纹**：以前只按 game.id 存，而且"文件已存在就不重下"，
           所以后台把同一款游戏的 url 换掉（比如四国军棋从 09 换成 11-junqi）以后，
           手机上跑的**还是老那份缓存**（用户看到的"还是你做的那个"就是这个）。
           现在 url 一变目录就变，一定重新下。 */
        let rootKey = "games/\(game.id)-\(GamesPageView.stableKey(game.url))"
        let root = caches.appendingPathComponent(rootKey, isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            /* 文件清单问服务器（每套游戏目录里那份 files.json），没有才用默认那 5 个 */
            let list = await miniAppFileList(baseDir: remoteDir)
            /* 清单变了（后台给游戏加了文件）也要重下：把清单的指纹存一份比一下 */
            let stamp = GamesPageView.stableKey(list.joined(separator: "|"))
            let stampFile = root.appendingPathComponent(".list")
            let oldStamp = (try? String(contentsOf: stampFile, encoding: .utf8)) ?? ""
            let needAll = force || oldStamp != stamp
            for f in list {
                let dst = root.appendingPathComponent(f)
                if !needAll, let sz = try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 0 { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try await API.shared.assetData(remoteDir.appendingPathComponent(f))
                try data.write(to: dst, options: .atomic)
            }
            try? stamp.write(to: stampFile, atomically: true, encoding: .utf8)
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
    /// 棋牌大厅：注入 window.chrisRoom（桌号 / 我的座位 / 同桌的人）
    var roomJs: String = ""
    /// 网页里走了一步 → 发给同桌的人
    var onMove: (([String: Any]) -> Void)? = nil

    func makeCoordinator() -> RankBridge {
        let b = RankBridge()
        return b
    }

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
        /* 棋牌大厅：把 window.chrisRoom / chrisMove 注进去，再挂一根 chrisRoom 的线 */
        if !roomJs.isEmpty {
            cfg.userContentController.addUserScript(
                WKUserScript(source: roomJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            context.coordinator.room.onMove = onMove
            cfg.userContentController.add(context.coordinator.room, name: "chrisRoom")
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
