import SwiftUI

/* ============================================================
   星联世界（新闻）

   两个地方用同一份排版：
     · 发现 → 星联世界           （NewsView = 顶栏 + 新闻流）
     · 会话里「星联世界」机器人那一页（ChatDetailView 里直接塞 NewsFeedView）

   版式对着腾讯新闻 App 排的（名字是我们自己的品牌）：
     · 频道条：热点 / 头条 / 要闻 / 热搜 / 百度（可左右滑；选中的加粗 + 蓝色下划线）
     · 头条条（第一条有图）：通栏大图 + 标题 19 粗（最多 3 行）+「来源 · 时间」
     · 其余有图：左边标题 17（最多 3 行），右边缩略图 112×76（圆角 4）
     · 没图的（微博 / 百度热搜）：榜单行 —— 名次（前 3 红、4~6 橙、后面灰）+ 标题 + 热度，
       「热 / 新 / 沸」这种小标跟在标题后面
     · 整页白底 + 16 缩进的发丝线，和腾讯新闻一样是「一块白」的观感
     · 点任意一条 → App 内的 Safari 打开原文（不跳出我们的 App）
   数据：/api/news?source=xxx（服务端多源聚合，只接国内源；每个源缓存 5 分钟）
   ============================================================ */

/// 新闻流本体：频道条 + 列表。发现页的入口和机器人的对话页共用这一个。
struct NewsFeedView: View {
    /// 聊天页里用「紧凑版」：大图矮一点、缩略图小一点，好塞进对话页
    var compact: Bool = false
    /// 外部点「刷新」时把这个数 +1，流里就重新拉一次
    var refreshToken: Int = 0
    /// 指定初始频道（精彩视频页点「B站热门」时传 bili）
    var initialSource: String = "qq"
    /// 指定频道条：传了就不看服务端那份（视频页只显示「B站热门」一栏）
    var onlyTabs: [NewsChannel]? = nil

    @State private var channels: [NewsChannel] = NewsFeedView.builtinChannels
    @State private var tab = "qq"
    @State private var items: [NewsItem] = []
    @State private var loading = false
    @State private var failed = false
    /// 正在拉的源（切来切去的时候，晚到的响应不许覆盖当前这一栏）
    @State private var loadingTab = ""
    /// 「换一批」用的偏移：同一栏往后挪一批，挪到底回到开头
    @State private var offset = 0
    @State private var total = 0
    @State private var web: WebURL?

    /// 拿不到频道列表时的兜底（和后台 /api/news 给的顺序一致）
    static let builtinChannels: [NewsChannel] = [
        NewsChannel(id: "qq", label: "热点", desc: "热点榜"),
        NewsChannel(id: "toutiao", label: "头条", desc: "今日头条热榜"),
        NewsChannel(id: "sina", label: "要闻", desc: "新浪滚动新闻"),
        NewsChannel(id: "weibo", label: "热搜", desc: "微博热搜榜"),
        NewsChannel(id: "baidu", label: "百度", desc: "百度热搜榜")
    ]

    /// 蓝色主色：和后台给「星联世界」那一行配的 #2C7BE5 是同一个
    private let accent = Color(hex: 0x2C7BE5)

    var body: some View {
        VStack(spacing: 0) {
            tabs
            content
        }
        .background(C.cardBg)
        .task {
            if tab.isEmpty { tab = initialSource }
            if let only = onlyTabs { channels = only }
            if items.isEmpty { await load(tab) }
        }
        .onChange(of: refreshToken) { _ in Task { await load(tab) } }
        .sheet(item: $web) { w in
            SafariSheet(url: w.url).ignoresSafeArea()
        }
    }

    /* ---------------------------------------------------------- 频道条 */

    private var tabs: some View {
        HStack(spacing: 0) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                ForEach(channels) { ch in
                    Button { select(ch.id) } label: {
                        VStack(spacing: 5) {
                            Text(Tr(ch.label))
                                .font(pf(16, tab == ch.id ? .semibold : .regular))
                                .foregroundColor(tab == ch.id ? accent : C.label)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(tab == ch.id ? accent : Color.clear)
                                .frame(width: 22, height: 3)
                        }
                        .padding(.top, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        /* 换一批：这一栏往后挪一批（榜单就那么多条，到底了从头再来） */
        Button { nextBatch() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(Tr("换一批")).font(pf(13))
            }
            .foregroundColor(accent)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        }
        .background(C.navBg)
        .overlay(alignment: .bottom) { HairLine() }
    }

    /// 换一批：偏移往后挪 20 条，到底回到开头
    private func nextBatch() {
        let step = 20
        offset += step
        if total > 0, offset >= total { offset = 0 }
        Task { await load(tab) }
    }

    /* ---------------------------------------------------------- 列表 */

    private var isBoard: Bool { tab == "weibo" || tab == "baidu" }

    @ViewBuilder private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty && loading {
                    ProgressView()
                        .tint(accent)
                        .padding(.top, compact ? 40 : 80)
                        .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    emptyView
                } else {
                    let rows = Array(items.enumerated())
                    ForEach(rows, id: \.element.id) { row in
                        Button { open(row.element) } label: {
                            cell(row.element, index: row.offset)
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                    }
                    footer
                }
            }
            .padding(.bottom, 28)
        }
        .background(C.cardBg)
        .refreshable { await load(tab) }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Text(failed ? Tr("没有取到新闻，等会儿再试") : Tr("正在加载…"))
                .font(pf(14))
                .foregroundColor(C.subLabel)
            Button { Task { await load(tab) } } label: {
                Text(Tr("重试"))
                    .font(pf(15, .medium))
                    .foregroundColor(accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, compact ? 50 : 90)
    }

    private var footer: some View {
        Text(Tr("已经到底了"))
            .font(pf(12))
            .foregroundColor(C.time)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
    }

    @ViewBuilder private func cell(_ it: NewsItem, index: Int) -> some View {
        if isBoard {
            boardCell(it, index: index)
        } else if !it.cover.isEmpty {
            if index == 0 { heroCell(it) } else { thumbCell(it) }
        } else {
            textCell(it)
        }
    }

    /// 头条条：通栏大图 + 大标题（腾讯新闻的头条就是这个样子）
    private func heroCell(_ it: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(path: it.cover, maxSide: 1400)
                .frame(height: compact ? 158 : 200)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(it.title)
                .font(pf(compact ? 17.5 : 19, .semibold))
                .foregroundColor(C.label)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            meta(it)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 普通条：左标题右缩略图
    private func thumbCell(_ it: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                Text(it.title)
                    .font(pf(compact ? 16 : 17))
                    .foregroundColor(C.label)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                meta(it)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RemoteImage(path: it.cover, maxSide: 800)
                .frame(width: compact ? 96 : 112, height: compact ? 66 : 76)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// 没图的：标题 + 摘要（新浪有几条就是纯文字）
    private func textCell(_ it: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(it.title)
                .font(pf(compact ? 16 : 17))
                .foregroundColor(C.label)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let s = it.summary, !s.isEmpty {
                Text(s)
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            meta(it)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 榜单行：名次 + 标题（+「热/新/沸」）+ 热度
    private func boardCell(_ it: NewsItem, index: Int) -> some View {
        let no = it.order > 0 ? it.order : (index + 1)
        return HStack(alignment: .top, spacing: 12) {
            Text("\(no)")
                .font(pf(17, .semibold))
                .foregroundColor(rankColor(no))
                .frame(width: 24, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Text(it.title)
                        .font(pf(compact ? 16 : 17))
                        .foregroundColor(C.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !it.tagText.isEmpty { tagChip(it.tagText) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if it.hotValue > 0 {
                        Text(Tr("热度") + " " + hotText(it.hotValue))
                            .font(pf(12))
                            .foregroundColor(C.time)
                    }
                    Text(it.src)
                        .font(pf(12))
                        .foregroundColor(C.time)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「来源 · 时间」那行小灰字
    private func meta(_ it: NewsItem) -> some View {
        HStack(spacing: 6) {
            Text(it.src)
            let t = timeText(it.at)
            if !t.isEmpty {
                Text("·")
                Text(t)
            }
        }
        .font(pf(12))
        .foregroundColor(C.time)
        .lineLimit(1)
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(pf(10, .medium))
            .foregroundColor(C.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(C.red.opacity(0.12))
            )
    }

    private func rankColor(_ no: Int) -> Color {
        if no <= 3 { return C.red }
        if no <= 6 { return C.orange }
        return C.time
    }

    /* ---------------------------------------------------------- 数据 */

    private func select(_ id: String) {
        guard id != tab else { return }
        tab = id
        offset = 0                      // 换栏目：从第一批开始
        items = []
        failed = false
        Task { await load(id) }
    }

    private func load(_ source: String) async {
        if loadingTab == source { return }
        loadingTab = source
        loading = true
        do {
            let feed = try await API.shared.news(source: source, limit: 20, offset: offset)
            guard source == tab else { loadingTab = ""; return }
            if onlyTabs == nil, !feed.tabs.isEmpty { channels = feed.tabs }
            if let t = feed.total, t > 0 { total = t }
            var seen = Set<String>()
            items = feed.items.filter { seen.insert($0.id).inserted }
            failed = items.isEmpty
        } catch {
            guard source == tab else { loadingTab = ""; return }
            if items.isEmpty { failed = true }
        }
        loading = false
        loadingTab = ""
    }

    private func open(_ it: NewsItem) {
        guard !it.link.isEmpty, let u = URL(string: it.link) else { return }
        web = WebURL(url: u)
    }

    /* ---------------------------------------------------------- 小工具 */

    /// 时间：刚刚 / 12分钟前 / 3小时前 / 昨天 / 09-28（腾讯新闻那行小字也是这么写的）
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd"
        return f
    }()

    private func timeText(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 0 { return "" }
        if mins < 1 { return Tr("刚刚") }
        if mins < 60 { return "\(mins)\(Tr("分钟前"))" }
        if mins < 60 * 24 { return "\(mins / 60)\(Tr("小时前"))" }
        if mins < 60 * 24 * 2 { return Tr("昨天") }
        return NewsFeedView.dayFmt.string(from: d)
    }

    /// 热度：1599542 → 160.0万
    private func hotText(_ v: Double) -> String {
        if v >= 10000 {
            let w = v / 10000
            return String(format: "%.1f万", w)
        }
        return String(format: "%.0f", v)
    }
}

/* ============================================================
   发现 → 星联世界：顶栏「‹ 星联世界 ⟳」+ 下面就是那份新闻流
   ============================================================ */

struct NewsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refreshToken = 0

    var body: some View {
        VStack(spacing: 0) {
            nav
            NewsFeedView(refreshToken: refreshToken)
        }
        .background(C.cardBg.ignoresSafeArea(edges: .bottom))
        .background(C.navBg.ignoresSafeArea(edges: .top))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }

    private var nav: some View {
        ZStack {
            Text(Tr("星联世界"))
                .font(pf(17, .semibold))
                .foregroundColor(C.label)
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: L.navH)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { refreshToken += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: L.navH)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: L.navH)
        .background(C.navBg)
        .overlay(alignment: .bottom) { HairLine() }
    }
}
