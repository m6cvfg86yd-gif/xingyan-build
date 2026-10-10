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

/// 一个特效：filter = 调色滤镜（CIFilter 名，空 = 不调色）；
/// face   = 人脸特效（会跟着脸动的贴纸：ears / crown / glasses / hearts / blush / sparkle）
struct StickerFx: Identifiable, Hashable {
    var id: String
    var name: String
    var filter: String = ""
    /// 滤镜参数（像素/点彩这类要"多大一格"）：0 = 用系统默认
    var scale: Double = 0
    var face: String = ""
    /// 是不是「人脸特效」那一类（界面分两个 tab 用）
    var isFace: Bool { !face.isEmpty }
}

/// 特效清单。第 0 项永远是「无特效」（照微信：无特效 / 特效 两个 tab）。
let stickerFxList: [StickerFx] = [
    StickerFx(id: "none", name: "无特效"),
    /* ---- 人脸特效（会跟着脸动，微信那种） ---- */
    StickerFx(id: "ears",    name: "猫耳朵", face: "ears"),
    StickerFx(id: "crown",   name: "皇冠",   face: "crown"),
    StickerFx(id: "glasses", name: "墨镜",   face: "glasses"),
    StickerFx(id: "hearts",  name: "爱心眼", face: "hearts"),
    StickerFx(id: "blush",   name: "腮红",   face: "blush"),
    StickerFx(id: "sparkle", name: "闪光",   face: "sparkle"),
    /* ---- 调色滤镜（顺手留着的，微信那页没有，我们当附赠） ---- */
    StickerFx(id: "clear",  name: "清透", filter: "CIPhotoEffectProcess"),
    StickerFx(id: "mono",   name: "黑白", filter: "CIPhotoEffectMono"),
    StickerFx(id: "retro",  name: "复古", filter: "CIPhotoEffectInstant"),
    StickerFx(id: "comic",  name: "漫画", filter: "CIComicEffect"),
    StickerFx(id: "sepia",  name: "怀旧", filter: "CISepiaTone"),
    /* ---- 像素风（用户要的「像素」）：整幅画面打成马赛克/像素块 ---- */
    StickerFx(id: "pixel",     name: "像素",     filter: "CIPixellate",           scale: 12),
    StickerFx(id: "pixelBig",  name: "大像素",   filter: "CIPixellate",           scale: 30),
    StickerFx(id: "hexPixel",  name: "六边像素", filter: "CIHexagonalPixellate",  scale: 16),
    StickerFx(id: "dots",      name: "点彩",     filter: "CIPointillize",         scale: 10)
]

/// 套一层特效：带 scale 的（像素/点彩）要把参数一起传进去，不然是系统默认那一档
func stickerApply(_ img: CIImage, _ fx: StickerFx) -> CIImage {
    guard !fx.filter.isEmpty else { return img }
    if fx.scale > 0 {
        /* 点彩那个滤镜的参数叫 radius，其它（像素/六边像素）叫 scale */
        let key = (fx.filter == "CIPointillize") ? kCIInputRadiusKey : kCIInputScaleKey
        return img.applyingFilter(fx.filter, parameters: [key: fx.scale])
    }
    return img.applyingFilter(fx.filter)
}

/// 「特效来自：××」那一行（微信写的是 WeChat Effect）
let stickerEffectSource = "星言 Effect"

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
    var fxIndex = 0
    /// 人脸框：**归一化、左上角为原点**（和 UIKit 画图一个方向）；没检到就是 nil。
    /// 只在相机那条队列里用（界面用的是 faceOverlay 那张图），所以不用 @Published。
    private var faceBox: CGRect?
    /// 人脸特效那一层（透明图，和取景画面同比例）—— 预览时直接盖在画面上
    @Published var faceOverlay: UIImage?
    /// 现在用的是不是前置（微信那一页右下角可以前后切）
    private(set) var usingFront = true

    private var lastCI: CIImage?
    private var started = false
    private var rendering = false
    private var frameNo = 0
    /* 这一帧要不要转 90°/180° 才"正"。
       ⚠ 不同机型 / 系统版本上，采集连接给的旋转是不一样的（iOS 17 的
       videoRotationAngle 和老的 videoOrientation 行为也有差别），照着一个写死的
       角度走，轻则取景像躺着的（用户说的「感觉镜头是错的」），重则 Vision 认不出脸
       （「拍不到人」）。所以这里**自己找一个能认到脸的方向**并记住：
       下面 detectOriented() 会依次试几个方向，谁认得到脸就用谁。 */
    private var fix: CGImagePropertyOrientation = .right

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

    /// 前后摄像头切换（微信「拍摄表情」右下角那颗）
    func flip() {
        usingFront.toggle()
        /* 换了镜头：上一颗镜头的人脸框不算数了，清掉让它重新找一个能认到脸的方向 */
        faceBox = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.commitConfiguration()
            self.configure()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let want: AVCaptureDevice.Position = usingFront ? .front : .back
        let pick = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: want)
        guard let dev = pick ?? AVCaptureDevice.default(for: .video),
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
        let raw = CIImage(cvPixelBuffer: buf)

        /* ① 先把这一帧"转正"：人脸检测顺便当成方向探针（见 detectOriented） */
        frameNo += 1
        var img = oriented(raw, fix)
        if frameNo % 4 == 1 {
            if let r = detectOriented(raw) {
                fix = r.fix
                faceBox = r.box
            } else {
                faceBox = nil
            }
            img = oriented(raw, fix)
        }

        let fx = stickerFxList[min(max(0, fxIndex), stickerFxList.count - 1)]
        img = stickerApply(img, fx)
        if fx.isFace {
            let before = faceBox
            var moved = false
            if let a = faceBox, let b = before {
                moved = abs(a.minX - b.minX) > 0.01 || abs(a.minY - b.minY) > 0.01 || abs(a.width - b.width) > 0.01
            } else if (faceBox == nil) != (before == nil) {
                moved = true
            }
            if moved || faceOverlay == nil {
                let over = makeFaceOverlay(fx.face, frameSize: img.extent.size)
                DispatchQueue.main.async { self.faceOverlay = over }
            }
        }
        if !fx.isFace, faceOverlay != nil {
            DispatchQueue.main.async { self.faceOverlay = nil }
        }
        lastCI = img
        guard !rendering else { return }
        rendering = true
        let ui = render(img)
        DispatchQueue.main.async {
            if let ui { self.frame = ui }
            self.rendering = false
        }
    }

    /// 拍一张：取**当前这一帧**（带滤镜），裁成正方形，再把**人脸特效**画上去
    func snapshot() -> UIImage? {
        guard let ci = lastCI, let base = render(cropSquare(ci)) else { return nil }
        let fx = stickerFxList[min(max(0, fxIndex), stickerFxList.count - 1)]
        guard fx.isFace, let over = faceOverlay, over.size.width > 1 else { return base }
        /* 那一层是按「整幅取景画面」的比例画的，这里按**实际裁剪的那块**把它对到方图里。
           ⚠ 以前这里按"居中裁"算偏移，但裁的时候是**以脸为中心**裁的 ——
           于是存下来的表情贴纸会歪到一边（脸在中间、耳朵跑到头上）。 */
        let rect = cropRect(ci)
        let side = rect.width
        let cropX = rect.minX
        let cropY = ci.extent.height - rect.maxY          // CI 是左下原点 → 换算成"离顶边多少"
        let s = ci.extent.width / over.size.width
        let r = UIGraphicsImageRenderer(size: base.size)
        return r.image { c in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            over.draw(in: CGRect(x: -cropX / s, y: -cropY / s, width: side / s, height: side / s))
        }
    }

    /* ---------------- 人脸特效：检测 + 画那一层 ---------------- */

    /// 按 EXIF 方向转一下（.up 就是原样）
    private func oriented(_ img: CIImage, _ o: CGImagePropertyOrientation) -> CIImage {
        o == .up ? img : img.oriented(o)
    }

    /// 这一帧该转哪个方向才对？**拿人脸当探针**：
    /// 先试上次记住的那个方向；没认到脸就把另外几个方向也挨个试一遍
    /// （只在这帧上试、而且缩到 480 再检，很快）。谁认到脸就用谁并记下来。
    /// 一个方向都认不到（屋里没人 / 太暗）：保住上次记住的方向。
    private func detectOriented(_ raw: CIImage) -> (box: CGRect, fix: CGImagePropertyOrientation)? {
        var seen = Set<UInt32>()
        let all: [CGImagePropertyOrientation] = [fix, .up, .right, .left, .down].filter { o in
            if seen.contains(o.rawValue) { return false }
            seen.insert(o.rawValue)
            return true
        }
        /* 已经认到过人：只走记住的那个方向（省性能）；还没认到过：多试几个 */
        let tries: [CGImagePropertyOrientation] = faceBox == nil ? all : [fix]
        for o in tries {
            if let box = faceBoxIn(oriented(raw, o)) { return (box, o) }
        }
        return nil
    }

    /// 找人脸（Vision）：结果框是「左下角为原点」的归一化坐标，
    /// 这里立刻转成**左上角为原点**（UIKit 画图那个方向），后面画贴纸就不用再翻来翻去。
    private func faceBoxIn(_ img: CIImage) -> CGRect? {
        /* 缩到 480 再检：只要归一化坐标，缩放不影响结果，但快很多 */
        let e = img.extent
        let long = max(e.width, e.height)
        var probe = img
        if long > 640 { probe = img.transformed(by: CGAffineTransform(scaleX: 480 / long, y: 480 / long)) }
        let req = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: probe, orientation: .up, options: [:])
        guard (try? handler.perform([req])) != nil, let f = req.results?.first else { return nil }
        let b = f.boundingBox
        return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
    }

    /// 画人脸特效那一层（小一号画，省性能；反正预览和方图都会等比缩放）
    private func makeFaceOverlay(_ kind: String, frameSize: CGSize) -> UIImage? {
        guard let box = faceBox, frameSize.width > 1, frameSize.height > 1 else { return nil }
        let long = max(frameSize.width, frameSize.height)
        let s = min(1, 480 / long)
        let size = CGSize(width: frameSize.width * s, height: frameSize.height * s)
        let rect = CGRect(x: box.minX * size.width, y: box.minY * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { c in
            drawStickerFace(kind, rect, c.cgContext)
        }
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

    /// 要裁的那块正方形：**检到脸就以脸为中心**（竖屏自拍的脸偏上，
    /// 按正中裁经常把整张脸切掉 —— 用户说的"拍不到人"），没检到就居中。
    private func cropRect(_ img: CIImage) -> CGRect {
        let e = img.extent
        let side = min(e.width, e.height)
        var x = e.midX - side / 2
        var y = e.midY - side / 2
        if let b = faceBox {
            let cx = e.minX + b.midX * e.width
            /* faceBox 是「左上角为原点」，CI 这张图是「左下角为原点」，y 要翻一下 */
            let cy = e.maxY - b.midY * e.height
            x = cx - side / 2
            y = cy - side / 2
        }
        x = min(max(e.minX, x), e.maxX - side)
        y = min(max(e.minY, y), e.maxY - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private func cropSquare(_ img: CIImage) -> CIImage {
        let rect = cropRect(img)
        return img.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private func render(_ img: CIImage) -> UIImage? {
        guard let cg = ctx.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/* ============================================================ 界面 */

struct StickerCamera: View {
    // 说明见文件末尾的两个小工具
    /// 拍好（抠完）交回去：调用方负责上传 + 加进「我添加的表情」
    var onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = StickerCam()
    /// 当前选中的特效（下标进 stickerFxList；0 = 无特效）
    @State private var fx = 0
    /// 上面那两个 tab：0 = 无特效，1 = 特效（照微信那一页）
    @State private var fxTab = 0
    @State private var shot: UIImage?
    @State private var busy = false
    @State private var flash = false
    /// 从相册选一张当表情
    @State private var showAlbum = false

    /// 现在选中的那一条
    private var fxNow: StickerFx { stickerFxList[min(max(0, fx), stickerFxList.count - 1)] }

    var body: some View {
        /* 微信「拍摄表情」的样子：**一小块相机窗口**（不是全屏取景）——
           上面标题 + 提示，中间那块小相机，下面特效 tab + 那排特效，
           最底下相册 / 快门 / 前后翻转。 */
        GeometryReader { geo in
            let camW = min(geo.size.width - 96, 250)
            let camH = camW * 4 / 3

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                HStack {
                    Button { cam.stop(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.12)))
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

                /* 微信那句提示就挂在标题下面 */
                if shot == nil {
                    Text(Tr("表情将会上传保存，在其他设备也可查看"))
                        .font(pf(12.5))
                        .foregroundColor(.white.opacity(0.62))
                        .padding(.top, 6)
                }

                Spacer(minLength: 10)

                /* ---- 一小块相机窗口 ---- */
                ZStack {
                    if let shot {
                        Image(uiImage: shot)
                            .resizable()
                            .scaledToFill()
                    } else if cam.denied {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                            Text(Tr("打不开相机，去系统设置里给星言开一下相机权限"))
                                .font(pf(12.5))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18)
                        }
                    } else {
                        StickerPreview(cam: cam)
                    }
                }
                .frame(width: camW, height: camH)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1))

                Spacer(minLength: 10)

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

                /* 白闪一下（微信按快门那一下也有） */
                if flash {
                    Color.white.opacity(0.85).ignoresSafeArea()
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
        .sheet(isPresented: $showAlbum) {
            PhotoPicker { img in
                /* 相册来的图：裁成正方形 + 套当前那层调色（不抠背景，人家选的就是想要的图）。
                   选完还是走「重拍 / 使用」这一步，和拍的一样。 */
                let sq = stickerSquare(img)
                let fxPick = fxNow
                DispatchQueue.global(qos: .userInitiated).async {
                    let out = stickerEffect(sq, fxPick)
                    DispatchQueue.main.async { shot = out }
                }
            }
        }
    }

    /// 下面那排「特效」：点一下实时换
    private var effectRow: some View {
        VStack(spacing: 8) {
            /* 照微信：左边两个 tab「无特效 / 特效」 */
            HStack(spacing: 8) {
                tabChip(Tr("无特效"), 0)
                tabChip(Tr("特效"), 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let list = fxTab == 0 ? Array(stickerFxList.prefix(1)) : Array(stickerFxList.dropFirst())
                    ForEach(list) { item in
                        let i = stickerFxList.firstIndex(of: item) ?? 0
                        Button {
                            fx = i
                            cam.fxIndex = i
                        } label: {
                            Text(Tr(item.name))
                                .font(pf(13, fx == i ? .semibold : .regular))
                                .foregroundColor(fx == i ? .black : .white)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(fx == i
                                                           ? Color.white
                                                           : Color.white.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            /* 微信那一行小字：「特效来自：WeChat Effect」——我们写自己的名字 */
            HStack(spacing: 6) {
                Text(Tr("特效来自：") + stickerEffectSource)
                    .font(pf(11.5))
                    .foregroundColor(.white.opacity(0.62))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    /// 「无特效 / 特效」那颗小胶囊
    private func tabChip(_ title: String, _ idx: Int) -> some View {
        Button {
            fxTab = idx
            if idx == 0 {
                fx = 0
                cam.fxIndex = 0
            } else if fx == 0 {
                fx = 1
                cam.fxIndex = 1
            }
        } label: {
            Text(title)
                .font(pf(12.5, fxTab == idx ? .semibold : .regular))
                .foregroundColor(fxTab == idx ? .white : .white.opacity(0.65))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(Capsule().fill(fxTab == idx
                                           ? Color.white.opacity(0.28)
                                           : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    /// 快门：一颗大圆钮（微信也是这个位置）
    private var shutterRow: some View {
        HStack(spacing: 0) {
            /* 左边：从相册选一张当表情（微信这一格就是相册） */
            Button { showAlbum = true } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

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

            /* 右边：前后摄像头切换 */
            Button { cam.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
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

/* ---------- 两个小工具（相册选图那条路用） ---------- */

/* ---------- 人脸特效怎么画（f = 人脸框，坐标跟 g 一致；左上角为原点） ---------- */

/// 一颗爱心（用于「爱心眼」）
private func stickerHeart(_ r: CGRect, _ g: CGContext) {
    let w = r.width, h = r.height
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.midX, y: r.maxY))
    p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.32),
               control1: CGPoint(x: r.midX - w * 0.58, y: r.maxY - h * 0.28),
               control2: CGPoint(x: r.minX, y: r.midY))
    p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.30),
               control1: CGPoint(x: r.minX + w * 0.16, y: r.minY - h * 0.06),
               control2: CGPoint(x: r.midX - w * 0.18, y: r.minY))
    p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.32),
               control1: CGPoint(x: r.midX + w * 0.18, y: r.minY),
               control2: CGPoint(x: r.maxX - w * 0.16, y: r.minY - h * 0.06))
    p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
               control1: CGPoint(x: r.maxX, y: r.midY),
               control2: CGPoint(x: r.midX + w * 0.58, y: r.maxY - h * 0.28))
    p.closeSubpath()
    g.addPath(p)
    g.fillPath()
}

/// 一颗四角星（用于「闪光」）
private func stickerStar(_ c: CGPoint, _ r: CGFloat, _ g: CGContext) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.18, y: c.y - r * 0.18))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.18, y: c.y + r * 0.18))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.18, y: c.y + r * 0.18))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * 0.18, y: c.y - r * 0.18))
    p.closeSubpath()
    g.addPath(p)
    g.fillPath()
}

/// 把某一种人脸特效画出来
func drawStickerFace(_ kind: String, _ f: CGRect, _ g: CGContext) {
    guard f.width > 6, f.height > 6 else { return }
    g.saveGState()
    switch kind {
    case "ears":
        /* 猫耳朵：头顶左右各一只（外面深灰、里面一撮粉） */
        let w = f.width * 0.38, h = f.height * 0.36
        for dx in [f.minX + f.width * 0.04, f.maxX - f.width * 0.04 - w] {
            let base = f.minY + f.height * 0.12
            let p = CGMutablePath()
            p.move(to: CGPoint(x: dx, y: base))
            p.addLine(to: CGPoint(x: dx + w / 2, y: base - h))
            p.addLine(to: CGPoint(x: dx + w, y: base))
            p.closeSubpath()
            g.setFillColor(UIColor(red: 0.19, green: 0.17, blue: 0.21, alpha: 0.96).cgColor)
            g.addPath(p); g.fillPath()
            let q = CGMutablePath()
            q.move(to: CGPoint(x: dx + w * 0.28, y: base - h * 0.08))
            q.addLine(to: CGPoint(x: dx + w / 2, y: base - h * 0.74))
            q.addLine(to: CGPoint(x: dx + w * 0.72, y: base - h * 0.08))
            q.closeSubpath()
            g.setFillColor(UIColor(red: 1, green: 0.62, blue: 0.72, alpha: 0.95).cgColor)
            g.addPath(q); g.fillPath()
        }
    case "crown":
        /* 皇冠：头顶一顶金色小冠 + 三颗白珠 */
        let w = f.width * 0.66, h = f.height * 0.30
        let x = f.midX - w / 2
        let y = f.minY - h * 0.42
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y + h))
        p.addLine(to: CGPoint(x: x + w * 0.12, y: y + h * 0.22))
        p.addLine(to: CGPoint(x: x + w * 0.30, y: y + h * 0.78))
        p.addLine(to: CGPoint(x: x + w * 0.50, y: y + h * 0.14))
        p.addLine(to: CGPoint(x: x + w * 0.70, y: y + h * 0.78))
        p.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.22))
        p.addLine(to: CGPoint(x: x + w, y: y + h))
        p.closeSubpath()
        g.setFillColor(UIColor(red: 1.0, green: 0.80, blue: 0.20, alpha: 0.98).cgColor)
        g.addPath(p); g.fillPath()
        g.setFillColor(UIColor(red: 1, green: 1, blue: 1, alpha: 0.92).cgColor)
        for i in 0..<3 {
            let cx = x + w * (0.14 + 0.36 * CGFloat(i))
            let d = max(3, f.width * 0.045)
            g.fillEllipse(in: CGRect(x: cx - d / 2, y: y + h * 0.86, width: d, height: d))
        }
    case "glasses":
        /* 墨镜：一条黑色圆角镜片横过眼睛那一带 */
        let w = f.width * 0.94, h = f.height * 0.19
        let x = f.midX - w / 2
        let y = f.minY + f.height * 0.30
        g.setFillColor(UIColor.black.withAlphaComponent(0.88).cgColor)
        let lens = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                          cornerWidth: h * 0.5, cornerHeight: h * 0.5, transform: nil)
        g.addPath(lens); g.fillPath()
        /* 中间那道桥 + 一点高光，才像墨镜 */
        g.fill(CGRect(x: f.midX - w * 0.05, y: y + h * 0.36, width: w * 0.10, height: h * 0.28))
        g.setFillColor(UIColor.white.withAlphaComponent(0.28).cgColor)
        g.fill(CGRect(x: x + w * 0.10, y: y + h * 0.18, width: w * 0.22, height: h * 0.16))
    case "hearts":
        /* 爱心眼：两只红爱心挂在眼睛位置 */
        g.setFillColor(UIColor(red: 1, green: 0.24, blue: 0.36, alpha: 0.95).cgColor)
        let d = f.width * 0.26
        stickerHeart(CGRect(x: f.minX + f.width * 0.14, y: f.minY + f.height * 0.30, width: d, height: d), g)
        stickerHeart(CGRect(x: f.maxX - f.width * 0.14 - d, y: f.minY + f.height * 0.30, width: d, height: d), g)
    case "blush":
        /* 腮红：两边脸颊各一团粉 */
        g.setFillColor(UIColor(red: 1, green: 0.45, blue: 0.55, alpha: 0.42).cgColor)
        let w = f.width * 0.30, h = f.height * 0.16
        g.fillEllipse(in: CGRect(x: f.minX + f.width * 0.04, y: f.minY + f.height * 0.58, width: w, height: h))
        g.fillEllipse(in: CGRect(x: f.maxX - f.width * 0.04 - w, y: f.minY + f.height * 0.58, width: w, height: h))
    case "sparkle":
        /* 闪光：脑袋周围几颗小星星 */
        g.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 0.95).cgColor)
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.02, 0.10, 0.10), (0.92, 0.06, 0.13), (1.02, 0.52, 0.09),
            (-0.04, 0.46, 0.12), (0.16, -0.10, 0.08), (0.78, -0.08, 0.11)
        ]
        for sp in spots {
            stickerStar(CGPoint(x: f.minX + f.width * sp.0, y: f.minY + f.height * sp.1),
                        max(3, f.width * sp.2), g)
        }
    default:
        break
    }
    g.restoreGState()
}

/// 裁成正方形（拍表情一律方形，和微信一样）
func stickerSquare(_ img: UIImage) -> UIImage {
    guard let cg = img.cgImage else { return img }
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let side = min(w, h)
    guard side > 0 else { return img }
    let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
    guard let cropped = cg.cropping(to: rect) else { return img }
    return UIImage(cgImage: cropped, scale: img.scale, orientation: img.imageOrientation)
}

/// 给一张图套上特效（特效是"无特效" = 原图不动）
func stickerEffect(_ img: UIImage, _ fx: StickerFx) -> UIImage {
    guard !fx.filter.isEmpty, let ci = CIImage(image: img) else { return img }
    let out = stickerApply(ci, fx)
    let ctx = CIContext(options: nil)
    guard let cg = ctx.createCGImage(out, from: out.extent) else { return img }
    return UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
}

/// 只观察预览这一帧的子视图：30fps 刷新只重画它，不动整页
private struct StickerPreview: View {
    @ObservedObject var cam: StickerCam
    var body: some View {
        GeometryReader { g in
            ZStack {
                if let f = cam.frame {
                    Image(uiImage: f)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                } else {
                    Color.black
                }
                /* 人脸特效那一层：和画面同比例、同一个 scaledToFill，所以贴纸正好压在脸上 */
                if let o = cam.faceOverlay {
                    Image(uiImage: o)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}
