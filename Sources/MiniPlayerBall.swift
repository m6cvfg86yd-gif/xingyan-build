import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation

/* ============================================================
   迷你播放球（用户要求：「要有个小图标可以在后台挂起」）

   · 只要有一首在放（或暂停着），屏幕上就常驻一颗小圆球 —— 会话页、通讯录、
     视界、我、以及**聊天页**里都能看见（MainTab 和聊天页各挂一份，位置共用）
   · 点一下球 → 打开大播放页（和微信点开小条一个意思）
   · 右下角那颗小圆钮 → 直接 播放/暂停（不用点进大页面）
   · 左上角那个小 ✕ → 停掉，球收起来
   · 按住球拖到任意位置（松手自动吸到最近的一边），位置记在本机；
     **往下甩**（竖直方向甩出 96pt）＝ 关掉这个小球（不会自己弹回来）
   · 退到后台照样接着放（Info.plist 已声明 audio 后台模式），
     锁屏 / 控制中心 / 耳机线控上也能看到歌名并 播放·暂停·快进

   想调它（都不用重新出包，后台 ui.json 写键就行）：
     miniBallOn   0 = 不显示这颗球（默认 1 显示）
     miniBallSize 球的直径，默认 54
   ============================================================ */

struct MiniPlayerBall: View {
    @ObservedObject private var player = MusicPlayer.shared

    /// 这颗球**只在屏幕上留一颗**：聊天那条全屏路径自己挂了一份，
    /// 外层这份在它弹出来时要先让位（不然两层都在画，过渡动画里会看到球在飘）。
    var hidden: Bool = false

    /* ⚠ 位置**不存比例**（以前存的是"屏宽的百分之几"）：屏幕高度一变
       （键盘弹起、切标签栏、弹层推上来）按比例算出来的 y 就跟着变，
       看着就是「音乐那颗小图标在乱跳」。现在只存两件事：
         贴哪一边（0 左 / 1 右）+ 离屏幕底多少 pt
       —— 页面高度怎么变，它都钉在那儿不动。 */
    @AppStorage("miniBallSide") private var side: Int = 1
    @AppStorage("miniBallBottom") private var bottom: Double = -1      // -1 = 还没拖过

    /// 这一次拖动的位移（松手归零，位置落进上面两个键里）
    @State private var dx: CGFloat = 0
    @State private var dy: CGFloat = 0
    @State private var dragging = false

    private var dia: CGFloat { max(42, min(76, UIConfig.num("miniBallSize", 54))) }
    private var on: Bool { UIConfig.num("miniBallOn", 1) > 0 }
    private var showing: Bool { on && !hidden && player.current != nil }

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
            let pad = dia / 2 + 6
            let bt = min(max(bottom < 0 ? defaultBottom : CGFloat(bottom), pad + 4), h)
            let cx = min(max((side == 0 ? pad : w - pad) + dx, pad), w - pad)
            let cy = min(max(h - bt + dy, L.safeTop + pad), h - pad)

            ball
                .position(x: cx, y: cy)
                .gesture(drag(w: w, h: h))
                .onTapGesture { openPlayer() }
        }
        .ignoresSafeArea()
        .opacity(showing ? 1 : 0)
        .allowsHitTesting(showing)
    }

    /// 没拖过的话：默认贴在右下角、底栏上面一点
    private var defaultBottom: CGFloat { dia / 2 + L.tabH + L.safeBottom + 10 }

    /* ------------------------------------------------------- 球本身 */

    private var ball: some View {
        ZStack {
            MusicCover(path: player.current?.cover ?? "", size: dia, radius: dia / 2)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))

            /* 外圈那一道绿色进度 */
            Circle()
                .trim(from: 0, to: max(0.02, min(1, player.progress)))
                .stroke(C.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: dia - 1.5, height: dia - 1.5)

            /* 右下角：播放 / 暂停（在放的时候是一圈很淡的"呼吸"） */
            MusicPlayButton(playing: player.playing,
                            loading: !player.loadingId.isEmpty && player.loadingId == (player.current?.id ?? ""),
                            size: dia * 0.44)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                .offset(x: dia * 0.33, y: dia * 0.33)
                .onTapGesture {
                    guard let t = MusicPlayer.shared.current else { return }
                    MusicPlayer.shared.toggle(t)
                }

            /* 左上角：关掉（停播 + 收球） */
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: "xmark")
                    .font(.system(size: dia * 0.17, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: dia * 0.36, height: dia * 0.36)
            .offset(x: -dia * 0.33, y: -dia * 0.33)
            .onTapGesture { MusicPlayer.shared.stop() }
        }
        .frame(width: dia, height: dia)
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
        .scaleEffect(dragging ? 1.08 : 1)
    }

    private func openPlayer() {
        guard let t = MusicPlayer.shared.current else { return }
        MusicSheet.shared.open(t)
    }

    /* ------------------------------------------------------- 拖动 */

    private func drag(w: CGFloat, h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                dragging = true
                dx = v.translation.width
                dy = v.translation.height
            }
            .onEnded { v in
                let pad = dia / 2 + 6
                let bt = min(max(bottom < 0 ? defaultBottom : CGFloat(bottom), pad + 4), h)

                /* 往下甩：关掉这颗球（用户说"卡片缩小后又自己弹回来"，
                   所以这里只有用户自己甩下来才收，别自动展开/自动弹回） */
                if v.translation.height > 96 && abs(v.translation.height) > abs(v.translation.width) * 1.4 {
                    dx = 0; dy = 0; dragging = false
                    MusicPlayer.shared.stop()
                    return
                }

                /* 吸附到最近的一边，纵向只记「离屏幕底多少」 */
                let nx = (side == 0 ? pad : w - pad) + v.translation.width
                let ny = min(max(h - bt + v.translation.height, L.safeTop + pad), h - pad)
                side = nx < w / 2 ? 0 : 1
                bottom = Double(min(max(h - ny, pad + 4), h - L.safeTop - pad))
                dx = 0; dy = 0
                dragging = false
            }
    }
}

/* ============================================================
   锁屏 / 控制中心 / 耳机线控（后台挂起时那颗"小图标"）

   MPNowPlayingInfoCenter 把在放的歌报给系统 —— 锁屏和控制中心就会显示
   歌名歌手 + 进度，还能拖进度；MPRemoteCommandCenter 收那几个按键。
   切歌、暂停、拖进度都同步过去（不改播放器本身的行为）。
   ============================================================ */

extension MusicPlayer {
    /// App 启动时挂一次（MusicPlayer.init 里调）
    func setupRemoteControls() {
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.removeTarget(nil)
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePlay() }
            return .success
        }

        c.pauseCommand.removeTarget(nil)
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePause() }
            return .success
        }

        c.togglePlayPauseCommand.removeTarget(nil)
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let t = self?.current else { return }
                self?.toggle(t)
            }
            return .success
        }

        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false

        /* 锁屏上拖进度条 */
        c.changePlaybackPositionCommand.removeTarget(nil)
        c.changePlaybackPositionCommand.addTarget { [weak self] ev in
            guard let e = ev as? MPChangePlaybackPositionCommandEvent, let self else { return .commandFailed }
            Task { @MainActor in
                guard let p = self.player, p.duration > 0 else { return }
                self.seek(e.positionTime / p.duration)
                self.syncNowPlaying()
            }
            return .success
        }
    }

    private func remotePlay() {
        guard let t = current else { return }
        if let p = player {
            try? AVAudioSession.sharedInstance().setActive(true)
            p.play(); playing = true; startTimer(); syncNowPlaying()
        } else {
            play(t)
        }
    }

    private func remotePause() {
        player?.pause()
        playing = false
        stopTimer()
        syncNowPlaying()
    }

    /// 把现在这首的 歌名/歌手/进度 报给系统（锁屏、控制中心、车机都用它）
    func syncNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = t.title
        info[MPMediaItemPropertyArtist] = t.artistText
        info[MPMediaItemPropertyPlaybackDuration] = total
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if let art = MusicPlayer.cachedArtwork(t) {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    /// 封面本地缓存的图（没有就返回 nil —— 锁屏上就只是一行歌名）
    static func cachedArtwork(_ t: MusicTrack) -> UIImage? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let p = caches.appendingPathComponent("musiccover").appendingPathComponent("\(t.id)")
        return UIImage(contentsOfFile: p.path)
    }
}
