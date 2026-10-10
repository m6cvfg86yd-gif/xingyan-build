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
    /// 歌词（后台「音乐（听一听）」里贴的）：LRC 或一行一句都行，空 = 没有
    var lyrics: String? = nil
    var at: Double?

    var artistText: String { (artist ?? "").isEmpty ? "未知歌手" : (artist ?? "") }
}

/* ---------------------------------------------------------- 歌词 */

struct MusicLyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String
}

enum MusicLyrics {
    /// 解析歌词：带 [00:12.34] 时间戳的按 LRC 走；纯文字就按总时长均分。
    static func parse(_ raw: String, duration: Double) -> [MusicLyricLine] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !rows.isEmpty else { return [] }

        if let re = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]") {
            var out: [MusicLyricLine] = []
            for r in rows {
                let ns = r as NSString
                let ms = re.matches(in: r, options: [], range: NSRange(location: 0, length: ns.length))
                var stamp: Double? = nil
                for m in ms {
                    let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                    let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                    var frac = 0.0
                    if m.range(at: 3).location != NSNotFound {
                        let raw3 = ns.substring(with: m.range(at: 3))
                        frac = (Double(raw3) ?? 0) / pow(10, Double(max(1, raw3.count)))
                    }
                    if stamp == nil { stamp = mm * 60 + ss + frac }
                }
                guard let t0 = stamp else { continue }
                let last = ms.last
                let body = (last == nil ? ns as String
                            : ns.substring(from: (last!.range.location + last!.range.length)))
                    .trimmingCharacters(in: .whitespaces)
                if body.isEmpty { continue }
                out.append(MusicLyricLine(id: out.count, time: t0, text: body))
            }
            if !out.isEmpty { return out.sorted { $0.time < $1.time } }
        }

        /* 没时间戳：一行一句，按总时长均分（前 8% 留给前奏） */
        let plain = rows.filter { !$0.isEmpty && !$0.hasPrefix("[") }
        guard !plain.isEmpty else { return [] }
        let span = duration > 1 ? duration : Double(plain.count) * 4
        let lead = span * 0.08
        let step = (span - lead) / Double(plain.count)
        return plain.enumerated().map { i, s in
            MusicLyricLine(id: i, time: lead + step * Double(i), text: s)
        }
    }

    /// 现在唱到第几行（-1 = 还没开始）
    static func current(_ lines: [MusicLyricLine], at t: Double) -> Int {
        guard !lines.isEmpty else { return -1 }
        var idx = 0
        for (i, l) in lines.enumerated() {
            if l.time <= t + 0.2 { idx = i } else { break }
        }
        return idx
    }
}

/* ---------------------------------------------------------- 歌词页 */

/// 播放页右上角那个「词」：整页歌词，当前那句高亮 + 自动滚到中间
struct MusicLyricsView: View {
    let track: MusicTrack?
    @ObservedObject private var player = MusicPlayer.shared
    @Environment(\.dismiss) private var dismiss

    private var lines: [MusicLyricLine] { MusicLyrics.parse(track?.lyrics ?? "", duration: player.total) }
    private var cur: Int { MusicLyrics.current(lines, at: player.seconds) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(track?.title ?? "").font(pf(15, .semibold)).foregroundColor(C.label).lineLimit(1)
                    Text(track?.artistText ?? "").font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.top, 6)

            if lines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 30)).foregroundColor(C.subLabel)
                    Text(Tr("这首歌还没有歌词")).font(pf(15)).foregroundColor(C.label)
                    Text(Tr("后台「音乐（听一听）」里，每首歌后面点「歌词」就能贴上去"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { sp in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            Color.clear.frame(height: 130)
                            ForEach(lines) { l in
                                Text(l.text)
                                    .font(pf(l.id == cur ? 17.5 : 15, l.id == cur ? .semibold : .regular))
                                    .foregroundColor(l.id == cur ? C.green : C.label.opacity(0.72))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .id(l.id)
                            }
                            Color.clear.frame(height: 180)
                        }
                        .padding(.horizontal, 26)
                    }
                    .onChange(of: cur) { i in
                        guard i >= 0 else { return }
                        withAnimation(.easeInOut(duration: 0.28)) { sp.scrollTo(i, anchor: .center) }
                    }
                }
            }
        }
        .background(C.cardBg.ignoresSafeArea())
    }
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
    /* ⚠ playing 的 setter 得是 internal：锁屏那颗"播放/暂停"（MiniPlayerBall.swift）
       在**别的文件**里要改它。改回 private(set) 会编不过。 */
    @Published var playing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var seconds: Double = 0
    @Published private(set) var total: Double = 0
    @Published private(set) var loadingId = ""

    /* ⚠ 这三个以前是 private。迷你播放球 / 锁屏那部分（MiniPlayerBall.swift）
       要在**别的文件**里读到它们，同一个 module 必须留成 internal ——
       别再改回 private，不然那边编不过。 */
    var player: AVAudioPlayer?
    var timer: Timer?
    private var cache: [String: Data] = [:]
    /// 锁屏/控制中心那几个按键挂过没有（挂一次就够）
    private var remoteReady = false
    /// 上一次报给锁屏的秒数（别每 0.3 秒都报一遍）
    private var syncedSecond: Int = -1

    /// 只在用到播放器的时候挂一次锁屏控制（省得在 init 里碰 MediaPlayer）
    func ensureRemote() {
        guard !remoteReady else { return }
        remoteReady = true
        setupRemoteControls()
    }

    func isPlaying(_ id: String) -> Bool { playing && current?.id == id }

    /// 点一下：同一首就暂停/继续，别的就换歌
    func toggle(_ t: MusicTrack) {
        if current?.id == t.id, let p = player {
            if p.isPlaying {
                p.pause(); playing = false; stopTimer()
            } else {
                /* 接着放：先把音频会话重新激活 —— 别的页面 / 语音播完可能把它关了，
                   会话没激活时 play() 是**没声音**的（用户说的「暂停之后放不出」多半是这个） */
                try? AVAudioSession.sharedInstance().setActive(true)
                p.play(); playing = true; startTimer()
            }
            syncNowPlaying()
            return
        }
        play(t)
    }

    /// 封面存一份到本机（锁屏/控制中心那张小图用；没有也没关系，只是不显示图）
    private func cacheCover(_ t: MusicTrack) {
        guard let cover = t.cover, !cover.isEmpty else { return }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let dir = caches.appendingPathComponent("musiccover", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let to = dir.appendingPathComponent(t.id)
        if FileManager.default.fileExists(atPath: to.path) { return }
        guard let url = API.shared.assetURL(cover) else { return }
        Task {
            if let d = try? await API.shared.assetData(url) {
                try? d.write(to: to, options: .atomic)
                await MainActor.run { self.syncNowPlaying() }
            }
        }
    }

    /// 本机缓存路径：一首歌一个文件（下载过就直接从本地放）
    private func localURL(_ t: MusicTrack) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let raw = (t.url as NSString).pathExtension
        let ext = (raw.isEmpty || raw.count > 5) ? "mp3" : raw
        return dir.appendingPathComponent("\(t.id).\(ext)")
    }

    func play(_ t: MusicTrack) {
        /* ⚠ 曲库里存的是**相对地址**（/uploads/xxx.mp3），必须用 assetURL 补上服务器前缀，
           不然 URLSession 拿一个没有域名的地址去请求，必然失败 —— 用户看到的「上传了不播放」就是这个。 */
        guard let url = API.shared.assetURL(t.url) else { return }
        ensureRemote()
        cacheCover(t)
        current = t
        /* ① 本机已经存过一份：直接放（秒开、离线也能放） */
        if let local = localURL(t), FileManager.default.fileExists(atPath: local.path),
           let p = try? AVAudioPlayer(contentsOf: local) {
            stopTimer()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = p
            p.delegate = self
            p.prepareToPlay()
            p.play()
            playing = true
            seconds = 0
            progress = 0
            total = p.duration
            startTimer()
            syncNowPlaying()
            return
        }
        if let d = cache[t.id] {
            start(data: d, track: t)
            return
        }
        loadingId = t.id
        Task {
            do {
                let data = try await API.shared.assetData(url)
                await MainActor.run {
                    self.loadingId = ""
                    self.cache[t.id] = data
                    /* 下完**先存到本机**再放（用户要求「存到本地后播放」；也省流量、离线能放） */
                    if let local = self.localURL(t) { try? data.write(to: local, options: .atomic) }
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
        syncNowPlaying()
    }

    func pause() {
        player?.pause()
        playing = false
        stopTimer()
        syncNowPlaying()
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
        syncNowPlaying()
    }

    /// 拖进度：ratio 0~1
    func seek(_ ratio: Double) {
        guard let p = player, p.duration > 0 else { return }
        let v = min(max(0, ratio), 1) * p.duration
        p.currentTime = v
        seconds = v
        progress = min(max(0, ratio), 1)
        syncNowPlaying()
    }

    /* 迷你球/锁屏那边要手动起停这个计时器，所以这两个不再是 private */
    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in self.tick() }
        }
    }
    func stopTimer() { timer?.invalidate(); timer = nil }
    func tick() {
        guard let p = player else { return }
        seconds = p.currentTime
        total = p.duration
        progress = p.duration > 0 ? min(1, p.currentTime / p.duration) : 0
        /* 锁屏上的进度每秒刷一次就够（别每 0.3 秒都报一次） */
        let s = Int(seconds)
        if s != syncedSecond { syncedSecond = s; syncNowPlaying() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playing = false
            self.progress = 0
            self.seconds = 0
            self.stopTimer()
            self.syncNowPlaying()
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
    @State private var showSearch = false
    /// 0 = 推荐 / 1 = 歌曲 / 2 = 朋友推荐（照微信「听一听」那三个 tab）
    @State private var tab = 0
    /// 「换一批」每点一次 +1，推荐列表跟着重排
    @State private var batch = 0
    @ObservedObject private var player = MusicPlayer.shared

    private var sendMode: Bool { sendTo != nil }

    private var matched: [MusicTrack] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tracks }
        return tracks.filter { $0.title.localizedCaseInsensitiveContains(q)
            || ($0.artist ?? "").localizedCaseInsensitiveContains(q) }
    }

    /// 今日推荐：打乱一批（点「换一批」就换一份）
    private var recommend: [MusicTrack] {
        var list = tracks
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return matched }
        /* ⚠ 以前这里每次算都现 shuffle()：这一页盯着播放器（进度 0.3 秒跳一次），
           等于每 0.3 秒重排一遍 —— 用户看到的「音乐卡片怎么在乱跳」就是这个。
           现在按「批次号」做**确定性**打乱：同一批永远同一个顺序，
           只有点「换一批」（batch + 1）才换一份新的。 */
        list.sort { recRank($0.id) < recRank($1.id) }
        return Array(list.prefix(12))
    }

    /// 按 id + 批次号算一个稳定的分数（同一批里顺序固定，换一批才变）
    private func recRank(_ id: String) -> UInt64 {
        var h = UInt64(truncatingIfNeeded: batch &* 2654435761) &+ 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// 推荐音乐人 = 曲库里出现过的歌手
    private var artists: [(String, String)] {
        var seen: [String: String] = [:]
        tracks.forEach { t in
            let a = (t.artist ?? "").isEmpty ? "未知歌手" : t.artist!
            if seen[a] == nil { seen[a] = t.cover ?? "" }
        }
        return seen.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr(sendMode ? "选择音乐" : "听一听"), back: { dismiss() }) {
                if !sendMode {
                    Button { showSearch.toggle() } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(C.label)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showSearch {
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
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 4)
            }

            if !sendMode {
                tabRow
                HairLine()
            }

            content

            if !sendMode, let cur = player.current { miniBar(cur) }
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

    /// 顶上那三个 tab（推荐 / 歌曲 / 朋友推荐）—— 微信「听一听」就是这样
    private var tabRow: some View {
        HStack(spacing: 22) {
            ForEach([Tr("推荐"), Tr("歌曲"), Tr("朋友推荐")].indices, id: \.self) { i in
                Button { tab = i } label: {
                    VStack(spacing: 6) {
                        Text([Tr("推荐"), Tr("歌曲"), Tr("朋友推荐")][i])
                            .font(pf(16, tab == i ? .semibold : .regular))
                            .foregroundColor(tab == i ? C.label : C.subLabel)
                        Rectangle()
                            .fill(tab == i ? C.green : Color.clear)
                            .frame(width: 22, height: 2.5)
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 10) { ProgressView(); Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel) }
                .frame(maxWidth: .infinity).frame(height: 100)
            Spacer(minLength: 0)
        } else if tracks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 30, weight: .light)).foregroundColor(C.subLabel)
                Text(Tr("曲库还没有歌（后台「音乐（听一听）」里传一首）"))
                    .font(pf(14)).foregroundColor(C.subLabel)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
            Spacer(minLength: 0)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if tab == 0 {
                        /* 今日推荐 + 换一批（微信顶上就是这一行） */
                        HStack(spacing: 8) {
                            Text(Tr("今日推荐")).font(pf(17, .semibold)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Button { batch += 1 } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12))
                                    Text(Tr("换一批")).font(pf(13))
                                }
                                .foregroundColor(C.subLabel)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                        /* 用**歌 id** 当身份（不是行号）：换一批的时候行是"换内容"，
                           不是"整排重建"，不会闪 */
                        ForEach(Array(recommend.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { HairLine(inset: 66) }
                            row(t)
                        }

                        if artists.count > 1 {
                            HStack {
                                Text(Tr("推荐音乐人")).font(pf(17, .semibold)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 10)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(Array(artists.enumerated()), id: \.offset) { _, a in
                                        VStack(spacing: 6) {
                                            MusicCover(path: a.1, size: 58, radius: 29)
                                            Text(a.0).font(pf(12.5)).foregroundColor(C.label).lineLimit(1)
                                                .frame(width: 68)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.bottom, 10)
                        }
                    } else if tab == 1 {
                        ForEach(Array(matched.enumerated()), id: \.offset) { i, t in
                            if i > 0 { HairLine(inset: 66) }
                            row(t)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text(Tr("朋友推荐还没有内容"))
                                .font(pf(14)).foregroundColor(C.subLabel)
                            Text(Tr("等朋友听过的歌多了，这里就会出现"))
                                .font(pf(12.5)).foregroundColor(C.subLabel.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity).padding(.top, 50)
                    }
                    Spacer().frame(height: 24)
                }
            }
            .background(C.pageBg)
        }
    }

    private func row(_ t: MusicTrack) -> some View {
        Button {
            if let onSend, sendMode {
                onSend(t)
                dismiss()
            } else {
                /* 点一下**只播放/暂停** —— 以前还会顺手弹出播放页，
                   手一抖就"播放 + 弹页"两件事一起发生（用户说的误触）。 */
                MusicPlayer.shared.toggle(t)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: t.cover ?? "", size: 46, radius: 7)
                    MusicPlayButton(playing: player.isPlaying(t.id), loading: player.loadingId == t.id, size: 20)
                        .offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                    Text(t.artistText).font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14).frame(height: 64)
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
            /* 点这条空白处 = 进播放页（大封面那页）；点右边的按钮才是 播放/暂停 */
            .contentShape(Rectangle())
            .onTapGesture { MusicSheet.shared.open(t) }
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
    /// 歌词页（右上角那个「词」）
    @State private var showLyrics = false

    private var t: MusicTrack? { sheet.track ?? player.current }

    /// 关掉这一页：**先把这个开关归位再 dismiss** —— 只 dismiss 不归位的话
    /// 标记还立着，下一次界面刷新又会把它弹回来（用户说的"关不掉"）。
    private func closeMe() {
        MusicSheet.shared.close()
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { closeMe() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(Tr("正在播放")).font(pf(14)).foregroundColor(C.subLabel)
                Spacer()
                /* 歌词（后台「音乐（听一听）」里贴的；没有歌词时这一页会提示去哪儿加） */
                Button { showLyrics = true } label: {
                    Text(Tr("词"))
                        .font(pf(15, .medium))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            /* 顶栏往下拖一截 = 关掉这一页（有些系统手势在这页上不好使，
               这里自己接一手，保证一定关得掉） */
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 10).onEnded { v in
                if v.translation.height > 70 && abs(v.translation.height) > abs(v.translation.width) {
                    closeMe()
                }
            })

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
        /* 整页往下拖也能关（拖得够远、方向是往下才关，横着拖进度条不受影响） */
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { v in
            if v.translation.height > 90 && abs(v.translation.height) > abs(v.translation.width) * 1.2 {
                closeMe()
            }
        })
        .sheet(isPresented: $showLyrics) { MusicLyricsView(track: t) }
        .onAppear {
            /* 只有「换了一首」才从头播；同一首进进出出别打断（以前每次进这页都重播一遍） */
            if let t, player.current?.id != t.id { MusicPlayer.shared.play(t) }
        }
        /* 这一页被往下划掉 / 点左上角关掉之后，把"要弹播放页"这个标记也清掉 ——
           不然标记还立着，下一次任何一次打开都会又弹一遍（"关不掉"的一种情况） */
        .onDisappear { MusicSheet.shared.close() }
    }
}

/* ⚠ 取曲库的接口写在 API.swift 里（那边的 get 是 private，扩展里调不到） */
