import SwiftUI

/* ============================================================
   聊天页「先占位、后渲染」的外罩 —— 2026-10-13

   为什么需要它（这次终于定性了）：
     ChatDetailView 是个**超大视图**，第一次求值（body → 布局 → 提交首帧）在慢一点的机器上
     可能要十几秒。而「点会话进聊天」属于系统的**场景更新（页面切换）**，那一小段时间有
     **看门狗**盯着：超时就直接 SIGKILL 掉进程。
     于是日志里永远只有「聊天页 8 准备打开 …」，没有「9 页面出现」，没有崩溃栈，
     内存也不大（App 40~50MB、系统还剩 6GB）—— 历史上「改一点就挂、退回去就好」，
     就是因为这点余量太薄：任何让首帧稍微重一点点的改动都会越线。

   办法（不动聊天页本身）：
     push 的时候先只渲染一个**很轻的占位**（一步就画完，切换动画稳稳过掉），
     等 0.4 秒过渡结束，再把真正的大视图塞进去 —— 那时看门狗那一段已经过去了。
     ⚠ 聊天页那个文件保持 B218 原样（一字不差），这里只是在它外面套一层。
   ============================================================ */

struct DeferredChatView: View {
    let chat: Chat
    @State private var ready = false

    var body: some View {
        ZStack {
            C.pageBg.ignoresSafeArea()
            if ready {
                ChatDetailView(chat: chat)
                    .transition(.opacity)
            } else {
                /* 占位：只有一个转圈 —— 这一步几乎不花时间，先把页面切换这一下让过去 */
                VStack(spacing: 10) {
                    ProgressView()
                    Text(chat.name)
                        .font(pf(15))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                        .padding(.horizontal, 30)
                }
            }
        }
        .task {
            guard !ready else { return }
            /* 0.4 秒：足够让 push 的转场动画走完（系统那一段看门狗就是盯这个） */
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeOut(duration: 0.18)) { ready = true }
        }
    }
}
