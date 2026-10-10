import SwiftUI
import AVFoundation

/* ============================================================
   音乐（App 里的「听一听」）

   · 曲库在服务器上（后台「音乐（听一听）」页传的歌），App 只读
   · 「听一听」页：列表 + 底下一根播放条（微信听一听就长这样）
   · 聊天「＋ → 音乐」：选一首 → 发出去是一张**音乐卡片**（封面 + 歌名 + 歌手）
   · 点卡片 → 进播放页（大封面 + 进度 + 播放/暂停）
   ⚠ 音频一定要**先下到本机再播**：AVPlayer 走自己的网络栈，
     我们服务器的地址带签名/可能不是 https，直接播会一直转圈（视频那边踩过）。
   ============================================================ */

struct MusicTrack: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String?
    var cover: String?
    var url: String
    var at: Double?

    var artistText: String { (artist ?? "").isEmpty ? "未知歌手" : (artist ?? "") }
}

/// 音乐卡片里的内容（和 chat 里那条消息的 JSON 对应）
struct MusicCardInfo {
    var id = ""
    var title = ""
    var artist = ""
    var cover = ""
    var url = ""

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        id = (o["id"] as? String) ?? ""
        title = (o["title"] as? String) ?? ""
        artist = (o["artist"] as? String) ?? ""
        cover = (o["cover"] as? String) ?? ""
        url = (o["url"] as? String) ?? ""
        guard !title.isEmpty, !url.isEmpty else { return nil }
    }

    var asTrack: MusicTrack { MusicTrack(id: id, title: title, artist: artist, cover: cover, url: url, at: nil) }
}

/* ---------------------------------------------------------- 播放器 */

@MainActor
final class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    /// 正在放哪一首 / 在不在放 / 进度（0~1）/ 已播秒数 / 总时长 / 正在下载哪一首
    @Published private(set) var current: MusicTrack?
    @Published private(set) var playing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var seconds: Double = 0
    @Published private(set) var total: Double = 0
    @Published private(set) var loadingId = ""

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var cache: [String: Data] = [:]

    func isPlaying(_ id: String) -> Bool { playing && current?.id == id }

    /// 点一下：同一首就暂停/继续，别的就换歌
    func toggle(_ t: MusicTrack) {
        if current?.id == t.id, let p = player {
            if p.isPlaying {
                p.pause(); playing = false; stopTimer()
            } else {
                p.play(); playing = true; startTimer()
            }
            return
        }
        play(t)
    }

    func play(_ t: MusicTrack) {
        guard let url = URL(string: t.url) else { return }
        if let d = cache[t.id] {
            current = t
            start(data: d, track: t)
            return
        }
        loadingId = t.id
        current = t
        Task {
            do {
                let data = try await API.shared.assetData(url)
                await MainActor.run {
                    self.loadingId = ""
                    self.cache[t.id] = data
                    self.start(data: data, track: t)
                }
            } catch {
                await MainActor.run {
                    self.loadingId = ""
                    self.current = nil
                    self.playing = false
                }
            }
        }
    }

    private func start(data: Data, track: MusicTrack) {
        stopTimer()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        playing = true
        seconds = 0
        progress = 0
        total = player?.duration ?? 0
        startTimer()
    }

    func pause() {
        player?.pause()
        playing = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        playing = false
        current = nil
        progress = 0
        seconds = 0
        total = 0
        stopTimer()
    }

    /// 拖进度：ratio 0~1
    func seek(_ ratio: Double) {
        guard let p = player, p.duration > 0 else { return }
        let v = min(max(0, ratio), 1) * p.duration
        p.currentTime = v
        seconds = v
        progress = min(max(0, ratio), 1)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in self.tick() }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func tick() {
        guard let p = player else { return }
        seconds = p.currentTime
        total = p.duration
        progress = p.duration > 0 ? min(1, p.currentTime / p.duration) : 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playing = false
            self.progress = 0
            self.seconds = 0
            self.stopTimer()
        }
    }
}

/* ---------------------------------------------------------- 小零件 */

/// mm:ss
func musicTime(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "00:00" }
    let t = Int(s.rounded())
    return String(format: "%02d:%02d", t / 60, t % 60)
}

/// 封面（没有就用一个音符占位）
struct MusicCover: View {
    var path: String
    var size: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
            if !path.isEmpty {
                RemoteImage(path: path, icon: "music.note")
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 一颗播放/暂停圆钮
struct MusicPlayButton: View {
    var playing: Bool
    var loading: Bool
    var size: CGFloat = 30
    var tint: Color = .white
    var bg: Color = Color.black.opacity(0.35)

    var body: some View {
        ZStack {
            Circle().fill(bg)
            if loading {
                ProgressView().tint(tint).scaleEffect(0.7)
            } else {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(tint)
                    .offset(x: playing ? 0 : size * 0.03)
            }
        }
        .frame(width: size, height: size)
    }
}

/* ---------------------------------------------------------- 聊天里的音乐卡片 */

struct MusicBubble: View {
    let info: MusicCardInfo
    /// 点整张卡：进播放页（微信就是点开进播放器）
    var onOpen: () -> Void
    @ObservedObject private var player = MusicPlayer.shared

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                MusicCover(path: info.cover, size: 52, radius: 8)
                MusicPlayButton(playing: player.isPlaying(info.id),
                                loading: player.loadingId == info.id, size: 22)
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(pf(15))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(info.artist.isEmpty ? "未知歌手" : info.artist)
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 232, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

/* ---------------------------------------------------------- 听一听（曲库页） */

struct ListenView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 有值 = 从聊天里进来的：点一首 = 发给这个会话（音乐卡片）
    var sendTo: Chat? = nil
    var onSend: ((MusicTrack) -> Void)? = nil

    @State private var tracks: [MusicTrack] = []
    @State private var loading = true
    @State private var query = ""
    @ObservedObject private var player = MusicPlayer.shared

    private var list: [MusicTrack] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tracks }
        return tracks.filter { $0.title.localizedCaseInsensitiveContains(q)
            || ($0.artist ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr(sendTo == nil ? "听一听" : "选择音乐"), back: { dismiss() })

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14.5)).foregroundColor(C.searchIcon)
                TextField(Tr("搜索歌名 / 歌手"), text: $query).font(pf(15))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).foregroundColor(C.searchIcon2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.searchBg))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)

            if loading {
                HStack(spacing: 10) { ProgressView(); Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel) }
                    .frame(height: 80)
            } else if list.isEmpty {
                Text(Tr("曲库还没有歌（后台「音乐（听一听）」里传一首）"))
                    .font(pf(14)).foregroundColor(C.subLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .frame(height: 120)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                        if i > 0 { HairLine(inset: 66) }
                        row(t)
                    }
                    Spacer().frame(height: 20)
                }
            }
            .background(C.pageBg)

            if sendTo == nil, let cur = player.current { miniBar(cur) }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            tracks = await API.shared.musicTracks()
            loading = false
        }
    }

    private func row(_ t: MusicTrack) -> some View {
        Button {
            if let onSend, sendTo != nil {
                onSend(t)
                dismiss()
            } else {
                MusicPlayer.shared.toggle(t)
                MusicSheet.shared.open(t)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: t.cover ?? "", size: 44, radius: 6)
                    MusicPlayButton(playing: player.isPlaying(t.id), loading: player.loadingId == t.id, size: 19)
                        .offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                    Text(t.artistText).font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14).frame(height: 62)
            .background(C.cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 底下一根播放条（微信听一听就这样）
    private func miniBar(_ t: MusicTrack) -> some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 10) {
                MusicCover(path: t.cover ?? "", size: 38, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(pf(14)).foregroundColor(C.label).lineLimit(1)
                    Text(t.artistText).font(pf(11.5)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { MusicPlayer.shared.toggle(t) } label: {
                    MusicPlayButton(playing: player.isPlaying(t.id), loading: player.loadingId == t.id,
                                    size: 32, tint: .white, bg: C.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(C.cardBg)
        }
    }
}

/* ---------------------------------------------------------- 播放页（大封面） */

/// 谁都能叫出播放页（聊天里点卡片、听一听里点一首）
@MainActor
final class MusicSheet: ObservableObject {
    static let shared = MusicSheet()
    @Published var open = false
    @Published var track: MusicTrack?
    func open(_ t: MusicTrack) { track = t; open = true }
    func close() { open = false }
}

struct MusicPlayingView: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var sheet = MusicSheet.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dragging = false
    @State private var dragValue: Double = 0

    private var t: MusicTrack? { sheet.track ?? player.current }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(Tr("正在播放")).font(pf(14)).foregroundColor(C.subLabel)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer(minLength: 10)

            MusicCover(path: t?.cover ?? "", size: 240, radius: 16)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            VStack(spacing: 6) {
                Text(t?.title ?? "").font(pf(19, .semibold)).foregroundColor(C.label).lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(t?.artistText ?? "").font(pf(13.5)).foregroundColor(C.subLabel).lineLimit(1)
            }
            .padding(.horizontal, 30)
            .padding(.top, 22)

            Spacer(minLength: 12)

            /* 进度条：拖的时候实时跟手 */
            VStack(spacing: 6) {
                Slider(value: Binding(
                    get: { dragging ? dragValue : player.progress },
                    set: { dragValue = $0 }
                ), in: 0...1, onEditingChanged: { on in
                    dragging = on
                    if !on { MusicPlayer.shared.seek(dragValue) }
                })
                .tint(C.green)
                .padding(.horizontal, 24)
                HStack {
                    Text(musicTime(dragging ? dragValue * player.total : player.seconds))
                        .font(pf(11.5)).foregroundColor(C.subLabel)
                    Spacer()
                    Text(musicTime(player.total)).font(pf(11.5)).foregroundColor(C.subLabel)
                }
                .padding(.horizontal, 28)
            }

            HStack(spacing: 40) {
                Button { MusicPlayer.shared.seek(max(0, player.progress - 0.1)) } label: {
                    Image(systemName: "gobackward").font(.system(size: 24)).foregroundColor(C.label)
                }
                .buttonStyle(.plain)
                Button {
                    if let t { MusicPlayer.shared.toggle(t) }
                } label: {
                    ZStack {
                        Circle().fill(C.green).frame(width: 66, height: 66)
                        if player.loadingId == (t?.id ?? "") {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 25, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: player.playing ? 0 : 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                Button { MusicPlayer.shared.seek(min(1, player.progress + 0.1)) } label: {
                    Image(systemName: "goforward").font(.system(size: 24)).foregroundColor(C.label)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            Spacer(minLength: 30)
        }
        .background(C.cardBg.ignoresSafeArea())
        .onAppear {
            if let t, player.current?.id != t.id { MusicPlayer.shared.play(t) }
            else if let t { MusicPlayer.shared.play(t) }
        }
    }
}

/* ⚠ 取曲库的接口写在 API.swift 里（那边的 get 是 private，扩展里调不到） */
