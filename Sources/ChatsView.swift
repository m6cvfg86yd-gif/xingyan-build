import SwiftUI
import UIKit

/* ============================================================
   会话行的触摸层 —— 左滑用它，**不用 SwiftUI 的 DragGesture**。

   为什么（线上实测）：SwiftUI 的 DragGesture 挂在行上会和外面那层 ScrollView
   抢手势。换成 iOS 26 SDK（Xcode 26）构建之后，竖向的上下滑被这个 DragGesture
   吃掉，表现就是「会话页上下滑不动」——而通讯录/发现/我 这些列表页没有这个手势，
   所以只有会话页有问题。

   UIKit 的 pan 可以声明「允许和 UIScrollView 的滚动手势同时识别」
   （delegate 返回 true），所以：
     · 手指竖向滑 → 我们完全不碰，列表照常上下滚
     · 手指横向拖 → 才算左滑，驱动行往左推
   单击也在这里一起处理（这一层盖在行上面，SwiftUI 的 onTapGesture 收不到）。
   ============================================================ */
struct RowSwipeCatcher: UIViewRepresentable {
    /// 单击（点的位置，用来区分「点头像」还是「点整行」）
    var onTap: (CGPoint) -> Void
    /// 这一下确定是横向拖动（方向判完才调）
    var onBegan: () -> Void
    /// 横向拖动的位移（从按下算起）
    var onChanged: (CGFloat) -> Void
    /// 松手：位移 + 横向速度（速度用来判「甩一下」是开还是收）
    var onEnded: (CGFloat, CGFloat) -> Void

    final class Coord: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void = { _ in }
        var onBegan: () -> Void = { }
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        /// 这一下已经判定成横向拖了吗
        private var horizontal = false

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            switch g.state {
            case .began:
                horizontal = false
            case .changed:
                if !horizontal {
                    /* 方向：横着明显多于竖着才算左滑；否则一律交给列表滚 */
                    guard abs(t.x) > abs(t.y) + 4 else { return }
                    horizontal = true
                    onBegan()
                }
                onChanged(t.x)
            case .ended, .cancelled, .failed:
                if horizontal { onEnded(t.x, g.velocity(in: g.view).x) }
                horizontal = false
            default:
                break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            onTap(g.location(in: g.view))
        }

        /// 关键：和 ScrollView 的滚动**同时识别**，谁也别抢谁的
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        v.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handleTap(_:)))
        tap.delegate = context.coordinator
        /* 不要 cancelsTouchesInView：这样这一层只是"看着"，不会把触摸从行里抢走 */
        tap.cancelsTouchesInView = false
        v.addGestureRecognizer(tap)

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }
}

struct ChatRow: View {
    let chat: Chat
    /// 点左边那个头像（只有机器人那几行给）：直接弹它自己的名片
    var onTapAvatar: (() -> Void)? = nil

    var body: some View {
        /* 微信的位置是固定的：头像在行高里居中，文字块和右边那列都从离顶 13 的地方开始 */
        HStack(alignment: .top, spacing: 0) {
            avatarBlock
                .padding(.top, avatarTop)
            Spacer().frame(width: L.rowGap)
            textColumn
                .padding(.top, L.rowPadTop)
            Spacer(minLength: 6)
            rightColumn
                .padding(.top, L.rowPadTop)
        }
        .padding(.leading, L.rowPadL)
        .padding(.trailing, L.rowPadR)
        .frame(height: L.rowH)
        .contentShape(Rectangle())
    }

    /// 头像在行高里居中（微信 76 的行、48 的头像 → 上下各 14）
    private var avatarTop: CGFloat { max(0, (L.rowH - L.avatar) / 2) }

    /// 头像：机器人那几行点它能弹名片，普通会话点了进聊天
    private var avatarBlock: some View {
        Group {
            if let tap = onTapAvatar {
                avatar.contentShape(Rectangle()).onTapGesture { tap() }
            } else {
                avatar
            }
        }
    }

    /// 名字在上、预览在下
    private var textColumn: some View {
        VStack(alignment: .leading, spacing: L.rowTextGap) {
            HStack(spacing: 5) {
                Text(chat.name)
                    .font(pf(L.rowNameSize))
                    .foregroundColor(C.name)
                    .lineLimit(1)
                    .layoutPriority(1)
                /* 昵称旁边挂等级图标（QQ 那套）：后台「显示在聊天里」开着才显示 */
                if let lv = chat.qqLevel, lv > 0, GrowthFlags.showInChats == true {
                    QQLevelBadge(level: lv, size: L.v(13, 3.6, 15), maxIcons: 3)
                        .fixedSize()
                }
                /* 会员徽章（对方开了会员就挂一个，单聊看对方、群聊看群主） */
                MemberBadge(tier: chat.memberTier,
                            short: chat.memberShort,
                            color: chat.memberColor,
                            color2: chat.memberColor2,
                            height: L.v(11.5, 3.2, 13))
                    .fixedSize()
            }
            Text(chat.lastMessage?.preview ?? "")
                .font(pf(L.rowPreviewSize))
                .foregroundColor(C.preview)
                .lineLimit(1)
        }
    }

    /// 右边一列：时间在上，未读徽标在下（微信就是这样，徽标不在头像上）
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(TimeFmt.list(chat.lastMessage?.createdAt ?? chat.updatedAt))
                .font(pf(L.rowTimeSize))
                .foregroundColor(C.time)
                .fixedSize()
        }
    }

    /// 未读标记：**压在头像右上角**（微信就是这样 —— 不在行右边）。
    /// 普通会话给数字徽标；免打扰会话只给一个小红点（微信的规则）。
    @ViewBuilder
    private var unreadOnAvatar: some View {
        if chat.unreadCount > 0 {
            /* 免打扰的会话、和「左滑 → 标为未读」的会话：微信都只点一个小红点，
               不给数字（数字留给真正等你看的消息） */
            if chat.muted == true || chat.flagged == true {
                UnreadDot(border: C.chatsRowBg)
                    .offset(x: 5, y: -5)
            } else {
                UnreadBadge(count: chat.unreadCount, border: C.chatsRowBg)
                    .offset(x: 8, y: -8)
            }
        }
    }

    private var avatar: some View {
        Avatar(path: chat.avatar ?? "", size: L.avatar, radius: 4, level: chat.qqLevel ?? 0)
            /* 好友设了状态：头像右下角挂一个小 emoji（微信就是这样） */
            .overlay(alignment: .bottomTrailing) {
                if let icon = chat.moodIcon, !icon.isEmpty {
                    Text(icon)
                        .font(.system(size: 9))
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(C.cardBg))
                        .overlay(Circle().stroke(C.hairline, lineWidth: 0.5))
                        .offset(x: 5, y: 5)
                }
            }
            /* 未读：数字徽标 / 免打扰的小红点压在这个头像的右上角 */
            .overlay(alignment: .topTrailing) {
                unreadOnAvatar
            }
    }
}

/* ============================================================
   会话行 + 左滑三级操作（完全照网页版）：
   ① 左滑露出 标为未读(绿) / 不显示(橙) / 删除(红)，三个各 80 宽，整条 240
   ② 点「不显示」→ 这一条撑满 249 变成「不显示该聊天」（橙），再点一下才执行
   ③ 点「删除」→ 这一条撑满 249 变红「清空记录同时不显示聊天」，再点一下才执行
   拖过一截会预览第二层；点别处整条收回去。

   手感（用户要求「有阻尼感」）：
   · 拖动时**越拉越沉**（超出三格只跟 30%，最多再多 92），拉到头不会硬顶死
   · 松手用**弹簧吸附**（interpolatingSpring），会轻轻回稳一下，不是 easeOut 硬切
   · 甩一下就开/收（看松手时的横向速度），慢拖则看拖过没拖过四成
   · 开、进入第二层各轻震一下（和微信的手感一致）
   长相（用户要求「卡片三条精致一点」）：
   · 三格做成**一张圆角小卡片**（上下各留 5 白、圆角 13、外面一层白描边 + 淡投影）
   · 每格小图标 + 文字竖排、底色上下做一点渐变、格子之间一条白细线
   · 想调就改 ui.json：swipeBtnW / swipeFont / swipeInset / swipeRadius / swipeIcon
   ============================================================ */

struct SwipeChatRow: View {
    enum Mode { case none, hideConfirm, delConfirm }

    let chat: Chat
    var onOpen: () -> Void
    /// 机器人那几行：点头像弹名片（普通会话传 nil）
    var onTapAvatar: (() -> Void)? = nil
    var onUnread: () -> Void
    var onHide: (Bool) -> Void      // true = 连记录一起清掉
    var onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var mode: Mode = .none
    @State private var dragging = false

    /// 三个按钮的尺寸：和原版微信一致（每个 80 宽、整行高 72、17 号白字）
    /// 想微调就改 ui.json 里的 swipeBtnW / swipeFont
    private var btnW: CGFloat { UIConfig.num("swipeBtnW", 80) }
    private var btnFont: CGFloat { UIConfig.num("swipeFont", 15.5) }
    private var fullW: CGFloat { btnW * 3 }
    /// 露出来的那块做成一张小卡片：上下留白、圆角、描边、淡投影
    private var cardInset: CGFloat { UIConfig.num("swipeInset", 5) }
    private var cardRadius: CGFloat { UIConfig.num("swipeRadius", 13) }
    private var iconSize: CGFloat { UIConfig.num("swipeIcon", 13.5) }
    private var cardH: CGFloat { max(20, L.rowH - cardInset * 2) }
    /// 开 / 换层的时候轻震一下
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    /// 吸附用的弹簧：**轻微过冲再回稳** —— 用户要的「阻尼感」就是它
    private var swipeSpring: Animation {
        .interpolatingSpring(mass: 0.9, stiffness: 250, damping: 25)
    }

    /* 会话列表每一行也用「卡片底色」，和通讯录的卡片一个色；
       置顶的仍然用置顶色区分一下 */
    /* 置顶行不再单独一层底色（用户反馈"会话页有几个东西被单独框起来"）：
       置顶只体现在排序上，一行一行的底色和普通会话完全一致。
       想恢复"置顶带灰底"就在后台 ui.json 里写 pinnedBg = "#F2F2F2|#333335"。 */
    private var rowBg: Color { C.chatsRowBg }

    var body: some View {
        ZStack(alignment: .trailing) {
            /* ① 行内容：跟着手指往左推 */
            ChatRow(chat: chat, onTapAvatar: onTapAvatar)
                .frame(width: L.width, height: L.rowH, alignment: .leading)
                .background(rowBg)
                .overlay(alignment: .bottom) { HairLine(inset: L.dividerLeft) }
                .offset(x: offset)
                .contentShape(Rectangle())
                .zIndex(1)

            /* ② 操作按钮：画在最上层，只露出滑开的那一块 —— 这样点一定点得到 */
            actionButtons
                .allowsHitTesting(offset != 0)
                .zIndex(2)
        }
        .frame(width: L.width, height: L.rowH, alignment: .leading)
        /* 底层铺一行底色：卡片上下那 5pt 留白露出来的就是它（和各行的底色完全一样）。
           以前没有这层，第二层撑满时左边会透出页面底色，看着像裂了一条缝。 */
        .background(rowBg)
        .clipped()
        /* ③ 手势层：**上下滑交给列表滚**，只有横向拖才算左滑 ——
           以前这里挂的是 SwiftUI 的 DragGesture，换成 iOS 26 SDK 构建之后
           它会和外面那层 ScrollView 抢手势，竖向上下滑被它吃掉，
           表现就是「会话页上下滑不动」（别的列表页没这个手势，所以只有会话页有问题）。
           UIKit 的 pan 可以声明「和 ScrollView 的滚动同时识别」，两边互不影响。
           宽度跟着 offset 收，滑开后露出来的三个按钮不会被这层挡住。 */
        .overlay(alignment: .leading) {
            RowSwipeCatcher(
                onTap: { p in
                    if offset != 0 {
                        close()
                    } else if p.x < L.rowPadL + L.avatar + 10, let tap = onTapAvatar {
                        tap()                       // 机器人那几行：点头像弹名片
                    } else {
                        onOpen()
                    }
                },
                onBegan: {
                    dragging = true
                    startOffset = offset
                },
                onChanged: { dx in
                    var x = startOffset + dx
                    if x > 0 {
                        /* 往右拖过头：只跟一点点，最多探出 10 —— 有阻尼才不像硬底 */
                        x = min(10, x * 0.22)
                    } else if x < -fullW {
                        /* 拉过三格之后：越拉越沉（只跟 30%，最多再多 92） */
                        x = -(fullW + min(92, (-x - fullW) * 0.30))
                    }
                    offset = x
                    /* 多拉一截就预览第二层（那一条撑满 240，变成「不显示该聊天」） */
                    if -x > fullW + 34 && mode == .none {
                        mode = .hideConfirm
                        haptic.impactOccurred(intensity: 0.7)
                    } else if -x < fullW - 9 && mode == .hideConfirm {
                        mode = .none
                    }
                },
                onEnded: { _, vx in
                    dragging = false
                    settle(velocity: vx)
                }
            )
            .frame(width: max(0, L.width + offset), height: L.rowH)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            switch mode {
            case .none:
                /* 第一层：标为未读 / 不显示 / 删除，各一个按钮宽 */
                bar("标为未读", "envelope.badge.fill", 0x2ECC9A, 0x12A377, btnW) {
                    onUnread()
                    close()
                }
                bar("不显示", "eye.slash.fill", 0xFFB153, 0xEE8A12, btnW, sep: true) {
                    mode = .hideConfirm
                    haptic.impactOccurred()
                    withAnimation(swipeSpring) { offset = -fullW }
                }
                bar("删除", "trash.fill", 0xFF6B62, 0xE23B33, btnW, sep: true) {
                    mode = .delConfirm
                    haptic.impactOccurred()
                    withAnimation(swipeSpring) { offset = -fullW }
                }
            case .hideConfirm:
                /* 第二层：整条撑满，再点一下才真的不显示 */
                bar("不显示该聊天", "eye.slash.fill", 0xFFB153, 0xEE8A12, fullW) {
                    onHide(false)
                    close()
                }
            case .delConfirm:
                /* 第二层：整条撑满，再点一下才真的删掉 */
                bar("清空记录同时不显示聊天", "trash.fill", 0xF2544C, 0xD62A23, fullW) {
                    onDelete()
                    close()
                }
            }
        }
        .frame(height: cardH)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
        )
        .padding(.vertical, cardInset)
        .frame(width: max(0, -offset), height: L.rowH, alignment: .trailing)
        .clipped()
        /* 卡片浮在行上面那一层投影（.clipped 之后才加，投出来才是卡片自己的形状） */
        .shadow(color: .black.opacity(0.16), radius: 9, x: 0, y: 3)
    }

    /// 松手吸附：**带阻尼的弹簧**（会轻轻回稳一下，不是硬切过去）
    private func settle(velocity vx: CGFloat) {
        if mode != .none {
            withAnimation(swipeSpring) { offset = -fullW }
            return
        }
        let open: Bool
        if vx <= -420 {
            open = true                     // 往左甩一下：直接开到最大
        } else if vx >= 420 {
            open = false                    // 往右甩一下：直接收回去
        } else {
            open = -offset > fullW * 0.42   // 慢慢拖的：拖过四成就算开
        }
        if open { haptic.impactOccurred() }
        withAnimation(swipeSpring) {
            offset = open ? -fullW : 0
            if !open { mode = .none }
        }
    }

    /// 一个可以点的格子：小图标 + 文字竖排、白字、底色上下一点渐变
    /// （不用 Button：Button 在会滑动的行里容易点不到）
    private func bar(_ title: String, _ symbol: String,
                     _ top: UInt32, _ bottom: UInt32, _ width: CGFloat,
                     sep: Bool = false,
                     action: @escaping () -> Void) -> some View {
        VStack(spacing: 3.5) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.96))
            Text(title)
                .font(pfExact(btnFont, .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: max(0, width), height: cardH)
        .background(
            LinearGradient(colors: [Color(hex: top), Color(hex: bottom)],
                           startPoint: .top, endPoint: .bottom)
        )
        /* 格子之间一条白细线（两端留空，不顶到卡片边） */
        .overlay(alignment: .leading) {
            if sep {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 0.7)
                    .padding(.vertical, 11)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    private func close() {
        withAnimation(swipeSpring) {
            offset = 0
            mode = .none
        }
    }
}

/* ============================================================ 微信（会话列表） */

struct ChatsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    @State private var keyword = ""
    /// 会话列表滚了多少（顶栏那层磨砂按它淡入淡出）
    @State private var scrolled: CGFloat = 0
    /// 下拉露出来的「二楼」露了多少（微信那个小程序层；由列表自己的下拉量驱动，不挂手势）
    @State private var pullDown: CGFloat = 0
    /// 二楼是不是"拉开停住了"：微信是拉过阈值就停着（不再弹回去），往上滚或点一下才收起
    @State private var floorUp = false
    /// 「二楼」总开关：后台 chatsFloor 写 0 = 整页不做二楼（被误触烦到可以直接关掉）
    private var floorOn: Bool { UIConfig.num("chatsFloor", 1) > 0 }
    /// 「二楼」的下拉阈值（pt）：拉过这么多才算"想开二楼"。
    /// 默认 **120**（原来 70 太浅，用户反馈"二楼一直误触"）。
    private var floorPull: CGFloat { max(40, UIConfig.num("chatsFloorPull", 120)) }
    /// 下拉时三颗"压感点"已经点亮了几颗（每亮一颗震一下；用户要求振动加强）
    @State private var floorTick = 0
    /// 「重力感」：手指下拉的距离 → 二楼实际露出的高度
    /// 前 60pt 完全跟手，再往深按 0.82 次方衰减（拉得越深越沉，像拽一个越来越重的东西）。
    /// 后台键 floorGravity：写 0 就是原来那种 1:1 跟手。
    private func heavyPull(_ d: CGFloat) -> CGFloat {
        let g = UIConfig.num("floorGravity", 1)
        if g <= 0 || d <= 60 { return d }
        let tail = max(0, d - 60)
        return 60 + CGFloat(pow(Double(tail), 0.82)) * 0.62 + tail * 0.38
    }
    @State private var path = NavigationPath()
    /// 点公众号那两条会话：直接开公众号页面
    @State private var oaOpenId = ""
    @State private var showOA = false
    @State private var showOAList = false
    @State private var plusMenu = false
    @State private var showScan = false
    /// 「收付款」（会话页右上「＋」→ 收付款；就是我 → 服务 → 收付款 那一页）
    @State private var showPayCode = false
    @State private var openRow: String?
    /// 「搜索」整页
    @State private var showSearch = false
    /// 点会话列表里机器人那几行的头像 → 弹它的名片
    @State private var botCardChat: Chat?
    /// 点左上角那两只眼睛 → 打开「小星」自己的对话页（元宝那种，不是普通聊天页）
    @State private var botChat: Chat?

    /// 顶栏小星那双眼睛的颜色：后台 ui.json 的 eyesColor 优先；
    /// 没配就跟右上角那个 ＋ 同色（navPlusBg）。两个键都在后台能改，不用出包。
    private var eyesTint: Color {
        UIConfig.colorIfSet("eyesColor") ?? UIConfig.color("navPlusBg", 0x0F5A3C, 0x0F5A3C)
    }

    private var list: [Chat] {
        /* 会话列表里点公众号那几条：**直接进公众号页面**，不是进聊天页
           （微信里服务号/订阅号点进去也是它们自己的页面） */
        /* 贾维斯从列表里拿掉（它改成左上角那只小脸，点脸进对话） */
        let base = app.chats.filter { $0.botRank != 0 }
        guard !keyword.isEmpty else { return base }
        return base.filter {
            $0.name.contains(keyword) || (($0.lastMessage?.preview ?? "").contains(keyword))
        }
    }

    /// 点一行会话：公众号的服务号 → 那一页；订阅号消息 → 公众号列表；其它 → 聊天页
    private func openRow(_ chat: Chat) {
        if let oa = chat.oaId, !oa.isEmpty {
            oaOpenId = oa
            showOA = true
        } else if chat.oaDigest == true {
            showOAList = true
        } else {
            path.append(chat)
        }
    }

    /// 和网页版一样：有未读时标题变成「微信(3)」
    private var navTitle: String {
        /* 离线：**学微信**——标题直接变成「星言（未连接）」，
           不再另外在页面上挂一条灰色横幅（横幅已经去掉了）。 */
        if app.offline {
            return Lang.isEnglish ? "\(C.tabText0) (No Connection)" : "\(C.tabText0)（未连接）"
        }
        let total = app.chats.reduce(0) { $0 + ($1.unread ?? 0) }
        /* 顶栏文字后台可改（tabTitle0），有未读时还是「文字(3)」 */
        return total > 0 ? "\(C.tabText0)(\(total))" : C.tabText0
    }

    /// 会话页顶栏那层「薄玻璃」（用户要的"透一丢丢"）
    /// 「二楼」露出来的那层（微信那层是"最近使用的小程序"）：先放四个最常用的入口，
    /// 压感提示（微信二楼那种）：1 个点 → 2 个点 → 3 个点，
    /// 每拉够一段点亮一个，颜色跟着由浅（半透明）到深（实心）；
    /// 点到第三个（= 后台 chatsFloorPull，默认 120pt）二楼页面才浮出来。
    private var pullDots: some View {
        let p = floorUp ? 100 : pullDown
        return HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                /* 三颗点按**当前阈值**三等分：阈值 120pt 时就是 40 / 80 / 120pt 各亮一个
                   （阈值是后台键 chatsFloorPull，调深了这几颗点也跟着走） */
                let step = floorPull * CGFloat(i + 1) / 3
                let lit = min(1, max(0, p / step))         // 这一颗的亮度（由浅到深）
                Circle()
                    .fill(C.label.opacity(0.18 + 0.72 * lit))
                    .frame(width: 7, height: 7)
                    .scaleEffect(0.72 + 0.28 * lit)
                    .animation(.easeOut(duration: 0.14), value: pullDown)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /* 二楼开 / 收那一下的动画。
       用户反馈「字还是会弹」—— 弹簧一直在这里：松手时用的是 dampingFraction 0.76，
       会过冲，整页（连同里面的字）都会回弹一下。
       后台 floorPopBounce 写 0 就换成**纯缓动**：一点回弹都没有（不是把弹簧调稳）。 */
    private var floorAnim: Animation {
        UIConfig.num("floorPopBounce", 1) > 0
            ? .spring(response: 0.52, dampingFraction: 0.76)
            : .easeOut(duration: 0.30)
    }

    /// 二楼现在露出多高（下拉跟着手指，箭头展开固定 150）
    private var floorReveal: CGFloat {
        /* 微信的二楼是**整页**：列表整块下去，二楼铺满全屏（不是顶栏下面一条） */
        let full = UIScreen.main.bounds.height
        /* 但**最底下要留一条**：露出会话列表最后一行 + 底栏（微信就是这么做的，
           截图里底上那条「微信（2233）」就是它），点那一条 / 往上滑就收起二楼。 */
        /* 用户要求：二楼下来是**盖住底栏**的（铺满整屏，连底部导航一起盖住）——
           底下只留一点点"两页叠在一起"的露出（在 miniFloor 里画那个小尖）。
           所以：开着的时候高度 = 整屏，底栏由 AppState.floorFull 收起来。 */
        let top = max(240, full)
        if floorUp { return top }
        if pullDown > 0.5 { return min(pullDown, top) }
        return 0
    }

    /// 名字/图标/动作以后都能挪到后台配置（和别的页面一样，改完不用出包）。
    @ViewBuilder private var miniFloor: some View {
        /* 「动感」：拉的这一路每块跟着手指**一块块长出来**（越靠下的越晚），
           松手停住的时候带一点**错开的弹簧**（一层层浮上来），不是整页一起硬切。 */
        let t: CGFloat = floorUp ? 1 : min(1, pullDown / max(1, floorPull))
        VStack(spacing: 10) {
            /* 整页版：顶上给状态栏 + 顶栏让出位置（内容不要钻到时间图标底下） */
            Color.clear.frame(height: floorUp ? L.safeTop + 8 : 0)
            /* 最近搜索（微信二楼第一行） */
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium))
                Text(Tr("最近搜索")).font(pf(15))
                Spacer(minLength: 0)
                Text("›").font(.system(size: 16))
            }
            .foregroundColor(C.subLabel)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture { showSearch = true }
            .modifier(FloorPop(up: floorUp, t: t, delay: 0.02))

            /* 最近使用的小程序（后台 miniApps 配的就是这几格） + 更多 › */
            HStack {
                Text(Tr("最近使用的小程序")).font(pf(12.5)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Text(Tr("更多") + " ›").font(pf(12.5)).foregroundColor(C.subLabel)
                    .onTapGesture { app.show(Tr("小程序列表下一步接后台")) }
            }
            .padding(.horizontal, 16)
            .modifier(FloorPop(up: floorUp, t: t, delay: 0.05))

            Text(Tr("点这里回到会话列表"))
                .font(pf(12)).foregroundColor(C.subLabel)
                .onTapGesture { withAnimation(floorAnim) { floorUp = false } }   // 点这一行收起二楼（微信也有这个手感）
                .modifier(FloorPop(up: floorUp, t: t, delay: 0.08))
            HStack(spacing: 0) {
                ForEach(miniApps.indices, id: \.self) { i in
                    let it = miniApps[i]
                    floorItem(it.1, it.2) { runMiniApp(it.0) }
                        .modifier(FloorPop(up: floorUp, t: t, delay: 0.10 + Double(i) * 0.045))
                }
            }
            Spacer(minLength: 0)
            /* 最底那一条：二楼底下露出被它顶下去的**会话列表开头**那一层
               （微信截图里是「微信（2233）」那一行）。
               用户要求：**二楼里不要出现「智信」这个标题**，所以这一条只留"一层页"的样子，
               不再写字；点一下照样收起二楼。 */
            Button {
                withAnimation(floorAnim) { floorUp = false }
            } label: {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                /* 参考图里那一条正好是 **80pt 高、文字居中** ——
                   而且它看着像"被二楼压着一层"：行底再罩一层淡紫（就是二楼那层烟透下来），
                   顶上加一道渐隐，让二楼和这一条连在一起（不是突然断开）。 */
                /* 「两页叠一起一点点」：这一条做成**从二楼底下露出来的一层页**——
                   上面两个角是圆的、比二楼收窄一点，看着就是底下还压着另一页。 */
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        C.chatsRowBg
                        Color(hex: 0x8E86C8).opacity(0.55)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 10)
                .shadow(color: .black.opacity(0.25), radius: 8, y: -3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(FloorPop(up: floorUp, t: t, delay: 0.24))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        /* 「烟雾感」= 照桌面 安全 文件夹那张参考图**量的颜色**做的三层：
           ① 底：上深下浅的深紫蓝渐变（图里量到 #1B1A2A → #2B283C → 上浅到 #322F44，
              这就是微信二楼背后那层"烟"）
           ② 一层很薄的磨砂：后面的会话列表透上来一点点（烟才像烟，不是一块色板）
           ③ 左上一团极淡的高光：烟在空中散开的那种不均匀 */
        .background(
            ZStack {
                /* 四个色标都能在后台调（改完重开 App 生效，不用出包）：
                   floorBg1 … floorBg4（写法 "#浅色|#深色"，不配就用内置这组）。
                   默认比原来那组**加深了一档**（用户要求：二楼背景再深一点）。 */
                LinearGradient(colors: [UIConfig.color("floorBg1", 0x121120, 0x121120),
                                        UIConfig.color("floorBg2", 0x181626, 0x181626),
                                        UIConfig.color("floorBg3", 0x1E1B2C, 0x1E1B2C),
                                        UIConfig.color("floorBg4", 0x242132, 0x242132)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.ultraThinMaterial)
                    .opacity(UIConfig.num("floorSmokeBlur", 0.35))
                RadialGradient(colors: [Color.white.opacity(UIConfig.num("floorSmokeGlow", 0.05)),
                                        Color.clear],
                               center: UnitPoint(x: 0.35, y: 0.12),
                               startRadius: 20, endRadius: 430)
                /* 会**流动**的烟（用户要求："后面没有烟雾效果流动"）——
                   四团很淡的雾各自慢慢飘，颜色/浓度/速度都能后台调：
                   floorSmokeColor（默认 8E86C8）、floorSmokeFlow（0.16）、floorSmokeSpeed（1） */
                FloorSmoke(color: Color(hexString: UIConfig.text("floorSmokeColor", "8E86C8"),
                                        fallback: 0x8E86C8),
                           intensity: UIConfig.num("floorSmokeFlow", 0.16),
                           speed: UIConfig.num("floorSmokeSpeed", 1))
                    .opacity(floorUp ? 1 : t)
            }
            /* 二楼是**全屏**的：顶上连状态栏那一条（时间 / 信号 / Wi-Fi）也要铺这层烟的颜色，
               不能让那里露出会话列表的底色。 */
            .ignoresSafeArea(edges: .top)
        )
        /* 二楼**顶上那条遮罩**：状态栏那一条压得最重、往下化开 ——
           微信二楼顶上也是这么压一条，内容就不会顶着时间/信号图标。
           浓度后台可调：floorTopMask（默认 0.42，写 0 就不要这条）。 */
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.black.opacity(UIConfig.num("floorTopMask", 0.42)),
                                    Color.black.opacity(0.14),
                                    Color.clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: L.safeTop + 46)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    private func floorItem(_ title: String, _ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(C.label)
                Text(Tr(title))
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 二楼那几格从后台配（ui.json 的 miniApps 一行一个：动作|名字|图标）；
    /// 没配就用内置这四格。动作支持：scan / pay / search / group（其它动作先忽略）。
    private var miniApps: [(String, String, String)] {
        let raw = UIConfig.text("miniApps", "")
        var out: [(String, String, String)] = []
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3, !parts[0].isEmpty {
                out.append((parts[0], parts[1], parts[2]))
            }
        }
        if out.isEmpty {
            return [("scan", "扫一扫", "qrcode.viewfinder"),
                    ("pay", "收付款", "creditcard"),
                    ("search", "搜一搜", "magnifyingglass"),
                    ("group", "发起群聊", "person.2.fill")]
        }
        return Array(out.prefix(4))
    }

    private func runMiniApp(_ action: String) {
        switch action {
        case "scan": showScan = true
        case "pay": showPayCode = true
        case "search": showSearch = true
        case "group": path.append("newGroup")
        default: app.show(Tr("这个入口还没接"))
        }
    }

    /// 微信那套：**不滚的时候顶栏和列表就是同一个底色（连在一起，没有分割线）**；
    /// 手指往上一滚，顶栏才慢慢浮起一层薄磨砂（列表从它后面穿过）。
    /// 滚了多少 = scrolled（列表顶上那根探针量的）。
    /// ⚠ 这里拆成两个键，别再合成一个：
    ///   · chatsNavGlassAlpha = **模糊（磨砂）**多强，默认 0.55；
    ///   · chatsNavMaskAlpha  = **遮罩底色**多实，默认 0.92 ——
    ///     以前只有一个键，用户把它调到 0.2（想更透）之后，一滚上来遮罩也没了，
    ///     正文直接压在标题上、糊成一片。现在遮罩单独一个键，透和看得清可以分开调。
    @ViewBuilder private func chatsNavGlass(_ scrolled: CGFloat) -> some View {
        let blur = UIConfig.num("chatsNavGlassAlpha", 1)
        let mask = UIConfig.num("chatsNavMaskAlpha", 0.25)
        /* 由浅到深：滚过 80pt 才完全浮出来，前段慢后段快 —— 拉的时候是渐变，不是"啪一下" */
        let raw = min(1, max(0, scrolled / 80))
        let t = pow(raw, 0.8)
        if t > 0.01 {
            /* ⚠ 微信顶栏的质感 = **iOS 系统栏材质**（`.bar`：模糊 + vibrancy，跟着系统外观自动换）：
                 · blur（chatsNavGlassAlpha）= 系统材质多实，默认 1
                 · mask（chatsNavMaskAlpha）= 上面那层染色压多浓，默认 0.25（一点点就好，压多了就成色板）
                 · 染色 = 后台「会话页顶栏遮罩颜色」，不配就跟页面底色一致 */
            ZStack {
                Rectangle().fill(.bar)
                    .opacity(max(0, min(1, blur)) * t)
                (UIConfig.colorIfSet("chatsNavMaskColor") ?? C.chatsPageBg)
                    .opacity(max(0, min(1, mask)) * t)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)      // 只是背景：绝不吃手势
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            /* 列表**整页铺满**（含顶栏底下）：滚动时会话会从顶栏那层薄玻璃后面滑过去 ——
               这就是用户要的那点「透」。顶栏最后画，永远压在最上面。
               （以前是 VStack：列表一定从顶栏下面开始，永远滚不到玻璃底下，所以看着像块实色板。） */
            ZStack(alignment: .top) {
                if app.chats.isEmpty {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: L.safeTop + L.navH)
                        emptyView
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            /* 顶上留出顶栏的高度：第一条会话还是从顶栏下面开始 */
                            /* 顶上留位：顶栏 + （二楼展开时）把列表**整体顶下去**，
                               让二楼占住让出来的那块 —— 微信就是这么连着的，不是盖在字上 */
                            Color.clear.frame(height: L.safeTop + L.navH + floorReveal)
                            ForEach(list) { chat in
                                SwipeChatRow(
                                    chat: chat,
                                    onOpen: { openRow(chat) },
                                    /* 只有真的机器人（botRank 0/1/2）点头像才弹「官方账号」名片；
                                       好友/群聊点头像跟整行一样进聊天（微信就是这样） */
                                    onTapAvatar: ((chat.botRank ?? 9) < 9) ? { botCardChat = chat } : nil,
                                    onUnread: { markUnread(chat) },
                                    onHide: { clear in hide(chat, clear: clear) },
                                    onDelete: { remove(chat) }
                                )
                            }
                        }
                        /* 探针：量列表滚了多少（顶栏那层磨砂/遮罩靠它淡入）。
                           ⚠ 以前这个探针挂在**第一行**上，一滚过第一行 LazyVStack 就把那一行回收，
                           探针没了 → 系统报回 0 → 遮罩以为"没滚"就收掉了（用户看到的
                           「过了第二行遮罩就没了」就是这个）。挂在整块内容上就不会被回收。 */
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ChatsScrollKey.self,
                                    value: -g.frame(in: .named("chatsScroll")).minY)
                            }
                        )
                    }
                    .coordinateSpace(name: "chatsScroll")
                    /* 二楼：直接用**拖动手势**驱动（simultaneous = 只观察、不抢滚动），
                       不再只依赖滚动探针 —— 手指在列表最上面往下拖就一定露出来，
                       而且是**跟着手指连着滑**（不是"空一块"）。 */
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { g in
                                guard scrolled < 8 else { return }      // 只有（基本）回到顶部才认这个下拉
                                let dy = g.translation.height
                                if floorOn, dy > 0 {
                                    pullDown = heavyPull(dy)
                                    /* 每点亮一颗提示点震一下（越往后越重，像压感） */
                                    let step = max(1, floorPull / 3)
                                    let lit = min(3, Int(dy / step))
                                    if lit != floorTick {
                                        floorTick = lit
                                        if lit > 0 {
                                            /* 用户要求"拉下来再加重"：前两颗 medium、第三颗 heavy */
                                            UIImpactFeedbackGenerator(style: lit >= 3 ? .heavy : .medium).impactOccurred()
                                        }
                                    }
                                } else if !floorUp {
                                    pullDown = 0
                                    floorTick = 0
                                }
                            }
                            .onEnded { g in
                                /* 弹簧 + 阻尼：拉过阈值就"吸"上去停在二楼（会有一点回弹），
                                   没拉够就软软地弹回去（不是硬切）。
                                   阈值由后台 chatsFloorPull 控制，默认 **120pt**
                                   （原来 70pt 太浅，用户反馈"二楼一直误触"）。 */
                                /* 防误触（用户反馈"还是会误触"）：
                                   ① 拉够阈值
                                   ② **松手时速度不快**（快速上滑蹭到顶部时 predictedEnd 冲得很远，
                                      这种是"滑到头弹一下"，不该开二楼）—— 只认慢慢拉过去的。 */
                                let fling = abs(g.predictedEndTranslation.height - g.translation.height)
                                let open = floorOn && pullDown > floorPull && fling < 220
                                /* 二楼下来那一下**振动加强**（用户要求）：heavy + 80ms 后再补一下 medium，
                                   摸着是"咚"的一下，比原来的 light 明显得多。 */
                                if open {
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    }
                                }
                                floorTick = 0
                                withAnimation(floorAnim) {
                                    floorUp = open
                                    pullDown = 0
                                }
                            }
                    )
                    .onPreferenceChange(ChatsScrollKey.self) { v in
                        let s = max(0, v)
                        /* 探针万一被回收/报 0，别把已经滚起来的顶栏遮罩又收回去 ——
                           只在「确实回到顶部」或「真的滚得更远」时才改 */
                        if s > scrolled || s < 1 {
                            if abs(s - scrolled) > 0.5 { scrolled = s }
                        }
                        /* 下拉的那一段（v 是负的）就是「二楼」露出来的高度：完全靠列表自己的
                           橡皮筋，不需要我们再挂一层手势，所以不会跟滚动抢手势。 */
                        let p = heavyPull(max(0, -v))
                        if abs(p - pullDown) > 0.5 { pullDown = p }
                        /* 二楼**只在松手那一下判断**（onEnded 里），不再拉到一半就自己弹出来 ——
                           之前"滑到头弹一下"也会被这里判定成开二楼，就是误触的主因。
                           阈值后台键：chatsFloorPull（现在 180pt）。 */
                        if s > 14, floorUp { floorUp = false }     // 往上滚 = 收起二楼
                    }
                    /* 列表不加底色，而且允许它滚到安全区（顶栏）底下 */
                    .ignoresSafeArea(edges: .top)
                    .background(Color.clear)
                    .refreshable { await app.loadChats() }
                }

                /* 顶栏固定不动 —— 画在列表上面（那层薄玻璃就是"透"的来源） */
                /* 「二楼」：往下拉的时候，顶栏下面让出来的那块空档里露出来的这层
                   （微信那层是"最近使用的小程序"）。它完全跟着**列表自己的下拉量**走，
                   不额外挂手势；只有拉出来超过 60pt 才接收点击，所以不会抢滚动/点击手势。 */
                if pullDown > 0.5 || floorUp {
                    ZStack(alignment: .top) {
                        /* 压感提示：**1 个点 → 2 个点 → 3 个点**，颜色跟着由浅到深；
                           点到第三个（≈72pt）二楼页面才浮出来 —— 微信二楼就是这种"越拉越实"的力度感。 */
                        VStack(spacing: 0) {
                            Spacer().frame(height: floorUp ? L.safeTop + 10 : 8)
                            pullDots
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(floorUp ? 0 : 1)

                        /* 拉到第三个点才看得到二楼页面（之前只有那几个点在提示力度） */
                        if floorUp || pullDown >= floorPull {
                            miniFloor
                                .frame(maxWidth: .infinity, alignment: .top)
                                /* 铺出来那一下：从顶上一路**放大 + 淡入**（更活一点） */
                                .transition(.opacity.combined(with: .scale(scale: 0.93, anchor: .top)))
                        }
                    }
                        .frame(height: floorReveal)
                        .frame(maxWidth: .infinity, alignment: .top)
                        /* 铺满全屏时从最顶上开始画（含状态栏那一条），不然就是顶栏下面一条 */
                        .padding(.top, floorUp ? 0 : L.safeTop + L.navH)
                        .clipped()
                        .allowsHitTesting(floorOn && (pullDown > floorPull * 0.6 || floorUp))
                        /* 二楼本身也是弹簧 + 阻尼地滑出来（不是一下跳出来） */
                        /* 弹簧**不带回弹**（damping 1.0）：二楼停住之后文字不会再抖一下 ——
                           0.70 那种会冲过目标再弹回来，字看着就在抖。 */
                        .animation(.spring(response: 0.42, dampingFraction: 1.0), value: floorUp)
                }

                VStack(spacing: 0) {
                    NavBar(title: navTitle,
                           /* 二楼拉开时，**顶栏那两块（小星眼睛 / 放大镜）不在二楼里显示**（用户要求） */
                           leftExtra: floorUp ? nil : AnyView(
                            /* 左边两块独立玻璃：小星眼睛 + 放大镜（放大镜就在眼睛右边） */
                            HStack(spacing: 8) {
                                Button {
                                    if let bot = app.chats.first(where: { $0.botRank == 0 }) {
                                        botChat = bot
                                    } else {
                                        Task { await app.loadChats()
                                            if let b = app.chats.first(where: { $0.botRank == 0 }) { botChat = b } }
                                    }
                                } label: {
                                    JarvisEyesAvatar(size: 28, tint: eyesTint)
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(.plain)

                                /* 放大镜：点开「搜索」整页（以前是列表最上面那个搜索框，现在收进这里） */
                                Button {
                                    showSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(C.label)
                                        .frame(width: 36, height: 36)
                                        .background { GlassBackground(shape: Circle(), shadow: true, seed: 0.40) }
                                }
                                .buttonStyle(.plain)

                            }
                            .padding(.leading, 4)
                           ),
                           /* 玻璃胶囊**保留**（标题/左下角那两块还是各自一块玻璃）；
                               「连着下面的会话页」是靠那层只在滚动时才浮起来的薄磨砂做的
                               （见 chatsNavGlass）—— 不滚的时候它和列表同一个底色，看着是一个整体。 */
                           floating: true,
                           leftExtraGlass: false) {
                        Button {
                            /* 弹出的手感：弹簧带动一点回弹（阻尼越小越弹） */
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { plusMenu = true }
                        } label: {
                            FlexIcon(custom: IconOverrides.custom("nav.plus"),
                                     size: UIConfig.num("navPlusSize", 20),
                                     color: UIConfig.color("navPlusInk", 0xFFFFFF, 0xFFFFFF),
                                     symbol: "plus")
                                .frame(width: UIConfig.num("navPlusW", 44),
                                       height: UIConfig.num("navPlusH", 36))
                                .background(Capsule(style: .continuous)
                                    .fill(UIConfig.color("navPlusBg", 0x0F5A3C, 0x0F5A3C)))
                        }
                        /* 点下去**亮一下 + 轻微缩小**，有"点到了"的手感（用户要求） */
                        .buttonStyle(NavPlusPressStyle())
                    }
                    /* 用户要求：会话页顶栏也要「一点玻璃透」——列表滚到顶栏下面时，
                       透过一层很薄的磨砂能看到一丢丢内容，而不是一块实色板。
                       浓淡后台可调（后台「界面配置 → 界面文字」里的 chatsNavGlassAlpha，
                       默认 0.55；写 0 退回原样）。 */
                    /* 顶栏背景：**先一层"挡点击"的透明层**（属于顶栏自己的背景，
                       所以小星眼睛/放大镜这些按钮永远画在它上面、照常能点），
                       再叠那层会浮出来的玻璃。后台开关 navBarSwallowTouch（默认 1 =
                       点顶栏空白处不会点到下面的会话行；写 0 恢复让路）。 */
                    .background {
                        ZStack {
                            if UIConfig.num("navBarSwallowTouch", 1) > 0 {
                                Color.clear
                                    .frame(height: L.navH)
                                    .contentShape(Rectangle())
                            }
                            chatsNavGlass(scrolled)
                        }
                    }
                    /* 那条细线**只在滚动以后**才出现（不滚时顶栏和列表是一个整体，微信就是这样） */
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(C.navLine).frame(height: 0.5)
                            .opacity(scrolled > 6 ? 1 : 0)
                    }
                    /* 用户要求：二楼里**不要出现「智信」这个标题和右边那个「＋」** ——
                       二楼是盖在列表上的，而顶栏是画在二楼**上面**的，所以这里得自己收掉：
                       二楼拉开时整条顶栏淡出 + 不再吃点击。 */
                    .opacity(floorUp ? 0 : 1)
                    .allowsHitTesting(!floorUp)
                    Spacer(minLength: 0)
                }
            }
            /* 第一页面（会话列表）的底色跟通讯录统一：都用后台的「页面底色」pageBg，
               以前这里用的是 navBg，深色下比通讯录浅一档（#18181A vs #0B0B0D）。 */
            .background(C.chatsPageBg.ignoresSafeArea(edges: .bottom))
            .sheet(isPresented: $showSearch) {
                SearchPage(onOpenChat: { c in path.append(c) })
                    .environmentObject(app)
            }
            .background(C.chatsPageBg.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            /* 返回列表这一下：**立刻**把底栏放出来。
               HidesTabBar 恢复底栏是挂在页面 onDisappear 上的，而 onDisappear 要等系统
               退场动画整段走完才触发 —— 底栏就"慢半拍才跳出来"（用户反馈的"返回后
               底部导航跳出来有延迟"）。导航栈回到根 = 一定在列表页，直接把层数清零，
               让底栏跟着返回动画一起滑上来；之后那些迟到的 onDisappear 再扣也只是减到 0。 */
            .onChange(of: path.count) { n in
                if n == 0 { app.tabBarDepth = 0 }
            }
            /* 二楼铺满全屏时**把底栏也盖住**（拉开时收起底栏，收起二楼时底栏自己回来）。
               ⚠ 这条必须挂在**外面这一层**：以前挂在二楼的子树里，二楼一收整棵子树就被移除，
               回调不触发 → floorFull 一直停在 true，底栏再也不回来了（用户反馈「底栏又没了」）。 */
            .onChange(of: floorUp) { v in
                withAnimation(.easeOut(duration: 0.2)) { app.floorFull = v }
            }
            .navigationDestination(for: Chat.self) { chat in
                ChatDetailView(chat: chat)
            }
            /* 公众号那两条会话：点进去是公众号页面（不是聊天页） */
            .navigationDestination(isPresented: $showOA) {
                OfficialAccountPage(accountId: oaOpenId)
            }
            .navigationDestination(isPresented: $showOAList) {
                OfficialAccountsView()
            }
            .navigationDestination(for: String.self) { key in
                if key == "newGroup" {
                    GroupCreateView { chat in
                        /* 建完群直接进这个群：走最外层整页打开，
                           不往导航栈里 push（push 在「刚 pop 掉建群页」那一下容易被系统丢掉，
                           表现就是「建完群没跳进去，要退出来重新点一下」）。 */
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { app.openChat = chat }
                    }
                } else if key == "addFriend" {
                    AddFriendView()
                } else if key == "myQR" {
                    MyQRView()
                } else {
                    ComingSoonView(title: key)
                }
            }
        }
        /* 右上角「＋」：下拉小卡片（毛玻璃 + 彩色图标），点别处收起 */
        .navPlusOverlay($plusMenu, items: [
            NavPlusItem(title: Tr("发起群聊"), symbol: "person.2.fill",
                        colors: [Color(hex: 0x3ED37F), Color(hex: 0x12A05A)]) { path.append("newGroup") },
            NavPlusItem(title: Tr("添加朋友"), symbol: "person.badge.plus",
                        colors: [Color(hex: 0x64B5F6), Color(hex: 0x2A6BC4)]) { path.append("addFriend") },
            NavPlusItem(title: Tr("扫一扫"), symbol: "qrcode.viewfinder",
                        colors: [Color(hex: 0xFFB627), Color(hex: 0xF08600)]) { showScan = true },
            NavPlusItem(title: Tr("收付款"), symbol: "creditcard.fill",
                        colors: [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)]) { showPayCode = true }
        ])
        /* 小星对话页：整页打开（点左上角那两只眼睛进来） */
        .fullScreenCover(item: $botChat) { c in
            BotChatView(chat: c).environmentObject(app)
        }
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .sheet(item: $botCardChat) { c in
            BotCardView(chat: c).environmentObject(app)
        }
        .sheet(isPresented: $showPayCode) {
            NavigationStack { PayCodePage() }
                .environmentObject(app)
        }
        .task {
            HitchWatch.shared.start("会话列表")
            // 进页面先拉一次，之后每 4 秒自动刷新一次（这样别人发消息不用切页就能看到）
            while !Task.isCancelled {
                await app.loadChats()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        /* 点推送通知进聊天：统一交给最外层的 MainTab 处理（它永远在线，
           在别的 tab 上点通知也能进得去；以前挂在会话页，人不在会话页就收不到）。 */
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(app.loadError ?? "正在加载会话…")
                .font(pf(14))
                .foregroundColor(C.subLabel)
            if app.loadError != nil {
                Button(Tr("重试")) { Task { await app.loadChats() } }
                    .font(pf(15))
                    .foregroundColor(C.green)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(C.chatsPageBg)
    }

    private func markUnread(_ chat: Chat) {
        Task {
            await API.shared.markUnread(chatId: chat.id)
            await app.loadChats()
            app.show(Tr("已标为未读"))
        }
    }

    private func hide(_ chat: Chat, clear: Bool) {
        Task {
            let err = clear
                ? await API.shared.deleteChat(chatId: chat.id)
                : await API.shared.hideChat(chatId: chat.id)
            await app.loadChats()
            app.show(err ?? (clear ? "已清空记录并设为不显示" : "已不显示该聊天"))
        }
    }

    private func remove(_ chat: Chat) {
        Task {
            let err = await API.shared.deleteChat(chatId: chat.id)
            await app.loadChats()
            app.show(err ?? "已删除")
        }
    }
}

/// 会话页 / 星联页右上角那个 ＋：按下去亮一下（像灯被按亮），松手回弹
/// 会话列表滚了多少（顶栏那层薄磨砂按它淡入）
private struct ChatsScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NavPlusPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            /* 用户要求：照 WhatsApp 那颗圆钮的手感 —— 按下去**中间一块特别亮**，
               光往外很快淡掉（不是整块一起泛白），中心再补一点过曝的白点。 */
            .overlay {
                ZStack {
                    RadialGradient(colors: [Color.white.opacity(0.95),
                                            Color.white.opacity(0.30),
                                            Color.white.opacity(0)],
                                   center: .center, startRadius: 0, endRadius: 34)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 16, height: 16)
                        .blur(radius: 7)
                }
                .blendMode(.plusLighter)
                .opacity(configuration.isPressed ? 1 : 0)
                .clipShape(Capsule(style: .continuous))
                .allowsHitTesting(false)
            }
            .brightness(configuration.isPressed ? 0.10 : 0)
            .shadow(color: Color.white.opacity(configuration.isPressed ? 0.5 : 0), radius: 10)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

/* ------------------------------------------------------------ 二楼的"动感" */

/// 二楼里每一块的入场动画：
/// · 拉的过程中跟着手指长出来（t = 下拉进度，0→1）
/// · 松手停住时（up = true）按 delay 错开弹一下 —— 越靠下的越晚，像一层层浮上来
/// 这样整页不是"一起硬切"，是有一点点层次和阻尼感的。
private struct FloorPop: ViewModifier {
    var up: Bool
    var t: CGFloat
    var delay: Double

    /// 「缩放弹出」的起手大小（后台键 floorPopScale，默认 0.88）
    private var popScale: CGFloat {
        max(0.5, min(1, UIConfig.num("floorPopScale", 0.88)))
    }
    /// 要不要那一点点过冲（后台键 floorPopBounce：写 0 = 原来那种最稳、不回弹的）
    private var bounce: Bool { UIConfig.num("floorPopBounce", 1) > 0 }

    func body(content: Content) -> some View {
        content
            .opacity(up ? 1 : 0.10 + 0.90 * t)
            /* 用户要的是「**缩放弹出**」：整块从 0.88 放大到正位（锚点在中间），
               带着一点点过冲的弹簧 —— 像从屏幕里弹出来，而不是页面那样滑出来。
               只改 scale（渲染层），不动布局，所以不会把文字抖移位（上次那个抖动是 offset 引起的）。 */
            .scaleEffect(up ? 1 : popScale + (1 - popScale) * t, anchor: .center)
            .offset(y: up ? 0 : (1 - t) * 18)
            .animation(bounce
                       ? .spring(response: 0.34, dampingFraction: 0.72).delay(delay)
                       /* 用户说「二楼出来不要有弹簧感」：后台 floorPopBounce 写 0 时走这条 ——
                          纯缓动、一点点回弹都没有（不是把弹簧调稳，是压根不用弹簧）。 */
                       : .easeOut(duration: 0.26).delay(delay),
                       value: up)
    }
}


