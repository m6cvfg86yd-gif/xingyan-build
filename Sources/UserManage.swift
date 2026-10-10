import SwiftUI
import UniformTypeIdentifiers

/* ============================================================
   App 里的「管理」（只有 ops = true 的账号才看得到这个入口）

   · 上新音乐：选一个 mp3/m4a → 填歌名歌手 → （可选）挑封面、贴歌词 → 加进曲库
   · 音乐图标：曲库里每一首后面都能换封面
   · 游戏图标：每一款小游戏都能换图标

   改的是**同一份数据**（服务器 data/music.json / data/miniapps.json），
   所以换完后台和所有人立刻就看到了，不用重新出包。
   ============================================================ */

struct ManageData: Decodable {
    var music: [MusicTrack]?
    var games: [MiniApp]?
    var apps: [MiniApp]?
}

struct UserManageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var data: ManageData? = nil
    @State private var loading = true
    @State private var busy = ""
    @State private var msg = ""

    /* 上新音乐这份表单 */
    @State private var title = ""
    @State private var artist = ""
    @State private var lyrics = ""
    @State private var audioURL = ""
    @State private var audioName = ""
    @State private var newCoverURL = ""
    @State private var showAudioPick = false
    /// 正在给谁挑图："" = 上新那首的封面；"mus_xxx" = 那首歌；"g01" = 那款游戏
    @State private var pickFor = ""
    @State private var showCoverPick = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("管理"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    addSection
                    musicIcons
                    gameIcons
                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        /* 选音频文件：mp3 / m4a / wav 都行（服务器那边收下就存成 /uploads/xxx） */
        .fileImporter(isPresented: $showAudioPick,
                      allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
                      allowsMultipleSelection: false) { result in
            uploadAudio(result)
        }
        .sheet(isPresented: $showCoverPick) {
            PhotoPicker { img in uploadPic(img) }
        }
    }

    /* ------------------------------------------------------- 上新音乐 */

    private var addSection: some View {
        card(Tr("上线新音乐")) {
            row(Tr("音频文件"), audioName.isEmpty ? Tr("未选择") : audioName) { showAudioPick = true }
            HairLine(inset: 16)
            HStack {
                Text(Tr("歌名")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                TextField(Tr("必填"), text: $title)
                    .font(pf(16)).multilineTextAlignment(.trailing)
            }
            .frame(height: 52).padding(.horizontal, 16)
            HairLine(inset: 16)
            HStack {
                Text(Tr("歌手")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                TextField(Tr("选填"), text: $artist)
                    .font(pf(16)).multilineTextAlignment(.trailing)
            }
            .frame(height: 52).padding(.horizontal, 16)
            HairLine(inset: 16)
            ZStack(alignment: .topLeading) {
                if lyrics.isEmpty {
                    Text(Tr("歌词（选填，一行一句或贴 LRC）"))
                        .font(pf(14)).foregroundColor(C.subLabel)
                        .padding(.top, 10).padding(.leading, 5)
                }
                TextEditor(text: $lyrics)
                    .font(pf(14))
                    .frame(height: 90)
                    .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 12)
            HairLine(inset: 16)
            row(Tr("封面"), newCoverURL.isEmpty ? Tr("未选择") : Tr("已选")) { startPick("") }
            HairLine(inset: 16)
            HStack {
                Button { Task { await addMusic() } } label: {
                    Text(busy == "add" ? Tr("上传中…") : Tr("加进曲库"))
                        .font(pf(15.5, .medium)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Capsule().fill(C.green))
                }
                .buttonStyle(.plain)
                .disabled(busy == "add" || title.isEmpty || audioURL.isEmpty)
                .opacity((title.isEmpty || audioURL.isEmpty) ? 0.5 : 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    /* ------------------------------------------------------- 音乐图标 */

    private var musicIcons: some View {
        card(Tr("音乐图标")) {
            if let list = data?.music, !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { HairLine(inset: 70) }
                    iconRow(cover: t.cover ?? "", title: t.title, sub: t.artistText,
                            busyKey: t.id) { startPick(t.id) }
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("曲库还是空的"))
            }
        }
    }

    /* ------------------------------------------------------- 游戏图标 */

    private var gameIcons: some View {
        card(Tr("游戏图标")) {
            if let list = data?.games, !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { HairLine(inset: 70) }
                    iconRow(cover: g.cover ?? "", title: g.name,
                            sub: g.groupText, busyKey: g.id) { startPick(g.id) }
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("还没有小游戏"))
            }
        }
    }

    private func iconRow(cover: String, title: String, sub: String,
                         busyKey: String, tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                    Text("🖼").font(pf(18))
                    if !cover.isEmpty {
                        RemoteImage(path: cover).frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                    Text(sub).font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(busy == busyKey ? Tr("上传中…") : Tr("换图标"))
                    .font(pf(13)).foregroundColor(C.green)
            }
            .padding(.horizontal, 14).frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /* ------------------------------------------------------- 小零件 */

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(pf(13)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            VStack(spacing: 0) { content() }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
        }
    }

    private func row(_ k: String, _ v: String, tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack {
                Text(k).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(v).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(pf(13.5)).foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func startPick(_ id: String) {
        pickFor = id
        showCoverPick = true
    }

    /* ------------------------------------------------------- 干活 */

    private func load() async {
        data = await API.shared.manageData()
        loading = false
    }

    private func uploadAudio(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let raw = try? Data(contentsOf: url), !raw.isEmpty else {
            msg = Tr("读不到这个文件"); return
        }
        if raw.count > 60 * 1024 * 1024 { msg = Tr("这个音频超过 60MB，先压一下"); return }
        busy = "audio"
        msg = Tr("正在上传音频…")
        Task {
            do {
                let b64 = raw.base64EncodedString()
                let payload: [String: Any] = ["dataUrl": "data:audio/mpeg;base64," + b64, "filename": name]
                let r = try await API.shared.rawUpload(payload)
                audioURL = r.url
                audioName = name
                msg = Tr("音频已上传")
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "音频上传失败"
            }
            busy = ""
        }
    }

    private func uploadPic(_ img: UIImage) {
        let key = pickFor
        busy = key.isEmpty ? "newcover" : key
        Task {
            do {
                let url = try await API.shared.upload(image: img)
                if key.isEmpty {
                    newCoverURL = url
                    msg = Tr("封面已上传")
                } else if key.hasPrefix("mus_") {
                    try await API.shared.manageSetIcon(kind: "music", id: key, cover: url)
                    msg = Tr("音乐图标已换好")
                } else {
                    try await API.shared.manageSetIcon(kind: "miniapp", id: key, cover: url)
                    msg = Tr("游戏图标已换好")
                }
                if !key.isEmpty { await load() }
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "换图标失败"
            }
            busy = ""
        }
    }

    private func addMusic() async {
        busy = "add"
        do {
            try await API.shared.manageSaveMusic(id: "", title: title, artist: artist,
                                                 cover: newCoverURL, url: audioURL, lyrics: lyrics)
            msg = Tr("已加进曲库：") + title
            title = ""; artist = ""; lyrics = ""; audioURL = ""; audioName = ""; newCoverURL = ""
            await load()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
        }
        busy = ""
    }
}
