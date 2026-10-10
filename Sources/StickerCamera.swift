import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import Vision

/* ============================================================
   拍摄表情（微信那个）

   · **单独一个小相机**（全屏），不是直接调系统相机 —— 用户要求
   · 底下有一排「特效」，是**实时**加在取景画面上的（微信里也是边看边换）
   · 拍下来自动把背景抠掉（苹果 Vision 的前景分割，iOS 17+），
     和微信表情一样只留人；我们的上传是 JPEG（没有透明通道），
     所以抠完**铺一层白底**，看着就是微信那种"白底表情"
   · 拍完可以「重拍」或者「使用」，「使用」交回调用方（上传 + 加进我添加的表情）
   ============================================================ */

/// 特效（实时滤镜）：名字 + CIFilter 的名字（空 = 原图）
let stickerEffects: [(String, String)] = [
    ("原图", ""),
    ("清透", "CIPhotoEffectProcess"),
    ("暖阳", "CIPhotoEffectTransfer"),
    ("冷调", "CIPhotoEffectFade"),
    ("黑白", "CIPhotoEffectMono"),
    ("复古", "CIPhotoEffectInstant"),
    ("浓烈", "CIPhotoEffectChrome"),
    ("胶片", "CIPhotoEffectNoir")
]

/// 小相机的采集/滤镜/抠图这一层（SwiftUI 外面那层只是壳）
final class StickerCam: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "sticker.cam.queue")
    private let ctx = CIContext(options: nil)

    /// 实时预览（已经过特效这一层）
    @Published var frame: UIImage?
    /// 没有摄像头 / 权限被拒
    @Published var denied = false
    /// 当前特效序号（切换时下一帧就变）
    var effect = 0

    private var lastCI: CIImage?
    private var started = false
    private var rendering = false

    func start() {
        guard !started else { return }
        started = true
        queue.async { [weak self] in self?.configure() }
    }

    func stop() {
        started = false
        queue.async { [weak self] in
            guard let s = self?.session else { return }
            if s.isRunning { s.stopRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        guard let dev = front ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.denied = true }
            return
        }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) {
            session.addOutput(out)
            if let conn = out.connection(with: .video) {
                /* 竖屏 + 前置镜像（自拍要跟镜子一样，微信也是这样） */
                if #available(iOS 17.0, *) {
                    if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                } else {
                    conn.videoOrientation = .portrait
                }
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = (dev.position == .front) }
            }
        }
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var img = CIImage(cvPixelBuffer: buf)
        let name = stickerEffects[min(max(0, effect), stickerEffects.count - 1)].1
        if !name.isEmpty { img = img.applyingFilter(name) }
        lastCI = img
        guard !rendering else { return }
        rendering = true
        let ui = render(img)
        DispatchQueue.main.async {
            if let ui { self.frame = ui }
            self.rendering = false
        }
    }

    /// 拍一张：取**当前这一帧**（带特效），裁成正方形
    func snapshot() -> UIImage? {
        guard let ci = lastCI else { return nil }
        return render(cropSquare(ci))
    }

    /// 把背景抠掉（微信拍摄表情那样只留人）：
    /// iOS 17 起苹果有现成的前景分割；不支持或失败就原图返回。
    /// 抠完铺白底 —— 上传是 JPEG，没有透明通道，白底看着就是微信那种表情。
    func cutout(_ image: UIImage) -> UIImage {
        guard #available(iOS 17.0, *), let cg = image.cgImage else { return image }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([req])) != nil,
              let res = req.results?.first,
              let mask = try? res.generateScaledMaskForImage(forInstances: res.allInstances, from: handler),
              let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        let base = CIImage(cgImage: cg)
        blend.setValue(base, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .white).cropped(to: base.extent),
                       forKey: kCIInputBackgroundImageKey)
        blend.setValue(CIImage(cvPixelBuffer: mask), forKey: kCIInputMaskImageKey)
        guard let out = blend.outputImage,
              let cgOut = ctx.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: cgOut)
    }

    private func cropSquare(_ img: CIImage) -> CIImage {
        let e = img.extent
        let side = min(e.width, e.height)
        let rect = CGRect(x: e.midX - side / 2, y: e.midY - side / 2, width: side, height: side)
        return img.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private func render(_ img: CIImage) -> UIImage? {
        guard let cg = ctx.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/* ============================================================ 界面 */

struct StickerCamera: View {
    /// 拍好（抠完）交回去：调用方负责上传 + 加进「我添加的表情」
    var onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = StickerCam()
    @State private var effect = 0
    @State private var shot: UIImage?
    @State private var busy = false
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let shot {
                Image(uiImage: shot)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if cam.denied {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.7))
                    Text(Tr("打不开相机，去系统设置里给星言开一下相机权限"))
                        .font(pf(14))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                StickerPreview(cam: cam)
                    .ignoresSafeArea()
            }

            /* 白闪一下（微信按快门那一下也有） */
            if flash {
                Color.white.opacity(0.85).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Button { cam.stop(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(Tr("拍摄表情"))
                        .font(pf(16, .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 34, height: 34)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Spacer()

                if shot == nil {
                    effectRow
                    shutterRow
                } else {
                    HStack(spacing: 12) {
                        Button { withAnimation(.easeOut(duration: 0.15)) { shot = nil } } label: {
                            Text(Tr("重拍"))
                                .font(pf(15, .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        Button {
                            if let s = shot { onDone(s) }
                            cam.stop()
                            dismiss()
                        } label: {
                            Text(Tr("使用"))
                                .font(pf(15, .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
    }

    /// 下面那排「特效」：点一下实时换
    private var effectRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stickerEffects.indices, id: \.self) { i in
                    Button {
                        effect = i
                        cam.effect = i
                    } label: {
                        Text(Tr(stickerEffects[i].0))
                            .font(pf(13, effect == i ? .semibold : .regular))
                            .foregroundColor(effect == i ? .black : .white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(effect == i
                                                       ? Color.white
                                                       : Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 14)
    }

    /// 快门：一颗大圆钮（微信也是这个位置）
    private var shutterRow: some View {
        HStack {
            Spacer()
            Button { shoot() } label: {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle().fill(Color.white)
                        .frame(width: 58, height: 58)
                    if busy { ProgressView().tint(.black) }
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
            Spacer()
        }
        .padding(.bottom, 26)
    }

    private func shoot() {
        guard !busy, let img = cam.snapshot() else { return }
        busy = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeIn(duration: 0.12)) { flash = false }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let out = cam.cutout(img)
            DispatchQueue.main.async {
                shot = out
                busy = false
            }
        }
    }
}

/// 只观察预览这一帧的子视图：30fps 刷新只重画它，不动整页
private struct StickerPreview: View {
    @ObservedObject var cam: StickerCam
    var body: some View {
        GeometryReader { g in
            if let f = cam.frame {
                Image(uiImage: f)
                    .resizable()
                    .scaledToFill()
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            } else {
                Color.black
            }
        }
    }
}
