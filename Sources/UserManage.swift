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
    /// 批量：选多个文件 / 选整个文件夹（一次把一堆歌导进来）
    @State private var showBatchPick = false
    @State private var showFolderPick = false
    @State private var batchTotal = 0
    @State private var batchDone = 0
    /// 正在给谁挑图："" = 上新那首的封面；"mus_xxx" = 那首歌；"g01" = 那款游戏
    @State private var pickFor = ""
    @State private var showCoverPick = false
    /// 正在编辑的小程序/小游戏（点一行进编辑页）
    @State private var editing: MiniApp? = nil

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("管理"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    addSection
                    musicIcons
                    gameIcons
                    miniappsSection
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
                      /* ⚠ 这里**不能只写音频类型**：从别处下载来的歌后缀五花八门
                         （flac / ape / wma / opus / 甚至认不出来的），只写 .audio 的话
                         这些文件在选择器里是灰的、根本点不了（用户反馈的
                         「我要上传的是昨天下载那种格式」就是这个）。
                         放开成 .item = 什么文件都能选，服务器那边会用 ffmpeg 转成 mp3。 */
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            uploadAudio(result)
        }
        /* 一次选好几首 */
        .fileImporter(isPresented: $showBatchPick, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        /* 直接挑一个文件夹：里面的歌全导进来（歌名就用文件名） */
        .fileImporter(isPresented: $showFolderPick, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let dir = urls.first { importFolder(dir) }
        }
        .sheet(isPresented: $showCoverPick) {
            PhotoPicker { img in uploadPic(img) }
        }
        /* 改小程序/小游戏：名字 / 说明 / 图标 emoji / 入口地址 */
        .sheet(item: $editing) { g in
            MiniAppEditSheet(item: g) { await load() }
                .environmentObject(app)
        }
    }

    /* ------------------------------------------------------- 上新音乐 */

    private var addSection: some View {
        card(Tr("上线新音乐")) {
            row(Tr("音频文件"), audioName.isEmpty ? Tr("未选择") : audioName) { showAudioPick = true }
            Text(Tr("mp3 / m4a / flac / wma …什么格式都行，服务器会自动转成 mp3"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 8)
            HairLine(inset: 16)
            row(Tr("批量导入"), batchTotal > 0 ? (Tr("已导入 ") + "\(batchDone)/\(batchTotal)") : Tr("一次选好几首")) { showBatchPick = true }
            HairLine(inset: 16)
            row(Tr("导入整个文件夹"), Tr("文件夹里的歌全进来（歌名=文件名）")) { showFolderPick = true }
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

    /* ------------------------------------------------------- 小程序（图标 + 文字） */

    private var miniappsSection: some View {
        card(Tr("小程序（图标 / 名字 / 说明）")) {
            if let list = data?.apps, !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { HairLine(inset: 70) }
                    Button { editing = a } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                                Text(a.iconText).font(.system(size: 22))
                                if let cv = a.cover, !cv.isEmpty {
                                    RemoteImage(path: cv).frame(width: 46, height: 46)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.name).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                                Text((a.desc ?? "").isEmpty ? a.url : a.desc!)
                                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(Tr("编辑")).font(pf(13)).foregroundColor(C.green)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 14).frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("还没有小程序"))
            }
        }
    }

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
                let payload: [String: Any] = ["dataUrl": "data:" + mimeFor(name) + ";base64," + b64,
                                              "filename": name]
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

    /// 按后缀报正确的 mime（以前不管什么文件都报 audio/mpeg，
    /// 结果服务器把 m4a 也存成 .mp3，扩展名和内容对不上）。认不出来就 octet-stream，
    /// 服务器照样收，并在入库时用 ffmpeg 嗅探真实格式转成 mp3。
    private let audioExts: Set<String> = ["mp3", "m4a", "flac", "wav", "aac", "ogg", "oga",
                                          "opus", "ape", "wma", "aiff", "aif", "amr", "mka", "mp4"]

    /// 挑了一个文件夹：把里面（含子文件夹）的音频挨个导进来
    private func importFolder(_ dir: URL) {
        let ok = dir.startAccessingSecurityScopedResource()
        if !ok { msg = Tr("读不到这个文件夹") ; return }
        var files: [URL] = []
        if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let u as URL in e where audioExts.contains(u.pathExtension.lowercased()) {
                files.append(u)
            }
        }
        guard !files.isEmpty else {
            dir.stopAccessingSecurityScopedResource()
            msg = Tr("这个文件夹里没找到音频文件")
            return
        }
        /* 权限要一直开到导完（下面那个 Task 里读完再释放） */
        importFiles(files, holding: dir)
    }

    /// 批量导入：歌名就用文件名；一首一首来（顺序上传，不炸内存也不炸服务器）
    private func importFiles(_ urls: [URL], holding: URL? = nil) {
        let list = urls.filter { audioExts.contains($0.pathExtension.lowercased()) }
        guard !list.isEmpty else {
            holding?.stopAccessingSecurityScopedResource()
            msg = Tr("没找到能导入的音频文件")
            return
        }
        batchTotal = list.count
        batchDone = 0
        Task {
            defer { holding?.stopAccessingSecurityScopedResource() }
            for u in list {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                do {
                    let raw = try Data(contentsOf: u)
                    if raw.count > 60 * 1024 * 1024 { batchDone += 1; continue }
                    let payload: [String: Any] = [
                        "dataUrl": "data:" + mimeFor(u.lastPathComponent) + ";base64," + raw.base64EncodedString(),
                        "filename": u.lastPathComponent
                    ]
                    let r = try await API.shared.rawUpload(payload)
                    try await API.shared.manageSaveMusic(id: "",
                                                         title: u.deletingPathExtension().lastPathComponent,
                                                         artist: "", cover: "", url: r.url, lyrics: "")
                } catch {
                    /* 单首失败不影响后面的 */
                }
                batchDone += 1
                msg = Tr("正在导入 ") + "\(batchDone)/\(batchTotal)"
            }
            msg = Tr("导入完成 ") + "\(batchDone)/\(batchTotal)"
            await load()
        }
    }

    private func mimeFor(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "m4r", "mp4", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg", "oga", "opus": return "audio/ogg"
        case "aiff", "aif": return "audio/aiff"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
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

/* ============================================================
   编辑一个小程序 / 小游戏：名字、说明、图标 emoji、图标图片、入口地址
   （用户要的「小程序图标文字更换加入我的管理」）
   ============================================================ */

struct MiniAppEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MiniApp
    /// 存完通知外面刷新列表
    var onSaved: () async -> Void

    @State private var name = ""
    @State private var desc = ""
    @State private var icon = ""
    @State private var group = ""
    @State private var url = ""
    @State private var cover = ""
    @State private var showPic = false
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("编辑小程序"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(busy ? C.subLabel : C.green)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    /* 图标：左边一个预览，点一下换图 */
                    Button { showPic = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.pageBg)
                                Text(icon.isEmpty ? "🧩" : icon).font(.system(size: 26))
                                if !cover.isEmpty {
                                    RemoteImage(path: cover).frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("图标图片")).font(pf(16)).foregroundColor(C.label)
                                Text(cover.isEmpty ? Tr("点一下选张图") : Tr("已设置，点一下换一张"))
                                    .font(pf(12)).foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16).frame(height: 76)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(C.cardBg)

                    textRow(Tr("名字"), $name)
                    textRow(Tr("说明"), $desc)
                    textRow(Tr("图标（emoji）"), $icon)
                    textRow(Tr("分组"), $group)
                    textRow(Tr("入口地址"), $url)

                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.top, 12)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 8)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            name = item.name
            desc = item.desc ?? ""
            icon = item.icon ?? ""
            group = item.group ?? ""
            url = item.url
            cover = item.cover ?? ""
        }
        .sheet(isPresented: $showPic) {
            PhotoPicker { img in
                busy = true
                Task {
                    if let u = try? await API.shared.upload(image: img) {
                        cover = u
                        msg = Tr("图标图片已上传，别忘了保存")
                    } else {
                        msg = Tr("图片上传失败")
                    }
                    busy = false
                }
            }
        }
    }

    private func textRow(_ k: String, _ v: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(k).font(pf(16)).foregroundColor(C.label)
                .frame(width: 92, alignment: .leading)
            TextField("", text: v)
                .font(pf(16))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(C.cardBg)
        .overlay(alignment: .bottom) { HairLine(inset: 16) }
    }

    private func save() async {
        busy = true
        do {
            try await API.shared.manageSaveMiniApp(id: item.id, name: name, desc: desc,
                                                   icon: icon, group: group, url: url)
            if cover != (item.cover ?? "") {
                try await API.shared.manageSetIcon(kind: "miniapp", id: item.id, cover: cover)
            }
            await onSaved()
            dismiss()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
        }
        busy = false
    }
}
