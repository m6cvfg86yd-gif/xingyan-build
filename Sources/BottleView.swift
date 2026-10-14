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
    /// 瓶子现在在干什么：0 = 漂着，1 = 扔出去，2 = 捞上来（BottleSea 按这个画动画）
    @State private var fx = 0
    /// 这次动作是什么时候开始的（算动画进度用）
    @State private var fxAt = Date()

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
                /* 海 + 会浮沉的瓶子（都在 Canvas 里按时间画，见下面的 BottleSea）：
                   ① 四层正弦海浪一直往两边推；② 瓶子浮在上面轻轻上下、左右晃；
                   ③ 扔出去 / 捞上来时瓶子会抛物线飞出去、或者从水里浮起来，并溅出涟漪。 */
                BottleSea(mode: fx, actionAt: fxAt)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
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
            /* 打点：页面真的被打开了、海里有几个瓶子 —— 用户报「漂流瓶没有东西」时，
               先看服务器日志里有没有这一条，就知道是「没进到这一页」还是「接口没通」。 */
            AppLog.error("漂流瓶", "打开页面，海里数量=" + String(total))
        }
        .sheet(isPresented: $showThrow) {
            ThrowBottleSheet { t in
                /* 先放**扔出去**的动画（瓶子划一道抛物线入水、溅一圈涟漪），
                   动画走完再真正发请求 —— 用户先看到"扔"这个动作，而不是干等接口。 */
                fxAt = Date()
                fx = 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 900_000_000)
                let ok = await API.shared.throwBottle(text: t)
                if ok {
                    total += 1
                    emptyNote = ""
                    app.show(Tr("瓶子已经扔进海里"))
                }
                fx = 0
                return ok
            }
            .environmentObject(app)
        }
    }

    private func pick() async {
        picking = true
        emptyNote = ""
        picked = nil
        /* 捞：瓶子先从水里**浮上来**（带一圈涟漪），再出纸条 */
        fxAt = Date()
        fx = 2
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let r = await API.shared.pickBottle()
        try? await Task.sleep(nanoseconds: 500_000_000)
        fx = 0
        total = r.total
        netOK = total > 0 || r.bottle != nil
        picking = false
        if let b = r.bottle {
            AppLog.error("漂流瓶", "捞到了 " + b.id + "（海里 " + String(total) + " 个）")
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { picked = b }
        } else {
            AppLog.error("漂流瓶", "捞到空的（total=" + String(total) + "，netOK=" + (netOK ? "1" : "0") + "）")
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
/* ---------------------------------------------------------------
   会动的海 + 会浮沉的瓶子（用户 2026-10-13：「漂流瓶还是没动画」）

   全部在 Canvas 里按时间画，不吃视图层数：
     · 四层正弦海浪：不同振幅、不同速度、不同透明度，左右反向推着走
     · 瓶子：玻璃身 + 瓶颈 + 木塞 + 高光，自己画（比 SF Symbol 那颗水滴像）
     · 漂着的时候：上下浮沉 + 轻轻左右晃
     · 扔出去（mode 1）：沿抛物线飞出去、翻滚，落水那一下溅一圈涟漪
     · 捞上来（mode 2）：先沉下去一点，再浮起来，同时一圈涟漪散开
   --------------------------------------------------------------- */
struct BottleSea: View {
    /// 0 = 漂着，1 = 扔出去，2 = 捞上来
    var mode: Int
    /// 这次动作的开始时间（算进度）
    var actionAt: Date

    @State private var ripples: [Date] = []

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    var body: some View {
        TimelineView(.animation) { ctx in
            let now = ctx.date
            let t = now.timeIntervalSinceReferenceDate
            Canvas { g, size in
                drawSea(&g, size, t)
                drawRipples(&g, size, now)
                drawBottle(&g, size, t, now)
            }
        }
        /* 动作一开始就记一条涟漪（扔出去是入水那一下，捞上来是浮出来那一下） */
        .onChange(of: actionAt) { _ in
            ripples.append(Date())
            if ripples.count > 6 { ripples.removeFirst(ripples.count - 6) }
        }
    }

    /* ---------- 海 ---------- */
    private func drawSea(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        /* 底：上浅下深的天蓝 → 深蓝 */
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [Color(hex: 0x2E7BD6),
                                                       Color(hex: 0x0E3F7A),
                                                       Color(hex: 0x062038)]),
                                     startPoint: .zero,
                                     endPoint: CGPoint(x: 0, y: size.height)))
        /* 四层浪：越往下越深、越慢，左右交替推 */
        for layer in 0..<4 {
            let l = Double(layer)
            let amp = 5.0 + l * 4.5
            let speed = (0.34 + l * 0.20) * (layer % 2 == 0 ? 1 : -1)
            let yBase = Double(size.height) * (0.40 + l * 0.10)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: yBase))
            var x: CGFloat = 0
            while x <= size.width {
                let xd = Double(x)
                let y = yBase
                    + sin(xd / 92.0 + t * speed + l) * amp
                    + sin(xd / 37.0 - t * speed * 1.5) * amp * 0.42
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
            g.fill(path, with: .color(Color(hex: 0x0E3F7A)
                .opacity(0.30 + l * 0.16)))
        }
    }

    /* ---------- 涟漪 ---------- */
    private func drawRipples(_ g: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let cx = size.width / 2
        let cy = size.height * 0.66
        for r in ripples {
            let age = now.timeIntervalSince(r)
            guard age >= 0, age < 2.0 else { continue }
            let p = age / 2.0
            for k in 0..<2 {                       // 两圈，错开一点
                let pk = clamp01((p - Double(k) * 0.18) / (1 - 0.18 * Double(k)))
                let w = 40 + pk * 165
                let rect = CGRect(x: cx - w, y: cy - w * 0.30, width: w * 2, height: w * 0.60)
                g.stroke(Path(ellipseIn: rect),
                         with: .color(Color.white.opacity((1 - pk) * 0.34)),
                         lineWidth: 1.4)
            }
        }
    }

    /* ---------- 瓶子 ---------- */
    private func drawBottle(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double, _ now: Date) {
        /* 水位线附近的浮点 + 一点随波起伏 */
        let baseX = size.width / 2
        let baseY = size.height * 0.60

        var dx: Double = sin(t * 0.62) * 10                 // 左右轻晃
        var dy: Double = sin(t * 0.95) * 7                  // 上下浮沉
        var rot: Double = sin(t * 0.72) * 7                 // 轻微倾斜
        var alpha: Double = 1

        if mode == 1 {                                      // 扔出去：抛物线 + 翻滚
            let p = clamp01(now.timeIntervalSince(actionAt) / 0.95)
            dx += p * 46
            dy -= sin(p * Double.pi) * 148
            rot += p * 540
            alpha = 1 - clamp01((p - 0.72) / 0.28) * 0.85   // 最后没入水里
        } else if mode == 2 {                               // 捞上来：先沉后浮
            let p = clamp01(now.timeIntervalSince(actionAt) / 0.9)
            dy += (1 - p) * 40
            rot += (1 - p) * -14
            alpha = 0.35 + p * 0.65
        }

        var ctx = g
        ctx.translateBy(x: baseX + dx, y: baseY + dy)
        ctx.rotate(by: .degrees(rot))
        ctx.opacity = alpha

        let w: CGFloat = 52, h: CGFloat = 108
        let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        /* 瓶身（玻璃） */
        let bodyPath = Path(roundedRect: body, cornerRadius: 17, style: .continuous)
        ctx.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.34), Color(hex: 0xBEE7FF).opacity(0.22)]),
            startPoint: CGPoint(x: body.minX, y: body.minY),
            endPoint: CGPoint(x: body.maxX, y: body.maxY)))
        ctx.stroke(bodyPath, with: .color(Color.white.opacity(0.55)), lineWidth: 1.6)
        /* 瓶颈 + 木塞 */
        let neck = CGRect(x: -7, y: -h / 2 - 16, width: 14, height: 20)
        ctx.fill(Path(roundedRect: neck, cornerRadius: 4, style: .continuous),
                 with: .color(Color.white.opacity(0.42)))
        let cork = CGRect(x: -9, y: -h / 2 - 26, width: 18, height: 12)
        ctx.fill(Path(roundedRect: cork, cornerRadius: 3, style: .continuous),
                 with: .color(Color(hex: 0xC08A4B)))
        /* 里面的纸条 */
        let paper = CGRect(x: -13, y: -6, width: 26, height: 40)
        ctx.fill(Path(roundedRect: paper, cornerRadius: 4, style: .continuous),
                 with: .color(Color(hex: 0xF7F1DE).opacity(0.92)))
        /* 高光 */
        let shine = CGRect(x: -w / 2 + 9, y: -h / 2 + 14, width: 8, height: 46)
        ctx.fill(Path(roundedRect: shine, cornerRadius: 4, style: .continuous),
                 with: .color(Color.white.opacity(0.55)))
    }
}

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
