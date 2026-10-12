import SwiftUI

struct MeView: View {
    @ObservedObject private var lang = LangStore.shared
    @State private var showMyQR = false
    @EnvironmentObject var app: AppState
    @State private var path = NavigationPath()
    /// 后台配的我页下面那几行（加一行、删一行，切回本页就变）
    @State private var items: [DiscoverItem] = []
    @State private var loaded = false
    @ObservedObject private var realtime = Realtime.shared
    /// 等级（QQ 那套）：涨了以后我页上的图标跟着刷新
    @ObservedObject private var growth = GrowthStore.shared
    /// 会员状态（我页那条金色小卡片要用：是不是会员、还剩几天）
    @ObservedObject private var member = MemberStore.shared
    /// 顶部那块玻璃要跟着白天/黑夜走（浅色 = 白磨砂、深色 = 黑磨砂）
    @Environment(\.colorScheme) private var scheme
    /// 未成年人模式开着的时候，「我」页名字旁边挂一把**小雨伞**（微信就是这样）
    @State private var teenOn = false
    @State private var showTeenCard = false
    /// 「状态 / 朋友的状态」现在是从下往上拉的底部面板（不再整页 push）
    @State private var statusPanel: StatusPanelKind? = nil

    /// 有会员档位就是会员（服务端只给会员下发这个字段）
    private var memberActive: Bool { (app.me?.memberTier ?? "").isEmpty == false }
    private var gold: Color { Color(hexString: (app.me?.memberColor?.isEmpty == false) ? app.me!.memberColor! : "#E0B44A") }
    private var gold2: Color { Color(hexString: (app.me?.memberColor2?.isEmpty == false) ? app.me!.memberColor2! : "#B8862A") }

    private var friendCount: Int { app.contacts.count }

    /// 活跃天（整数就不带小数点）
    private var daysText: String {
        let v = growth.totalDays
        let r = (v * 10).rounded() / 10
        return abs(r - r.rounded()) < 0.001 ? String(Int(r)) : String(format: "%.1f", r)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    profileTop
                    meGap

                    // 下面这些行全部来自后台配置（/api/me-page）
                    ForEach(grouped.indices, id: \.self) { gi in
                        /* 用户要求：我页的卡片底色**和会话页每行一致**（暗色 #141419）。
                           后台 ui.json 写 meGlass = 0 就是实色卡（吃 cardBg）；
                           留默认 1 还是原来那张透出封面的玻璃卡。 */
                        /* 对齐微信：卡片一律实色（原来那个透出封面的玻璃卡去掉了） */
                        GroupCard(bg: C.meCardBg) {
                            ForEach(grouped[gi].indices, id: \.self) { ri in
                                let item = grouped[gi][ri]
                                if ri > 0 { rowLine }
                                MenuRow(icon: (item.svg?.isEmpty == false) ? item.svg! : I.star,
                                        iconColor: Color(hexString: item.color ?? "#4A90D9", fallback: 0x4A90D9),
                title: Tr(item.label),
                                        onTap: { open(item) },
                                        clearBg: true,
                                        /* 彩色圆角方块 + 白色图标（和鸿蒙端一套）
                                           参数顺序要跟 MenuRow 声明一致：onTap → clearBg → iconTile */
                                        iconTile: true,
                                        /* 方块里用**苹果自带 SF Symbols**（不再用后台手画 SVG） */
                                        sf: RowIcon.sf(action: item.action, label: item.label))
                            }
                            if UIConfig.num("showPromo", 0) > 0 && gi == grouped.count - 1 {
                                rowLine
                                promoRow
                            }
                        }
                        meGap
                    }

                    Spacer().frame(height: 24)
                }
            }
            .background(C.pageBg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            /* 「我」页右上角那个二维码图标点开就是这一页（以前这个弹层只挂在设置页，
               所以在「我」页点二维码只把标志位置成了 true、什么都不会弹出来） */
            .sheet(isPresented: $showMyQR) { MyQRView() }
            /* 「状态」和「朋友的状态」照微信做成**底部面板**：从下往上拉，
               能停在半屏（拉下来就停住），上面露出「我」这一页。 */
            .sheet(item: $statusPanel) { k in
                Group {
                    if k == .friends {
                        /* 朋友的状态：打开停在半屏；再往下拉能停在 1/3 那档（上面露出「我」页），
                           再往下才关掉 —— 微信就是"拉下来会停住" */
                        FriendsStatusView().bottomPanel([.height(320), .medium, .large], open: .medium)
                    } else if (app.me?.moodIcon ?? "").isEmpty && (app.me?.moodText ?? "").isEmpty {
                        StatusView().bottomPanel([.height(340), .height(600), .large], open: .height(600))
                    } else {
                        StatusDetailView().bottomPanel([.height(340), .height(600), .large], open: .height(600))
                    }
                }
                .environmentObject(app)
            }
            /* 点「我」页名字旁边那把小雨伞：进未成年人模式那一页 */
            .sheet(isPresented: $showTeenCard) {
                TeenModeView().environmentObject(app)
            }
            .navigationDestination(for: String.self) { key in
                if key == "settings" {
                    SettingsView()
                } else if key == "moments" {
                    /* 微信的逻辑：从「我」这一页进朋友圈 = 只看我自己的动态（封面也是我的） */
                    MomentsView(mineOnly: true)
                } else if key == "profile" {
                    ProfileEditView()
                } else if key == "member" {
                    MemberCenterView()
                } else if key == "service" {
                    ServiceView()
                } else if key == "favorites" {
                    FavoritesView()
                } else if key == "stickers" {
                    StickerView()
                } else if key == "works" {
                    WorksView()
                } else if key == "channels" {
                    /* 「我 → 视频号」= 发现页那个「精彩视频」（同一个页面） */
                    ChannelsView()
                } else if key == "status" {
                    /* 微信：还没有状态 → 进选择页；已经有状态 → 先进「我的状态」（看谁看过、还剩多久） */
                    if (app.me?.moodIcon ?? "").isEmpty && (app.me?.moodText ?? "").isEmpty {
                        StatusView()
                    } else {
                        StatusDetailView()
                    }
                } else if key == "friendsStatus" {
                    /* 状态旁边那颗：所有好友现在挂的状态（微信那一栏） */
                    FriendsStatusView()
                } else if key == "manage" {
                    /* App 内的管理（只有 ops 账号看得到这个入口）：
                       上新音乐 / 换音乐图标 / 换游戏图标 */
                    UserManageView()
                } else if key == "paypwd" {
                    PayPasswordView()
                } else if key == "gesture" {
                    GestureSetupView()
                } else if key == "voicelock" {
                    VoiceLockSetupView()
                } else if key == "level" {
                    MyLevelView()
                } else if key == "score" {
                    SecurityScoreView()
                } else if key == "switch" {
                    SwitchAccountView()
                } else if key == "realname" {
                    RealNameView()
                } else if key == "account" {
                    AccountSecurityView()
                } else if key == "pair" {
                    PairApproveView()
                } else if key == "devices" {
                    /* 账号与安全 → 登录设备管理（真设备列表） */
                    LoginDevicesView()
                } else if key == "devices.faq" {
                    DevicesFaqView()
                } else if key == "teen" {
                    TeenModeView()
                } else if key == "care" {
                    CareModeView()
                } else if key == "notify" {
                    NotifyView()
                } else if key == "privacy" {
                    PrivacyView()
                } else if key == "general" {
                    GeneralView()
                } else if key == "storage" {
                    StorageSpaceView()
                } else if key == "feedback" {
                    FeedbackView()
                } else if key == "about" {
                    AboutView()
                } else if key == "cards" {
                    /* 我 → 卡包（照微信：优惠券 / 会员卡 / 礼品卡 / 票） */
                    CardsView()
                } else if key == "shop" {
                    /* 我 → 小店与卡包（后台 me-page.json 里那一行 action = shop）
                       ⚠ 2026-10-12 用户要求：点这行**直接进商城**（拼多多风格那个 H5），
                       不再先落在我们自己那个「零钱余额 + 商品列表」的中间页
                       （原生小店页还在，ShopView.swift 没删，只是入口不再走它）。 */
                    MallWebPage()
                } else if key == "eyes" {
                    /* 设置 → 通用 → 更多 → 显示小星（三档开关：开 / 静态 / 关） */
                    EyesSettingsView()
                } else if key == "health" {
                    /* 设置 → 更多 → 故障修复（微信那套检查 + 修复） */
                    HealthCheckView()
                } else if key == "selfperm" {
                    /* 设置 → 账号 → 个人信息与权限 */
                    SelfPermView()
                } else if key == "more" {
                    /* 设置 → 通用 → 更多（未成年人模式 / 关怀模式 / 等级 / 安全分 / 登录设备） */
                    MoreSettingsView()
                } else if key == "setchat" {
                    /* 设置 → 功能 → 聊天 */
                    ChatSettingsView()
                } else if key == "setcall" {
                    /* 设置 → 功能 → 音视频通话 */
                    CallSettingsView()
                } else if key == "chatbg" {
                    ChatBackgroundSheet()
                } else if key == "changepwd" {
                    ChangePasswordSheet()
                } else if key == "g.theme" {
                    AppearanceView()
                } else if key == "g.lang" {
                    LanguageView()
                } else if key == "g.chatbg" {
                    ChatBackgroundSheet()
                } else if key == "g.storage" {
                    StorageView()
                } else if key == "g.history" {
                    ChatHistoryView()
                } else if key == "g.voice" {
                    VoiceChangerView()
                } else if key == "storage.manage" {
                    ChatStorageManageView()
                } else if key == "feedback.history" {
                    FeedbackHistoryView()
                } else {
                    ComingSoonView(title: String(key.dropFirst(5)))
                }
            }
        }
        // 自己的资料变了（头像 / 昵称 / 封面 / 状态）→ 我页立刻变
        .onChange(of: realtime.event) { ev in
            if ev.user != nil || ev.type == "profile" {
                Task { app.me = try? await API.shared.me() }
            }
            if ev.type == "ui" { Task { await loadItems() } }
        }
        .task {
            if !loaded { await loadItems() }
            await MemberStore.shared.refresh()      // 会员状态（那条小金卡要用）
            /* 「我」页那把小雨伞：未成年人模式开着才显示 */
            if let t = try? await API.shared.teen() { teenOn = t.enabled == true }
        }
    }

    /// 按 group 分组：同一组排一张卡（和网页版一致）
    private var grouped: [[DiscoverItem]] {
        var out: [[DiscoverItem]] = []
        var last: Int? = nil
        for it in items {
            let g = it.group ?? 1
            if last == nil || g != last! { out.append([]); last = g }
            out[out.count - 1].append(it)
        }
        return out
    }

    private func loadItems() async {
        if let list = try? await API.shared.mePage(), !list.isEmpty {
            items = list
            loaded = true
        } else if items.isEmpty {
            items = DiscoverItem.builtinMe       // 拉不到就用内置那套，别空着
        }
    }

    private func open(_ item: DiscoverItem) {
        switch item.action ?? "soon" {
        case "cards": path.append("cards")          // 我 → 卡包（2026-10-12 加的）
        case "shop": path.append("shop")            // 我 → 小店与卡包（2026-10-12 加的）
        case "service": path.append("service")
        case "favorites": path.append("favorites")
        case "moments": path.append("moments")
        case "works": path.append("works")
        case "stickers": path.append("stickers")
        case "settings": path.append("settings")
        /* 照微信补的那几行：视频号点开就是「精彩视频」那一页（和发现页共用）；
           小店与卡包 / 插件 我们还没有对应的页面，先走「敬请期待」。 */
        case "channels": path.append("channels")
        default: path.append("soon:" + item.label)
        }
    }

    private var gap: some View {
        Rectangle().fill(C.pageBg).frame(height: L.groupGap)
    }

    /// 组与组之间的缝：「我」页现在是**玻璃卡片**风格，卡片自己内缩 12pt + 圆角，
    /// 而 GroupGap 画的是两条**通顶全宽**的细线（老的平铺列表留下的一对）——
    /// 从卡片边上多伸出去一截，看着就是"多出来的线"。这里只留一条灰缝。
    private var meGap: some View {
        Rectangle().fill(C.pageBg).frame(height: L.groupGap)
    }

    private var rowLine: some View {
        HairLine(inset: L.menuLineInset)
    }

    /* 成长系统（等级 / 活跃天）显示开关：后台 ui.json 写 growthShow = 0 就**整块不显示**
       （名字后面那枚等级徽章、资料卡里的「等级 / 活跃天」两格、设置搜索里的「我的等级」全藏起来）。
       服务端 growth.json 的 enabled=false 只是停记账，不控制显示，所以这里单独给一个键。 */
    private var growthShow: Bool { UIConfig.num("growthShow", 1) > 0 }

    /* ---------------------------------------------------------- 顶部资料卡 */

    /* 有状态色的时候，顶部整条（含系统状态栏那一条）都铺状态色 —— 和微信一样。
       文字自动黑/白：状态色偏暗就用白字，偏亮就用黑字，保证怎么选都看得清。 */
    private var moodOn: Bool {
        !((app.me?.moodText ?? "").isEmpty && (app.me?.moodIcon ?? "").isEmpty)
            && !MoodColor.clean(app.me?.moodColor).isEmpty
    }
    private var moodC1: String { MoodColor.clean(app.me?.moodColor) }
    private var moodC2: String {
        let c2 = MoodColor.clean(app.me?.moodColor2)
        if !c2.isEmpty { return c2 }
        let s = MoodColor.shift(moodC1, to: true)
        return s.isEmpty ? moodC1 : s
    }
    /// 顶部主文字颜色：没设状态时上面是深蓝封面 → 白色；设了状态 → 跟着状态色走
    private var topInk: Color {
        if moodOn { return MoodColor.isDark(moodC1) ? .white : C.label }
        return .white
    }
    /// 顶部副文字颜色：比主文字淡一档
    private var topInk2: Color {
        if moodOn { return MoodColor.isDark(moodC1) ? Color.white.opacity(0.82) : C.label.opacity(0.55) }
        /* 深蓝封面上：白色淡一档 */
        return Color.white.opacity(0.82)
    }

    /// 顶部整条背景：有状态色 → 斜向渐变 + 顶部一层薄薄的压暗（状态栏图标才看得清）
    @ViewBuilder private var profileTopBg: some View {
        if moodOn {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hexString: moodC1, fallback: 0xD8F2E4),
                                        Color(hexString: moodC2, fallback: 0x1DC9BD)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                /* 顶部薄压暗：状态栏那一条的图标/时间保证看得清（微信的状态色也这么做） */
                LinearGradient(colors: [Color.black.opacity(0.10), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: L.safeTop + 44)
            }
            .ignoresSafeArea(edges: .top)
        } else {
            /* 没设状态的时候：一张**深蓝渐变封面**（就是我页 C 方案的底）——
               头像、零钱那几张玻璃卡片浮在它上面，玻璃才有东西可以透。
               右上角补一道柔光，免得整块太平。 */
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x0E2A47),
                                        Color(hex: 0x1E5F8C),
                                        Color(hex: 0x7FB2D9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.white.opacity(0.30), Color.clear],
                               center: UnitPoint(x: 0.84, y: 0.10),
                               startRadius: 4, endRadius: 200)
                /* 顶部薄压暗：状态栏那一条的图标/时间保证看得清 */
                LinearGradient(colors: [Color.black.opacity(0.14), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: L.safeTop + 44)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    /* ---------------------------------------------------------- 方案 3：矮封面 + 资料卡
       以前头像下面竖着摞了三枚胶囊（会员 / 等级 / 状态），各占一行，顶上看着像一排按钮。
       现在：封面只占顶上一条，头像压在资料卡上沿，名字、星言号、朋友/等级/活跃天、
       会员 + 状态 全部收进**同一张玻璃卡**里 —— 层次从 4 层变成 2 层。 */

    /* 2026-10-12 用户要求「对齐微信做」：
       微信的「我」页**平时顶上什么封面都没有**，只有设了状态时顶上那一块才铺状态色。
       所以封面高度改成：有状态 = 盖住「状态栏 + 资料行」那一整块；没状态 = 0（完全不占位）。 */
    /// 顶部染色块的高度（含系统状态栏）。资料行 96 高，所以整块 = safeTop + 96 + 10（那 10 是下面那道灰缝）
    private var coverH: CGFloat { moodOn ? L.safeTop + 106 : 0 }
    /// 资料行顶部离屏幕顶的距离：就是状态栏那一条（没状态时也留，不然内容会顶到刘海）
    private var cardTopY: CGFloat { L.safeTop + 10 }
    /// 资料行里的头像。微信量出来是 68（方角 6）。
    private var topAvatar: CGFloat { 68 }

    /// 顶部那一块：**只有设了状态才画**（铺状态自己的渐变色，和微信一样）。
    /// 没设状态就是空的 —— 微信「我」页平时顶上什么都没有。
    @ViewBuilder private var meCover: some View {
        if moodOn {
            /* 用户要求：「状态点了顶部卡片要发生相应的颜色变化」——
               设了状态就把顶上那一整块（状态栏 + 资料行 + 下沿那道缝）铺成这个状态的颜色。
               没设状态什么都不画：微信平时就是干净的页面底。 */
            profileTopBg
                .frame(maxWidth: .infinity)
        }
    }

    private var profileTop: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: cardTopY)
            /* ⚠ 微信顶上这一块是**通顶**的：左右不留边、没有圆角，就是一整条。
               我上一版做成了内缩 12pt 的圆角卡，用户说「微信不是这样的」，这里去掉内缩。 */
            meProfileCard
            Color.clear.frame(height: 12)
        }
        .background(alignment: .top) {
            meCover.frame(height: coverH)
        }
    }

    /// 「我」页顶部那条资料行（对齐微信：一行里放下头像 / 名字 / 星言号 / 二维码 / 箭头）
    private var meProfileCard: some View {
        /* 对齐微信：资料区就是**一行** ——
           头像（64、方角 6）在左；右边是名字 20 + 会员/等级小徽章 + 星言号；
           设了状态时再多一行「状态 emoji + 文案」；最右边是二维码图标和箭头。
           原来那套「头像压在卡片上沿 + 三条统计 + 两枚胶囊」是自定义设计，微信没有，收掉了。 */
        HStack(spacing: 14) {
            Button { path.append("profile") } label: {
                HStack(spacing: 14) {
                    Avatar(path: app.me?.avatarPath ?? "", size: topAvatar,
                           radius: 6, level: growth.shownLevel)
                        .frame(width: topAvatar, height: topAvatar)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            /* 未成年人模式开着：名字前面挂一把小雨伞（点一下进那一页，微信就是这样） */
                            if teenOn {
                                Button { showTeenCard = true } label: {
                                    UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 15)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(app.me?.name ?? "")
                                .font(pf(22, .semibold))
                                .foregroundColor(C.label)
                                .lineLimit(1)
                            if growthShow {
                                QQLevelBadge(level: growth.shownLevel, size: 14, maxIcons: 3)
                                    .fixedSize()
                            }
                            /* 会员徽章本身可点 → 进会员中心（原来那枚「开通会员」胶囊也是这个去处，
                               收行的时候一起没了，这里挂回到名字右边这颗小徽章上） */
                            Button { path.append("member") } label: {
                                MemberBadge(tier: app.me?.memberTier,
                                            short: app.me?.memberShort,
                                            color: app.me?.memberColor,
                                            color2: app.me?.memberColor2,
                                            height: 13)
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                        }
                        Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                            .font(pf(14))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                        /* 状态 + 朋友的状态（微信就是名字下面这一行）。
                           ⚠ 我上一版把这两个入口整个收掉了，用户反馈「状态和朋友状态都弄没了」——
                          这里补回来：**设了状态**显示「🌙 睡觉中」，**没设**显示「+ 状态」，两种都能点，
                          点了进状态页（和微信一样）；右边一颗浅灰「朋友的状态 ›」。 */
                        HStack(spacing: 12) {
                            Button {
                                path.append("status")
                            } label: {
                                HStack(spacing: 4) {
                                    if moodOn {
                                        Text((app.me?.moodIcon ?? "") + " " + (app.me?.moodText ?? ""))
                                            .lineLimit(1)
                                    } else {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 12))
                                        Text(Tr("状态"))
                                    }
                                }
                                .font(pf(13))
                                .foregroundColor(C.subLabel)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                path.append("friendsStatus")
                            } label: {
                                HStack(spacing: 2) {
                                    Text(Tr("朋友的状态"))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .font(pf(13))
                                .foregroundColor(C.subLabel)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            /* 二维码：整行最右边（点开「我的二维码」） */
            Button { showMyQR = true } label: {
                SVGIcon(markup: I.qr, size: 20, color: C.label)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Chevron(size: 10, line: 1.8)
        }
        .padding(.horizontal, 16)
        .frame(height: 124)
        .frame(maxWidth: .infinity)
        /* 通顶实色条：微信这里**没有圆角、没有左右留边**，就是页面宽度的一条。
           （下面那些分组卡才是内缩 12 的圆角卡，两者别混。） */
        .background(C.meCardBg)
    }

    /// 资料卡里的一格数据（大数字 + 小标题）
    @ViewBuilder
    private func statCell(_ value: String, _ label: String, tap: Bool) -> some View {
        let body = VStack(spacing: 2) {
            Text(value)
                .font(pf(16, .semibold))
                .foregroundColor(C.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(pf(11))
                .foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        if tap {
            Button { path.append("level") } label: { body }.buttonStyle(.plain)
        } else {
            body
        }
    }

    private var statLine: some View {
        Rectangle().fill(C.hairline).frame(width: 0.5, height: 26)
    }

    /// 会员入口：一枚金色胶囊（未开通 = 浅金「开通会员」；已开通 = 实金 + 剩余天数）
    private var memberPill: some View {
        Button { path.append("member") } label: {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(memberActive ? .white : Color(hex: 0x8A5B12))
                Text(memberActive
                     ? ((app.me?.memberShort ?? "VIP") + Tr(" · 剩余 ") + "\(MemberStore.shared.me?.daysLeft ?? 0)" + Tr(" 天"))
                     : Tr("开通会员"))
                    .font(pf(11.5, .medium))
                    .foregroundColor(memberActive ? .white : Color(hex: 0x8A5B12))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Capsule().fill(LinearGradient(
                    colors: memberActive ? [gold, gold2]
                                         : [Color(hex: 0xFCE9BC), Color(hex: 0xF0C978)],
                    startPoint: .leading, endPoint: .trailing))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    /// 我页那行等级：图标 + Lv.x + 活跃 N 天（点进我的等级）
    private var levelRow: some View {
        Button { path.append("level") } label: {
            HStack(spacing: 6) {
                QQLevelBadge(level: growth.level, size: L.v(15, 4.2, 17), maxIcons: 3)
                    .fixedSize()
                Text("Lv." + String(growth.shownLevel))
                    .font(pf(L.v(13.5, 3.6, 14.5), .semibold))
                    .foregroundColor(C.label)
                Text(Tr("活跃 ") + daysText + Tr(" 天"))
                    .font(pf(L.v(12.5, 3.4, 13.5)))
                    .foregroundColor(C.subLabel)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(C.arrow)
            }
            .padding(.horizontal, L.v(10, 3.2, 13))
            .frame(height: L.v(26, 7.5, 30))
            .background { CardGlassBox(radius: 999) }
            .overlay(Capsule().stroke(C.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// 状态**旁边**那颗：点进去是**所有好友现在的状态**（微信那一栏）
    private var friendsStatusChip: some View {
        chip {
            Text("👥")
            Text(Tr("朋友的状态"))
        } action: {
            statusPanel = .friends
        }
    }

    /// 只有 ops 账号看得到的那颗：App 里直接维护曲库和图标（不用开电脑后台）
    private var manageChip: some View {
        chip {
            Text("🛠")
            Text(Tr("管理"))
        } action: {
            path.append("manage")
        }
    }

    /// 状态那一条：选了状态就跟着状态的颜色走（两个色就是渐变），没选就是普通白条
    private var statusChip: some View {
        let mood = app.me?.moodText ?? ""
        let c1 = app.me?.moodColor ?? ""
        let c2 = app.me?.moodColor2 ?? ""
        let hasColor = !mood.isEmpty && !c1.isEmpty
        return Button {
            statusPanel = .status
        } label: {
            HStack(spacing: L.v(2, 1, 4)) {
                if !mood.isEmpty {
                    Text(app.me?.moodIcon ?? "")
                    Text(mood)
                } else {
                    Text("＋").foregroundColor(C.subLabel)
                    Text(Tr("状态"))
                }
            }
            /* 方案 3：状态胶囊在**白玻璃资料卡里面**（不再压在状态色封面上），
               所以没状态就是普通描边胶囊；有状态就直接把状态色当底色、白字 —— 
               卡片是浅色的，不再需要「磨砂白压色」那一套。 */
            .font(pf(11.5, .medium))
            .foregroundColor(hasColor ? .white : C.label)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule().fill(hasColor
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hexString: c1),
                                                            Color(hexString: c2.isEmpty ? c1 : c2)],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.clear))
            )
            .overlay(
                Capsule().stroke(hasColor ? Color.white.opacity(0.35)
                                          : Color.dyn(0xE5E5E5, 0x333335), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func chip<Content: View>(@ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: L.v(2, 1, 4)) { content() }
                .font(pf(L.v(12.5, 3.4, 13.5)))
                .foregroundColor(Color.dyn(0x191919, 0xF2F2F7))
                .padding(.horizontal, L.v(10, 3.2, 13))
                .frame(height: L.v(28, 8, 32))
                .overlay(
                    Capsule().stroke(Color.dyn(0xE5E5E5, 0x333335), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    /* ---------------------------------------------------------- 推荐位 */

    private var promoRow: some View {
        Button {
            app.show(Tr("推荐位排在下一批"))
        } label: {
            HStack(spacing: L.v(10, 3.2, 13)) {
                SVGIcon(markup: I.coke, size: L.v(38, 11, 46), color: .white)
                    .frame(width: L.v(26, 7.6, 32), height: L.v(38, 11, 46))
                VStack(alignment: .leading, spacing: L.v(3, 1.2, 5)) {
                    Text(Tr("热卖 5000+"))
                        .font(pf(L.v(10.5, 2.9, 11.5)))
                        .foregroundColor(Color.dyn(0xE0393B, 0xFF8A8D))
                        .padding(.horizontal, L.v(5, 1.6, 7))
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.dyn(0xFFECEB, 0x4A1F20)))
                    Text(Tr("添加第1个作品"))
                        .font(pf(L.v(14, 3.9, 15.5)))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
            }
            .padding(.leading, L.v(16, 5, 19))
            .padding(.trailing, L.v(14, 4, 16))
            .frame(height: L.menuH)
            .background(Color.clear)      // 同上：玻璃卡里不铺自己的底色
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }
}

/// 「我」页那两颗胶囊点出来的底部面板：状态 / 朋友的状态
fileprivate enum StatusPanelKind: String, Identifiable {
    case status, friends
    var id: String { rawValue }
}

/* ============================================================
   微信那种「底部面板」：从下往上拉、松手会**停**在某一档，
   上面那一截露出上一页（不是整页盖住）。
   iOS 16.4+ 还能让背景照常能点能滑（presentationBackgroundInteraction）。
   ============================================================ */
fileprivate struct BottomPanelModifier: ViewModifier {
    var detents: Set<PresentationDetent>
    /// 打开时停在哪一档（不给的话系统默认停在**最小**那档，一开就是半截）
    var open: PresentationDetent
    @State private var sel: PresentationDetent? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        let pick = Binding(get: { sel ?? open }, set: { sel = $0 })
        if #available(iOS 16.4, *) {
            content
                .presentationDetents(detents, selection: pick)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(18)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
        } else {
            content
                .presentationDetents(detents, selection: pick)
                .presentationDragIndicator(.visible)
        }
    }
}

fileprivate extension View {
    /// 把这一页当「底部面板」弹（见上面 BottomPanelModifier 的说明）
    func bottomPanel(_ detents: Set<PresentationDetent>,
                     open: PresentationDetent) -> some View {
        modifier(BottomPanelModifier(detents: detents, open: open))
    }
}

/* ============================================================ 设置 */

struct SettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmLogout = false
    @State private var busy = false
    @State private var showBg = false
    @State private var showBgPick = false
    @State private var showTheme = false
    /// 有没有设过支付密码（设置页那一行显示「已设置 / 未设置」）
    @State private var hasPay = false
    @State private var showFeedback = false
    @State private var showTeen = false
    @State private var showCare = false
    @State private var showAbout = false
    @State private var showLang = false
    @State private var showPairApprove = false
    @State private var showSwitchAccount = false
    /// 实名认证状态（设置页那一行显示「已实名 / 未实名」）
    @State private var realNameText = ""
    /// 「账号与安全」那一行右侧的小字：显示手机号（没绑就显示星言号）
    private var accountSubtitle: String {
        let p = (app.me?.phone ?? "").trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { return maskPhone(p) }          // 设置页也只显示打码后的手机号
        return app.me?.username ?? ""
    }
    @State private var showRealName = false
    @State private var showMyQR = false
    @State private var showPrivacy = false
    @State private var showNotify = false
    @State private var showGeneral = false
    @State private var showStorage = false
    /// 「存储空间」那一行右侧的占用文字。
    /// 它要遍历本机所有媒体文件算大小 —— 以前直接写在 body 里同步算，
    /// 每次重绘都把文件系统走一遍（几百个媒体文件就是几百次 stat），
    /// 设置页一卡一卡的就是这么来的。现在改成进页面在后台算一次。
    @State private var storageText = ""
    @State private var showProfileEdit = false
    /// 设置 → 诊断工具（版本/机型/内存/缓存/网络/上次崩溃/打点，一键上报）
    @State private var showDiag = false
    /* 设置页顶上的搜索（和微信一样：打字就出结果，点结果直接进那一项） */
    @State private var query = ""
    @State private var searchActive = false
    @FocusState private var searchFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("设置"), back: { dismiss() })
            settingsSearchBar
            ScrollView {
                VStack(spacing: 0) {
                    /* 照微信「设置」那一页的排布（用户给的那张截图）：
                       搜索框在顶上，下面**四段** —— 账号 / 通用 / 功能 / 帮助与关于，
                       每段上面一行人小的灰色小标题，段里就是一行一项。 */

                    settingsGroupHeader(Tr("账号"))
                    GroupCard {
                        settingLink(Tr("个人资料"), "", key: "profile")
                        HairLine(inset: 16)
                        settingLink(Tr("账号安全"), accountSubtitle, key: "account")
                        HairLine(inset: 16)
                        settingLink(Tr("个人信息与权限"), "", key: "selfperm")
                    }

                    settingsGroupHeader(Tr("通用"))
                    GroupCard {
                        settingLink(Tr("通知"), "", key: "notify")
                        HairLine(inset: 16)
                        /* 外观 / 界面语言 / 聊天背景（微信就叫「界面与显示」） */
                        settingLink(Tr("界面与显示"), "", key: "general")
                        HairLine(inset: 16)
                        /* 微信把「加我验证 / 加我的方式 / 朋友圈可见范围」收在这一行里 */
                        settingLink(Tr("朋友权限"), "", key: "privacy")
                        HairLine(inset: 16)
                        /* 本地存储：媒体和聊天记录都存在本机，这里能看到占用、能分类清理 */
                        settingLink(Tr("存储空间"), storageText, key: "storage")
                        HairLine(inset: 16)
                        /* 更多：未成年人模式 / 关怀模式 / 我的等级 / 安全分 / 登录设备管理 */
                        settingLink(Tr("更多"), "", key: "more")
                    }

                    settingsGroupHeader(Tr("功能"))
                    GroupCard {
                        settingLink(Tr("聊天"), "", key: "setchat")
                        HairLine(inset: 16)
                        settingLink(Tr("音视频通话"), "", key: "setcall")
                        HairLine(inset: 16)
                        settingLink(Tr("聊天记录管理"), "", key: "g.history")
                    }

                    /* 微信那张截图里，「帮助与反馈 / 关于微信」上面是有小节标题
                       「帮助与关于」的。我们原来这三行直接接在「功能」段后面、
                       中间只垫了 8pt 空白，看着就像是「功能」段的一部分 —— 分类乱就乱在这。
                       现在补上小节标题，三段变四段：账号 / 通用 / 功能 / 帮助与关于。 */
                    settingsGroupHeader(Tr("帮助与关于"))

                    GroupCard {
                        settingLink(Tr("帮助与反馈"), "", key: "feedback")
                        HairLine(inset: 16)
                        /* 诊断工具（用户要求「在设置里加入全套诊断工具」）：
                           版本 / 机型 / 内存 / 缓存 / 网络 / 上次崩溃 / 聊天页打点，
                           进这一页就能一键上报给开发者 —— 以后出问题不用再靠猜。
                           它属于「帮助」这一类的工具，所以跟着帮助与反馈放同一段。 */
                        Button { showDiag = true } label: {
                            HStack(spacing: 12) {
                                Text(Tr("诊断工具")).font(pf(17)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(C.meCardBg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        /* 「关于我们」压在这一段的最后一行 —— 微信也是把「关于微信」放最下面 */
                        settingLink(Tr("关于我们 · 版本更新"), "1.0 · " + AppInfo.build, key: "about")
                    }

                    /* 切换账号（微信就在「退出登录」上面这一行） */
                    NavigationLink(value: "switch") {
                        HStack {
                            Text(Tr("切换账号"))
                                .font(pf(17))
                                .foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(C.meCardBg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    Button {
                        confirmLogout = true
                    } label: {
                        Text(busy ? "退出中…" : "退出登录")
                            .font(pf(17))
                            .foregroundColor(C.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(C.meCardBg)
                    }
                    .disabled(busy)
                    .padding(.top, 8)

                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
            /* 打了字就把结果盖在列表上（微信设置页也是这个感觉） */
            .overlay {
                if !trimmedQuery.isEmpty {
                    searchResultList
                        .background(C.pageBg)
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        /* 聊天背景：换成整页选择 —— 上面 6 张黑白基础背景缩略图，
           下面还是「默认背景 / 从相册选一张」那两条老入口。 */
        /* 聊天背景现在是整页 push（见 searchItems 里那条 key: "chatbg"） */
        .confirmationDialog(Tr("外观"), isPresented: $showTheme, titleVisibility: .visible) {
            Button(Tr("跟随系统")) { app.setAppearance("auto") }
            Button(Tr("浅色")) { app.setAppearance("light") }
            Button(Tr("深色")) { app.setAppearance("dark") }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showBgPick) {
            PhotoPicker { image in changeBg(image) }
        }
        .sheet(isPresented: $showDiag) {
            DiagView().environmentObject(app)
        }
        /* 二级菜单一律**整页 push**（以前是 sheet / 半屏，用户要求跟微信一样整页进去）；
           落点在「我」页那条 navigationDestination 上。 */
        .confirmationDialog(Tr("界面语言"), isPresented: $showLang, titleVisibility: .visible) {
            Button(Tr("简体中文")) { setLang("zh") }
            Button("English") { setLang("en") }
            Button(Tr("取消"), role: .cancel) { }
        }
        .task {
            hasPay = await API.shared.hasPayPassword()
            /* 实名状态：设置页那一行显示「已实名 / 未实名」 */
            let rn = await API.shared.realNameStatus()
            realNameText = rn.verified ? Tr("已实名") : Tr("未实名")
            /* 本机存储占用：放到后台线程算（遍历文件系统），算完再上屏 */
            let used = await Task.detached(priority: .utility) {
                LocalStore.text(LocalStore.totalUsage())
            }.value
            storageText = used
        }
        .confirmationDialog(Tr("确定退出登录？"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(Tr("退出登录"), role: .destructive) {
                busy = true
                Task {
                    await app.logout()
                    busy = false
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    /// 切换界面语言：存下来 + 让标签栏那些文案立刻重绘
    private func setLang(_ code: String) {
        Lang.code = code
        app.show(code == "en" ? "Language switched to English" : "界面语言已切成中文")
        dismiss()
        /* 同上：运行中不重绘，重开 App 生效 */
    }

    private func changeBg(_ image: UIImage) {
        busy = true
        Task {
            if let url = try? await API.shared.uploadOriginal(image: image) {   // 聊天背景用原图
                await API.shared.changeBackground(url)
                app.me = try? await API.shared.me()
                app.show(Tr("聊天背景换好了"))
            }
            busy = false
        }
    }

    /* ---------------------------------------------------------- 设置页搜索（和微信一样的逻辑） */

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// 能被搜到的一项：title 是显示的名字，keywords 是搜索词
    /// （把子项都塞进 keywords，所以搜「支付密码」也能找到「账号与安全」；
    ///  有的项是推页面（key），有的是弹窗（run））
    private struct SettingSearchItem: Identifiable {
        let id = UUID()
        let title: String
        let sub: String
        let keywords: String
        var key: String? = nil
        var run: (() -> Void)? = nil
    }

    private var searchItems: [SettingSearchItem] {
        let items: [SettingSearchItem] = [
            SettingSearchItem(title: Tr("个人资料"), sub: "",
                              keywords: "个人资料 头像 昵称 名字 个人信息 资料", key: "profile"),
            SettingSearchItem(title: Tr("账号安全"), sub: accountSubtitle,
                              keywords: "账号 安全 账号与安全 手机号 手机 实名 认证 支付密码 支付 密码 安全锁 手势 声音锁 登录设备 设备 安全分 个人信息 资料",
                              key: "account"),
            SettingSearchItem(title: Tr("个人信息与权限"), sub: "",
                              keywords: "个人信息 权限 系统权限 授权 相册 相机 麦克风 位置", key: "selfperm"),
            SettingSearchItem(title: Tr("实名认证"), sub: realNameText,
                              keywords: "实名 认证 身份证 实名制", key: "realname"),
            SettingSearchItem(title: Tr("支付密码"), sub: hasPay ? Tr("已设置") : Tr("未设置"),
                              keywords: "支付密码 密码 设置密码 改密码 重置", key: "paypwd"),
            SettingSearchItem(title: Tr("安全锁（手势密码）"), sub: "",
                              keywords: "安全锁 手势密码 手势 锁", key: "gesture"),
            SettingSearchItem(title: Tr("声音锁"), sub: "",
                              keywords: "声音锁 声纹 声音", key: "voicelock"),
            SettingSearchItem(title: Tr("我的等级"), sub: "",
                              keywords: "等级 活跃天 成长 升级 图标", key: "level"),
            SettingSearchItem(title: Tr("安全分"), sub: "",
                              keywords: "安全分 评分 安全", key: "score"),
            SettingSearchItem(title: Tr("登录设备管理"), sub: "",
                              keywords: "登录设备 设备 手机 电脑 退出设备", key: "devices"),
            SettingSearchItem(title: Tr("未成年人模式"), sub: "",
                              keywords: "未成年人 青少年 防沉迷 伞 模式", key: "teen"),
            SettingSearchItem(title: Tr("关怀模式"), sub: CareMode.on ? Tr("已开启") : Tr("未开启"),
                              keywords: "关怀 大字 字号 老年人 模式", key: "care"),
            SettingSearchItem(title: Tr("通知"), sub: "",
                              keywords: "新消息 通知 提醒 铃声 震动 免打扰", key: "notify"),
            SettingSearchItem(title: Tr("朋友权限"), sub: "",
                              keywords: "朋友权限 隐私 加我 好友 验证 朋友圈 通讯录", key: "privacy"),
            SettingSearchItem(title: Tr("界面与显示"), sub: "",
                              keywords: "界面与显示 通用 外观 深色 浅色 主题 界面语言 中文 英文", key: "general"),
            SettingSearchItem(title: Tr("更多"), sub: "",
                              keywords: "更多 未成年人 关怀 等级 安全分 登录设备 诊断", key: "more"),
            SettingSearchItem(title: Tr("聊天"), sub: "",
                              keywords: "聊天 聊天背景 语音变声 聊天记录 存储", key: "setchat"),
            SettingSearchItem(title: Tr("音视频通话"), sub: "",
                              keywords: "音视频通话 视频 语音 通话 来电", key: "setcall"),
            SettingSearchItem(title: Tr("聊天背景"), sub: "",
                              keywords: "聊天背景 背景 壁纸 图片", key: "chatbg"),
            SettingSearchItem(title: Tr("外观"), sub: "",
                              keywords: "外观 深色 浅色 跟随系统 主题", run: { showTheme = true }),
            SettingSearchItem(title: Tr("界面语言"), sub: "",
                              keywords: "界面语言 语言 中文 英文 language", run: { showLang = true }),
            SettingSearchItem(title: Tr("帮助与反馈"), sub: "",
                              keywords: "帮助 反馈 意见 客服 投诉", key: "feedback"),
            SettingSearchItem(title: Tr("关于我们 · 版本更新"), sub: "1.0 · " + AppInfo.build,
                              keywords: "关于 版本 更新 检查更新 当前版本", key: "about"),
            SettingSearchItem(title: Tr("诊断工具"), sub: "",
                              keywords: "诊断 上报 日志 崩溃 机型 内存 缓存 网络", run: { showDiag = true }),
            SettingSearchItem(title: Tr("切换账号"), sub: "",
                              keywords: "切换账号 换号 登录 账号", key: "switch"),
            SettingSearchItem(title: Tr("退出登录"), sub: "",
                              keywords: "退出登录 退出 注销 登出", run: { confirmLogout = true })
        ]
        /* 成长系统关掉（growthShow=0）时，"我的等级"这条搜索结果也不给 */
        return UIConfig.num("growthShow", 1) > 0 ? items : items.filter { $0.key != "level" }
    }

    private var matches: [SettingSearchItem] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return searchItems.filter {
            $0.title.lowercased().contains(q) || $0.keywords.lowercased().contains(q)
        }
    }

    private var settingsSearchBar: some View {
        HStack(spacing: 9) {
            /* 框里叠两层：没点进来时「🔍 搜索」**居中**（和微信一样），
               点进来才变成左边图标 + 左对齐输入 + 右边清除。 */
            ZStack {
                if !searchActive && query.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(C.searchIcon)
                        Text(Tr("搜索"))
                            .font(pf(15))
                            .foregroundColor(C.searchIcon)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocus = true }
                }
                HStack(spacing: 8) {
                    if searchActive || !query.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(C.searchIcon)
                    }
                    TextField("", text: $query)
                        .font(pf(15))
                        .focused($searchFocus)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(C.searchIcon2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.searchBg))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))

            /* 点进搜索框才出现「取消」（和微信一样） */
            if searchActive {
                Button {
                    query = ""
                    searchFocus = false
                } label: {
                    Text(Tr("取消")).font(pf(15)).foregroundColor(C.label)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(C.pageBg)
        .animation(.easeOut(duration: 0.16), value: searchActive)
        .onChange(of: searchFocus) { f in searchActive = f }
    }

    private var searchResultList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if matches.isEmpty {
                    Text(Tr("没有找到") + "「\(trimmedQuery)」")
                        .font(pf(14))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)
                } else {
                    GroupCard {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { idx, item in
                            searchResultRow(item)
                            if idx < matches.count - 1 { HairLine(inset: 16) }
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer().frame(height: 30)
            }
        }
        .background(C.pageBg)
    }

    @ViewBuilder
    private func searchResultRow(_ item: SettingSearchItem) -> some View {
        if let key = item.key {
            NavigationLink(value: key) { searchRowLabel(item) }
                .buttonStyle(MenuPressStyle())
        } else {
            Button {
                searchFocus = false
                item.run?()
            } label: {
                searchRowLabel(item)
            }
            .buttonStyle(MenuPressStyle())
        }
    }

    private func searchRowLabel(_ item: SettingSearchItem) -> some View {
        HStack(spacing: 12) {
            Text(item.title).font(pf(17)).foregroundColor(C.label)
            Spacer(minLength: 0)
            if !item.sub.isEmpty {
                Text(item.sub).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(C.meCardBg)
        .contentShape(Rectangle())
    }

    private func settingRow(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(pf(17)).foregroundColor(C.label)
                Spacer(minLength: 0)
                if !value.isEmpty {
                    Text(value).font(pf(15)).foregroundColor(C.subLabel)
                }
                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(C.meCardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }

    /// 照微信：每一段上面那一行人小的灰色小标题（账号 / 通用 / 功能）。
    /// 灰色比页面底色深一点、比正文浅（截图里量出来是 #666~#767676 这一档）。
    /// 左内边距必须是 16 —— 微信那张截图里量出来，小标题和下面行标题的
    /// 左边缘是**对齐**的（都在 17pt 一档）；我们原来是 22，比行标题多缩进 6pt，
    /// 截图叠一起能明显看出来错位，所以改成和 settingLink 一样的 16。
    private func settingsGroupHeader(_ text: String) -> some View {
        Text(text)
            .font(pf(13.5))
            .foregroundColor(Color.dyn(0x767676, 0x8F8F8F))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 7)
    }

    /// 和 settingRow 长得一样，但点进去是下一个页面（用导航）
    private func settingLink(_ title: String, _ value: String, key: String) -> some View {
        NavigationLink(value: key) {
            HStack(spacing: 12) {
                Text(title).font(pf(17)).foregroundColor(C.label)
                Spacer(minLength: 0)
                if !value.isEmpty {
                    Text(value).font(pf(15)).foregroundColor(C.subLabel)
                }
                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(C.meCardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }
}

