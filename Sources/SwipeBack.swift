import SwiftUI
import UIKit

/* ============================================================
   左边缘右滑返回（和手机微信 / 系统那一套一样）

   2026-10-16 用户：「多个位置的返回左滑会出现误触到其他界面」。

   上一版是 SwiftUI 的 `.simultaneousGesture`（和内容"同时识别"）：
     · 手指从左边起滑时，**下面的行/列表也收到这一下** —— 滑的距离稍微短一点，
       松手时那一行就把这一下当成"点了一下"，于是推进了别的页面（用户说的"误触"）；
     · 而且每一页都挂了一份，遇到"一页里又盖着一页"的时候会**两边都响应**，
       一次返回退了两层 —— 落在哪一页就不对了。

   现在换成 UIKit 的做法（和系统边缘手势同款）：
     ① 整个窗口只装**一个** `UIPanGestureRecognizer`，由 `SwipeBackCenter` 统一管；
     ② 只有"最后进来的那一页"（栈顶）能响应 —— 不会再一次退两层；
     ③ `cancelsTouchesInView = true`：边缘这一下滑动**不会再传给孩子**，
        所以不会顺带点开一行、也不会把表情面板/翻页那种横滑带着一起动；
     ④ `shouldBegin` 里判方向：竖着滑（想滚列表）或者往左滑，一律不管，交给列表；
     ⑤ 没注册过 `swipeBack` 的页面完全不受影响（手势直接被拒收）。
   ============================================================ */

/// 一页的返回手势（由 `SwipeBackModifier` 创建、`SwipeBackCenter` 统一调度）
final class SwipeBackPage: ObservableObject {
    let id = UUID()
    var onBack: () -> Void = {}
    var enabled = true
    var width: CGFloat = 390
    /// 页面往右移出去的距离（0 = 原位）
    @Published var offset: CGFloat = 0
}

final class SwipeBackCenter: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackCenter()

    /// 注册进来的页面（**后进的在后面** —— 只有最后那个 = 栈顶能响应）
    private var pages: [SwipeBackPage] = []
    private weak var pan: UIPanGestureRecognizer?
    /// 这一下已经判定成"边缘返回"了吗
    private var tracking = false
    private var tracked: SwipeBackPage?

    /// 边缘判定：手指按在离屏幕左边 20pt 以内才算（和系统一样窄 ——
    /// 宽了会把列表最左边的按钮也吃掉）
    private let edge: CGFloat = 20

    func push(_ p: SwipeBackPage) {
        pages.removeAll { $0 === p }
        pages.append(p)
        installIfNeeded()
    }

    func remove(_ p: SwipeBackPage) {
        pages.removeAll { $0 === p }
        if tracked === p { tracked = nil; tracking = false }
        p.offset = 0
    }

    /// 现在该谁响应：最后一个 enabled 的页面
    private var top: SwipeBackPage? {
        for p in pages.reversed() where p.enabled { return p }
        return nil
    }

    private func installIfNeeded() {
        guard pan == nil else { return }
        guard let win = Self.keyWindow() else { return }
        let g = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        g.delegate = self
        /* ★ 关键的一条：这一下判定成边缘返回之后，孩子（行、按钮、翻页）
           就收不到这次触摸了 —— "误触到其他界面"就是从这儿堵死的。 */
        g.cancelsTouchesInView = true
        g.delaysTouchesBegan = false
        win.addGestureRecognizer(g)
        pan = g
    }

    static func keyWindow() -> UIWindow? {
        let all = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        /* 优先挑**普通层级**的那个主窗口：状态栏那一层（StatusBarStyle 建的那个
           windowLevel = .statusBar 的小窗口）不该挂手势 —— 挂上去等于手势永远失效。 */
        return all.first { $0.isKeyWindow && $0.windowLevel == .normal }
            ?? all.first { $0.isKeyWindow }
            ?? all.first { $0.windowLevel == .normal && !$0.isHidden }
    }

    /* ---------------- 手势 ---------------- */

    /// 只有"手指按在左边 20pt 以内"这一种触摸才接
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard top != nil else { return false }
        guard let v = g.view else { return false }
        return touch.location(in: v).x <= edge
    }

    /// 方向不对就别开始：竖着滑（滚列表）和往左滑都不算返回
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let p = top, let v = g.view, let pan = g as? UIPanGestureRecognizer else { return false }
        let vel = pan.velocity(in: v)
        guard vel.x > 0 else { return false }
        guard abs(vel.x) > abs(vel.y) * 1.1 else { return false }
        tracked = p
        return true
    }

    /* ⚠ 2026-10-16 用户：「朋友圈没有左滑返回」。
       病根就是这一句以前写的 false：朋友圈那一页自己挂了两个**整页级**的
       DragGesture（下拉刷新那颗彩球，minimumDistance 只有 6）—— 它们 6pt 就先认出来了，
       而这里声明"我不跟别人同时识别"，于是我们的边缘手势被判输、这一下根本收不到
       （其它页面没有整页手势，所以只有朋友圈不灵）。
       现在改成 true：允许同时识别 —— 只要我们这边一开始（左边缘 + 横向右滑），
       `cancelsTouchesInView` 会立刻把别人那一下掐掉，不会两边一起动。 */
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handle(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        let t = g.translation(in: v)
        switch g.state {
        case .began:
            tracking = true
            tracked?.offset = max(0, t.x)
        case .changed:
            guard tracking, let p = tracked else { return }
            /* 跟手：**逐帧直接赋值**，不加动画（和微信一样） */
            p.offset = max(0, t.x)
        case .ended:
            guard tracking, let p = tracked else { return }
            tracking = false
            tracked = nil
            let far = p.offset > p.width * 0.28
            let fast = g.velocity(in: v).x > p.width * 1.1
            if far || fast {
                withAnimation(.easeOut(duration: 0.2)) { p.offset = p.width }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    if p.offset > 0 { p.onBack() }
                    p.offset = 0
                }
            } else {
                withAnimation(.easeOut(duration: 0.22)) { p.offset = 0 }
            }
        default:
            /* 被取消 / 失败：收回原位，不触发返回 */
            tracking = false
            if let p = tracked { withAnimation(.easeOut(duration: 0.2)) { p.offset = 0 } }
            tracked = nil
        }
    }
}

struct SwipeBackModifier: ViewModifier {
    let enabled: Bool
    let onBack: () -> Void

    @StateObject private var page = SwipeBackPage()

    private var width: CGFloat { max(1, L.width) }

    func body(content: Content) -> some View {
        ZStack {
            content
                .offset(x: page.offset)
                .overlay(
                    Color.black
                        .opacity(0.16 * Double(min(1, page.offset / width)))
                        .allowsHitTesting(false)
                )
        }
        .background(C.pageBg)
        .onAppear {
            page.onBack = onBack
            page.width = width
            page.enabled = enabled
            SwipeBackCenter.shared.push(page)
        }
        .onDisappear { SwipeBackCenter.shared.remove(page) }
        .onChange(of: enabled) { v in page.enabled = v }
        .onChange(of: width) { w in page.width = w }
    }
}

extension View {
    /// 左边缘右滑返回（和手机微信一样）
    func swipeBack(_ enabled: Bool = true, onBack: @escaping () -> Void) -> some View {
        modifier(SwipeBackModifier(enabled: enabled, onBack: onBack))
    }
}
