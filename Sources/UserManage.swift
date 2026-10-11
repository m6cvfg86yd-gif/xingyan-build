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
    /// 系统通知开关（照微信那个「微信团队」号）
    @State private var snOn = true
    @State private var snTypes: [String: Bool] = [:]
    /// 官方号（星言团队 / 星联世界 …）：名字 + 头像，像换头像一样换
    @State private var officials: [API.OfficialAccount] = []
    @State private var editingOfficial: API.OfficialAccount? = nil
    /// 音乐多选删除：选中了哪些 / 是不是在选
    @State private var pickingMusic = false
    @State private var pickedMusic: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("管理"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    addSection
                    musicIcons
                    gameIcons
                    miniappsSection
                    sysNoticeSection
                    officialSection
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
        /* 改官方号：名字 + 头像（点一下选张图，和换头像一样） */
        .sheet(item: $editingOfficial) { o in
            OfficialEditSheet(item: o) { await load() }
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
                HStack {
                    Text(pickingMusic ? (Tr("已选 ") + "\(pickedMusic.count)" + Tr(" 首")) : Tr("点每首右边的图换封面"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                    Button {
                        if pickingMusic { Task { await deletePicked() } }
                        else { pickingMusic = true }
                    } label: {
                        Text(pickingMusic ? Tr("删除选中") : Tr("批量删除"))
                            .font(pf(13, .medium))
                            .foregroundColor(pickingMusic ? C.red : C.green)
                    }
                    .buttonStyle(.plain)
                    if pickingMusic {
                        Button { pickingMusic = false; pickedMusic = [] } label: {
                            Text(Tr("取消")).font(pf(13)).foregroundColor(C.subLabel)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 10)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                HairLine(inset: 16)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { HairLine(inset: 70) }
                    iconRow(cover: t.cover ?? "", title: t.title, sub: t.artistText,
                            busyKey: t.id, id: t.id,
                            picking: pickingMusic, picked: pickedMusic.contains(t.id)) {
                        if pickingMusic {
                            if pickedMusic.contains(t.id) { pickedMusic.remove(t.id) }
                            else { pickedMusic.insert(t.id) }
                        } else {
                            startPick(t.id)
                        }
                    }
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("曲库还是空的"))
            }
        }
    }

    /* ------------------------------------------------------- 游戏图标 */

    /* ------------------------------------------------------- 小程序（图标 + 文字） */

    /* 系统通知（「星言团队」那个号）：开关就在这儿管 */
    private var sysNoticeSection: some View {
        card(Tr("系统通知（星言团队）")) {
            tipRow(Tr("总开关"), Binding(
                get: { snOn },
                set: { v in
                    snOn = v
                    Task { try? await API.shared.saveSysNotice(enabled: snOn, types: snTypes) }
                }
            ))
            ForEach(snKeys, id: \.key) { k in
                HairLine(inset: 16)
                tipRow(Tr(k.name), Binding(
                    get: { snTypes[k.key] ?? true },
                    set: { v in
                        snTypes[k.key] = v
                        Task { try? await API.shared.saveSysNotice(enabled: snOn, types: snTypes) }
                    }
                ))
            }
            HairLine(inset: 16)
            Text(Tr("开着的时候：新设备登录 / 改密码 / 改手机号 / 收到转账 / 后台公告，都会用那个号给用户发一张卡片（会话列表有红点）"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var snKeys: [(key: String, name: String)] {
        [("login", "登录提醒"), ("security", "安全提醒"), ("pay", "支付通知"), ("notice", "官方公告")]
    }

    /// 带开关的一行
    private func tipRow(_ title: String, _ on: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(pf(15.5)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Toggle("", isOn: on).labelsHidden().tint(C.green)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    /* ------------------------------------------------------- 官方号（名字 / 头像） */

    /* 「星言团队」这种官方号：名字和头像都能在这儿换，换法跟换头像一模一样
       （点一行 → 进去点头像选张图、点名字改字 → 保存）。只有管理（ops）能进这一页。 */
    private var officialSection: some View {
        card(Tr("官方号（名字 / 头像）")) {
            if officials.isEmpty {
                hint(loading ? Tr("正在加载…") : Tr("还没有官方号"))
            } else {
                ForEach(Array(officials.enumerated()), id: \.element.key) { i, o in
                    if i > 0 { HairLine(inset: 72) }
                    Button { editingOfficial = o } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                                Text(o.name.isEmpty ? "★" : String(o.name.prefix(1)))
                                    .font(pf(20)).foregroundColor(C.subLabel)
                                if let av = o.avatar, !av.isEmpty {
                                    RemoteImage(path: av).frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(o.name).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                                Text((o.desc ?? "").isEmpty ? Tr("点一下换名字 / 头像") : o.desc!)
                                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(Tr("编辑")).font(pf(13)).foregroundColor(C.green)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 14).frame(height: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HairLine(inset: 16)
            Text(Tr("「星言团队」和「星联世界」这些官方号的名字、头像都在这儿换：头像点一下选张图，名字点一下改字。改完所有人那边立刻变，不用出包。"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

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
                         busyKey: String, id: String = "",
                         picking: Bool = false, picked: Bool = false,
                         tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack(spacing: 12) {
                if picking {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .foregroundColor(picked ? C.green : C.subLabel)
                }
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
                if !picking {
                    Text(busy == busyKey ? Tr("上传中…") : Tr("换图标"))
                        .font(pf(13)).foregroundColor(C.green)
                }
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
        /* 官方号清单（名字 / 头像） */
        if let list = try? await API.shared.officialAccounts() { officials = list }
        /* 系统通知那几个开关要显示服务器上的真实状态，不能一直默认「全开」 */
        let cfg = await API.shared.sysNoticeCfg()
        snOn = cfg.enabled
        snTypes = cfg.types
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

    /// 批量删除选中的歌
    private func deletePicked() async {
        let ids = Array(pickedMusic)
        guard !ids.isEmpty else { msg = Tr("先勾几首再删"); return }
        busy = "del"
        do {
            try await API.shared.manageRemoveMusic(ids: ids)
            msg = Tr("已删除 ") + "\(ids.count)" + Tr(" 首")
            pickedMusic = []
            pickingMusic = false
            await load()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "删除失败"
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

/* ============================================================
   改一个官方号（「星言团队」/「星联世界」/ AI 助手 …）：名字 + 头像
   —— 头像跟换头像一样：点一下选张图、上传、保存。
   用户要的「团队名字后图标都可以在管理里换，包括新闻这些的官方图标」。
   ============================================================ */

struct OfficialEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: API.OfficialAccount
    /// 存完通知外面刷新列表
    var onSaved: () async -> Void

    @State private var name = ""
    @State private var avatar = ""
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("官方号"), back: { dismiss() }) {
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
                    /* 头像：点一下选张图（和换头像一样） */
                    Button { pickAvatar() } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.pageBg)
                                Text(name.isEmpty ? "★" : String(name.prefix(1)))
                                    .font(pf(24)).foregroundColor(C.subLabel)
                                if !avatar.isEmpty {
                                    RemoteImage(path: avatar).frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("头像")).font(pf(16)).foregroundColor(C.label)
                                Text(busy ? Tr("上传中…") : Tr("点一下选张图片"))
                                    .font(pf(12)).foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16).frame(height: 84)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(C.cardBg)

                    textRow(Tr("名字"), $name)

                    HStack(spacing: 10) {
                        Text(Tr("标识")).font(pf(16)).foregroundColor(C.label)
                            .frame(width: 92, alignment: .leading)
                        Text(item.key).font(pf(15)).foregroundColor(C.subLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(C.cardBg)
                    .overlay(alignment: .bottom) { HairLine(inset: 16) }

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
            avatar = item.avatar ?? ""
        }
    }

    /* 选头像：**不用嵌套的 sheet**（这一页本身就是 sheet，再从里面弹一个 PHPicker，
       有时候会直接崩 / 第二次点没反应）。走 AlbumPicker：它自己找到最上面的控制器
       present，最稳；而且回来的图是**降采样**过的，不再把整张原图解进内存。 */
    private func pickAvatar() {
        CrashCatcher.note("官方号", "点头像 key=" + item.key)
        AlbumPicker.present { img in
            CrashCatcher.note("官方号", "选到图 \(Int(img.size.width))x\(Int(img.size.height)) key=" + item.key)
            uploadAvatar(img)
        }
    }

    private func uploadAvatar(_ img: UIImage) {
        busy = true
        Task {
            do {
                let u = try await API.shared.upload(image: img)
                avatar = u
                msg = Tr("头像已上传，点右上角保存")
                CrashCatcher.note("官方号", "头像上传完 key=" + item.key)
            } catch {
                msg = (error as? APIError)?.errorDescription ?? Tr("图片上传失败")
                CrashCatcher.note("官方号", "头像上传失败 key=" + item.key + "：" + msg)
            }
            busy = false
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
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if nm.isEmpty { msg = Tr("名字不能为空"); return }
        busy = true
        do {
            try await API.shared.saveOfficial(key: item.key, name: nm, avatar: avatar)
            CrashCatcher.note("官方号", "保存完 key=" + item.key + " name=" + nm)
            await onSaved()
            dismiss()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
            CrashCatcher.note("官方号", "保存失败 key=" + item.key + "：" + msg)
        }
        busy = false
    }
}
