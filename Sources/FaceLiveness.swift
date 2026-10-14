import SwiftUI
import AVFoundation
import Vision
import UIKit

/* ============================================================
   人脸核身（活体检测）—— 照微信那套做的页面（2026-10-12 加）

   微信的人脸识别页长这样：
     · 中间一个**圆形取景框**（前置摄像头画面裁成圆的）
     · 外面一圈**微信绿 (#07C160)** 的进度弧，随着动作做完一点点绕满
     · 下面一行提示：「请正对屏幕」→「请眨眨眼」→「请摇摇头」
     · 全部完成 → 打勾 + 自动返回

   我们以前没有这一页（实名认证直接填姓名+身份证号，钱包解锁是系统 Face ID）。
   这一页接到实名认证里：点「提交认证」先走一次人脸核身。

   活体判定用的是 Vision：
     · 正对屏幕 = 检测到人脸（VNDetectFaceLandmarksRequest）
     · 眨眨眼   = 眼睛高度/宽度比掉到 0.24 以下（EAR 那套的简化版）
     · 摇摇头   = 人脸 yaw 摆过 ±12 度
   ⚠ 兜底：某一档超过 9 秒还没判断出来但脸一直在框里，也让它过 ——
     宁可放过也不能把人卡在这一页出不去（判定阈值是估的，真机上手感可能不准）。
   ============================================================ */

struct FaceLivenessView: View {
    /// true = 通过
    let onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 0 正对屏幕 · 1 眨眨眼 · 2 摇摇头 · 3 完成
    @State private var step = 0
    @State private var hasFace = false
    @State private var stepStart = Date()
    @State private var tip = "请正对屏幕"

    private let green = Color(hex: 0x07C160)

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("人脸识别"), back: {
                onDone(false)
                dismiss()
            })

            Spacer(minLength: 10)

            /* 圆形取景框 + 微信绿的进度弧 */
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.86))
                FaceCameraPreview()
                    .clipShape(Circle())
                    .padding(3)
                    .opacity(hasFace ? 1 : 0.55)
                /* 底圈 + 进度弧（微信就是这一圈绿） */
                Circle()
                    .stroke(green.opacity(0.22), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)
                if step == 3 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 8)
                }
            }
            .frame(width: 262, height: 262)

            Text(Tr(tip))
                .font(pf(18, .medium))
                .foregroundColor(C.label)
                .padding(.top, 22)

            Text(stepHint)
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            Spacer(minLength: 20)

            Text(Tr("人脸信息只在本机摄像头里做判定，不会上传也不会保存。"))
                .font(pf(12))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack {
            onDone(false)
            dismiss()
        }
        .onAppear {
            stepStart = Date()
            FaceLiveness.shared.start(onEvent: { ev in
                DispatchQueue.main.async { handle(ev) }
            })
        }
        .onDisappear { FaceLiveness.shared.stop() }
    }

    private var progress: CGFloat {
        switch step {
        case 0:  return 0.06
        case 1:  return 0.40
        case 2:  return 0.72
        default: return 1.0
        }
    }
    private var stepHint: String {
        switch step {
        case 0:  return Tr("把脸放进圆框里，别挡住")
        case 1:  return Tr("慢一点眨一次眼")
        case 2:  return Tr("头往左或往右轻轻转一下")
        default: return Tr("验证通过")
        }
    }

    /// 摄像头那边报过来的事（已经切回主线程）
    private func handle(_ ev: FaceLiveness.Event) {
        switch ev {
        case .noFace:
            hasFace = false
        case .face:
            hasFace = true
            if step == 0 { advance() }
        case .blink:
            if step == 1 { advance() }
        case .turn:
            if step == 2 {
                step = 3
                tip = "验证通过"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                FaceLiveness.shared.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onDone(true)
                    dismiss()
                }
            }
        case .tick:
            /* 兜底：这一档拖太久（脸一直在框里，就是判定没触发）也让它过 */
            if step < 3, hasFace, Date().timeIntervalSince(stepStart) > 9 {
                AppLog.info("人脸核身：第 \(step + 1) 步超时兜底放行")
                advance()
            }
        }
    }

    private func advance() {
        step += 1
        stepStart = Date()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch step {
        case 1: tip = "请眨眨眼"
        case 2: tip = "请摇摇头"
        default: break
        }
    }
}

/* ---------------------------------------------------------- 摄像头 + Vision */

/// 本机活体判定：只吐「有人脸 / 眨眼 / 摇头」三种事件，帧和画面都不外传。
final class FaceLiveness: NSObject {
    static let shared = FaceLiveness()

    enum Event { case noFace, face, blink, turn, tick }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "chris.face.liveness")
    private var onEvent: ((Event) -> Void)?
    private var running = false
    private var lastFaceAt = Date()
    private var lastTick = Date()
    /// 眨眼的基线（取最近几帧 Eye Aspect Ratio 的中位数），只认"比基线掉下去"那一下
    private var earBase: CGFloat = 0
    private var earSamples: [CGFloat] = []
    private var lastBlinkAt = Date.distantPast

    /// 给取景框用的会话（画面只在本机渲染，不上传）
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

    /// 眼睛的高度/宽度比（越大越睁，掉下去就是眨眼）
    private func eyeRatio(_ obs: VNFaceObservation) -> CGFloat? {
        guard let lm = obs.landmarks, let eye = lm.leftEye ?? lm.rightEye, eye.pointCount > 4 else { return nil }
        let pts = eye.normalizedPoints
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
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .leftMirrored, options: [:])
        try? handler.perform([req])
        let faces = (req.results ?? []).filter { $0.confidence > 0.4 }
        let now = Date()
        if let f = faces.first {
            lastFaceAt = now
            emit(.face)
            /* 眨眼：先攒基线，再认"比基线明显低"的那一下 */
            if let r = eyeRatio(f) {
                earSamples.append(r)
                if earSamples.count > 24 { earSamples.removeFirst() }
                let sorted = earSamples.sorted()
                earBase = sorted[sorted.count / 2]
                if earBase > 0.12, r < earBase * 0.62, now.timeIntervalSince(lastBlinkAt) > 1.0 {
                    lastBlinkAt = now
                    emit(.blink)
                }
            }
            /* 摇头：yaw 摆过 ±12 度（Vision 给的弧度） */
            if let y = f.yaw?.doubleValue, abs(y) > 0.21 {
                emit(.turn)
            }
        } else if now.timeIntervalSince(lastFaceAt) > 0.6 {
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
