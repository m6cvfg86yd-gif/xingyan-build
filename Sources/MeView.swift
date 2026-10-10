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
                        GroupCard(glass: UIConfig.num("meGlass", 1) > 0, bg: C.meCardBg) {
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

    /// 封面高度（含系统状态栏那一条）
    private var coverH: CGFloat { L.safeTop + UIConfig.num("meCoverH", 76) }
    /// 资料卡顶部离屏幕顶的距离：卡片压在封面下沿上，上面露出一截蓝
    private var cardTopY: CGFloat { coverH - UIConfig.num("meCardOverlap", 39) }
    private var topAvatar: CGFloat { L.v(58, 15.6, 66) }

    /// 方案 3 的封面：只占顶上一条，是一块**磨砂玻璃** ——
    /// 浅色模式是白磨砂、深色模式是黑磨砂（Material 自己跟着主题走，不用写两套颜色）。
    @ViewBuilder private var meCover: some View {
        if moodOn {
            /* 用户要求：「状态点了顶部卡片要发生相应的颜色变化」。
               设了状态时，顶上这条封面就换成**这个状态自己的颜色**（从图标/分类来的
               那对渐变色，moodC1 → moodC2）—— 状态名和文案也留在卡里。
               以前这里永远是最上面那块磨砂玻璃：profileTopBg 写了但没人用，
               所以设完状态顶上颜色一点变化都没有。 */
            profileTopBg
                .frame(maxWidth: .infinity)
        } else {
            ZStack(alignment: .top) {
            if scheme == .dark {
                /* ⚠ 深色下**不用 Material**：`.ultraThinMaterial` 在深色里会把底色抬亮一大截，
                   实测顶那条封面是 #313133，而页面底是 #0B0B0D、卡片是 #1C1C1E ——
                   三个档摆在一起就是"深色下底色不一致"（用户反馈）。
                   深色直接给一层和卡片同一档的近黑，只留顶上那道很淡的光。 */
                Color(hex: 0x131315)
                LinearGradient(colors: [Color.white.opacity(0.05), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: L.safeTop + 64)
            } else {
                /* 底：浅色给白，磨砂层再压上去 */
                Color(hex: 0xFFFFFF)
                Rectangle().fill(.ultraThinMaterial)
                /* 顶上一道光：玻璃放在死色上会像一块塑料，这一笔才有"磨砂/通透"的层次 */
                LinearGradient(colors: [Color.white.opacity(0.60), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: L.safeTop + 64)
            }
        }
        .frame(maxWidth: .infinity)
        }
    }

    private var profileTop: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: cardTopY)
            meProfileCard
                .padding(.horizontal, UIConfig.num("meGlassInset", 12))
            Color.clear.frame(height: 12)
        }
        .background(alignment: .top) {
            meCover.frame(height: coverH)
        }
    }

    /// 「我」页顶部那张资料卡：头像压在卡片上沿，其余全在卡里
    private var meProfileCard: some View {
        VStack(spacing: 0) {
            /* 名字 + 等级徽章 + 会员徽章（居中；左右各留 46pt，别顶到右上角二维码） */
            HStack(spacing: 6) {
                /* 未成年人模式开着：名字前面挂一把小雨伞（点一下进那一页，微信就是这样） */
                if teenOn {
                    Button { showTeenCard = true } label: {
                        UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 16)
                    }
                    .buttonStyle(.plain)
                }
                Text(app.me?.name ?? "")
                    .font(pf(L.v(17, 4.8, 19.5), .semibold))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                if growthShow {
                    QQLevelBadge(level: growth.shownLevel,
                                 size: L.v(15, 4.2, 17), maxIcons: 3)
                        .fixedSize()
                }
                MemberBadge(tier: app.me?.memberTier,
                            short: app.me?.memberShort,
                            color: app.me?.memberColor,
                            color2: app.me?.memberColor2,
                            height: L.v(12.5, 3.5, 14))
                    .fixedSize()
            }
            .padding(.top, topAvatar / 2 + 8)
            .padding(.horizontal, 46)

            Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .padding(.top, 5)

            /* 数据条：朋友 / 等级 / 活跃天（后两格点进去都是「我的等级」） */
            HStack(spacing: 0) {
                statCell("\(friendCount)", Tr("朋友"), tap: false)
                /* 成长系统关掉（growthShow=0）时，只留「朋友」一格 */
                if growthShow {
                    statLine
                    statCell("Lv." + String(growth.shownLevel), Tr("等级"), tap: true)
                    statLine
                    statCell(daysText, Tr("活跃天"), tap: true)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 10)

            /* 会员 + 状态：两枚胶囊并排居中 */
            HStack(spacing: 8) {
                memberPill
                statusChip
            }
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                                opacity: UIConfig.num("meGlassAlpha", 0.62),
                                edgeAlpha: UIConfig.num("meGlassEdge", 0.55),
                                shadow: true,
                                seed: 0.42,
                                native: true)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(C.meCardBg.opacity(0.42))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        /* 头像：压在卡片上沿，点进个人信息 */
        .overlay(alignment: .top) {
            Button { path.append("profile") } label: {
                Avatar(path: app.me?.avatarPath ?? "", size: topAvatar,
                       circle: true, level: growth.shownLevel)
                    .frame(width: topAvatar, height: topAvatar)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(y: -topAvatar / 2)
        }
        /* 二维码：卡片右上角，点开「我的二维码」 */
        .overlay(alignment: .topTrailing) {
            Button { showMyQR = true } label: {
                SVGIcon(markup: I.qr, size: L.v(19, 5.4, 21), color: C.label)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .padding(.top, topAvatar / 2 + 2)
        }
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

    /// 状态那一条：选了状态就跟着状态的颜色走（两个色就是渐变），没选就是普通白条
    private var statusChip: some View {
        let mood = app.me?.moodText ?? ""
        let c1 = app.me?.moodColor ?? ""
        let c2 = app.me?.moodColor2 ?? ""
        let hasColor = !mood.isEmpty && !c1.isEmpty
        return Button {
            path.append("status")
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
                    GroupCard {
                        /* 和微信「设置」一模一样的顺序：
                           账号与安全 → 新消息通知 → 隐私 → 通用 → 帮助与反馈 → 关于 → 切换账号 → 退出登录
                           （个人信息、实名、支付密码、安全锁、安全分、登录设备都归到「账号与安全」里了） */
                        settingLink(Tr("账号与安全"), accountSubtitle, key: "account")
                        HairLine(inset: 16)
                        settingRow(Tr("未成年人模式"), "") { showTeen = true }
                        HairLine(inset: 16)
                        settingRow(Tr("关怀模式"), CareMode.on ? Tr("已开启") : Tr("未开启")) { showCare = true }
                        HairLine(inset: 16)
                        settingRow(Tr("新消息通知"), "") { showNotify = true }
                        HairLine(inset: 16)
                        settingRow(Tr("隐私"), "") { showPrivacy = true }
                        HairLine(inset: 16)
                        /* 通用：外观 / 界面语言 / 聊天背景（微信也把这几项收在「通用」里） */
                        settingRow(Tr("通用"), "") { showGeneral = true }
                        HairLine(inset: 16)
                        /* 本地存储：媒体和聊天记录都存在本机，这里能看到占用、能分类清理 */
                        settingRow(Tr("存储空间"), storageText) { showStorage = true }
                    }

                    Rectangle().fill(C.pageBg).frame(height: 8)

                    GroupCard {
                        settingRow(Tr("帮助与反馈"), "") { showFeedback = true }
                        HairLine(inset: 16)
                        settingRow(Tr("关于我们 · 版本更新"), "1.0 · " + AppInfo.build) { showAbout = true }
                    }

                    /* 切换账号（微信就在「退出登录」上面这一行） */
                    Button {
                        showSwitchAccount = true
                    } label: {
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
        .sheet(isPresented: $showBg) {
            ChatBackgroundSheet().environmentObject(app)
        }
        .confirmationDialog(Tr("外观"), isPresented: $showTheme, titleVisibility: .visible) {
            Button(Tr("跟随系统")) { app.setAppearance("auto") }
            Button(Tr("浅色")) { app.setAppearance("light") }
            Button(Tr("深色")) { app.setAppearance("dark") }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showBgPick) {
            PhotoPicker { image in changeBg(image) }
        }
        .sheet(isPresented: $showFeedback) { FeedbackView() }
        .sheet(isPresented: $showTeen) { TeenModeView().environmentObject(app) }
        .sheet(isPresented: $showCare) { CareModeView().environmentObject(app) }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showPairApprove) { PairApproveView() }
        .sheet(isPresented: $showMyQR) { MyQRView() }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showNotify) { NotifyView() }
        .sheet(isPresented: $showGeneral) { GeneralView() }
        .sheet(isPresented: $showStorage) { StorageSpaceView() }
        .sheet(isPresented: $showProfileEdit) { ProfileEditView() }
        .sheet(isPresented: $showSwitchAccount) { SwitchAccountView() }
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
            SettingSearchItem(title: Tr("账号与安全"), sub: accountSubtitle,
                              keywords: "账号 安全 手机号 手机 实名 认证 支付密码 支付 密码 安全锁 手势 声音锁 登录设备 设备 安全分 个人信息 资料",
                              key: "account"),
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
            SettingSearchItem(title: Tr("未成年人模式"), sub: "",
                              keywords: "未成年人 青少年 防沉迷 伞 模式", run: { showTeen = true }),
            SettingSearchItem(title: Tr("关怀模式"), sub: CareMode.on ? Tr("已开启") : Tr("未开启"),
                              keywords: "关怀 大字 字号 老年人 模式", run: { showCare = true }),
            SettingSearchItem(title: Tr("新消息通知"), sub: "",
                              keywords: "新消息 通知 提醒 铃声 震动 免打扰", run: { showNotify = true }),
            SettingSearchItem(title: Tr("隐私"), sub: "",
                              keywords: "隐私 加我 好友 朋友圈 通讯录", run: { showPrivacy = true }),
            SettingSearchItem(title: Tr("通用"), sub: "",
                              keywords: "通用 外观 深色 浅色 主题 界面语言 中文 英文", run: { showGeneral = true }),
            SettingSearchItem(title: Tr("聊天背景"), sub: "",
                              keywords: "聊天背景 背景 壁纸 图片", run: { showBg = true }),
            SettingSearchItem(title: Tr("外观"), sub: "",
                              keywords: "外观 深色 浅色 跟随系统 主题", run: { showTheme = true }),
            SettingSearchItem(title: Tr("界面语言"), sub: "",
                              keywords: "界面语言 语言 中文 英文 language", run: { showLang = true }),
            SettingSearchItem(title: Tr("帮助与反馈"), sub: "",
                              keywords: "帮助 反馈 意见 客服 投诉", run: { showFeedback = true }),
            SettingSearchItem(title: Tr("关于我们 · 版本更新"), sub: "1.0 · " + AppInfo.build,
                              keywords: "关于 版本 更新 检查更新 当前版本", run: { showAbout = true }),
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

