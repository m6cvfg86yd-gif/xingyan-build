import SwiftUI

/* ============================================================
   拼多多风格「商城」——原生版（2026-10-12 从 H5 改成原生）

   以前是服务器上的 /mall/index.html，用 WKWebView 打开；用户要求改成原生的，
   现在整页是 SwiftUI，数据存在本机 JSON（Documents/dd_mall.json），
   第一次打开用内置那 16 个商品当种子（和 H5 里 SEED_PRODUCTS 一模一样的数据）。

   页面：首页（秒杀 + 分类 + 双列瀑布流）/ 推荐（种草）/ 消息 / 购物车 / 我的
        + 商品详情 + 下单（单独购买 / 发起拼单）+ 我的订单 + 收藏 + 足迹 + 搜索

   ⚠ 用户要求：这一页**不显示零钱余额**。下单就是生成一条订单记录（不扣零钱），
   订单状态在「我的 → 我的订单」里能一步步往前走（拼团中 → 待发货 → 待收货 → 已完成）。
   ============================================================ */

/* ---------------------------------------------------------- 数据 */

struct DDProduct: Identifiable, Codable, Hashable {
    var id: String
    /// 商品图：和 H5 一样用 emoji 画（不依赖服务器图片，离线也有图）
    var em: String
    /// 也可以放一张真图（管理里从相册传上来的地址）；有图就优先显示图
    var img: String? = nil
    var title: String
    /// 拼单价
    var price: Double
    /// 单独购买价（划线价）
    var orig: Double
    var sold: String
    /// 几人团
    var grp: Int
    var tags: [String]
    var shop: String
    var cate: String
    /// 是否上架（管理里可以下架；下架的只有管理看得到）
    var on: Bool? = nil

    /// 上架中
    var live: Bool { on ?? true }

    /// 给服务器（/api/ops/mall）用的字典
    var dict: [String: Any] {
        ["id": id, "em": em, "img": img ?? "", "title": title,
         "price": price, "orig": orig, "sold": sold, "grp": grp,
         "tags": tags, "shop": shop, "cate": cate, "on": live]
    }
}

struct DDCartLine: Identifiable, Codable, Hashable {
    var pid: String
    var count: Int
    var id: String { pid }
}

/// 一条订单。status：grouping 拼团中 / wait 待发货 / shipped 待收货 / done 已完成 / cancel 已取消
struct DDOrder: Identifiable, Codable, Hashable {
    var id: String
    var pid: String
    var em: String
    var title: String
    var shop: String
    var price: Double
    var count: Int
    var group: Bool
    /// 拼团要几个人
    var need: Int
    /// 已经几个人（含我自己）
    var have: Int
    var status: String
    var at: Date

    var statusText: String {
        switch status {
        case "grouping": return "拼团中"
        case "wait":     return "待发货"
        case "shipped":  return "待收货"
        case "done":     return "已完成"
        case "cancel":   return "已取消"
        default:         return status
        }
    }
    var canConfirm: Bool { status == "shipped" }
    var canCancel: Bool { status == "grouping" || status == "wait" }
}

/// 商城数据（单例 + 落盘）
@MainActor
final class DDStore: ObservableObject {
    static let shared = DDStore()

    @Published private(set) var products: [DDProduct] = []
    /// 首页轮播图（管理里可以换/加/删；服务器 data/mall.json 是真源）
    @Published private(set) var banners: [String] = []
    /// 商城名 / 标语（管理页可改；用户要求「商城名」）
    @Published private(set) var mallName: String = "星言商城"
    @Published private(set) var mallSlogan: String = "拼着买 才便宜"
    @Published private(set) var orders: [DDOrder] = []
    @Published private(set) var cart: [DDCartLine] = []
    @Published private(set) var history: [String] = []
    @Published private(set) var favs: [String] = []
    /// 看过的商品 id（最近 60 个，最新的在前）→「我的 → 浏览足迹」
    @Published private(set) var views: [String] = []
    /// 收货地址（没填就显示「还没填收货地址」）
    @Published var address: String = ""
    /// 收货地址簿（照京东：多条、可设默认、可编辑删除）——`address` 是改名之前的老字段，只用来迁移
    @Published private(set) var addresses: [DDAddress] = []

    private struct Box: Codable {
        var products: [DDProduct]
        var orders: [DDOrder]
        var cart: [DDCartLine]
        var history: [String]
        var favs: [String]
        var address: String
        /// 老缓存里没有这个字段（Optional 才不会解码失败）
        var banners: [String]?
        /// 同上：浏览足迹（老缓存里没有）
        var views: [String]?
        /// 同上：地址簿（老缓存里没有）
        var addresses: [DDAddress]?
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("dd_mall.json")
    }

    private init() {
        if let d = try? Data(contentsOf: fileURL),
           let b = try? JSONDecoder().decode(Box.self, from: d) {
            products = b.products
            orders = b.orders
            cart = b.cart
            history = b.history
            favs = b.favs
            address = b.address
            banners = b.banners ?? []
            views = b.views ?? []
            addresses = b.addresses ?? []
        }
        if products.isEmpty { products = DDStore.seeds }
        /* 老版本只有一个 address 字符串：升级上来时把它变成地址簿里的第一条，别让用户白填过 */
        if addresses.isEmpty, !address.isEmpty {
            addresses = [DDAddress(id: "a" + String(Int(Date().timeIntervalSince1970 * 1000)),
                                   name: "", phone: "", region: "", detail: address, isDefault: true)]
        }
    }

    private func save() {
        let b = Box(products: products, orders: orders, cart: cart,
                    history: history, favs: favs, address: address, banners: banners,
                    views: views, addresses: addresses)
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: fileURL) }
    }

    /* ---------------- 和管理端同步（服务器 data/mall.json 是真源） ---------------- */

    /// 上架中的商品（商城首页/搜索只显示这些；管理页看得到全部）
    var live: [DDProduct] { products.filter { $0.live } }

    /// 从服务器拉一份（进商城、管理里改完、下拉刷新都走它）
    func refresh() async {
        let (ps, bs, nm, sl) = await API.shared.mallData()
        if !ps.isEmpty { products = ps }
        banners = bs
        if !nm.isEmpty { mallName = nm }
        if !sl.isEmpty { mallSlogan = sl }
        save()
    }

    /// 管理侧：改商城名 + 标语
    func opsSetName(_ name: String, _ slogan: String) async {
        _ = await API.shared.opsMall(["action": "settings", "name": name, "slogan": slogan])
        await refresh()
    }

    /// 管理侧：新增或改一件商品
    func opsSave(_ p: DDProduct) async {
        _ = await API.shared.opsMall(["action": "product", "item": p.dict])
        await refresh()
    }

    /// 管理侧：删一件商品
    func opsRemove(_ id: String) async {
        _ = await API.shared.opsMall(["action": "remove", "id": id])
        await refresh()
    }

    /// 管理侧：整份换轮播图
    func opsBanners(_ urls: [String]) async {
        _ = await API.shared.opsMall(["action": "banners", "banners": urls])
        await refresh()
    }

    func product(_ id: String) -> DDProduct? { products.first { $0.id == id } }

    /* ---------------- 购物车 ---------------- */

    var cartCount: Int { cart.reduce(0) { $0 + $1.count } }
    var cartTotal: Double {
        cart.reduce(0) { sum, line in
            sum + (product(line.pid)?.price ?? 0) * Double(line.count)
        }
    }

    func addCart(_ pid: String, count: Int = 1) {
        if let i = cart.firstIndex(where: { $0.pid == pid }) {
            cart[i].count += count
        } else {
            cart.append(DDCartLine(pid: pid, count: count))
        }
        save()
    }

    func setCount(_ pid: String, _ n: Int) {
        guard let i = cart.firstIndex(where: { $0.pid == pid }) else { return }
        if n <= 0 { cart.remove(at: i) } else { cart[i].count = n }
        save()
    }

    func clearCart() { cart.removeAll(); save() }

    /* ---------------- 订单 ---------------- */

    var groupingCount: Int { orders.filter { $0.status == "grouping" }.count }

    @discardableResult
    func place(pid: String, count: Int, group: Bool, fromCart: Bool = false) -> DDOrder {
        let p = product(pid)
        let unit = group ? (p?.price ?? 0) : (p?.orig ?? p?.price ?? 0)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let o = DDOrder(id: "dd" + String(now) + String(Int.random(in: 100...999)),
                        pid: pid,
                        em: p?.em ?? "📦",
                        title: p?.title ?? "商品",
                        shop: p?.shop ?? "",
                        price: unit,
                        count: max(1, count),
                        group: group,
                        need: max(2, p?.grp ?? 2),
                        have: group ? 1 : 0,
                        status: group ? "grouping" : "wait",
                        at: Date())
        orders.insert(o, at: 0)
        if fromCart { cart.removeAll { $0.pid == pid } }
        save()
        return o
    }

    /// 邀请好友拼单：直接把人数凑满 → 成团，状态进「待发货」
    func invite(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].have = orders[i].need
        orders[i].status = "wait"
        save()
    }

    func cancelOrder(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].status = "cancel"
        save()
    }

    func ship(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        if orders[i].status == "wait" { orders[i].status = "shipped"; save() }
    }

    func confirm(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].status = "done"
        save()
    }

    func removeOrder(_ id: String) {
        orders.removeAll { $0.id == id }
        save()
    }

    /* ---------------- 收藏 / 足迹 ---------------- */

    func isFav(_ pid: String) -> Bool { favs.contains(pid) }

    func toggleFav(_ pid: String) {
        if let i = favs.firstIndex(of: pid) { favs.remove(at: i) } else { favs.insert(pid, at: 0) }
        save()
    }

    func pushHistory(_ q: String) {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        history.removeAll { $0 == s }
        history.insert(s, at: 0)
        if history.count > 12 { history = Array(history.prefix(12)) }
        save()
    }

    func clearHistory() { history.removeAll(); save() }

    /* ---------------- 浏览足迹 ---------------- */

    /// 记一条浏览足迹（点开商品详情时调）：同一个商品只留最近一次
    func recordView(_ pid: String) {
        guard !pid.isEmpty else { return }
        views.removeAll { $0 == pid }
        views.insert(pid, at: 0)
        if views.count > 60 { views = Array(views.prefix(60)) }
        save()
    }

    /// 足迹 → 商品（被下架/删掉的自动跳过，不会显示成空白卡）
    var viewed: [DDProduct] { views.compactMap { product($0) } }

    func clearViews() { views.removeAll(); save() }

    func setAddress(_ s: String) { address = s; save() }

    /* ---------------- 收货地址簿（照京东那套） ---------------- */

    /// 默认地址（没设默认就用第一条）
    var defaultAddress: DDAddress? {
        addresses.first { $0.isDefault } ?? addresses.first
    }

    /// 地址簿里有没有「信息不全」的（姓名或手机号空着）——下单前提醒一下
    var hasCompleteAddress: Bool {
        guard let a = defaultAddress else { return false }
        return !a.name.isEmpty && a.phone.count >= 6
    }

    /// 收货地址那一行的副标题（下单页 / 我的 都用它）
    var addressLine: String {
        guard let a = defaultAddress else { return "" }
        return a.region + a.detail
    }

    private func normalizeDefault(_ keep: String = "") {
        if addresses.isEmpty { return }
        /* 只允许一个默认：优先 keep，其次原来标了默认的，再次第一条 */
        if !keep.isEmpty, let i = addresses.firstIndex(where: { $0.id == keep }) {
            for k in addresses.indices { addresses[k].isDefault = (k == i) }
            return
        }
        if addresses.contains(where: { $0.isDefault }) {
            var seen = false
            for k in addresses.indices {
                if addresses[k].isDefault {
                    if seen { addresses[k].isDefault = false } else { seen = true }
                }
            }
        } else {
            addresses[0].isDefault = true
        }
    }

    /// 新增一条（京东：新地址默认「设为默认」开关打开时才抢默认）
    func addAddress(_ a: DDAddress) {
        var x = a
        if x.id.isEmpty { x.id = "a" + String(Int(Date().timeIntervalSince1970 * 1000)) }
        if addresses.isEmpty { x.isDefault = true }
        if x.isDefault { for k in addresses.indices { addresses[k].isDefault = false } }
        addresses.append(x)
        normalizeDefault(x.isDefault ? x.id : "")
        save()
    }

    func updateAddress(_ a: DDAddress) {
        guard let i = addresses.firstIndex(where: { $0.id == a.id }) else { return }
        if a.isDefault { for k in addresses.indices { addresses[k].isDefault = false } }
        addresses[i] = a
        normalizeDefault(a.isDefault ? a.id : "")
        save()
    }

    func removeAddress(_ id: String) {
        addresses.removeAll { $0.id == id }
        normalizeDefault()
        save()
    }

    func setDefaultAddress(_ id: String) {
        normalizeDefault(id)
        save()
    }

    /* ---------------- 分类 / 搜索 ---------------- */

    var categories: [String] {
        var seen: [String] = []
        for p in live where !seen.contains(p.cate) { seen.append(p.cate) }
        return seen
    }

    func search(_ q: String) -> [DDProduct] {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return live }
        return live.filter {
            $0.title.localizedCaseInsensitiveContains(s)
                || $0.shop.localizedCaseInsensitiveContains(s)
                || $0.cate == s
                || $0.tags.contains { $0.contains(s) }
        }
    }

    /* ---------------- 种子商品（和 H5 里那 16 个一模一样） ---------------- */

    static let seeds: [DDProduct] = [
        DDProduct(id: "p01", em: "🎧", title: "【百亿补贴】无线蓝牙耳机 主动降噪 入耳式 超长续航 苹果安卓通用",
                  price: 39.9, orig: 199, sold: "10万+", grp: 2, tags: ["百亿补贴", "官方直营"], shop: "数码优选旗舰店", cate: "数码"),
        DDProduct(id: "p02", em: "👟", title: "轻便透气跑步鞋 男款夏季网面运动鞋 软底减震",
                  price: 59.9, orig: 159, sold: "3.2万", grp: 2, tags: ["限时秒杀", "退货包运费"], shop: "潮鞋工厂店", cate: "服饰"),
        DDProduct(id: "p03", em: "🍊", title: "现摘沃柑 5斤装 手剥甜橙 新鲜当季水果 产地直发",
                  price: 16.8, orig: 39.9, sold: "8.6万", grp: 2, tags: ["产地直发", "坏果包赔"], shop: "果农直供店", cate: "生鲜"),
        DDProduct(id: "p04", em: "🧴", title: "氨基酸洗面奶 深层清洁温和不紧绷 敏感肌可用 200ml",
                  price: 19.9, orig: 69, sold: "5.1万", grp: 3, tags: ["正品保障"], shop: "肌研美妆专营", cate: "美妆"),
        DDProduct(id: "p05", em: "☕", title: "保温杯 316不锈钢 大容量便携车载水杯 24小时保温",
                  price: 29.9, orig: 99, sold: "2.7万", grp: 2, tags: ["限时秒杀"], shop: "日用家居优选", cate: "家居"),
        DDProduct(id: "p06", em: "🍜", title: "螺蛳粉 广西正宗柳州风味 5包装 加臭加辣速食",
                  price: 24.9, orig: 49.9, sold: "12万", grp: 2, tags: ["百亿补贴", "爆款"], shop: "美味零食铺", cate: "食品"),
        DDProduct(id: "p07", em: "📱", title: "120W超级快充充电宝 20000毫安 大容量 自带四线",
                  price: 69, orig: 199, sold: "4.4万", grp: 2, tags: ["官方补贴"], shop: "数码优选旗舰店", cate: "数码"),
        DDProduct(id: "p08", em: "🧸", title: "儿童毛绒玩具公仔 安抚陪睡娃娃 生日礼物正版授权",
                  price: 22.8, orig: 79, sold: "1.9万", grp: 3, tags: ["母婴优选"], shop: "萌趣玩具城", cate: "母婴"),
        DDProduct(id: "p09", em: "👕", title: "纯棉短袖T恤 男款夏季宽松百搭 三件装 不易变形",
                  price: 39.9, orig: 129, sold: "6.8万", grp: 2, tags: ["退货包运费"], shop: "基础款服饰店", cate: "服饰"),
        DDProduct(id: "p10", em: "🥛", title: "纯牛奶 250ml×12盒 全脂营养早餐奶 整箱实惠装",
                  price: 33.9, orig: 69, sold: "9.3万", grp: 2, tags: ["百亿补贴", "日期新鲜"], shop: "乳品官方旗舰", cate: "食品"),
        DDProduct(id: "p11", em: "🪥", title: "电动牙刷 声波震动 智能定时 情侣款 含4个刷头",
                  price: 45.9, orig: 169, sold: "2.2万", grp: 2, tags: ["限时秒杀"], shop: "口腔护理专营", cate: "美妆"),
        DDProduct(id: "p12", em: "🍚", title: "东北五常大米 10斤装 当季新米 香糯软弹 真空包装",
                  price: 34.9, orig: 79, sold: "7.5万", grp: 2, tags: ["产地直发"], shop: "粮油旗舰店", cate: "食品"),
        DDProduct(id: "p13", em: "⌚", title: "智能运动手环 心率血氧监测 防水计步 长续航 通用腕带",
                  price: 79, orig: 299, sold: "1.6万", grp: 3, tags: ["官方补贴"], shop: "数码优选旗舰店", cate: "数码"),
        DDProduct(id: "p14", em: "🧺", title: "衣物收纳箱 大容量可折叠 防潮防尘 衣柜整理三件套",
                  price: 26.9, orig: 89, sold: "3.7万", grp: 2, tags: ["9.9元包邮"], shop: "日用家居优选", cate: "家居"),
        DDProduct(id: "p15", em: "🍰", title: "千层蛋糕 动物奶油 现做现发 网红下午茶甜品",
                  price: 29.9, orig: 88, sold: "2.5万", grp: 2, tags: ["顺丰冷链"], shop: "甜品烘焙坊", cate: "食品"),
        DDProduct(id: "p16", em: "🧢", title: "棒球帽 男女同款 遮阳防晒 显脸小 可调节",
                  price: 15.9, orig: 59, sold: "4.1万", grp: 2, tags: ["9.9元包邮"], shop: "基础款服饰店", cate: "服饰")
    ]
}

/* ---------------------------------------------------------- 小零件 */

extension View {
    /// 商城一律按**浅色**渲染：用户要求「商城背景不要黑色的」——
    /// 深色模式下 App 的底色是 #191919，商城这一页保持拼多多那种白底/浅灰底
    /// （颜色走 App 那套 C.* 的浅色值：页面 #EDEDED、卡片 #FFFFFF、文字深灰）。
    func ddLight() -> some View { environment(\.colorScheme, .light) }
}

/// 商城的调色板 —— **和服务器上那个 H5 商城（/mall/index.html）里量出来的一模一样**
/// （用户要求「原生的商城颜值不要变，和 h5 的」）。H5 的 CSS 变量：
///   --red:#e02f24  --red-deep:#c81e14  --red-light:#fff1ef  --orange:#ff7a1a
///   --grad-red:135deg #ff5f3a → #ef3323 55% → #d81a10
///   --grad-btn:96deg #ffab2e → #ff5f00 55% → #f43c0a
///   --grad-btn-soft:96deg #ff8b3d → #f5361c
///   --bg:#f5f5f7  --text:#141414  --text-sub:#8a8a90  --text-weak:#b4b4ba
///   --card:#ffffff  --radius:16px  --radius-sm:12px
enum DDColor {
    static let red      = Color(hex: 0xE02F24)
    static let redDeep  = Color(hex: 0xC81E14)
    static let redLight = Color(hex: 0xFFF1EF)
    static let orange   = Color(hex: 0xFF7A1A)
    static let page     = Color(hex: 0xF5F5F7)
    static let card     = Color(hex: 0xFFFFFF)
    static let ink      = Color(hex: 0x141414)
    static let sub      = Color(hex: 0x8A8A90)
    static let weak     = Color(hex: 0xB4B4BA)
    static let line     = Color(hex: 0xEDEBE9)
    /// 顶栏那块红（H5 的 --grad-red）
    static let gradHeader = LinearGradient(
        colors: [Color(hex: 0xFF5F3A), Color(hex: 0xEF3323), Color(hex: 0xD81A10)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// 主要按钮（H5 的 --grad-btn）
    static let gradBtn = LinearGradient(
        colors: [Color(hex: 0xFFAB2E), Color(hex: 0xFF5F00), Color(hex: 0xF43C0A)],
        startPoint: .leading, endPoint: .trailing)
    /// 次要按钮（H5 的 --grad-btn-soft）
    static let gradBtnSoft = LinearGradient(
        colors: [Color(hex: 0xFF8B3D), Color(hex: 0xF5361C)],
        startPoint: .leading, endPoint: .trailing)
    /// 商品图那块暖色底
    static let gradThumb = LinearGradient(
        colors: [Color(hex: 0xFFF3EC), Color(hex: 0xFFFBF7)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// 商品图（emoji + 暖色渐变底，和 H5 的观感一致）
struct DDThumb: View {
    var em: String
    var size: CGFloat
    var radius: CGFloat = 10
    /// 有真图就显示真图（管理里从相册传上来的），没有就用 emoji 顶着
    var img: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DDColor.gradThumb)
            if let img, !img.isEmpty {
                RemoteImage(path: img, icon: "photo")
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                Text(em).font(.system(size: size * 0.46))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 价格：¥ 小一号、数字大一号（拼多多那种写法）
struct DDPrice: View {
    var value: Double
    var size: CGFloat = 17
    var color: Color = DDColor.red

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("¥").font(pf(size * 0.7, .semibold)).foregroundColor(color)
            Text(moneyFmt(value)).font(pf(size, .bold)).foregroundColor(color)
        }
    }
}

/* ---------------------------------------------------------- 商城首页（根） */

struct MallNativeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    @State private var tab = 0
    @State private var openProduct: DDProduct? = nil
    @State private var showSearch = false
    @State private var showOrders = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            tabBar
        }
        .background(DDColor.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(item: $openProduct) { p in
            /* onCart：详情页里点「加购物车」→ 直接切到购物车那个 tab */
            DDDetailView(product: p, onCart: { tab = 3 }).environmentObject(app)
        }
        .sheet(isPresented: $showSearch) {
            DDSearchView { p in
                showSearch = false
                openProduct = p
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showOrders) {
            DDOrdersView().environmentObject(app)
        }
        /* 进商城先拉一次服务器上的商城数据（商品 + 轮播图）——管理里改完立刻能看到 */
        .task { await store.refresh() }
        .ddLight()
        /* 顺带把状态栏也按浅色算：不然深色模式下状态栏是白字、压在浅色商城上会看不清 */
        .preferredColorScheme(.light)
    }

    private var titles = ["商城", "种草", "消息", "购物车", "我的"]

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tab == 0 ? .white : DDColor.ink)
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if tab == 0 {
                    /* 商城名 + 标语：管理页里能改（用户要求「商城名」） */
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.mallName)
                            .font(pf(17, .semibold)).foregroundColor(.white).lineLimit(1)
                        Text(store.mallSlogan)
                            .font(pf(11)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { showOrders = true } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(Tr(titles[tab]))
                        .font(pf(17, .semibold)).foregroundColor(DDColor.ink)
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 34, height: 40)
                }
            }
            if tab == 0 {
                Button { showSearch = true } label: { searchBox }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(headerBg)
    }

    @ViewBuilder private var headerBg: some View {
        if tab == 0 {
            /* H5 的 --grad-red：135deg #ff5f3a → #ef3323 55% → #d81a10 */
            DDColor.gradHeader
        } else {
            DDColor.page
        }
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: 0xB0A6A2))
            Text(Tr("搜索想要的商品")).font(pf(14)).foregroundColor(Color(hex: 0xB0A6A2))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Color.white))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        switch tab {
            case 0: DDHomeTab(onOpen: openProduct_tap)
            case 1: DDRecTab(onOpen: openProduct_tap)
            case 2: DDMsgTab(onOrders: { showOrders = true })
            case 3: DDCartTab(onOpen: openProduct_tap, onOrders: { showOrders = true })
            default: DDMineTab(onOrders: { showOrders = true }, onOpen: openProduct_tap)
        }
    }

    /// 点商品 → 打开详情（顺手记一条「浏览足迹」，我的 → 浏览足迹 里能看到）
    private func openProduct_tap(_ p: DDProduct) {
        store.recordView(p.id)
        openProduct = p
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 0) {
                tabButton(0, "首页", "house.fill", 0)
                tabButton(1, "推荐", "sparkles", 0)
                tabButton(2, "消息", "bell.fill", store.groupingCount)
                tabButton(3, "购物车", "cart.fill", store.cartCount)
                tabButton(4, "我的", "person.fill", 0)
            }
            .padding(.top, 7)
            .padding(.bottom, max(4, L.safeBottom))
        }
        .background(DDColor.card)
    }

    private func tabButton(_ i: Int, _ label: String, _ icon: String, _ badge: Int) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: tab == i ? .semibold : .regular))
                        .foregroundColor(tab == i ? DDColor.red : DDColor.sub)
                        .frame(width: 26, height: 22)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : String(badge))
                            .font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).frame(height: 14)
                            .background(Capsule().fill(DDColor.redDeep))
                            .offset(x: 8, y: -6)
                    }
                }
                Text(Tr(label))
                    .font(pf(10.5, tab == i ? .medium : .regular))
                    .foregroundColor(tab == i ? DDColor.red : DDColor.sub)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/* ---------------------------------------------------------- 首页 */

struct DDHomeTab: View {
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    @State private var cate: String? = nil
    @State private var secs = 2 * 3600 + 41 * 60 + 33
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var list: [DDProduct] {
        guard let c = cate else { return store.live }
        return store.live.filter { $0.cate == c }
    }

    var body: some View {
        /* 用 ScrollViewReader：点轮播图 / 「更多抢购」→ 滚到「为你推荐」那一栏
           （以前这两个地方点了没反应，用户报的「有些东西点不了」） */
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    carousel(proxy)
                    seckill(proxy)
                    cateRow
                    sectionTitle(Tr("为你推荐"), right: Tr("边逛边拼"))
                    grid.id("dd-grid")
                    Spacer().frame(height: 16)
                }
                .padding(.top, 10)
            }
            .background(DDColor.page)
            .onReceive(ticker) { _ in if secs > 0 { secs -= 1 } }
        }
    }

    private func toGrid(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("dd-grid", anchor: .top) }
    }

    /* ---------------- 首页轮播图（管理页里可以换图 / 加图 / 删图） ----------------
       没有图就不占地方（空数组时整块不画）；有图就横滑一屏一张 + 底下小圆点，
       每 3 秒自动翻一张。 */
    @State private var bannerPage = 0

    @ViewBuilder private func carousel(_ proxy: ScrollViewProxy) -> some View {
        let imgs = store.banners.filter { !$0.isEmpty }
        if !imgs.isEmpty {
            VStack(spacing: 8) {
                TabView(selection: $bannerPage) {
                    ForEach(imgs.indices, id: \.self) { i in
                        Button { toGrid(proxy) } label: {
                            RemoteImage(path: imgs[i], icon: "photo")
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 146)

                if imgs.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(imgs.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == bannerPage % imgs.count
                                      ? DDColor.red : Color(hex: 0xD9D3D0))
                                .frame(width: i == bannerPage % imgs.count ? 14 : 6, height: 6)
                        }
                    }
                }
            }
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                withAnimation(.easeInOut(duration: 0.35)) {
                    bannerPage = (bannerPage + 1) % max(1, imgs.count)
                }
            }
        }
    }

    private func seckill(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Tr("限时秒杀")).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
                Text(clockText)
                    .font(pf(12, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(Color(hex: 0x1F1F1F)))
                Spacer(minLength: 0)
                Button { toGrid(proxy) } label: {
                    Text(Tr("更多抢购")).font(pf(12.5)).foregroundColor(DDColor.sub)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.live.prefix(8))) { p in
                        Button { onOpen(p) } label: { seckillCell(p) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func seckillCell(_ p: DDProduct) -> some View {
        VStack(spacing: 4) {
            DDThumb(em: p.em, size: 74, radius: 8, img: p.img)
            DDPrice(value: p.price, size: 15)
            Text("¥" + moneyFmt(p.orig))
                .font(pf(11)).foregroundColor(DDColor.sub)
                .strikethrough()
        }
        .frame(width: 78)
    }

    private var clockText: String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var cateRow: some View {
        let names: [String] = store.categories
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(Tr("分类")).font(pf(15, .semibold)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                if cate != nil {
                    Button { cate = nil } label: {
                        Text(Tr("全部")).font(pf(12.5)).foregroundColor(DDColor.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(names, id: \.self) { c in
                        Button { cate = (cate == c ? nil : c) } label: {
                            Text(Tr(c))
                                .font(pf(13.5, cate == c ? .semibold : .regular))
                                .foregroundColor(cate == c ? .white : DDColor.ink)
                                .padding(.horizontal, 14).frame(height: 30)
                                .background(Capsule().fill(cate == c
                                                            ? DDColor.red
                                                            : DDColor.page))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func sectionTitle(_ t: String, right: String) -> some View {
        HStack {
            Text(t).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
            Spacer(minLength: 0)
            Text(right).font(pf(12.5)).foregroundColor(DDColor.sub)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(list) { p in
                Button { onOpen(p) } label: { DDProductCard(product: p) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }
}

/// 双列瀑布流里的那张商品卡
struct DDProductCard: View {
    let product: DDProduct
    @ObservedObject private var store = DDStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DDThumb(em: product.em, size: 150, radius: 10, img: product.img)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(product.title)
                .font(pf(13.5)).foregroundColor(DDColor.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                DDPrice(value: product.price, size: 16)
                Text("¥" + moneyFmt(product.orig))
                    .font(pf(11)).foregroundColor(DDColor.sub).strikethrough()
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                /* 没有真实销量数据的商品就不写「已拼 xxx」——不编数字 */
                if !product.sold.isEmpty {
                    Text(Tr("已拼") + product.sold)
                        .font(pf(11)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                Text(Tr("\(product.grp)人团"))
                    .font(pf(10.5)).foregroundColor(DDColor.red)
                    .padding(.horizontal, 5).frame(height: 17)
                    .background(Capsule().fill(DDColor.redLight))
            }
            HStack(spacing: 4) {
                Image(systemName: store.isFav(product.id) ? "heart.fill" : "heart")
                    .font(.system(size: 11))
                    .foregroundColor(store.isFav(product.id) ? DDColor.redDeep : DDColor.sub)
                Text(product.shop).font(pf(11)).foregroundColor(DDColor.sub).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/* ---------------------------------------------------------- 推荐（种草） */

struct DDRecTab: View {
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(store.live) { p in
                    Button { onOpen(p) } label: { recCard(p) }
                        .buttonStyle(.plain)
                }
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 10)
        }
        .background(DDColor.page)
    }

    private func recCard(_ p: DDProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xFFD9CC)).frame(width: 26, height: 26)
                    .overlay(Text("拼").font(pf(12, .semibold)).foregroundColor(DDColor.red))
                Text(p.shop).font(pf(13.5, .medium)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(Tr("种草")).font(pf(11)).foregroundColor(.white)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(DDColor.red))
            }
            Text(p.title).font(pf(15)).foregroundColor(DDColor.ink).lineLimit(3)
            HStack(spacing: 8) {
                DDThumb(em: p.em, size: 96, radius: 10, img: p.img)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(p.tags.prefix(2), id: \.self) { t in
                            Text(t).font(pf(10.5)).foregroundColor(DDColor.red)
                                .padding(.horizontal, 5).frame(height: 17)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(DDColor.redLight))
                        }
                    }
                    DDPrice(value: p.price, size: 18)
                    if !p.sold.isEmpty {
                        Text(Tr("已拼") + p.sold).font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }
}

/* ---------------------------------------------------------- 消息 */

struct DDMsgTab: View {
    @ObservedObject private var store = DDStore.shared
    /// 点消息卡片 → 去看订单（以前整条卡片点不了，只有「邀好友拼单」那颗按钮能点）
    var onOrders: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                if store.orders.isEmpty {
                    Text(Tr("还没有拼单消息")).font(pf(14)).foregroundColor(DDColor.sub)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ForEach(store.orders) { o in
                        /* 用 onTapGesture 而不是再套一层 Button：
                           套 Button 会把里面那颗「邀好友拼单」吃掉（嵌套按钮点不动） */
                        row(o)
                            .contentShape(Rectangle())
                            .onTapGesture { onOrders() }
                    }
                }
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 10)
        }
        .background(DDColor.page)
    }

    private func row(_ o: DDOrder) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DDThumb(em: o.em, size: 46, radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(msgTitle(o)).font(pf(14.5, .medium)).foregroundColor(DDColor.ink).lineLimit(2)
                Text(o.title).font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
                Text(timeText(o.at)).font(pf(11.5)).foregroundColor(DDColor.sub)
            }
            Spacer(minLength: 0)
            if o.status == "grouping" {
                Button { store.invite(o.id) } label: {
                    Text(Tr("邀好友拼单"))
                        .font(pf(12.5, .medium)).foregroundColor(.white)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(DDColor.red))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func msgTitle(_ o: DDOrder) -> String {
        switch o.status {
        case "grouping":
            let left = max(1, o.need - o.have)
            return Tr("你参与的拼单还差 ") + String(left) + Tr(" 人成团")
        case "wait":    return Tr("拼单成功，商家正在打包")
        case "shipped": return Tr("包裹已发出，注意收货")
        case "done":    return Tr("订单已完成，去评价一下吧")
        default:        return Tr("订单已取消")
        }
    }
}

/* ---------------------------------------------------------- 购物车 */

struct DDCartTab: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void
    var onOrders: () -> Void

    @State private var checked: Set<String> = []
    @State private var showPay = false

    private var lines: [DDCartLine] { store.cart }
    private var total: Double {
        lines.filter { checked.contains($0.pid) }.reduce(0) { sum, l in
            sum + (store.product(l.pid)?.price ?? 0) * Double(l.count)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if lines.isEmpty {
                VStack(spacing: 10) {
                    Text("🛒").font(.system(size: 42))
                    Text(Tr("购物车还是空的")).font(pf(15)).foregroundColor(DDColor.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(lines) { l in line(l) }
                        Spacer().frame(height: 12)
                    }
                    .padding(.vertical, 10)
                }
                bottomBar
            }
        }
        .background(DDColor.page)
    }

    private func line(_ l: DDCartLine) -> some View {
        let p = store.product(l.pid)
        return HStack(spacing: 10) {
            Button { toggle(l.pid) } label: {
                Image(systemName: checked.contains(l.pid) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(checked.contains(l.pid) ? DDColor.red : DDColor.sub)
            }
            .buttonStyle(.plain)

            Button { if let p { onOpen(p) } } label: {
                HStack(spacing: 10) {
                    DDThumb(em: p?.em ?? "📦", size: 64, radius: 8, img: p?.img)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(p?.title ?? "").font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                        DDPrice(value: (p?.price ?? 0) * Double(l.count), size: 15)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                step("−") { store.setCount(l.pid, l.count - 1) }
                Text(String(l.count)).font(pf(13)).frame(width: 30)
                step("+") { store.setCount(l.pid, l.count + 1) }
            }
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func step(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(pf(15, .medium)).foregroundColor(DDColor.ink)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(DDColor.page))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 10) {
                Button { checked = (checked.count == lines.count ? [] : Set(lines.map { $0.pid })) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: checked.count == lines.count && !lines.isEmpty
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundColor(checked.count == lines.count ? DDColor.red : DDColor.sub)
                        Text(Tr("全选")).font(pf(13.5)).foregroundColor(DDColor.ink)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(Tr("合计 ")).font(pf(13)).foregroundColor(DDColor.sub)
                DDPrice(value: total, size: 18)
                Button { showPay = true } label: {
                    Text(Tr("去结算") + (checked.isEmpty ? "" : "(\(checked.count))"))
                        .font(pf(15, .medium)).foregroundColor(.white)
                        .padding(.horizontal, 18).frame(height: 38)
                        .background(Capsule().fill(checked.isEmpty
                                                   ? DDColor.sub : DDColor.red))
                }
                .buttonStyle(.plain)
                .disabled(checked.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(DDColor.card)
        }
        .sheet(isPresented: $showPay) { paySheet }
    }

    private var paySheet: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("确认下单"))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(lines.filter { checked.contains($0.pid) }) { l in
                        HStack(spacing: 10) {
                            DDThumb(em: store.product(l.pid)?.em ?? "📦", size: 46, radius: 8, img: store.product(l.pid)?.img)
                            Text(store.product(l.pid)?.title ?? "")
                                .font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                            Spacer(minLength: 0)
                            Text("×" + String(l.count)).font(pf(13)).foregroundColor(DDColor.sub)
                        }
                        .padding(12)
                        .background(DDColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Text(Tr("合计 ") + "¥" + moneyFmt(total))
                        .font(pf(16, .semibold)).foregroundColor(DDColor.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 14)
                    Spacer().frame(height: 8)
                }
                .padding(.vertical, 10)
            }
            Button {
                for l in lines where checked.contains(l.pid) {
                    store.place(pid: l.pid, count: l.count, group: false, fromCart: true)
                }
                checked = []
                showPay = false
                app.show(Tr("下单成功，去「我的订单」看进度"))
            } label: {
                Text(Tr("提交订单"))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23).fill(DDColor.gradBtn))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, max(10, L.safeBottom))
            .padding(.top, 6)
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }

    private func toggle(_ pid: String) {
        if checked.contains(pid) { checked.remove(pid) } else { checked.insert(pid) }
    }
}

/* ---------------------------------------------------------- 我的 */

struct DDMineTab: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = DDStore.shared
    var onOrders: () -> Void
    var onOpen: (DDProduct) -> Void

    @State private var showFav = false
    @State private var showAddr = false
    @State private var showViews = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                profileCard
                orderCard
                toolCard
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 10)
        }
        .background(DDColor.page)
        .sheet(isPresented: $showFav) {
            DDFavView(onOpen: { p in
                showFav = false
                onOpen(p)
            })
            .environmentObject(app)
        }
        /* 「我的 → 收货地址」= 独立的地址簿页（照京东，不是原来那个单行输入框） */
        .sheet(isPresented: $showAddr) { DDAddressListView() }
        .sheet(isPresented: $showViews) {
            DDViewsView(onOpen: { p in
                showViews = false
                onOpen(p)
            })
        }
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            Avatar(path: app.me?.avatar ?? "", size: 56, radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.me?.nickname ?? app.me?.username ?? Tr("我"))
                    .font(pf(17, .semibold)).foregroundColor(DDColor.ink).lineLimit(1)
                Text(Tr("星言号 ") + (app.me?.username ?? ""))
                    .font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(String(store.orders.count)).font(pf(16, .semibold)).foregroundColor(DDColor.ink)
                Text(Tr("我的拼单")).font(pf(11)).foregroundColor(DDColor.sub)
            }
        }
        .padding(14)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private var orderCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Tr("我的订单")).font(pf(15.5, .semibold)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Button { onOrders() } label: {
                    HStack(spacing: 2) {
                        Text(Tr("全部订单")).font(pf(12.5)).foregroundColor(DDColor.sub)
                        Chevron(size: 8, line: 1.4)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            HairLine(inset: 14)
            HStack(spacing: 0) {
                orderEntry("拼团中", "person.2.fill", store.orders.filter { $0.status == "grouping" }.count)
                orderEntry("待发货", "shippingbox.fill", store.orders.filter { $0.status == "wait" }.count)
                orderEntry("待收货", "truck.box.fill", store.orders.filter { $0.status == "shipped" }.count)
                orderEntry("已完成", "checkmark.seal.fill", store.orders.filter { $0.status == "done" }.count)
            }
            .padding(.vertical, 14)
        }
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func orderEntry(_ label: String, _ icon: String, _ n: Int) -> some View {
        Button { onOrders() } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(DDColor.red)
                        .frame(width: 28, height: 24)
                    if n > 0 {
                        Text(String(n)).font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).frame(height: 14)
                            .background(Capsule().fill(DDColor.redDeep))
                            .offset(x: 8, y: -5)
                    }
                }
                Text(Tr(label)).font(pf(11.5)).foregroundColor(DDColor.ink)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolCard: some View {
        VStack(spacing: 0) {
            toolRow("我的收藏", "heart.fill", Tr("\(store.favs.count) 件")) { showFav = true }
            HairLine(inset: 52)
            toolRow("收货地址", "location.fill",
                    store.defaultAddress == nil ? Tr("还没填") : store.addressLine) { showAddr = true }
            HairLine(inset: 52)
            /* ⚠ 以前这里的动作是空的 `{ }`，点了没反应 —— 用户报的「有些东西点不了」就是它 */
            toolRow("浏览足迹", "clock.fill", Tr("\(store.viewed.count) 件")) { showViews = true }
        }
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func toolRow(_ title: String, _ icon: String, _ right: String,
                         _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(DDColor.red)
                    .frame(width: 24)
                Text(Tr(title)).font(pf(15)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(right).font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
                Chevron(size: 9, line: 1.5)
            }
            .padding(.horizontal, 14).frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

/* ---------------------------------------------------------- 商品详情 */

struct DDDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    let product: DDProduct
    /// 加进购物车之后要干什么（商城那边传进来：跳到「购物车」那个 tab）
    private let onCart: (() -> Void)?

    init(product: DDProduct, onCart: (() -> Void)? = nil) {
        self.product = product
        self.onCart = onCart
    }

    @State private var showOrder = false
    @State private var group = true

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    hero
                    priceCard
                    groupCard
                    shopCard
                    Spacer().frame(height: 12)
                }
                .padding(.vertical, 10)
            }
            bottomBar
        }
        .background(DDColor.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showOrder) {
            DDOrderSheet(product: product, group: group)
                .environmentObject(app)
        }
        .ddLight()
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DDColor.ink)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(Tr("商品详情")).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
            Spacer(minLength: 0)
            Button { store.toggleFav(product.id) } label: {
                Image(systemName: store.isFav(product.id) ? "heart.fill" : "heart")
                    .font(.system(size: 17))
                    .foregroundColor(store.isFav(product.id) ? DDColor.redDeep : DDColor.ink)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DDColor.card)
        .overlay(HairLine(), alignment: .bottom)
    }

    private var hero: some View {
        ZStack {
            DDColor.gradThumb
            if let img = product.img, !img.isEmpty {
                RemoteImage(path: img, icon: "photo")
                    .frame(maxWidth: .infinity).frame(height: 260).clipped()
            } else {
                Text(product.em).font(.system(size: 150))
            }
        }
        .frame(height: 260)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                DDPrice(value: product.price, size: 26)
                Text(Tr("单独购买 ¥") + moneyFmt(product.orig))
                    .font(pf(12)).foregroundColor(DDColor.sub).strikethrough()
                Spacer(minLength: 0)
                if !product.sold.isEmpty {
                    Text(Tr("已拼") + product.sold).font(pf(12)).foregroundColor(DDColor.sub)
                }
            }
            Text(product.title).font(pf(16, .medium)).foregroundColor(DDColor.ink)
            HStack(spacing: 5) {
                ForEach(product.tags, id: \.self) { t in
                    Text(t).font(pf(11)).foregroundColor(DDColor.red)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 4).fill(DDColor.redLight))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private var groupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(Tr("正在拼单")).font(pf(15, .semibold)).foregroundColor(DDColor.ink)
                Text(Tr("\(product.grp)人团")).font(pf(11)).foregroundColor(.white)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(DDColor.red))
                Spacer(minLength: 0)
                Text(Tr("还差 1 人成团")).font(pf(12)).foregroundColor(DDColor.sub)
            }
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: 0xFFD9CC)).frame(width: 34, height: 34)
                        .overlay(Text(i == 0 ? "拼" : "友")
                            .font(pf(13, .semibold)).foregroundColor(DDColor.red))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i == 0 ? Tr("拼友 138****6621") : Tr("拼友 186****3302"))
                            .font(pf(13.5)).foregroundColor(DDColor.ink)
                        Text(Tr("还剩 ") + String(23 - i * 7) + Tr(" 小时"))
                            .font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                    Spacer(minLength: 0)
                    Button { app.show(Tr("已加入 TA 的拼单")) } label: {
                        Text(Tr("去拼单"))
                            .font(pf(13, .medium)).foregroundColor(.white)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(DDColor.red))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private var shopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: 0xFFD9CC)).frame(width: 36, height: 36)
                    .overlay(Text("店").font(pf(14, .semibold)).foregroundColor(DDColor.red))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.shop).font(pf(14.5, .medium)).foregroundColor(DDColor.ink)
                    Text(Tr("分类：") + Tr(product.cate)).font(pf(12)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                Button { addToCart() } label: {
                    Text(Tr("加购物车"))
                        .font(pf(13)).foregroundColor(DDColor.red)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().stroke(DDColor.red, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            HairLine()
            Text(Tr("商品介绍")).font(pf(14, .semibold)).foregroundColor(DDColor.ink)
            Text(product.title + Tr("。产地直发、坏果包赔、退货包运费，拼单更便宜。"))
                .font(pf(13.5)).foregroundColor(DDColor.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 10) {
                Button { addToCart() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "cart.badge.plus").font(.system(size: 19))
                        Text(Tr("购物车")).font(pf(10.5))
                    }
                    .foregroundColor(DDColor.ink)
                    .frame(width: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    group = false
                    showOrder = true
                } label: {
                    VStack(spacing: 1) {
                        Text(Tr("单独购买")).font(pf(15, .medium))
                        Text("¥" + moneyFmt(product.orig)).font(pf(11.5))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0xFF8B3D)))
                }
                .buttonStyle(.plain)
                Button {
                    group = true
                    showOrder = true
                } label: {
                    VStack(spacing: 1) {
                        Text(Tr("发起拼单")).font(pf(15, .medium))
                        Text("¥" + moneyFmt(product.price)).font(pf(11.5))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 22).fill(DDColor.gradBtn))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.top, 8)
            .padding(.bottom, max(8, L.safeBottom))
        }
        .background(DDColor.card)
    }

    /// 加入购物车：提示一下 → 关掉详情页 → **自动跳到「购物车」那个 tab**
    /// （用户报的「购物车不会自动跳转到购物车」就是这里）
    private func addToCart() {
        store.addCart(product.id)
        app.show(Tr("已加入购物车"))
        onCart?()
        dismiss()
    }
}

/* ---------------------------------------------------------- 下单 */

struct DDOrderSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    let product: DDProduct
    @State private var group: Bool
    @State private var count = 1
    /// 这次下单用哪条地址（空 = 用默认那条）
    @State private var pickedAddrId = ""
    @State private var showAddrList = false

    init(product: DDProduct, group: Bool) {
        self.product = product
        _group = State(initialValue: group)
    }

    private var unit: Double { group ? product.price : product.orig }
    private var total: Double { unit * Double(count) }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("确认订单"))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        DDThumb(em: product.em, size: 68, radius: 8, img: product.img)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(product.title).font(pf(13.5)).foregroundColor(DDColor.ink).lineLimit(2)
                            DDPrice(value: unit, size: 17)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(spacing: 0) {
                        pick(Tr("发起拼单") + "（\(product.grp)人团）", Tr("按拼单价，人满发货"), true)
                        HairLine(inset: 14)
                        pick(Tr("单独购买"), Tr("按单买价，不用等人"), false)
                    }
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 0) {
                        Text(Tr("数量")).font(pf(14.5)).foregroundColor(DDColor.ink)
                        Spacer(minLength: 0)
                        Button { if count > 1 { count -= 1 } } label: {
                            Text("−").font(pf(16, .medium)).foregroundColor(DDColor.ink)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(DDColor.page))
                        }
                        .buttonStyle(.plain)
                        Text(String(count)).font(pf(14)).frame(width: 36)
                        Button { count += 1 } label: {
                            Text("+").font(pf(16, .medium)).foregroundColor(DDColor.ink)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(DDColor.page))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    /* 收货地址：显示默认那条，点一下进地址簿挑（照京东） */
                    Button { showAddrList = true } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 19)).foregroundColor(DDColor.red)
                            VStack(alignment: .leading, spacing: 4) {
                                if let a = chosenAddr {
                                    HStack(spacing: 8) {
                                        Text(a.name.isEmpty ? Tr("未填收货人") : a.name)
                                            .font(pf(15, .medium)).foregroundColor(DDColor.ink)
                                        if !a.phone.isEmpty {
                                            Text(a.phone).font(pf(13)).foregroundColor(DDColor.sub)
                                        }
                                    }
                                    Text(a.full.isEmpty ? Tr("还没填详细地址") : a.full)
                                        .font(pf(13)).foregroundColor(DDColor.sub)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(Tr("请先填写收货地址"))
                                        .font(pf(15)).foregroundColor(DDColor.red)
                                    Text(Tr("点这里新增一条")) .font(pf(12.5)).foregroundColor(DDColor.sub)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DDColor.sub.opacity(0.55))
                                .padding(.top, 4)
                        }
                        .padding(14)
                        .background(DDColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Text(Tr("合计")).font(pf(14)).foregroundColor(DDColor.sub)
                        Spacer(minLength: 0)
                        DDPrice(value: total, size: 20)
                    }
                    .padding(.horizontal, 4)
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            Button { submit() } label: {
                Text(group ? Tr("发起拼单") : Tr("立即支付"))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23).fill(DDColor.gradBtn))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.bottom, max(10, L.safeBottom))
        }
        .background(DDColor.page.ignoresSafeArea())
        .sheet(isPresented: $showAddrList) {
            DDAddressListView(pick: { a in pickedAddrId = a.id })
        }
        .ddLight()
    }

    /// 这次下单用哪条地址：下单页里挑的那条优先，其次默认那条
    private var chosenAddr: DDAddress? {
        if !pickedAddrId.isEmpty, let a = store.addresses.first(where: { $0.id == pickedAddrId }) {
            return a
        }
        return store.defaultAddress
    }

    private func pick(_ title: String, _ sub: String, _ isGroup: Bool) -> some View {
        Button { group = isGroup } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(15, .medium)).foregroundColor(DDColor.ink)
                    Text(sub).font(pf(12)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                Image(systemName: group == isGroup ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(group == isGroup ? DDColor.red : DDColor.sub)
            }
            .padding(.horizontal, 14).frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        store.place(pid: product.id, count: count, group: group)
        dismiss()
        app.show(group ? Tr("拼单已发起，等好友来拼") : Tr("下单成功，去「我的订单」看进度"))
    }
}

/* ---------------------------------------------------------- 我的订单 */

struct DDOrdersView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    @State private var filter = 0

    private let names = ["全部", "拼团中", "待发货", "待收货", "已完成"]

    private var list: [DDOrder] {
        switch filter {
        case 1: return store.orders.filter { $0.status == "grouping" }
        case 2: return store.orders.filter { $0.status == "wait" }
        case 3: return store.orders.filter { $0.status == "shipped" }
        case 4: return store.orders.filter { $0.status == "done" }
        default: return store.orders
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("我的订单"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(names.indices, id: \.self) { i in
                        Button { filter = i } label: {
                            Text(Tr(names[i]))
                                .font(pf(13.5, filter == i ? .semibold : .regular))
                                .foregroundColor(filter == i ? .white : DDColor.ink)
                                .padding(.horizontal, 14).frame(height: 30)
                                .background(Capsule().fill(filter == i
                                                            ? DDColor.red : DDColor.page))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 8)
            .background(DDColor.page)

            if list.isEmpty {
                VStack(spacing: 8) {
                    Text("📦").font(.system(size: 38))
                    Text(Tr("这里还没有订单")).font(pf(14.5)).foregroundColor(DDColor.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DDColor.page)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(list) { o in card(o) }
                        Spacer().frame(height: 14)
                    }
                    .padding(.vertical, 10)
                }
                .background(DDColor.page)
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }

    private func card(_ o: DDOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(o.shop).font(pf(13.5, .medium)).foregroundColor(DDColor.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(Tr(o.statusText))
                    .font(pf(12.5, .medium))
                    .foregroundColor(o.status == "done" || o.status == "cancel" ? DDColor.sub : DDColor.red)
            }
            HStack(alignment: .top, spacing: 10) {
                DDThumb(em: o.em, size: 62, radius: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(o.title).font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                    if o.group {
                        Text(Tr("拼团 ") + "\(o.have)/\(o.need)" + Tr(" 人"))
                            .font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                    Text(timeText(o.at)).font(pf(11)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    DDPrice(value: o.price, size: 15)
                    Text("×" + String(o.count)).font(pf(11.5)).foregroundColor(DDColor.sub)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if o.status == "grouping" {
                    Button { store.invite(o.id) } label: { smallBtn(Tr("邀好友拼单"), true) }
                        .buttonStyle(.plain)
                }
                if o.status == "wait" {
                    Button { store.ship(o.id) } label: { smallBtn(Tr("提醒发货"), false) }
                        .buttonStyle(.plain)
                }
                if o.canConfirm {
                    Button { store.confirm(o.id) } label: { smallBtn(Tr("确认收货"), true) }
                        .buttonStyle(.plain)
                }
                if o.canCancel {
                    Button { store.cancelOrder(o.id) } label: { smallBtn(Tr("取消订单"), false) }
                        .buttonStyle(.plain)
                }
                if o.status == "done" || o.status == "cancel" {
                    Button { store.removeOrder(o.id) } label: { smallBtn(Tr("删除"), false) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func smallBtn(_ t: String, _ filled: Bool) -> some View {
        Text(t)
            .font(pf(12.5))
            .foregroundColor(filled ? .white : DDColor.ink)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(filled ? DDColor.red : DDColor.page))
    }
}

/* ---------------------------------------------------------- 收藏 / 搜索 */

struct DDFavView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    private var list: [DDProduct] { store.products.filter { store.isFav($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("我的收藏"))
            if list.isEmpty {
                Text(Tr("还没有收藏的商品")).font(pf(14.5)).foregroundColor(DDColor.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(list) { p in
                            Button { onOpen(p) } label: { DDProductCard(product: p) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }
}

/* ---------------------------------------------------------- 浏览足迹 */

/// 我看过的商品（点开详情就记一条；和「我的收藏」一个样子）
struct DDViewsView: View {
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    private var list: [DDProduct] { store.viewed }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("浏览足迹"))
            if list.isEmpty {
                Text(Tr("还没有浏览记录")).font(pf(14.5)).foregroundColor(DDColor.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(list) { p in
                            Button { onOpen(p) } label: { DDProductCard(product: p) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                Button {
                    store.clearViews()
                } label: {
                    Text(Tr("清空浏览足迹"))
                        .font(pf(14.5)).foregroundColor(DDColor.sub)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }
}

struct DDSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    @State private var q = ""

    private var hot: [String] { ["百亿补贴", "限时秒杀", "数码", "服饰", "生鲜", "食品"] }
    private var result: [DDProduct] { store.search(q) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(DDColor.ink)
                            .frame(width: 32, height: 38)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14)).foregroundColor(DDColor.weak)
                        TextField(Tr("搜索想要的商品"), text: $q)
                            .font(pf(14.5))
                            .submitLabel(.search)
                            .onSubmit { store.pushHistory(q) }
                        if !q.isEmpty {
                            Button { q = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15)).foregroundColor(DDColor.weak)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(DDColor.card))
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 8)
            .background(DDColor.page)

            if q.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !store.history.isEmpty {
                            HStack {
                                Text(Tr("搜索历史")).font(pf(14.5, .semibold)).foregroundColor(DDColor.ink)
                                Spacer(minLength: 0)
                                Button { store.clearHistory() } label: {
                                    Text(Tr("清空")).font(pf(12.5)).foregroundColor(DDColor.sub)
                                }
                                .buttonStyle(.plain)
                            }
                            chips(store.history, fill: true)
                        }
                        Text(Tr("热门搜索")).font(pf(14.5, .semibold)).foregroundColor(DDColor.ink)
                        chips(hot, fill: false)
                        Spacer().frame(height: 10)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
                .background(DDColor.page)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(result) { p in
                            Button {
                                store.pushHistory(q)
                                onOpen(p)
                            } label: { resultRow(p) }
                            .buttonStyle(.plain)
                        }
                        if result.isEmpty {
                            Text(Tr("没有找到相关商品")).font(pf(14)).foregroundColor(DDColor.sub)
                                .padding(.top, 50)
                        }
                        Spacer().frame(height: 14)
                    }
                    .padding(.vertical, 10)
                }
                .background(DDColor.page)
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }

    private func chips(_ arr: [String], fill: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
            ForEach(arr, id: \.self) { s in
                Button { q = s } label: {
                    Text(s)
                        .font(pf(13)).foregroundColor(fill ? DDColor.ink : DDColor.red)
                        .padding(.horizontal, 10).frame(height: 30)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(fill ? DDColor.card : DDColor.redLight))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resultRow(_ p: DDProduct) -> some View {
        HStack(spacing: 10) {
            DDThumb(em: p.em, size: 62, radius: 8, img: p.img)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.title).font(pf(13.5)).foregroundColor(DDColor.ink).lineLimit(2)
                HStack(spacing: 6) {
                    DDPrice(value: p.price, size: 16)
                    if !p.sold.isEmpty {
                        Text(Tr("已拼") + p.sold).font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                }
                Text(p.shop).font(pf(11.5)).foregroundColor(DDColor.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
    }
}

/* ---------------------------------------------------------- 公共小条 */

/// sheet 上那条「取消 + 标题」的顶栏（这些页面是弹出来的，不需要返回箭头）
struct DDSheetBar: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
        ZStack {
            Text(Tr(title)).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
            HStack {
                Button { dismiss() } label: {
                    Text(Tr("关闭")).font(pf(16)).foregroundColor(DDColor.ink)
                        .frame(height: 44)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .frame(height: L.navH)
        .background(DDColor.card)
        .overlay(HairLine(), alignment: .bottom)
    }
}

/// 「x 分钟前 / 昨天 / 10-12 15:20」这种时间
func ddTimeText(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) {
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 1 { return "刚刚" }
        if mins < 60 { return "\(mins) 分钟前" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "今天 " + f.string(from: d)
    }
    if cal.isDateInYesterday(d) {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "昨天 " + f.string(from: d)
    }
    let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
    return f.string(from: d)
}

private func timeText(_ d: Date) -> String { ddTimeText(d) }
