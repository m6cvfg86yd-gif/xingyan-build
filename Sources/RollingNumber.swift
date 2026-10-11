import SwiftUI

/* ============================================================
   自绘的「数字滚动」（用户选的 A 方案）

   ⚠ 刻意**不用**系统的 `contentTransition(.numericText())`，也**不给视图挂**
   `.animation(_, value:)` —— 那两套在 iOS 26 上和会话页顶栏那颗"一直在跑的
   机器人眼镜动画"打架，会把主线程拖死、被系统杀掉（B149 / B166 就是这样把
   「点聊天」搞闪退的，日志里没有任何崩溃栈）。

   这里只有：两张 Text（旧值 / 新值）＋ 纯位移 ＋ 换值那一刻的一次 withAnimation，
   外面 `clipped()` 裁掉溢出。效果和微信一样：旧的往上移出去、新的从下面进来。
   ============================================================ */

struct RollingNumber: View {
    let value: Int
    var font: Font = .system(size: 17, weight: .semibold)
    var color: Color = C.label
    /// 一行的高度（比字号略大一点就行）
    var lineH: CGFloat = 21

    @State private var shown: Int = 0
    @State private var old: Int = 0
    /// 1 = 静止（只显示 shown）；0 = 刚换成新值，正在往上推
    @State private var settle: CGFloat = 1
    @State private var ready = false

    var body: some View {
        ZStack {
            if settle < 1 {
                Text("\(old)")
                    .font(font).foregroundColor(color)
                    .offset(y: -lineH * (1 - settle))
            }
            Text("\(value)")
                .font(font).foregroundColor(color)
                .offset(y: (1 - settle) * lineH)
        }
        .frame(height: lineH)
        .clipped()
        .onAppear {
            guard !ready else { return }
            ready = true
            shown = value
            old = value
        }
        .onChange(of: value) { v in
            guard ready else { return }
            old = shown
            shown = v
            settle = 0
            /* 只有这一次带动画：不挂在视图上，不会和别的动画打架 */
            withAnimation(.easeOut(duration: 0.22)) { settle = 1 }
        }
    }
}

