import SwiftUI
import AVFoundation
import Vision
import UIKit

/* ============================================================
   人脸核身（活体检测）—— 2026-10-15 按用户要求重做

   用户原话：「实名认证的人脸识别做的有点假，我要微信那种摇一摇转一转要真实的，
             并且是真实人脸捕捉」
   → 这一版做了两件关键事：
     ① **真实人脸捕捉**：前置摄像头（AVCaptureSession）出帧，每一帧都用 Vision
        （VNDetectFaceLandmarksRequest）在**本机**找人脸、量五官 —— 画面不上传、不保存。
     ② **真的要做动作才算过**：随机抽 3 个动作（眨眨眼 / 张张嘴 / 摇摇头 / 点点头），
        每一个都必须真的做到那一下才进下一档。
        ⚠ 旧版有个「9 秒没判断出来也放行」的兜底 —— 那个会让人干站着也能过（就是"假"的来源），
          这一版**删掉了**：超时只会重来这一档，绝不偷偷放行；
          多张脸 / 离太远 / 挡住 都会拦着不让过。

   页面照微信：中间圆形取景框 + 一圈微信绿进度弧 + 下面一行「请眨眨眼」这种提示 +
   做完打勾自动返回。
   ============================================================ */

/// 要用户做的动作
enum FaceAction: CaseIterable {
    case blink      // 眨眨眼
    case mouth      // 张张嘴
    case shake      // 摇摇头（左右都要甩到）
    case nod        // 点点头

    var title: String {
        switch self {
        case .blink: return "请眨眨眼"
        case .mouth: return "请张张嘴"
        case .shake: return "请摇摇头"
        case .nod:   return "请点点头"
        }
    }
    var hint: String {
        switch self {
        case .blink: return "慢慢眨一次眼，别挡住眼睛"
        case .mouth: return "嘴张开一点点就行"
        case .shake: return "头往左、再往右，轻轻摇一下"
        case .nod:   return "头往下、再抬起来，点一下头"
        }
    }
    var icon: String {
        switch self {
        case .blink: return "eye"
        case .mouth: return "mouth"
        case .shake: return "arrow.left.and.right"
        case .nod:   return "arrow.up.and.down"
        }
    }
}

struct FaceLivenessView: View {
    /// true = 通过
    let onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 这一次要做的三个动作（第一个固定眨眼，另外两个随机）
    @State private var plan: [FaceAction] = []
    @State private var idx = 0
    @State private var hasFace = false
    @State private var tooMany = false
    @State private var tooFar = false
    @State private var hint = ""
    /// 只在「脸在框里」的时候累加，超时就重来这一档
    @State private var stall = 0
    @State private var yawMin = 0.0
    @State private var yawMax = 0.0
    @State private var pitchMin = 0.0
    @State private var pitchMax = 0.0
    @State private var done = false

    private let green = Color(hex: 0x07C160)

    private var cur: FaceAction? { idx < plan.count ? plan[idx] : nil }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("人脸识别"), back: {
                FaceLiveness.shared.stop()
                onDone(false)
                dismiss()
            })

            Spacer(minLength: 8)

            /* 圆形取景框 + 微信绿进度弧 */
            ZStack {
                Circle().fill(Color.black.opacity(0.88))
                FaceCameraPreview()
                    .clipShape(Circle())
                    .padding(3)
                    .opacity(hasFace && !tooMany ? 1 : 0.5)
                Circle().stroke(green.opacity(0.22), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: progress)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 8)
                } else if let a = cur {
                    Image(systemName: a.icon)
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.white.opacity(hasFace ? 0.95 : 0.5))
                        .offset(y: 96)
                }
            }
            .frame(width: 262, height: 262)

            Text(Tr(title))
                .font(pf(18, .medium))
                .foregroundColor(C.label)
                .padding(.top, 22)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Text(Tr(subTitle))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            /* 做动作的小图标条：做完一档变绿 */
            HStack(spacing: 10) {
                ForEach(Array(plan.enumerated()), id: \.offset) { i, a in
                    Image(systemName: i < idx ? "checkmark.circle.fill" : a.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(i < idx ? green : C.subLabel.opacity(0.5))
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 16)

            Text(Tr("人脸信息只在这台手机的摄像头里做判定，不会上传也不会保存。"))
                .font(pf(12))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack {
            FaceLiveness.shared.stop()
            onDone(false)
            dismiss()
        }
        .onAppear {
            if plan.isEmpty {
                /* 第一个固定眨眼（最容易做），另外两个随机 —— 每次进来动作都不一样 */
                let others = FaceAction.allCases.filter { $0 != .blink }.shuffled()
                plan = [.blink] + others.prefix(2)
            }
            stall = 0
            FaceLiveness.shared.start { ev in
                DispatchQueue.main.async { handle(ev) }
            }
        }
        .onDisappear { FaceLiveness.shared.stop() }
    }

    /* ---------------- 文案 / 进度 ---------------- */

    private var title: String {
        if done { return "验证通过" }
        if tooMany { return "画面里只能有一个人" }
        if !hasFace { return "请把脸放进圆框里" }
        if tooFar { return "靠近一点" }
        return cur?.title ?? "请正对屏幕"
    }

    private var subTitle: String {
        if done { return "" }
        if tooMany { return "把旁边的人移出画面，或者找一个安静的地方" }
        if !hasFace { return "光线亮一点、别挡住脸" }
        if tooFar { return "脸再靠近一点，占满中间这个框" }
        if !hint.isEmpty { return hint }
        return cur?.hint ?? ""
    }

    private var progress: CGFloat {
        guard !plan.isEmpty else { return 0.04 }
        if done { return 1 }
        return max(0.04, CGFloat(idx) / CGFloat(plan.count))
    }

    /* ---------------- 事件（都在主线程） ---------------- */

    private func handle(_ ev: FaceLiveness.Event) {
        switch ev {
        case .noFace:
            hasFace = false
            tooFar = false
        case .multi:
            tooMany = true
        case .face(let h):
            tooMany = false
            hasFace = true
            tooFar = h < 0.30           // 脸太小 = 离太远，先让他靠近
        case .blink:
            if cur == .blink, hasFace, !tooFar { advance() }
        case .mouth:
            if cur == .mouth, hasFace, !tooFar { advance() }
        case .yaw(let y):
            guard cur == .shake, hasFace, !tooFar else { return }
            yawMin = min(yawMin, y); yawMax = max(yawMax, y)
            /* 左右都真的甩到了才算（只往一边转不算「摇头」） */
            if yawMax > 0.17, yawMin < -0.17, yawMax - yawMin > 0.45 { advance() }
        case .pitch(let p):
            guard cur == .nod, hasFace, !tooFar else { return }
            pitchMin = min(pitchMin, p); pitchMax = max(pitchMax, p)
            if pitchMax > 0.12, pitchMin < -0.12, pitchMax - pitchMin > 0.30 { advance() }
        case .tick:
            /* ⚠ 只在「脸在框里」的时候计时；超时 = **重来这一档**，绝不放行 */
            guard hasFace, !tooMany, !done else { return }
            stall += 1
            if stall == 4 { hint = "没看清，再来一次" }
            if stall >= 12 {
                resetStep()
                hint = "这次没看清：照着提示再做一次"
            }
        }
    }

    private func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        idx += 1
        resetStep()
        if idx >= plan.count {
            done = true
            FaceLiveness.shared.stop()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                onDone(true)
                dismiss()
            }
        }
    }

    private func resetStep() {
        stall = 0
        hint = ""
        yawMin = 0; yawMax = 0
        pitchMin = 0; pitchMax = 0
    }
}

/* ---------------------------------------------------------- 摄像头 + Vision */

/// 本机活体判定：只往外吐「有没有脸 / 眨眼 / 张嘴 / yaw / pitch」，
/// 画面和每一帧都留在本机（不上传、不落盘）。
final class FaceLiveness: NSObject {
    static let shared = FaceLiveness()

    enum Event {
        case noFace
        case multi
        /// 脸在画面里占多高（0~1，越大越近）
        case face(CGFloat)
        case blink
        case mouth
        /// 左右转头（弧度，正负是两边）
        case yaw(Double)
        /// 上下点头（弧度）
        case pitch(Double)
        /// 半秒一次的心跳（界面用它算「这一档拖了多久」）
        case tick
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "chris.face.liveness")
    private var onEvent: ((Event) -> Void)?
    private var running = false
    private var lastFaceAt = Date()
    private var lastTick = Date()
    private var lastBlinkAt = Date.distantPast
    private var lastMouthAt = Date.distantPast
    private var lastMultiAt = Date.distantPast
    /// 眼睛开合基线 + 「闭过一下没有」（眨眼要求闭上再睁开）
    private var earSamples: [CGFloat] = []
    private var earClosed = false

    var captureSession: AVCaptureSession { session }

    func start(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        guard !running else { return }
        running = true
        queue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if self.session.inputs.isEmpty,
               let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: dev),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.outputs.isEmpty, self.session.canAddOutput(out) {
                self.session.addOutput(out)
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        onEvent = nil
        guard running else { return }
        running = false
        queue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func emit(_ ev: Event) { onEvent?(ev) }

    /// 眼睛的高度 / 宽度比（越大越睁着）
    private func eyeRatio(_ obs: VNFaceObservation) -> CGFloat? {
        guard let lm = obs.landmarks, let eye = lm.leftEye ?? lm.rightEye, eye.pointCount > 4 else { return nil }
        let pts = eye.normalizedPoints
        let xs = pts.map { CGFloat($0.x) }, ys = pts.map { CGFloat($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX
        guard w > 0.0001 else { return nil }
        return (maxY - minY) / w
    }

    /// 嘴张开程度：内唇的高度 / 宽度（闭着嘴很小，张嘴明显变大）
    private func mouthOpen(_ obs: VNFaceObservation) -> CGFloat? {
        guard let lm = obs.landmarks, let m = (lm.innerLips ?? lm.outerLips), m.pointCount > 3 else { return nil }
        let pts = m.normalizedPoints
        let xs = pts.map { CGFloat($0.x) }, ys = pts.map { CGFloat($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX
        guard w > 0.0001 else { return nil }
        return (maxY - minY) / w
    }
}

extension FaceLiveness: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard running, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNDetectFaceLandmarksRequest()
        /* 前置摄像头：画面是镜像的，喂给 Vision 也要按 leftMirrored 转 */
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .leftMirrored, options: [:])
        try? handler.perform([req])
        let faces = (req.results ?? []).filter { $0.confidence > 0.4 }
        let now = Date()

        if faces.count > 1 {
            if now.timeIntervalSince(lastMultiAt) > 0.5 {
                lastMultiAt = now
                emit(.multi)
            }
            return
        }

        if let f = faces.first {
            lastFaceAt = now
            emit(.face(CGFloat(f.boundingBox.height)))

            /* 眨眼：先攒「睁着眼」的基线，闭到 60% 以下、再睁回来 → 记一次眨完 */
            if let r = eyeRatio(f) {
                if !earClosed {
                    earSamples.append(r)
                    if earSamples.count > 30 { earSamples.removeFirst() }
                }
                let sorted = earSamples.sorted()
                let base = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                if base > 0.10 {
                    if !earClosed, r < base * 0.62 {
                        earClosed = true
                    } else if earClosed, r > base * 0.85 {
                        earClosed = false
                        if now.timeIntervalSince(lastBlinkAt) > 0.8 {
                            lastBlinkAt = now
                            emit(.blink)
                        }
                    }
                }
            }
            /* 张嘴 */
            if let mo = mouthOpen(f), mo > 0.30, now.timeIntervalSince(lastMouthAt) > 1.0 {
                lastMouthAt = now
                emit(.mouth)
            }
            /* 转头 / 点头：弧度直接报出去，判断交给界面（每一档要求不一样） */
            if let y = f.yaw?.doubleValue { emit(.yaw(y)) }
            if let p = f.pitch?.doubleValue { emit(.pitch(p)) }
        } else if now.timeIntervalSince(lastFaceAt) > 0.5 {
            emit(.noFace)
        }

        if now.timeIntervalSince(lastTick) > 0.5 {
            lastTick = now
            emit(.tick)
        }
    }
}

/// 圆形取景框里的摄像头画面（和扫一扫那套一个做法：UIView + previewLayer）
struct FaceCameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = FaceLiveness.shared.captureSession
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { }
}
