import SwiftUI

/* ============================================================
   漂流瓶（2026-10-12 用户：「摇一摇改成漂流瓶」）

   微信当年的「漂流瓶」：扔一个（写一句话丢进海里）/ 捞一个（随机捞别人的瓶子）。
   现在我们把它做成发现页那一行（服务端 discover.json 里 d05 已改名为「漂流瓶」、
   action = bottle，App 里点进去就是这一页；老的 shake 也走这里）。

   服务器接口：POST /api/bottle/throw {text} / POST /api/bottle/pick / GET /api/bottle/count
   数据在服务器 data/bottles.json（最多 500 个，同一个瓶子不会被同一个人重复捞到）。
   ============================================================ */

struct BottlePageView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var total = 0
    @State private var showThrow = false
    @State private var picking = false
    @State private var picked: API.APIBottle?
    @State private var emptyNote = ""
    @State private var flip = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("漂流瓶"), back: { dismiss() }) {
                Button { showThrow = true } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 40, height: 32)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                /* 海：上面天蓝、下面深蓝，一条一条很淡的波纹 */
                LinearGradient(colors: [Color(hex: 0x2E7BD6), Color(hex: 0x0E3F7A), Color(hex: 0x072748)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: i % 2 == 0 ? 10 : 6)
                            .padding(.horizontal, CGFloat(20 + i * 12))
                            .padding(.top, CGFloat(18 + i * 8))
                    }
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    /* 瓶子的图形：用 SF Symbol 里最像的那个（捞的时候晃一下） */
                    Image(systemName: "drop.fill")
                        .font(.system(size: 76, weight: .light))
                        .foregroundColor(.white.opacity(0.92))
                        .rotationEffect(.degrees(flip ? 12 : -12))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        .padding(.bottom, 18)

                    Text(picked == nil
                         ? (emptyNote.isEmpty ? Tr("海里漂着 ") + String(total) + Tr(" 个瓶子") : emptyNote)
                         : Tr("捞到一个瓶子"))
                        .font(pf(15))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    if let b = picked {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(b.text)
                                .font(pf(16))
                                .foregroundColor(C.label)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 6) {
                                Text((b.fromName ?? "").isEmpty ? Tr("一个陌生人") : (b.fromName ?? ""))
                                    .font(pf(12.5)).foregroundColor(C.subLabel)
                                Spacer(minLength: 0)
                                Text(shortTime(b.at ?? "")).font(pf(12)).foregroundColor(C.subLabel)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.96)))
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        Button { showThrow = true } label: {
                            Text(Tr("扔一个"))
                                .font(pf(16, .medium)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.18)))
                                .overlay(RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Button { Task { await pick() } } label: {
                            HStack(spacing: 6) {
                                if picking { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text(picking ? Tr("正在捞…") : Tr("捞一个"))
                            }
                            .font(pf(16, .medium)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 24).fill(Color(hex: 0x1F8FF0)))
                        }
                        .buttonStyle(.plain)
                        .disabled(picking)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(26, L.safeBottom + 14))
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            total = await API.shared.bottleCount()
            netOK = total > 0        // 数量拉到了 = 接口是通的（0 也可能是真空海，看下面捞一次的结果）
            /* 瓶子图形轻轻晃着（不晃也不影响用） */
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { flip = true }
        }
        .sheet(isPresented: $showThrow) {
            ThrowBottleSheet { t in
                if await API.shared.throwBottle(text: t) {
                    total += 1
                    emptyNote = ""
                    app.show(Tr("瓶子已经扔进海里"))
                    return true
                }
                return false
            }
            .environmentObject(app)
        }
    }

    private func pick() async {
        picking = true
        emptyNote = ""
        picked = nil
        withAnimation(.easeOut(duration: 0.2)) { }
        let r = await API.shared.pickBottle()
        total = r.total
        netOK = total > 0 || r.bottle != nil
        picking = false
        if let b = r.bottle {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { picked = b }
        } else {
            /* 分两种情况：① 服务器说海里真没有（empty）② 请求本身失败了 ——
               以前一律显示「海里没有瓶子」，用户根本看不出是断网 / 服务器没这个口。 */
            if total == 0 && !netOK {
                emptyNote = Tr("连不上服务器（捞不出来）—— 检查一下网络，或稍后再试")
            } else {
                emptyNote = Tr("海里暂时没有别人的瓶子，先扔一个吧")
            }
        }
    }

    /// 这一页最近一次请求到底通没通（通了才敢说「海里没瓶子」）
    @State private var netOK = false

    private func shortTime(_ at: String) -> String {
        /* 服务器给的是 ISO 时间；只显示 月-日 时:分，解析不了就原样 */
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: at) else { return "" }
        let o = DateFormatter()
        o.dateFormat = "MM-dd HH:mm"
        return o.string(from: d)
    }
}

/* ---------------------------------------------------------- 扔一个 */

struct ThrowBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onThrow: (String) async -> Bool

    @State private var text = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("扔一个漂流瓶"), back: { dismiss() }) {
                Button {
                    Task {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        busy = true
                        let ok = await onThrow(t)
                        busy = false
                        if ok { dismiss() }
                    }
                } label: {
                    Text(busy ? Tr("发送中…") : Tr("扔出去"))
                        .font(pf(16, .medium)).foregroundColor(C.green)
                        .frame(height: 32).padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .font(pf(16))
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                HStack {
                    Text(Tr("说点什么，扔进海里，等陌生人捞到"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                    Text(String(text.count) + "/200").font(pf(12))
                        .foregroundColor(text.count > 200 ? C.red : C.subLabel)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.cardBg))
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(C.pageBg.ignoresSafeArea())
        .onChange(of: text) { v in if v.count > 200 { text = String(v.prefix(200)) } }
    }
}
