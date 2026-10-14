import SwiftUI

/* ============================================================
   补齐「产品功能清单」里缺的那几页：
     · 群列表（通讯录 → 群聊）
     · 查找聊天记录（聊天页「⋯」→ 查找聊天记录）
     · 银行卡 / 绑定银行卡（钱包）
     · 意见反馈、关于我们 / 版本更新（设置）
     · 密码找回（登录页 → 忘记密码）
   ============================================================ */

/* ---------------------------------------------------------- 群列表 */

struct GroupListView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onOpenChat: (Chat) -> Void

    private var groups: [Chat] {
        app.chats.filter { $0.type == "group" }
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("群聊"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    if groups.isEmpty {
                        Text(Tr("还没有群聊，在「＋ → 发起群聊」里建一个"))
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        GroupCard {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { idx, chat in
                                Button {
                                    /* 这一行只负责「上报：用户点了哪个群」，导航交给调用方。
                                       以前这里先 dismiss() 再 onOpenChat()：两个导航动作挤在同一帧里，
                                       dismiss 那一刀会把紧接着压上去的聊天页一起顶掉 ——
                                       表现就是用户在星联点群聊「点了没反应」。 */
                                    onOpenChat(chat)
                                } label: {
                                    HStack(spacing: 12) {
                                        Avatar(path: chat.avatar ?? "", size: 44, radius: 6)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(chat.name)
                                                .font(pf(16.5))
                                                .foregroundColor(C.label)
                                                .lineLimit(1)
                                            Text("\(chat.memberCount ?? 0) 位成员")
                                                .font(pf(12.5))
                                                .foregroundColor(C.subLabel)
                                        }
                                        Spacer(minLength: 0)
                                        Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 62)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if idx < groups.count - 1 { HairLine(inset: 72) }
                            }
                        }
                        .padding(.top, 8)
                    }
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await app.loadChats() }
    }
}

/* ---------------------------------------------------------- 查找聊天记录 */

struct ChatSearchView: View {
    let chat: Chat
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var hits: [FoundMessage] = []
    @State private var busy = false
    @State private var done = false
    /// 打字停一下自动搜的那次任务（下一次打字就取消掉）
    @State private var typingTask: Task<Void, Never>? = nil
    /// 每次搜索发一个号，晚回来的旧结果不许覆盖新结果
    @State private var token = 0
    /// 上面那排分类（照微信「查找聊天内容」）：选了就只留这一类
    @State private var filter = ""
    /// 分类筛选用的那批（没打字时用它）：从服务器拉最近 200 条，本地按类型筛
    @State private var localRows: [FoundMessage] = []
    @State private var localLoaded = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("查找聊天记录"), back: { dismiss() })

            searchBar
            if trimmed.isEmpty { chips }
            resultArea
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear { focused = true }
        .onDisappear { typingTask?.cancel() }
    }

    /* ---------------------------------------------------------- 顶上那条搜索框 */

    private var trimmed: String { keyword.trimmingCharacters(in: .whitespaces) }

    private var searchBar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(C.searchIcon)
                TextField(Tr("搜索聊天记录"), text: $keyword)
                    .font(pf(15))
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { search() }
                    .onChange(of: keyword) { _ in typingChanged() }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(C.searchIcon2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.searchBg))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))

            Button { search() } label: {
                Text(Tr("搜索"))
                    .font(pf(14.5, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 34)
                    .background(Capsule().fill(LinearGradient(colors: PanelTint.green,
                                                              startPoint: .topLeading,
                                                              endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
            .opacity(trimmed.isEmpty ? 0.45 : 1)
            .disabled(trimmed.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /* ---------------------------------------------------------- 结果区 */

    /* ------------- 分类胶囊（照微信「查找聊天内容」那一排） ------------- */

    private let chipList: [(String, String)] = [
        ("图片与视频", "image"), ("文件", "file"), ("链接", "link"), ("音乐与音频", "music"),
        ("交易", "trade"), ("位置", "location"), ("名片", "card"), ("表情", "sticker")
    ]

    private var chips: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(chipList, id: \.1) { c in
                Button {
                    filter = (filter == c.1) ? "" : c.1
                    loadLocalIfNeeded()
                } label: {
                    Text(Tr(c.0))
                        .font(pf(13))
                        .foregroundColor(filter == c.1 ? .white : C.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule().fill(filter == c.1 ? C.green : C.searchBg))
                        .overlay(Capsule().stroke(C.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// 分类筛选要用的那份聊天记录（拉一次就够）
    private func loadLocalIfNeeded() {
        guard !localLoaded else { return }
        localLoaded = true
        Task {
            if let r = try? await API.shared.messages(chatId: chat.id, limit: 200) {
                localRows = r.messages.reversed().compactMap { m in
                    FoundMessage(id: m.id, seq: m.seq, kind: m.kindName, content: m.body,
                                 createdAt: m.createdAt, senderId: m.senderId, senderName: m.senderName)
                }
            }
        }
    }

    /// 这一类要不要留
    private func kindMatch(_ kind: String, _ f: String) -> Bool {
        switch f {
        case "image":    return ["image", "images", "video", "livephoto"].contains(kind)
        case "file":     return kind == "file"
        case "link":     return ["link", "oa"].contains(kind)
        case "music":    return ["music", "audio"].contains(kind)
        case "trade":    return ["transfer", "redpacket", "gift"].contains(kind)
        case "location": return kind == "location"
        case "card":     return kind == "card"
        case "sticker":  return kind == "sticker"
        default:         return true
        }
    }

    /// 现在要显示的那一批：打了字看搜索结果，没打字看分类
    private var rows: [FoundMessage] {
        let base = trimmed.isEmpty ? localRows : hits
        guard !filter.isEmpty else { return base }
        return base.filter { kindMatch($0.kind ?? "", filter) }
    }

    @ViewBuilder
    private var resultArea: some View {
        if busy && hits.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(Tr("正在翻这个会话的全部历史…"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 56)
            Spacer(minLength: 0)
        } else if rows.isEmpty {
            /* 什么都没输入 / 没选分类 = 就是上面那排分类，下面留白（和微信一样） */
            if trimmed.isEmpty && filter.isEmpty { Spacer(minLength: 0) } else { emptyState }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    resultHeader
                    PanelCard {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, m in
                            resultRow(m)
                            if idx < rows.count - 1 { PanelDivider() }
                        }
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var resultHeader: some View {
        HStack(spacing: 6) {
            Text(Tr("聊天记录") + " · \(rows.count) 条")
                .font(pf(12.5, .medium))
                .foregroundColor(C.subLabel)
            Spacer(minLength: 0)
            if rows.count >= 60 {
                Text(Tr("只显示最近 60 条"))
                    .font(pf(11.5))
                    .foregroundColor(C.subLabel)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func resultRow(_ m: FoundMessage) -> some View {
        let look = Self.look(for: m.kind)
        return HStack(alignment: .top, spacing: 11) {
            PanelIcon(symbol: look.symbol, colors: look.colors, size: 28)
            VStack(alignment: .leading, spacing: 6) {
                highlighted(preview(m))
                    .font(pf(15))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text((m.senderName?.isEmpty == false) ? m.senderName! : Tr("消息"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                    Text("·").font(pf(12)).foregroundColor(C.subLabel)
                    Text(TimeFmt.bubble(m.createdAt ?? ""))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xEDF1F5), Color(hex: 0xDCE4EC)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 27, weight: .light))
                    .foregroundColor(C.subLabel)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)

            Text(!filter.isEmpty
                 ? Tr("这一类还没有记录")
                 : (done ? Tr("没找到") + "「\(trimmed)」" + Tr("相关的聊天记录")
                         : Tr("输入关键字，或点上面对应的分类")))
                .font(pf(14))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            if !done {
                Text(Tr("文字、图片、文件、红包…都在这份历史里，搜到什么都能对上"))
                    .font(pf(12))
                    .foregroundColor(C.subLabel.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }

    /* ---------------------------------------------------------- 干活 */

    /// 点了「搜索」或者键盘回车：立刻搜，不等那 0.45 秒
    private func search() {
        typingTask?.cancel()
        let q = trimmed
        guard !q.isEmpty else { hits = []; done = false; return }
        busy = true
        focused = false
        token += 1
        let mine = token
        Task {
            let res = await API.shared.searchMessages(chatId: chat.id, query: q)
            guard mine == token else { return }      // 又搜了新的，这次结果作废
            hits = res
            busy = false
            done = true
        }
    }

    /// 打字停下来 0.45 秒自动搜一次（微信也是边打边出结果，不用点确认）
    private func typingChanged() {
        typingTask?.cancel()
        let q = trimmed
        guard !q.isEmpty else {
            hits = []
            done = false
            busy = false
            return
        }
        typingTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            busy = true
            token += 1
            let mine = token
            let res = await API.shared.searchMessages(chatId: chat.id, query: q)
            guard mine == token else { return }
            hits = res
            busy = false
            done = true
        }
    }

    /// 结果里那条消息该显示成什么（图片 / 视频这种 content 是网址，直接显示会很难看）
    private func preview(_ m: FoundMessage) -> String {
        let c = m.content ?? ""
        switch (m.kind ?? "text") {
        case "text":     return ClassicEmojiSet.expand(c)
        case "image":    return Tr("[图片]")
        case "video":    return Tr("[视频]")
        case "voice", "audio": return Tr("[语音]")
        case "location": return Tr("[位置]")
        case "file":
            if let d = c.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let n = o["name"] as? String, !n.isEmpty {
                return Tr("[文件] ") + n
            }
            return Tr("[文件]")
        case "redpacket": return Tr("[红包]")
        case "transfer":  return Tr("[转账]")
        case "gift":      return Tr("[礼物]")
        case "call":      return Tr("[通话]")
        case "card":      return Tr("[名片]")
        case "sticker", "emoji": return Tr("[表情]")
        default:          return c.isEmpty ? Tr("[消息]") : ClassicEmojiSet.expand(c)
        }
    }

    /// 命中的关键字标绿加粗（一段一段拼起来，微信就是这样）
    private func highlighted(_ text: String) -> Text {
        let kw = trimmed
        guard !kw.isEmpty else { return Text(text) }
        var out = Text("")
        var rest = Substring(text)
        while let r = rest.range(of: kw, options: [.caseInsensitive]) {
            out = out + Text(String(rest[rest.startIndex..<r.lowerBound]))
            out = out + Text(String(rest[r])).foregroundColor(C.green).bold()
            rest = rest[r.upperBound...]
        }
        return out + Text(String(rest))
    }

    /// 消息类型对应的图标和颜色
    private static func look(for kind: String?) -> (symbol: String, colors: [Color]) {
        switch (kind ?? "text") {
        case "image":    return ("photo.fill", PanelTint.teal)
        case "video":    return ("video.fill", PanelTint.blue)
        case "voice", "audio": return ("mic.fill", PanelTint.purple)
        case "file":     return ("doc.fill", PanelTint.orange)
        case "location": return ("location.fill", PanelTint.green)
        case "redpacket": return ("gift.fill", PanelTint.red)
        case "transfer": return ("creditcard.fill", PanelTint.orange)
        case "call":     return ("phone.fill", PanelTint.blue)
        case "card":     return ("person.crop.square.fill", PanelTint.blue)
        case "gift":     return ("gift.fill", PanelTint.purple)
        case "sticker", "emoji": return ("face.smiling.fill", PanelTint.orange)
        default:         return ("text.bubble.fill", PanelTint.gray)
        }
    }
}

/* ---------------------------------------------------------- 银行卡 */

struct BankCardsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [BankCard] = []
    @State private var loading = true
    @State private var showAdd = false
    @State private var bank = "招商银行"
    @State private var number = ""
    @State private var holder = ""
    @State private var busy = false

    /// 可选银行（从服务器拉，带品牌色；拉不到就用下面这份兜底）
    @State private var bankList: [API.BankInfo] = []
    private var banks: [String] {
        let names = bankList.map { $0.name }
        return names.isEmpty
            ? ["工商银行", "建设银行", "农业银行", "中国银行", "招商银行", "交通银行", "邮储银行", "其他银行"]
            : names
    }

    /// 这家银行的品牌色（服务器给了就用，没给就按名字兜一个）
    private func bankColor(_ name: String) -> Color {
        if let c = bankList.first(where: { $0.name == name })?.color,
           case let hex = c.replacingOccurrences(of: "#", with: ""),
           hex.count == 6, let v = Int(hex, radix: 16) {
            return Color(hex: UInt32(v))
        }
        let table: [String: Int] = ["工商银行": 0xC8161D, "建设银行": 0x0B4DA2, "农业银行": 0x0E8B4A,
                                    "中国银行": 0xB01F24, "招商银行": 0xC7000B, "交通银行": 0x1B4E9B,
                                    "邮储银行": 0x0E7B40, "中信银行": 0xD0202F, "民生银行": 0x0E5EA8,
                                    "浦发银行": 0x0A4C8B, "兴业银行": 0x1F4C9C, "光大银行": 0x8B1A2B,
                                    "平安银行": 0xF36F21, "广发银行": 0xC8102E, "华夏银行": 0x0E5EA8,
                                    "微众银行": 0x0E9C6B, "网商银行": 0x1F7BE0]
        return Color(hex: UInt32(table[name] ?? 0x8A8A8E))
    }

    private func bankShort(_ name: String) -> String {
        if let s = bankList.first(where: { $0.name == name })?.short, !s.isEmpty { return s }
        return String(name.prefix(1))
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("银行卡"), back: { dismiss() }) {
                Button {
                    showAdd = true
                } label: {
                    Text(Tr("绑定"))
                        .font(pf(16, .medium))
                        .foregroundColor(C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if loading {
                        ProgressView().padding(.top, 40)
                    } else if cards.isEmpty {
                        Text("还没有绑定银行卡\n点右上角「绑定」加一张")
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                    } else {
                        GroupCard {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, c in
                                HStack(spacing: 12) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(C.green)
                                        .frame(width: 34, height: 34)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(C.searchBg))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.bank ?? "银行卡")
                                            .font(pf(16))
                                            .foregroundColor(C.label)
                                        Text(((c.type ?? "储蓄卡") + " · 尾号 \(c.tail ?? "****")") + ((c.holder ?? "").isEmpty ? "" : " · \(c.holder!)"))
                                            .font(pf(12.5))
                                            .foregroundColor(C.subLabel)
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        unbind(c.id)
                                    } label: {
                                        Text(Tr("解绑"))
                                            .font(pf(13.5))
                                            .foregroundColor(C.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 66)
                                if idx < cards.count - 1 { HairLine(inset: 62) }
                            }
                        }
                        .padding(.top, 8)
                    }
                    Text(Tr("只保存银行、尾号和持卡人，完整卡号不会留在手机上。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await reload() }
        .task { bankList = await API.shared.banks() }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    /* 银行：横向摆一排名牌小方块（每家一个品牌色），跟微信一样点一下就选中 */
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Tr("选择银行")).font(pf(15)).foregroundColor(C.label)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(banks, id: \.self) { name in
                                    let on = (bank == name)
                                    Button { bank = name } label: {
                                        HStack(spacing: 6) {
                                            Text(bankShort(name))
                                                .font(pf(13, .semibold))
                                                .foregroundColor(.white)
                                                .frame(width: 22, height: 22)
                                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(bankColor(name)))
                                            Text(name).font(pf(14)).foregroundColor(on ? C.label : C.subLabel)
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(height: 36)
                                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(on ? C.searchBg : C.cardBg))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(on ? C.green : C.hairline, lineWidth: on ? 1.4 : 0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    HairLine(color: C.navLine)
                    HairLine(color: C.navLine)
                    field("卡号") {
                        TextField("16~19 位卡号", text: $number)
                            .keyboardType(.numberPad)
                    }
                    HairLine(color: C.navLine)
                    field("持卡人") {
                        TextField("姓名", text: $holder)
                    }
                    Button {
                        add()
                    } label: {
                        Text(busy ? "绑定中…" : "确认绑定")
                            .font(pf(16, .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(C.green)
                            .cornerRadius(12)
                    }
                    .disabled(busy)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                }
                .padding(.top, 10)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("绑定银行卡"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { showAdd = false } } }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ c: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            c()
        }
        .font(pf(15))
        .frame(height: 54)
        .padding(.horizontal, 14)
        .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
    }

    private func reload() async {
        cards = await API.shared.bankCards()
        loading = false
    }

    private func add() {
        let n = number.trimmingCharacters(in: .whitespaces)
        let h = holder.trimmingCharacters(in: .whitespaces)
        if n.count < 16 { app.show(Tr("卡号要 16~19 位")); return }
        if h.isEmpty { app.show(Tr("请填持卡人姓名")); return }
        busy = true
        Task {
            if let err = await API.shared.addBankCard(bank: bank, number: n, holder: h) {
                app.show(err)
            } else {
                app.show(Tr("绑定成功"))
                showAdd = false
                number = ""
                holder = ""
                await reload()
            }
            busy = false
        }
    }

    private func unbind(_ id: String) {
        Task {
            if let err = await API.shared.deleteBankCard(id: id) {
                app.show(err)
            } else {
                app.show(Tr("已解绑"))
                await reload()
            }
        }
    }
}

/* ---------------------------------------------------------- 关于我们 / 版本更新 */

struct AboutView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @State private var latest = ""
    @State private var appName = "CHRIS 聊天"
    @ObservedObject private var push = PushCenter.shared
    /// 服务器那边推送配置好没（没配好就是「等服务器配置」）
    @State private var pushServerReady = false

    private var pushText: String {
        if !push.authorized { return Tr("通知权限没开") }
        if push.token.isEmpty { return push.lastError.isEmpty ? Tr("登记中…") : push.lastError }
        if pushServerReady { return Tr("已开启") }
        return Tr("等服务器配置")
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("关于我们"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Group {
                            if let img = AppIconImage.image {
                                Image(uiImage: img).resizable()
                            } else {
                                RoundedRectangle(cornerRadius: 16).fill(C.green)
                            }
                        }
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text(appName)
                            .font(pf(19, .semibold))
                            .foregroundColor(C.label)
                        Text("版本 1.0（打包 \(AppInfo.build)）")
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)

                    GroupCard {
                        /* 2026-10-12 用户「关于我们的页面微信化一点」：
                           照微信「关于微信」那一页 —— 图标/名字/版本居中在上，
                           下面一组行：功能介绍 / 隐私保护指引 / 版本更新（+ 服务器、推送自检），
                           最底下居中一行小灰字版权。 */
                        Button { showFeature = true } label: {
                            aboutRow(Tr("功能介绍"))
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        Button { showPrivacy = true } label: {
                            aboutRow(Tr("隐私保护指引"))
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        Button {
                            checkVersion()
                        } label: {
                            HStack {
                                Text(Tr("版本更新")).font(pf(16)).foregroundColor(C.label)
                                Spacer()
                                Text(checking ? "检查中…" : (latest.isEmpty ? "检查更新" : latest))
                                    .font(pf(14))
                                    .foregroundColor(C.subLabel)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        HStack {
                            Text(Tr("服务器")).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                       Text(API.shared.base)
                               .font(pf(13))
                               .foregroundColor(C.subLabel)
                               .lineLimit(1)
                               .truncationMode(.middle)
                       }
                       .padding(.horizontal, 16)
                       .frame(height: 52)
                        HairLine(inset: 16)
                        /* 推送自检：权限同意没、服务器那边配好没、这台手机登记过没 */
                        HStack {
                            Text(Tr("推送通知")).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                            Text(pushText)
                                .font(pf(13))
                                .foregroundColor(C.subLabel)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }

                    Text(Tr("自建即时通讯：账号、聊天记录、朋友圈都存在你自己的服务器上，不上传第三方。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 30)
                        .padding(.top, 18)
                    /* 微信那一页最下面就是一行居中的小灰字版权 */
                    Text("© 2026 " + appName + Tr(" · 保留所有权利"))
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            if let b = await API.shared.branding(), let n = b.appName, !n.isEmpty { appName = n }
            if let s = await API.shared.pushStatus() { pushServerReady = (s.configured == true && s.enabled == true) }
        }
        .sheet(isPresented: $showFeature) { aboutText(Tr("功能介绍"), featureText) }
        .sheet(isPresented: $showPrivacy) { aboutText(Tr("隐私保护指引"), privacyText) }
    }

    /* ---------------- 关于页的两行文字 + 两段正文（照微信那两页） ---------------- */

    @State private var showFeature = false
    @State private var showPrivacy = false

    private var featureText: String {
        Tr("星言是一款自建服务器的即时通讯：")
            + Tr("\n· 聊天：单聊 / 群聊，文字、图片、语音、视频、文件、位置、名片、红包、转账")
            + Tr("\n· 通话：一对一和群里的语音 / 视频通话")
            + Tr("\n· 朋友圈：发动态、图片和视频，点赞评论，可设可见范围")
            + Tr("\n· 视界：视频号、直播、听一听、小游戏、小程序")
            + Tr("\n· 其他：收藏、笔记、卡包、小店与商城、成长等级、状态、人脸核身")
            + Tr("\n\n数据都存你自己的服务器上，不经过第三方。")
    }

    private var privacyText: String {
        Tr("我们只收集提供服务所必需的信息，并且都保存在你自己的服务器上：")
            + Tr("\n· 账号：手机号 / 用户名，用来登录和找回")
            + Tr("\n· 资料：昵称、头像、性别、地区（不填也能用）")
            + Tr("\n· 内容：聊天记录、朋友圈、收藏 —— 只在你的服务器上，用于同步给你自己的设备")
            + Tr("\n· 权限：相机 / 麦克风 / 相册 / 通讯录 / 定位，只在对应功能里用，可随时在系统设置里关掉")
            + Tr("\n\n我们不会把这些信息卖给或提供给第三方；注销账号后服务器上的数据按你的选择删除。")
    }

    private func aboutRow(_ title: String) -> some View {
        HStack {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 0)
            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    private func aboutText(_ title: String, _ body: String) -> some View {
        VStack(spacing: 0) {
            NavBar(title: title, back: { showFeature = false; showPrivacy = false })
            ScrollView(showsIndicators: false) {
                Text(body)
                    .font(pf(15))
                    .foregroundColor(C.label)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func checkVersion() {
        checking = true
        Task {
            if let v = await API.shared.serverVersion() {
                latest = v.isEmpty ? "已是最新" : "服务器版本 \(v)"
            } else {
                latest = "连不上服务器"
            }
            checking = false
        }
    }
}

/* ---------------------------------------------------------- 密码找回 */

/* ---------------------------------------------------------- 生日选择 */

struct BirthdayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var birthday: String

    @State private var date = Date()

    var body: some View {
        /* 整页 push（个人信息的子项）：不再自带 NavigationStack */
        VStack(spacing: 0) {
            NavBar(title: Tr("选择生日"), back: { dismiss() }) {
                Button {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    birthday = f.string(from: date)
                    dismiss()
                } label: {
                    Text(Tr("确定")).font(pf(15.5, .medium)).foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.top, 10)
                Spacer()
            }
            .background(C.pageBg)
            .onAppear {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: birthday) { date = d }
                else {
                    var c = DateComponents()
                    c.year = 2000; c.month = 1; c.day = 1
                    date = Calendar.current.date(from: c) ?? Date()
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}

struct ResetPasswordSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    field {
                        TextField("手机号", text: $phone).keyboardType(.numberPad)
                    }
                    HairLine(color: C.navLine)
                    field {
                        TextField("验证码", text: $code).keyboardType(.numberPad)
                        Button(Tr("获取验证码")) { sendCode() }
                            .font(.system(size: 14))
                            .foregroundColor(C.loginGreen)
                    }
                    HairLine(color: C.navLine)
                    field {
                        SecureField("新密码（至少 6 位）", text: $newPassword)
                    }

                    if let e = error {
                        Text(e).font(.system(size: 13)).foregroundColor(C.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }

                    Button { submit() } label: {
                        Text(busy ? "请稍候…" : "重置密码并登录")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(LoginTheme.accent)
                            .cornerRadius(16)
                    }
                    .disabled(busy)
                    .padding(.top, 20)

                    Text(Tr("验证码和「手机号登录」共用，5 分钟内有效。重置后其他设备会自动退出登录。"))
                        .font(.system(size: 12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("密码找回"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } } }
        }
    }

    private func field<Content: View>(@ViewBuilder _ c: () -> Content) -> some View {
        HStack(spacing: 8) { c() }
            .font(.system(size: 15))
            .frame(height: 54)
            .padding(.horizontal, 14)
            .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
    }

    private func sendCode() {
        let p = phone.trimmingCharacters(in: .whitespaces)
        if p.count < 5 { error = "请填写手机号"; return }
        error = nil
        Task {
            do {
                if let dev = try await API.shared.phoneCode(phone: p) {
                    code = dev
                    app.show("验证码：\(dev)")
                } else { app.show(Tr("验证码已发送")) }
            } catch { self.error = (error as? APIError)?.errorDescription ?? "发送失败" }
        }
    }

    private func submit() {
        let p = phone.trimmingCharacters(in: .whitespaces)
        if p.isEmpty || code.isEmpty { error = "请填手机号和验证码"; return }
        if newPassword.count < 6 { error = "新密码至少 6 位"; return }
        busy = true
        error = nil
        Task {
            let r = await API.shared.resetPassword(phone: p, code: code, newPassword: newPassword)
            if let err = r.error {
                error = err
                busy = false
                return
            }
            do {
                /* 重置接口已经把登录态发下来了（Set-Cookie → App 收进 token），
                   这里只要把自己的资料拉回来就行；不用再走一次登录，
                   也就不会被登录滑动验证挡住。 */
                app.me = try? await API.shared.me()
                dismiss()
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "重置成功，但自动登录失败，请用新密码登录"
                busy = false
            }
        }
    }
}
