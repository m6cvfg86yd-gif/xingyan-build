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

    /* ---------------- 2026-10-15 对齐京东加的字段（全可空，老数据/老包都兼容） ---------------- */
    /// 副标题（京东：标题下面那行卖点）
    var subtitle: String? = nil
    var brand: String? = nil
    /// 评分 0~5（没评价就是 nil）
    var rating: Double? = nil
    /// 销量（数，比 sold 那个字符串更细）
    var sales: Int? = nil
    /// 规格（颜色/尺码/套餐），选完价格可能变
    var variants: [DDVariant]? = nil
    /// 参数表：一行是 [名称, 值]
    var params: [[String]]? = nil
    /// 图文详情的图（没有就用主图 + 生成的图文块）
    var detailImages: [String]? = nil
    /// 服务承诺
    var services: [String]? = nil
    /// 店铺 id（关注店铺用；没有就用店铺名）
    var shopId: String? = nil

    /// 店铺标识（关注/取关按它记）
    var shopKey: String { (shopId?.isEmpty == false) ? shopId! : shop }

    /// 规格列表：后台没配就按类目合成几个 —— 京东每个商品都有规格，不能让用户点了没反应
    var specList: [DDVariant] {
        if let v = variants, !v.isEmpty { return v }
        switch cate {
        case "服饰":
            return ["S", "M", "L", "XL"].map { DDVariant(name: $0, price: price, stock: 99) }
        case "运动", "母婴":
            return ["38", "40", "42", "44"].map { DDVariant(name: $0, price: price, stock: 88) }
        case "美妆", "食品":
            return [DDVariant(name: "单件装", price: price, stock: 99),
                    DDVariant(name: "3件装", price: (price * 2.7 * 100).rounded() / 100, stock: 99),
                    DDVariant(name: "整箱装", price: (price * 8.5 * 100).rounded() / 100, stock: 99)]
        default:
            return [DDVariant(name: "标准款", price: price, stock: 99),
                    DDVariant(name: "升级款", price: (price * 1.25 * 100).rounded() / 100, stock: 99)]
        }
    }

    /// 服务承诺（后台没配就给京东最常见的几句）
    var serviceList: [String] {
        if let s = services, !s.isEmpty { return s }
        return ["7天无理由退货", "退货包运费", "正品保障", "极速退款"]
    }

    /// 给服务器（/api/ops/mall）用的字典
    var dict: [String: Any] {
        ["id": id, "em": em, "img": img ?? "", "title": title,
         "price": price, "orig": orig, "sold": sold, "grp": grp,
         "tags": tags, "shop": shop, "cate": cate, "on": live]
    }
}

/// 一个规格（京东的 SKU）
struct DDVariant: Codable, Hashable, Identifiable {
    var name: String
    var price: Double
    var stock: Int
    var id: String { name }
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
    /* ---------------- 2026-10-15 对齐京东加的字段 ---------------- */
    /// 下单时选的规格
    var spec: String = ""
    /// 订单号（京东那种长号）
    var orderNo: String = ""
    /// 运费
    var freight: Double = 0
    /// 用掉的优惠券金额
    var couponOff: Double = 0
    /// 发票抬头（空 = 不开发票）
    var invoice: String = ""
    var payWay: String = "微信支付"
    var remark: String = ""
    /// 收货信息（下单那一刻存下来，以后改地址不影响老订单）
    var addrName: String = ""
    var addrPhone: String = ""
    var addrText: String = ""
    /// 快递公司 / 单号
    var express: String = ""
    var expressNo: String = ""
    /// 付过款的时间（待付款倒计时用）
    var paidAt: Date? = nil
    /// 评价过没有
    var reviewed: Bool = false
    /// 会员立减（星言PLUS 专享价省下来的钱）
    var memberOff: Double = 0

    /// 实付 = 单价×数量 + 运费 − 优惠券 − 会员立减
    var total: Double { max(0, price * Double(count) + freight - couponOff - memberOff) }

    /// 京东那种订单号（纯演示用，本机生成）
    static func makeNo() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: Date()) + String(Int.random(in: 100000...999999))
    }

    var statusText: String {
        switch status {
        case "paying":   return "待付款"
        case "grouping": return "拼团中"
        case "wait":     return "待发货"
        case "shipped":  return "待收货"
        case "done":     return "已完成"
        case "cancel":   return "已取消"
        default:         return status
        }
    }
    var canConfirm: Bool { status == "shipped" }
    var canCancel: Bool { status == "paying" || status == "grouping" || status == "wait" }
    var canPay: Bool { status == "paying" }
    /// 已完成、还没评价过 → 能去评价晒单
    var canReview: Bool { status == "done" && !reviewed }
    /// 待付款的剩余秒数（30 分钟）
    var payLeft: Int {
        guard status == "paying" else { return 0 }
        return max(0, 1800 - Int(Date().timeIntervalSince(at)))
    }
}

/// 商城数据（单例 + 落盘）
/// 一条**后台下发**的广告（data/mall.json 的 ads[]，后台「商城 → 广告」里写）
struct DDAd: Decodable, Identifiable, Hashable {
    var id: String
    /// grid = 插在瀑布流里的广告卡 · strip = 楼层之间的广告条
    var kind: String?
    var emoji: String?
    var title: String
    var sub: String?
    var cta: String?
    /// 两个十六进制颜色（可空 = 用默认红）
    var top: String?
    var bottom: String?
    /// vip / music / subsidy / none（none 就按 link 打开网页）
    var action: String?
    var link: String?
    var on: Bool?
    var sort: Int?

    var isGrid: Bool { (kind ?? "strip") == "grid" }
    var topColor: UInt32 { UInt32((top ?? "").replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xFFF1EA }
    var bottomColor: UInt32 { UInt32((bottom ?? "").replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xFF5F3A }
}

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
    /* ---------------- 2026-10-15 对齐京东加的数据 ---------------- */
    /// 商品评价（本机记录；确认收货后自己也能发）
    @Published private(set) var reviews: [DDReview] = []
    /// 售后单（退款 / 退货 / 换货）
    @Published private(set) var afterSales: [DDAfterSale] = []
    /// 关注的店铺
    @Published private(set) var followedShops: [String] = []
    /// 优惠券（结算时抵钱）
    @Published private(set) var coupons: [DDCoupon] = []
    /// 商城服务通知（成团 / 发货 / 签收）
    @Published private(set) var notices: [DDNotice] = []
    /// 购物车里每条选了什么规格：pid → 规格名
    @Published private(set) var cartSpec: [String: String] = [:]
    /// 发票抬头（结算页用）
    @Published var invoiceTitle: String = ""
    /// 支付方式（演示：只在订单里记一下，不真扣钱）
    @Published var payWay: String = "微信支付"
    /* ---------------- 2026-10-15 对齐京东：会员（星言 PLUS） ---------------- */
    /// 会员到期时间（nil / 已经过去 = 不是会员）
    @Published private(set) var vipUntil: Date? = nil
    /// 自动续费开关（演示：只记状态）
    @Published var vipAutoRenew = true
    /// 会员累计帮省（下单时的会员立减往这里累加）
    @Published private(set) var vipSaved: Double = 0
    /* ---------------- 2026-10-15：卡片可关 / 不感兴趣 ---------------- */
    /// 关掉的小广告 id（广告卡右上角那个 ×）
    @Published private(set) var hiddenAds: [String] = []
    /// 「不感兴趣」的商品 id（推荐流不再出现）
    @Published private(set) var disliked: [String] = []
    /// 「不感兴趣」的类目（少推荐这一类）
    @Published private(set) var mutedCates: [String] = []
    /// 后台下发的广告（空 = 用 App 内置那两条）
    @Published private(set) var ads: [DDAd] = []

    /// 会员折扣：下单按 95 折算会员价（京东 PLUS 是专享价，这里统一一个系数，能算也能看见）
    static let vipRate = 0.95

    var isVip: Bool {
        guard let d = vipUntil else { return false }
        return d > Date()
    }

    /// 会员还剩几天（不是会员 = 0）
    var vipDaysLeft: Int {
        guard isVip, let d = vipUntil else { return 0 }
        return max(0, Int(ceil(d.timeIntervalSinceNow / 86400)))
    }

    /// 会员到期那天（写成人话）
    var vipUntilText: String {
        guard let d = vipUntil else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// 会员价 = 拼单价 × 折扣（不是会员就是原价）
    func vipPrice(_ p: DDProduct) -> Double {
        isVip ? ((p.price * DDStore.vipRate * 100).rounded() / 100) : p.price
    }

    /// 这一单会员立减多少（不是会员 = 0）
    func vipOff(_ amount: Double) -> Double {
        isVip ? ((amount * (1 - DDStore.vipRate) * 100).rounded() / 100) : 0
    }

    /// 开通 / 续费：months 个月（演示：不真扣钱，只把到期时间往后推）
    func openVip(months: Int) {
        let base = max(Date(), vipUntil ?? Date())
        vipUntil = Calendar.current.date(byAdding: .month, value: max(1, months), to: base) ?? base
        vipAutoRenew = true
        save()
    }

    func setVipAutoRenew(_ on: Bool) {
        vipAutoRenew = on
        save()
    }

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
        var reviews: [DDReview]?
        var afterSales: [DDAfterSale]?
        var followedShops: [String]?
        var coupons: [DDCoupon]?
        var notices: [DDNotice]?
        var cartSpec: [String: String]?
        var invoiceTitle: String?
        var payWay: String?
        /// 会员（老缓存里没有这几个字段）
        var vipUntil: Date?
        var vipAutoRenew: Bool?
        var vipSaved: Double?
        var hiddenAds: [String]?
        var disliked: [String]?
        var mutedCates: [String]?
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
            reviews = b.reviews ?? []
            afterSales = b.afterSales ?? []
            followedShops = b.followedShops ?? []
            coupons = b.coupons ?? []
            notices = b.notices ?? []
            cartSpec = b.cartSpec ?? [:]
            invoiceTitle = b.invoiceTitle ?? ""
            payWay = b.payWay ?? "微信支付"
            vipUntil = b.vipUntil
            vipAutoRenew = b.vipAutoRenew ?? true
            vipSaved = b.vipSaved ?? 0
            hiddenAds = b.hiddenAds ?? []
            disliked = b.disliked ?? []
            mutedCates = b.mutedCates ?? []
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
                    views: views, addresses: addresses,
                    reviews: reviews, afterSales: afterSales, followedShops: followedShops,
                    coupons: coupons, notices: notices, cartSpec: cartSpec,
                    invoiceTitle: invoiceTitle, payWay: payWay,
                    vipUntil: vipUntil, vipAutoRenew: vipAutoRenew, vipSaved: vipSaved,
                    hiddenAds: hiddenAds, disliked: disliked, mutedCates: mutedCates)
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: fileURL) }
    }

    /* ---------------- 和管理端同步（服务器 data/mall.json 是真源） ---------------- */

    /// 上架中的商品（商城首页/搜索只显示这些；管理页看得到全部）
    var live: [DDProduct] { products.filter { $0.live } }

    /* ---------------- 2026-10-15 用户：「拼单功能先关闭，可以后台开启」 ----------------
       后台 ui.json 里写 `mallGroup = 1` 就打开拼单；**默认 0 = 关**。
       关掉之后就是京东那种「直接买」：
         · 商品详情底部只剩「加入购物车 / 立即购买」（不再 单独购买 vs 发起拼单）
         · 结算页不再选拼单方式，直接按这个价结算
         · 订单里不再出现「拼团中 / 邀好友拼单 / 拼单消息」（老订单里的拼团中还在，只是不再新增） */
    static var groupOn: Bool { UIConfig.num("mallGroup", 0) > 0 }

    /// 从服务器拉一份（进商城、管理里改完、下拉刷新都走它）
    func refresh() async {
        let (ps, bs, nm, sl, ad) = await API.shared.mallData()
        if !ps.isEmpty { products = ps }
        banners = bs
        if !nm.isEmpty { mallName = nm }
        if !sl.isEmpty { mallSlogan = sl }
        ads = ad.filter { $0.on != false }.sorted { ($0.sort ?? 99) < ($1.sort ?? 99) }
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
        /* 第一次加这个商品时，默认选第一个规格（京东加购就带规格） */
        if cartSpec[pid] == nil, let p = product(pid) { cartSpec[pid] = p.specList.first?.name ?? "" }
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
    func place(pid: String, count: Int, group: Bool, fromCart: Bool = false,
               spec: String = "", address: DDAddress? = nil, remark: String = "",
               freight: Double = 0, couponOff: Double = 0, invoice: String = "",
               memberOff: Double = 0,
               payWay: String = "微信支付", paying: Bool = true) -> DDOrder {
        let p = product(pid)
        /* 选了规格就按规格价 */
        var unit = group ? (p?.price ?? 0) : (p?.orig ?? p?.price ?? 0)
        if let v = p?.specList.first(where: { $0.name == spec }) { unit = v.price }
        /* 会员：按会员价成交（不是会员时 vipOff 返回 0） */
        let vipOff = memberOff > 0 ? memberOff : self.vipOff(unit * Double(max(1, count)))
        if vipOff > 0 { vipSaved += vipOff }
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
                        status: paying ? "paying" : (group ? "grouping" : "wait"),
                        at: Date(),
                        spec: spec,
                        orderNo: DDOrder.makeNo(),
                        freight: freight,
                        couponOff: couponOff,
                        invoice: invoice,
                        payWay: payWay,
                        remark: remark,
                        addrName: address?.name ?? "",
                        addrPhone: address?.phone ?? "",
                        addrText: address?.full ?? "",
                        memberOff: vipOff)
        orders.insert(o, at: 0)
        if fromCart { cart.removeAll { $0.pid == pid } }
        pushNotice(DDNotice(id: "n" + String(now), title: "订单已提交",
                            body: "「" + o.title + "」等你付款，30 分钟未付会自动取消",
                            at: Date(), kind: "order"))
        save()
        return o
    }

    /// 付款（演示：不真扣钱，只把状态推进）
    func pay(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        guard orders[i].status == "paying" else { return }
        orders[i].paidAt = Date()
        orders[i].status = orders[i].group ? "grouping" : "wait"
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "付款成功",
                            body: orders[i].group ? "拼单已发起，人满就发货" : "商家正在打包，48 小时内发货",
                            at: Date(), kind: "order"))
        save()
    }

    /// 邀请好友拼单：直接把人数凑满 → 成团，状态进「待发货」
    func invite(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].have = orders[i].need
        orders[i].status = "wait"
        /* 成团也推一条服务通知（消息 tab 里能看到 —— 对齐京东） */
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "拼单成功",
                            body: "「" + orders[i].title + "」已成团，商家马上打包发货",
                            at: Date(), kind: "group"))
        save()
    }

    func cancelOrder(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].status = "cancel"
        save()
    }

    func ship(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        if orders[i].status == "wait" {
            orders[i].status = "shipped"
            /* 发货就给个快递公司和单号（京东发货后能看物流） */
            let kuaidi = ["顺丰速运", "中通快递", "圆通速递", "韵达快递"]
            orders[i].express = kuaidi[Int.random(in: 0..<kuaidi.count)]
            orders[i].expressNo = "SF" + String(Int(Date().timeIntervalSince1970)) + String(Int.random(in: 100...999))
            pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                                title: "包裹已发出",
                                body: orders[i].express + "：" + orders[i].expressNo,
                                at: Date(), kind: "ship"))
            save()
        }
    }

    func confirm(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].status = "done"
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "交易完成", body: "去给「" + orders[i].title + "」写个评价吧",
                            at: Date(), kind: "done"))
        save()
    }

    func markReviewed(_ orderId: String) {
        guard let i = orders.firstIndex(where: { $0.id == orderId }) else { return }
        orders[i].reviewed = true
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "评价成功", body: "感谢你的评价", at: Date(), kind: "review"))
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

    /* ---------------- 评价（对齐京东） ---------------- */

    /// 本机发的评价 + 每个商品自带的几条示例评价（确定性生成，不随机跳）
    func reviews(of p: DDProduct) -> [DDReview] {
        let mine = reviews.filter { $0.pid == p.id }
        return (mine + DDReview.samples(for: p)).sorted { $0.at > $1.at }
    }

    /// 平均分（没评价就 nil，界面显示"暂无评价"）
    func rating(of p: DDProduct) -> Double? {
        let list = reviews(of: p)
        guard !list.isEmpty else { return nil }
        return list.reduce(0.0) { $0 + Double($1.rating) } / Double(list.count)
    }

    func addReview(_ r: DDReview) {
        reviews.insert(r, at: 0)
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "评价成功", body: "你对「" + r.title + "」的评价已经发布",
                            at: Date(), kind: "review"))
        save()
    }

    /* ---------------- 售后（退款/退货/换货） ---------------- */

    func addAfterSale(_ a: DDAfterSale) {
        afterSales.insert(a, at: 0)
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "售后已提交", body: a.kind + "申请已提交，商家会在 24 小时内处理",
                            at: Date(), kind: "aftersale"))
        save()
    }

    func afterSales(of orderId: String) -> [DDAfterSale] { afterSales.filter { $0.orderId == orderId } }

    func cancelAfterSale(_ id: String) {
        afterSales.removeAll { $0.id == id }
        save()
    }

    /* ---------------- 关注的店铺 ---------------- */

    func isFollowed(_ key: String) -> Bool { followedShops.contains(key) }

    func toggleFollow(_ key: String) {
        guard !key.isEmpty else { return }
        if let i = followedShops.firstIndex(of: key) { followedShops.remove(at: i) }
        else { followedShops.insert(key, at: 0) }
        save()
    }

    /// 关注过的店铺 → 商品列表（去重）
    var followedProducts: [DDProduct] {
        var out: [DDProduct] = []
        for p in products where followedShops.contains(p.shopKey) && !out.contains(where: { $0.id == p.id }) {
            out.append(p)
        }
        return out
    }

    /* ---------------- 优惠券 ---------------- */

    /// 这张券现在能不能用在 total 上
    func couponUsable(_ c: DDCoupon, total: Double) -> Bool {
        !c.used && Date() < c.until && total >= c.min
    }
    func usableCoupons(_ total: Double) -> [DDCoupon] {
        coupons.filter { couponUsable($0, total: total) }.sorted { $0.off > $1.off }
    }
    func useCoupon(_ id: String) {
        guard let i = coupons.firstIndex(where: { $0.id == id }) else { return }
        coupons[i].used = true
        save()
    }
    /// 第一次打开商城送两张（京东新客券那套）
    func seedCouponsIfNeeded() {
        guard coupons.isEmpty else { return }
        let now = Date()
        coupons = [
            DDCoupon(id: "c5", title: "满 20 减 5", off: 5, min: 20, until: now.addingTimeInterval(30 * 86400), used: false),
            DDCoupon(id: "c12", title: "满 50 减 12", off: 12, min: 50, until: now.addingTimeInterval(30 * 86400), used: false)
        ]
        save()
    }

    /* ---------------- 服务通知 ---------------- */

    func pushNotice(_ n: DDNotice) {
        notices.insert(n, at: 0)
        if notices.count > 60 { notices = Array(notices.prefix(60)) }
    }
    func clearNotices() { notices.removeAll(); save() }

    /// 删掉一条服务通知（消息 tab 里左滑删除用）
    func removeNotice(_ id: String) {
        notices.removeAll { $0.id == id }
        save()
    }

    /* ---------------- 卡片可关 / 不感兴趣（2026-10-15 用户要求） ---------------- */

    /// 广告被 × 掉了（记下来，以后不再出现）
    func hideAd(_ id: String) {
        guard !hiddenAds.contains(id) else { return }
        hiddenAds.append(id)
        save()
    }
    func adHidden(_ id: String) -> Bool { hiddenAds.contains(id) }

    /// 长按商品 →「不感兴趣」：这件商品不再推，同时**少推这一类**
    func notInterested(_ p: DDProduct, muteCate: Bool) {
        if !disliked.contains(p.id) { disliked.append(p.id) }
        if muteCate, !p.cate.isEmpty, !mutedCates.contains(p.cate) { mutedCates.append(p.cate) }
        save()
    }
    /// 恢复（把「少推这一类」撤掉）
    func unmuteCate(_ c: String) {
        mutedCates.removeAll { $0 == c }
        save()
    }
    /// 推荐流用的「干净列表」：去掉不感兴趣的；被打过「少推」的类目排到最后
    func feed(_ list: [DDProduct]) -> [DDProduct] {
        list.filter { !disliked.contains($0.id) }
            .sorted { a, b in
                let ma = mutedCates.contains(a.cate) ? 1 : 0
                let mb = mutedCates.contains(b.cate) ? 1 : 0
                return ma < mb
            }
    }

    /* ---------------- 购物车（店铺分组 / 失效 / 规格） ---------------- */

    func cartSpecOf(_ pid: String) -> String { cartSpec[pid] ?? "" }
    func setCartSpec(_ pid: String, _ spec: String) { cartSpec[pid] = spec; save() }

    /// 失效条目：商品被删了或下架了
    var invalidCart: [DDCartLine] {
        cart.filter { l in
            guard let p = product(l.pid) else { return true }
            return !p.live
        }
    }
    /// 有效的条目
    var validCart: [DDCartLine] {
        cart.filter { l in (product(l.pid)?.live ?? false) }
    }
    /// 按店铺分组（京东购物车就是一店一卡片）
    func cartGrouped() -> [(shop: String, lines: [DDCartLine])] {
        var order: [String] = []
        var map: [String: [DDCartLine]] = [:]
        for l in validCart {
            let s = product(l.pid)?.shop ?? "店铺"
            if map[s] == nil { order.append(s) }
            map[s, default: []].append(l)
        }
        return order.map { (shop: $0, lines: map[$0] ?? []) }
    }
    /// 移除失效条目
    func clearInvalidCart() {
        let bad = Set(invalidCart.map { $0.pid })
        cart.removeAll { bad.contains($0.pid) }
        save()
    }

    func removeCartLine(_ pid: String) {
        cart.removeAll { $0.pid == pid }
        save()
    }

    /// 再来一单：把那张订单里的商品重新加回购物车
    func reorder(_ o: DDOrder) {
        addCart(o.pid, count: max(1, o.count))
        setCartSpec(o.pid, o.spec)
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

/* 2026-10-15 用户：「顶部的渐变色弄浅色高级感」——
   原来商城顶部是 H5 那套正红（#FF5F3A → #EF3323 → #D81A10），现在换成**很淡的暖白渐变**
   （#FFFBF8 → #FFF1EA → #FFE6DC）：字/图标跟着变深色，搜索框留一条极细描边。
   想回正红（或换成别的）：后台 ui.json 里写
     mallTopGrad = "#FF5F3A,#EF3323,#D81A10"
   2~3 个十六进制颜色，逗号隔开就行。 */
func ddTopGradient() -> LinearGradient {
    func col(_ s: String) -> Color? {
        let v = s.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        guard let n = UInt32(v, radix: 16) else { return nil }
        return Color(hex: n)
    }
    let raw = UIConfig.text("mallTopGrad", "")
    if !raw.isEmpty {
        let cols = raw.split(separator: ",").map { col(String($0)) }.compactMap { $0 }
        if cols.count >= 2 {
            return LinearGradient(colors: cols, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    return LinearGradient(colors: [Color(hex: 0xFFFBF8), Color(hex: 0xFFF1EA), Color(hex: 0xFFE6DC)],
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
        /* 2026-10-15 家长版（京东）价格排版：**¥ 小、整数大、小数小** ——
           京东那种「¥39.9」里 39 特别大、.9 收小，一眼就是电商味。 */
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("¥").font(pf(size * 0.62, .semibold)).foregroundColor(color)
            Text(DDPrice.split(value).0)
                .font(pf(size * 1.12, .bold)).foregroundColor(color)
            if !DDPrice.split(value).1.isEmpty {
                Text(DDPrice.split(value).1)
                    .font(pf(size * 0.72, .bold)).foregroundColor(color)
            }
        }
    }

    /// 把价格切成 (整数部分, ".小数部分") —— 京东那种大小字排版用
    static func split(_ v: Double) -> (String, String) {
        let s = moneyFmt(v)
        guard s.contains(".") else { return (s, "") }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (s, "") }
        return (String(parts[0]), "." + String(parts[1]))
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
    /// 会员中心（顶栏那颗 PLUS）
    @State private var showVip = false

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
            DDDetailView(product: p,
                         onCart: { tab = 3 },
                         onOpenOther: { openProduct = $0 }).environmentObject(app)
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
        .sheet(isPresented: $showVip) {
            DDVipPageView(onOpen: { p in
                showVip = false
                openProduct_tap(p)
            })
            .environmentObject(app)
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
                        .foregroundColor(DDColor.ink)
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if tab == 0 {
                    /* 2026-10-15 用户：「顶部感觉和京东要一样」——
                       京东顶上是「一条大搜索框 + 右边两个图标」，没有大标题。
                       所以搜索框挪上来当主角，商城名/标语缩成下面一行小字（品牌还留着）。 */
                    Button { showSearch = true } label: { searchBox }
                        .buttonStyle(.plain)
                    Button { showVip = true } label: {
                        Text("PLUS")
                            .font(pf(11.5, .bold)).foregroundColor(Color(hex: 0x5A3E14))
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(Capsule().fill(Color(hex: 0xFFE7B0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { showOrders = true } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(DDColor.ink)
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
                HStack(spacing: 4) {
                    Text(store.mallName).font(pf(12.5, .semibold)).foregroundColor(DDColor.ink)
                    Text(store.mallSlogan).font(pf(11)).foregroundColor(DDColor.sub)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        /* ⚠ 红色要**顶到状态栏**（京东就是这样）：只给背景铺到安全区上面，
           内容照旧从安全区下面开始 */
        .background { headerBg.ignoresSafeArea(edges: .top) }
    }

    @ViewBuilder private var headerBg: some View {
        if tab == 0 {
            ddTopGradient()
        } else {
            DDColor.page
        }
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: 0xA79C97))
            Text(Tr("搜索想要的商品")).font(pf(14)).foregroundColor(Color(hex: 0xA79C97))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Color.white))
        /* 浅色顶部上，白搜索框要一条极细描边 + 一丁点投影才立得住（高级感的来源） */
        .overlay(Capsule().stroke(Color(hex: 0xF0E4DE), lineWidth: 0.6))
        .shadow(color: Color(hex: 0x8A6A5A).opacity(0.06), radius: 6, y: 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        switch tab {
            case 0: DDHomeTab(onOpen: openProduct_tap, onCart: { tab = 3 })
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
            /* 2026-10-15 用户：「底栏还是太高了」（商城）——
               病根：这里以前又加了 `max(4, L.safeBottom)`（=34），可**外面那层 VStack
               本来就已经避开 home 条那 34 了**，等于同一个 34 算了两遍 → 底栏高一截。
               现在：内容高 49（京东那个量级，图标 23 + 字 10 在里面居中）+
               贴着 home 条上方留 6pt；白色底**铺到屏幕最底**（home 条那一块也是白的，
               和微信/京东一模一样）。想微调：ui.json 的 mallTabH / mallTabPad。 */
            .frame(height: UIConfig.num("mallTabH", 49))
            .padding(.bottom, UIConfig.num("mallTabPad", 2))
        }
        .background { DDColor.card.ignoresSafeArea(edges: .bottom) }
    }

    private func tabButton(_ i: Int, _ label: String, _ icon: String, _ badge: Int) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: UIConfig.num("mallTabIcon", 23),
                                      weight: tab == i ? .semibold : .regular))
                        .foregroundColor(tab == i ? DDColor.red : DDColor.sub)
                        .frame(width: 28, height: 24)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : String(badge))
                            .font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).frame(height: 14)
                            .background(Capsule().fill(DDColor.redDeep))
                            .offset(x: 9, y: -5)
                    }
                }
                Text(Tr(label))
                    .font(pf(UIConfig.num("mallTabLabel", 10), tab == i ? .medium : .regular))
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
    @EnvironmentObject private var app: AppState
    /// 后台广告可以配一个网址（action = none 时点开它）
    @Environment(\.openURL) private var openLink
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void
    /// 详情页里点「加购物车」→ 外面切到购物车那个 tab
    var onCart: () -> Void = { }

    /// 打开的频道页（百亿补贴 / 排行榜 / 9.9包邮 / 厂家直供）
    @State private var channel: DDChannelKind? = nil
    /// 广告位点开的东西：会员中心 / 听一听
    @State private var showVipAd = false
    @State private var showMusicAd = false
    /// 宫格第二行那四个功能（京东那种：订单 / 购物车 / 收藏 / 足迹）
    @State private var showAdOrders = false
    @State private var showAdFav = false
    @State private var showAdViews = false
    @State private var cate: String? = nil
    @State private var secs = 2 * 3600 + 41 * 60 + 33
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var list: [DDProduct] {
        let base = cate == nil ? store.live : store.live.filter { $0.cate == cate }
        /* 「不感兴趣」的不再出现；「少推这一类」的沉到最后 */
        return store.feed(base)
    }

    var body: some View {
        /* 用 ScrollViewReader：点轮播图 / 「更多抢购」→ 滚到「为你推荐」那一栏
           （以前这两个地方点了没反应，用户报的「有些东西点不了」） */
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    carousel(proxy)
                    /* 2026-10-15 对齐京东：轮播图下面那排频道 */
                    DDChannelRow(onOpen: { channel = $0 }, onFunc: { f in
                        switch f {
                        case "orders": showAdOrders = true
                        case "cart":   onCart()
                        case "fav":    showAdFav = true
                        default:       showAdViews = true
                        }
                    })
                    /* 楼间小广告：**后台下发的**（后台没配就用内置那条百亿补贴） */
                    adStrip
                    seckill(proxy)
                    sectionTitle(Tr("为你推荐"), right: Tr("边逛边拼"))
                    /* 京东那种：标题下面一条可横滑的分类 tab（推荐 / 各分类） */
                    cateRow
                    if !store.mutedCates.isEmpty { mutedNote }
                    grid.id("dd-grid")
                    Spacer().frame(height: 16)
                }
                .padding(.top, 10)
            }
            .background(DDColor.page)
            .onReceive(ticker) { _ in if secs > 0 { secs -= 1 } }
            /* 频道页整页打开（它自己带返回 + 商品列表 + 商品详情） */
            .sheet(item: $channel) { k in
                DDChannelView(kind: k, onCart: { channel = nil; onCart() })
                    .environmentObject(app)
            }
            /* 广告位点开的两页 */
            .sheet(isPresented: $showVipAd) {
                DDVipPageView { p in
                    showVipAd = false
                    onOpen(p)
                }
                .environmentObject(app)
            }
            .fullScreenCover(isPresented: $showMusicAd) {
                NavigationStack { ListenView().environmentObject(app) }
            }
            /* 宫格第二行那几颗：订单 / 收藏 / 足迹（购物车那颗切 tab，不用弹页） */
            .sheet(isPresented: $showAdOrders) { DDOrdersView().environmentObject(app) }
            .sheet(isPresented: $showAdFav) {
                DDFavView(onOpen: { p in
                    showAdFav = false
                    onOpen(p)
                })
                .environmentObject(app)
            }
            .sheet(isPresented: $showAdViews) {
                DDViewsView(onOpen: { p in
                    showAdViews = false
                    onOpen(p)
                })
            }
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
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            /* 2026-10-15 用户：「商城的主页排版不行，功能逻辑主页对齐京东」——
               京东那个秒杀块是**左边一块红（竖排「限时秒杀」+ 倒计时）+ 右边横滑商品**。 */
            HStack(spacing: 0) {
                Button { toGrid(proxy) } label: {
                    VStack(spacing: 5) {
                        Text(Tr("限时")).font(pf(14, .semibold)).foregroundColor(.white)
                        Text(Tr("秒杀")).font(pf(14, .semibold)).foregroundColor(.white)
                        Text(clockText)
                            .font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background(Capsule().fill(Color.black.opacity(0.22)))
                    }
                    .frame(width: 74)
                    .frame(maxHeight: .infinity)
                    .background(LinearGradient(colors: [Color(hex: 0xFF5F3A), Color(hex: 0xD81A10)],
                                               startPoint: .top, endPoint: .bottom))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(store.live.prefix(8))) { p in
                            Button { onOpen(p) } label: { seckillCell(p) }
                                .buttonStyle(.plain)
                        }
                        Button { toGrid(proxy) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DDColor.sub)
                                Text(Tr("更多")).font(pf(11)).foregroundColor(DDColor.sub)
                            }
                            .frame(width: 54, height: 108)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(height: 108)
        }
        .padding(.vertical, 10)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func seckillCell(_ p: DDProduct) -> some View {
        VStack(spacing: 4) {
            DDThumb(em: p.em, size: 78, radius: 6, img: p.img)
            DDPrice(value: p.price, size: 15)
            Text("¥" + moneyFmt(p.orig))
                .font(pf(10.5)).foregroundColor(DDColor.sub)
                .strikethrough()
        }
        .frame(width: 82)
    }

    private var clockText: String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var cateRow: some View {
        /* 2026-10-15 用户要求「功能逻辑对齐京东」——
           京东推荐区上面不是一排胶囊，是**一条可以左右滑的 tab**：
           选中那个字变红 + 底下一道红短线（其余灰字），左边第一个是「推荐」。 */
        let names: [String] = ["推荐"] + store.categories
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(names, id: \.self) { c in
                    let on = (c == "推荐" && cate == nil) || cate == c
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            cate = (c == "推荐") ? nil : (cate == c ? nil : c)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(Tr(c))
                                .font(pf(15, on ? .semibold : .regular))
                                .foregroundColor(on ? DDColor.red : DDColor.ink)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(on ? DDColor.red : Color.clear)
                                .frame(width: 18, height: 2.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func sectionTitle(_ t: String, right: String) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DDColor.red).frame(width: 3.5, height: 15)
            Text(t).font(pf(16.5, .semibold)).foregroundColor(DDColor.ink)
            Spacer(minLength: 0)
            Text(right).font(pf(12.5)).foregroundColor(DDColor.sub)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DDColor.weak)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    /// 「已少推：xxx」+ 一键恢复（长按商品选「少推这一类」之后出现）
    private var mutedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash").font(.system(size: 12)).foregroundColor(DDColor.sub)
            Text(Tr("已少推：") + store.mutedCates.map { Tr($0) }.joined(separator: "、"))
                .font(pf(12)).foregroundColor(DDColor.sub).lineLimit(1)
            Spacer(minLength: 0)
            Button {
                if let c = store.mutedCates.first { store.unmuteCate(c) }
            } label: {
                Text(Tr("恢复")).font(pf(12.5, .medium)).foregroundColor(DDColor.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                Button { onOpen(p) } label: { DDProductCard(product: p) }
                    .buttonStyle(.plain)
                    /* 长按 → 不感兴趣（京东也是长按；选「少推这一类」就把这一类沉到最后） */
                    .contextMenu {
                        Button(role: .destructive) {
                            store.notInterested(p, muteCate: false)
                            app.show(Tr("好的，这件不再推给你"))
                        } label: { Label(Tr("不感兴趣"), systemImage: "hand.thumbsdown") }
                        if !p.cate.isEmpty {
                            Button {
                                store.notInterested(p, muteCate: true)
                                app.show(Tr("好的，少推「") + Tr(p.cate) + Tr("」"))
                            } label: { Label(Tr("不感兴趣，少推这一类"), systemImage: "eye.slash") }
                        }
                    }
                /* 每 6 个商品插一张小广告（和京东首页一样，左下角标了「广告」） */
                if (i + 1) % 6 == 0 { adCard(i / 6) }
            }
        }
        .padding(.horizontal, 10)
    }

    /// 楼间广告条：后台 ads 里 kind=strip 的第一条（没有就用内置那条）
    @ViewBuilder private var adStrip: some View {
        let list = store.ads.filter { !$0.isGrid }
        if list.isEmpty {
            DDAdStrip(emoji: "🗂", title: "百亿补贴 · 折扣最狠的一批",
                      sub: "省得最多的排前面，点进去直接逛", cta: "去看看",
                      top: 0xFFF1EA, bottom: 0xFF5F3A) { channel = .subsidy }
                .padding(.horizontal, 10)
        } else if let a = list.first, !store.adHidden("ad:" + a.id) {
            DDAdStrip(emoji: a.emoji ?? "🛍", title: a.title, sub: a.sub ?? "",
                      cta: a.cta ?? "去看看", top: a.topColor, bottom: a.bottomColor) {
                runAd(a)
            }
            .padding(.horizontal, 10)
        }
    }

    /// 插在瀑布流里的广告卡：**后台 ads 里 kind=grid 的轮着来**（没有就用内置那两条）
    @ViewBuilder private func adCard(_ n: Int) -> some View {
        let grid = store.ads.filter { $0.isGrid }
        if !grid.isEmpty {
            let a = grid[n % grid.count]
            if !store.adHidden("ad:" + a.id) {
                DDAdCard(emoji: a.emoji ?? "🛍", title: a.title, sub: a.sub ?? "",
                         cta: a.cta ?? "去看看", top: a.topColor, bottom: a.bottomColor,
                         adKey: "ad:" + a.id) { runAd(a) }
            }
        } else if n % 2 == 1 {
            if !store.adHidden("🎧听一听：曲库新歌随便放") {
                DDAdCard(emoji: "🎧", title: "听一听：曲库新歌随便放",
                         sub: "边逛边放，好友还能看到你在听什么", cta: "去听歌",
                         top: 0xB98CFF, bottom: 0x7A45D6) { showMusicAd = true }
            }
        } else {
            if !store.adHidden("👑星言PLUS 会员") {
                DDAdCard(emoji: "👑", title: "星言PLUS 会员",
                         sub: "下单立减 5%，退货免运费，专属客服", cta: "去开通",
                         top: 0xFFE7B0, bottom: 0xD9A94A) { showVipAd = true }
            }
        }
    }

    /// 后台那条广告点开干什么：vip / music / subsidy 走 App 内页；其它就按 link 打开
    private func runAd(_ a: DDAd) {
        switch a.action ?? "none" {
        case "vip":      showVipAd = true
        case "music":    showMusicAd = true
        case "subsidy":  channel = .subsidy
        default:
            if let s = a.link, !s.isEmpty, let u = URL(string: s) { openLink(u) }
        }
    }
}

/// 双列瀑布流里的那张商品卡
struct DDProductCard: View {
    let product: DDProduct
    @ObservedObject private var store = DDStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            /* 京东那张卡：图**正方形**（1:1）、圆角 6，标题 2 行 14，
               价格 ¥小/整数大/小数小，底下一行「已拼 xxx · 包邮」+ 店铺名 */
            DDThumb(em: product.em, size: 150, radius: 6, img: product.img)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
            Text(product.title)
                .font(pf(UIConfig.num("mallCardTitle", 14))).foregroundColor(DDColor.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                DDPrice(value: product.price, size: UIConfig.num("mallCardPrice", 17))
                Text("¥" + moneyFmt(product.orig))
                    .font(pf(11)).foregroundColor(DDColor.sub).strikethrough()
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                /* 没有真实销量数据的商品就不写「已拼 xxx」——不编数字 */
                if !product.sold.isEmpty {
                    Text(Tr("已拼") + product.sold)
                        .font(pf(10.5)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                /* 京东那种小标签：包邮 / 退货包运费（取商品自带标签里的头一个） */
                if DDStore.groupOn == false, let tag = product.tags.first {
                    Text(tag).font(pf(9.5)).foregroundColor(DDColor.red)
                        .padding(.horizontal, 4).frame(height: 15)
                        .background(RoundedRectangle(cornerRadius: 3).fill(DDColor.redLight))
                }
                /* 拼单关了就不再显示「x人团」（京东那种直接买） */
                if DDStore.groupOn {
                    Text(Tr("\(product.grp)人团"))
                        .font(pf(10.5)).foregroundColor(DDColor.red)
                        .padding(.horizontal, 5).frame(height: 17)
                    .background(Capsule().fill(DDColor.redLight))
                }
            }
            Text(product.shop).font(pf(10.5)).foregroundColor(DDColor.sub).lineLimit(1)
        }
        .padding(7)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }
}

/* ---------------------------------------------------------- 消息 */

struct DDMsgTab: View {
    @ObservedObject private var store = DDStore.shared
    /// 点消息卡片 → 去看订单（以前整条卡片点不了，只有「邀好友拼单」那颗按钮能点）
    var onOrders: () -> Void

    @State private var confirmClear = false

    /// 还在拼单中、要「邀好友拼单」那一颗的订单
    private var grouping: [DDOrder] { store.orders.filter { $0.status == "grouping" } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                /* 2026-10-15：消息 tab 接**真服务通知** ——
                   DDStore.notices 里是下单/付款/成团/发货/签收/评价/售后时真推的那些。 */
                if store.notices.isEmpty && grouping.isEmpty {
                    Text(Tr("还没有消息")).font(pf(14)).foregroundColor(DDColor.sub)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    Text(Tr("下单、付款、成团、发货、签收、评价之后，这里都会有服务通知"))
                        .font(pf(12)).foregroundColor(DDColor.sub)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                } else {
                    if !store.notices.isEmpty {
                        head(Tr("服务通知"), right: Tr("清空")) { confirmClear = true }
                        ForEach(store.notices) { n in noticeRow(n) }
                    }
                    if !grouping.isEmpty {
                        head(Tr("拼单消息"), right: "")
                        ForEach(grouping) { o in row(o) }
                    }
                }
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 10)
        }
        .background(DDColor.page)
        .alert(Tr("清空服务通知？"), isPresented: $confirmClear) {
            Button(Tr("取消"), role: .cancel) { }
            Button(Tr("清空"), role: .destructive) { store.clearNotices() }
        }
    }

    private func head(_ t: String, right: String, tap: @escaping () -> Void = { }) -> some View {
        HStack {
            Text(t).font(pf(13.5, .medium)).foregroundColor(DDColor.sub)
            Spacer(minLength: 0)
            if !right.isEmpty {
                Button { tap() } label: {
                    Text(right).font(pf(12.5)).foregroundColor(DDColor.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /* 一条服务通知：左边的图标按类型分（订单 / 发货 / 完成 / 评价 / 成团 / 售后） */
    private func noticeRow(_ n: DDNotice) -> some View {
        /* 2026-10-15 用户：「服务通知要可以左滑删除」——包一层左滑行，滑出「删除」 */
        DDSwipeRow(onTap: { onOrders() }, onDelete: { store.removeNotice(n.id) }) {
            noticeCard(n)
        }
    }

    private func noticeCard(_ n: DDNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(noticeColor(n.kind).opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: noticeIcon(n.kind))
                    .font(.system(size: 16))
                    .foregroundColor(noticeColor(n.kind))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(n.title).font(pf(14.5, .medium)).foregroundColor(DDColor.ink).lineLimit(2)
                Text(n.body).font(pf(12.5)).foregroundColor(DDColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeText(n.at)).font(pf(11.5)).foregroundColor(DDColor.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func noticeIcon(_ kind: String) -> String {
        switch kind {
        case "order":     return "doc.text.fill"
        case "group":     return "person.3.fill"
        case "ship":      return "shippingbox.fill"
        case "done":      return "checkmark.seal.fill"
        case "review":    return "star.fill"
        case "aftersale": return "arrow.uturn.backward.circle.fill"
        default:          return "bell.fill"
        }
    }

    private func noticeColor(_ kind: String) -> Color {
        switch kind {
        case "order":     return DDColor.red
        case "group":     return DDColor.redDeep
        case "ship":      return Color(hex: 0x2E6BFF)
        case "done":      return Color(hex: 0x1CA36B)
        case "review":    return DDColor.orange
        case "aftersale": return DDColor.weak
        default:          return DDColor.red
        }
    }

    /* 拼单消息那一行：用 onTapGesture 而不是再套一层 Button ——
       套 Button 会把里面那颗「邀好友拼单」吃掉（嵌套按钮点不动） */
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture { onOrders() }
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
    /// 支付方式 / 星言支付收银台
    @State private var showPayWayCart = false
    @State private var showXYPayCart = false

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
                        /* 京东购物车是按店铺分组的：一店一个表头，下面挂这个店的商品 */
                        ForEach(Array(store.cartGrouped().enumerated()), id: \.offset) { _, g in
                            shopHead(g.shop, g.lines)
                            ForEach(g.lines) { l in line(l) }
                        }
                        /* 失效商品（下架/删掉的）单独一块，能一键清空 */
                        if !store.invalidCart.isEmpty {
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
                                        .foregroundColor(DDColor.sub)
                                    Text(Tr("失效商品")).font(pf(13.5, .medium)).foregroundColor(DDColor.ink)
                                    Text(String(store.invalidCart.count) + Tr(" 件")).font(pf(12)).foregroundColor(DDColor.sub)
                                    Spacer(minLength: 0)
                                    Button { store.clearInvalidCart() } label: {
                                        Text(Tr("清空失效")).font(pf(12.5)).foregroundColor(DDColor.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12).frame(height: 40)
                                ForEach(store.invalidCart) { l in
                                    HStack(spacing: 10) {
                                        Text("📦").font(.system(size: 20))
                                            .frame(width: 46, height: 46)
                                            .background(DDColor.page)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Text(store.product(l.pid)?.title ?? Tr("商品已下架"))
                                            .font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Button { store.removeCartLine(l.pid) } label: {
                                            Text(Tr("移除")).font(pf(12.5)).foregroundColor(DDColor.sub)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12).frame(height: 60)
                                }
                            }
                            .background(DDColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, 10)
                        }
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        /* 左滑删除这一条（京东/微信购物车都能滑） */
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { store.removeCartLine(l.pid) } label: { Text(Tr("删除")) }
        }
    }

    /// 店铺表头（京东：一店一行，右边显示这店选了几件）
    private func shopHead(_ shop: String, _ ls: [DDCartLine]) -> some View {
        let n = ls.filter { checked.contains($0.pid) }.count
        return HStack(spacing: 8) {
            Image(systemName: "storefront").font(.system(size: 13)).foregroundColor(DDColor.ink)
            Text(shop).font(pf(13.5, .medium)).foregroundColor(DDColor.ink).lineLimit(1)
            Spacer(minLength: 0)
            Text(n > 0 ? (Tr("已选 ") + String(n) + Tr(" 件")) : Tr("未选"))
                .font(pf(11.5)).foregroundColor(DDColor.sub)
        }
        .padding(.horizontal, 14).frame(height: 34)
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
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text(Tr("合计 ") + "¥" + moneyFmt(total))
                        .font(pf(16, .semibold)).foregroundColor(DDColor.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 14)
                    /* 会员：下单时还会再减这一笔（place() 里按同一套算） */
                    if store.isVip {
                        Text(Tr("PLUS会员立减 ") + "-¥" + moneyFmt(store.vipOff(total)))
                            .font(pf(12.5)).foregroundColor(DDColor.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 14)
                    }
                    Spacer().frame(height: 8)
                    /* 支付方式（星言支付 / 微信支付）——京东结算页也有这一行 */
                    Button { showPayWayCart = true } label: {
                        HStack(spacing: 8) {
                            Text(Tr("支付方式")).font(pf(14)).foregroundColor(DDColor.ink)
                            Spacer(minLength: 0)
                            Text(store.payWay).font(pf(13.5)).foregroundColor(DDColor.sub)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DDColor.sub.opacity(0.55))
                        }
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(DDColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer().frame(height: 8)
                }
                .padding(.vertical, 10)
            }
            Button {
                payAll()
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
        .confirmationDialog(Tr("支付方式"), isPresented: $showPayWayCart, titleVisibility: .visible) {
            if XYPay.on { Button(XYPay.name) { store.payWay = XYPay.name } }
            Button(Tr("微信支付")) { store.payWay = "微信支付" }
        }
        .sheet(isPresented: $showXYPayCart) {
            XYPaySheet(amount: payableTotal, target: cartPayTitle, note: Tr("购物车结算"),
                       onSuccess: { realPayAll() })
                .environmentObject(app)
        }
        .ddLight()
    }

    private var cartPayTitle: String {
        let n = lines.filter { checked.contains($0.pid) }.count
        return n > 0 ? Tr("合并付款 ") + String(n) + Tr(" 件商品") : Tr("购物车结算")
    }

    /// 购物车这一次要付多少（含会员立减）
    private var payableTotal: Double {
        max(0, total - (store.isVip ? store.vipOff(total) : 0))
    }

    private func payAll() {
        if XYPay.on, store.payWay == XYPay.name {
            showXYPayCart = true
            return
        }
        realPayAll()
    }

    private func realPayAll() {
        let paid = (XYPay.on && store.payWay == XYPay.name)
        for l in lines where checked.contains(l.pid) {
            let o = store.place(pid: l.pid, count: l.count, group: false, fromCart: true)
            /* 星言支付 = 当场付掉（推进到待发货 + 「付款成功」通知） */
            if paid { store.pay(o.id) }
        }
        checked = []
        showPay = false
        app.show(paid ? Tr("支付成功") : Tr("下单成功，去「我的订单」看进度"))
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
    @State private var showMyReviews = false
    @State private var showAfterSales = false
    @State private var showCoupons = false
    @State private var showFollowed = false
    @State private var showService = false
    /// 会员中心（京东：我的页顶上那张金卡点进去）
    @State private var showVip = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                profileCard
                DDVipBanner { showVip = true }
                    .padding(.horizontal, 10)
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
        .sheet(isPresented: $showMyReviews) { DDMyReviewsView() }
        .sheet(isPresented: $showAfterSales) { DDAfterSaleListView() }
        .sheet(isPresented: $showCoupons) { DDCouponSheet(total: 0) { _ in } }
        .sheet(isPresented: $showFollowed) {
            DDShopFollowListView(onOpen: { p in
                showFollowed = false
                onOpen(p)
            })
        }
        .sheet(isPresented: $showService) { DDHelpCenterView().environmentObject(app) }
        .sheet(isPresented: $showVip) {
            DDVipPageView(onOpen: { p in
                showVip = false
                onOpen(p)
            })
            .environmentObject(app)
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
                Text(Tr(DDStore.groupOn ? "我的拼单" : "我的订单")).font(pf(11)).foregroundColor(DDColor.sub)
            }
        }
        .padding(14)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                /* 拼单关了就不再有「拼团中」（京东那种：待付款 / 待发货 / 待收货 / 已完成） */
                if DDStore.groupOn {
                    orderEntry("拼团中", "person.2.fill", store.orders.filter { $0.status == "grouping" }.count)
                } else {
                    orderEntry("待付款", "creditcard.fill", store.orders.filter { $0.status == "paying" }.count)
                }
                orderEntry("待发货", "shippingbox.fill", store.orders.filter { $0.status == "wait" }.count)
                orderEntry("待收货", "truck.box.fill", store.orders.filter { $0.status == "shipped" }.count)
                orderEntry("已完成", "checkmark.seal.fill", store.orders.filter { $0.status == "done" }.count)
            }
            .padding(.vertical, 14)
        }
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            HairLine(inset: 52)
            toolRow("我的评价", "star.bubble", Tr("\(store.reviews.count) 条")) { showMyReviews = true }
            HairLine(inset: 52)
            toolRow("退款/售后", "arrow.uturn.backward", Tr("\(store.afterSales.count) 单")) { showAfterSales = true }
            HairLine(inset: 52)
            toolRow("我的优惠券", "ticket", Tr("\(store.usableCoupons(99999).count) 张可用")) { showCoupons = true }
            HairLine(inset: 52)
            toolRow("关注的店铺", "heart.circle", Tr("\(store.followedShops.count) 家")) { showFollowed = true }
            HairLine(inset: 52)
            toolRow("联系客服", "bubble.left.and.bubble.right", "") { showService = true }
        }
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    /// 点了「看了又看 / 进店」换商品（商城那边把 sheet 的 item 换掉）
    private let onOpenOther: ((DDProduct) -> Void)?

    init(product: DDProduct, onCart: (() -> Void)? = nil, onOpenOther: ((DDProduct) -> Void)? = nil) {
        self.product = product
        self.onCart = onCart
        self.onOpenOther = onOpenOther
    }

    @State private var showOrder = false
    @State private var group = true
    /// 选中的规格（默认第一个；京东加购带规格）
    @State private var pickedSpec = ""
    @State private var showSpec = false
    @State private var showShare = false
    @State private var showService = false
    @State private var showShop = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    hero
                    priceCard
                    serviceRow
                    /* 拼单关了就不显示「正在拼单」那一块（后台 ui.json 写 mallGroup=1 会回来） */
                    if DDStore.groupOn { groupCard }
                    shopCard
                    DDReviewSection(product: product)
                    DDParamSection(product: product)
                    DDDetailLongSection(product: product)
                    sectionTitle(Tr("看了又看"))
                    recommendRow
                    Spacer().frame(height: 12)
                }
                .padding(.vertical, 10)
            }
            bottomBar
        }
        .background(DDColor.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showOrder) {
            DDOrderSheet(product: product, group: group, spec: pickedSpec)
                .environmentObject(app)
        }
        .sheet(isPresented: $showSpec) {
            DDSpecSheet(product: product) { v in pickedSpec = v.name }
                .ddLight()
        }
        .sheet(isPresented: $showShare) { DDShareSheet(product: product).environmentObject(app) }
        .sheet(isPresented: $showService) { DDHelpCenterView(product: product).environmentObject(app) }
        .sheet(isPresented: $showShop) {
            DDShopPageView(shop: product.shop, onOpen: { p in
                showShop = false
                onOpenOther?(p)
            })
        }
        .ddLight()
        /* 进详情页就把规格默认选第一个（京东加购带规格） */
        .onAppear { if pickedSpec.isEmpty { pickedSpec = product.specList.first?.name ?? "" } }
    }

    /// 服务承诺那一条（京东：7天无理由 / 运费险 …）
    private var serviceRow: some View {
        HStack(spacing: 14) {
            ForEach(product.serviceList.prefix(4), id: \.self) { s in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11)).foregroundColor(DDColor.red)
                    Text(s).font(pf(11.5)).foregroundColor(DDColor.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func sectionTitle(_ t: String) -> some View {
        HStack {
            Text(t).font(pf(15, .semibold)).foregroundColor(DDColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 4)
    }

    /// 看了又看（同店铺/同类目随便挑几个）
    private var recommendRow: some View {
        let others = store.live.filter { $0.id != product.id && ($0.cate == product.cate || $0.shop == product.shop) }.prefix(6)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(others)) { p in
                    Button { onOpenOther?(p) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            DDThumb(em: p.em, size: 104, radius: 10, img: p.img)
                            DDPrice(value: p.price, size: 15)
                            Text(p.title).font(pf(11.5)).foregroundColor(DDColor.sub)
                                .lineLimit(2).frame(width: 104, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
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
            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17))
                    .foregroundColor(DDColor.ink)
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
                if DDStore.groupOn {
                    Text(Tr("单独购买 ¥") + moneyFmt(product.orig))
                        .font(pf(12)).foregroundColor(DDColor.sub).strikethrough()
                } else {
                    /* 不拼单就只有这一个价（京东那样），划线价留着做对比 */
                    Text("¥" + moneyFmt(product.orig))
                        .font(pf(12)).foregroundColor(DDColor.sub).strikethrough()
                }
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                /* 京东那三颗：进店 / 关注 / 客服 */
                Button { showShop = true } label: {
                    Text(Tr("进店")).font(pf(12.5)).foregroundColor(DDColor.ink)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(DDColor.page))
                }
                .buttonStyle(.plain)
                Button { store.toggleFollow(product.shopKey) } label: {
                    Text(store.isFollowed(product.shopKey) ? Tr("已关注") : Tr("关注"))
                        .font(pf(12.5)).foregroundColor(store.isFollowed(product.shopKey) ? DDColor.sub : DDColor.red)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().stroke(store.isFollowed(product.shopKey) ? DDColor.sub.opacity(0.4) : DDColor.red, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { showService = true } label: {
                    Text(Tr("客服")).font(pf(12.5)).foregroundColor(DDColor.ink)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(DDColor.page))
                }
                .buttonStyle(.plain)
            }
            HairLine()
            Text(Tr("商品介绍")).font(pf(14, .semibold)).foregroundColor(DDColor.ink)
            Text(product.title + Tr(DDStore.groupOn
                                    ? "。产地直发、坏果包赔、退货包运费，拼单更便宜。"
                                    : "。产地直发、坏果包赔、退货包运费，48 小时内发货。"))
                .font(pf(13.5)).foregroundColor(DDColor.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                if DDStore.groupOn {
                    /* 拼单开着：单独购买 / 发起拼单 两颗（原来的样子） */
                    Button {
                        group = false
                        showOrder = true
                    } label: {
                        buyButton(Tr("单独购买"), "¥" + moneyFmt(product.orig), Color(hex: 0xFF8B3D))
                    }
                    .buttonStyle(.plain)
                    Button {
                        group = true
                        showOrder = true
                    } label: {
                        buyButton(Tr("发起拼单"), "¥" + moneyFmt(product.price), nil)
                    }
                    .buttonStyle(.plain)
                } else {
                    /* 拼单关着：京东那种「加入购物车 / 立即购买」 */
                    Button { justAddToCart() } label: {
                        buyButton(Tr("加入购物车"), "", Color(hex: 0xFF8B3D))
                    }
                    .buttonStyle(.plain)
                    Button {
                        group = false
                        showOrder = true
                    } label: {
                        buyButton(Tr("立即购买"), "¥" + moneyFmt(product.price), nil)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            .padding(.bottom, max(8, L.safeBottom))
        }
        .background(DDColor.card)
    }

    /// 底部那颗大按钮（拼单开着/关着都用它画，样式统一）
    private func buyButton(_ title: String, _ price: String, _ solid: Color?) -> some View {
        VStack(spacing: 1) {
            Text(title).font(pf(15, .medium))
            if !price.isEmpty { Text(price).font(pf(11.5)) }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity).frame(height: 44)
        .background {
            if let solid { RoundedRectangle(cornerRadius: 22).fill(solid) }
            else { RoundedRectangle(cornerRadius: 22).fill(DDColor.gradBtn) }
        }
    }

    /// 只加购物车：不跳页、不关详情（京东那颗「加入购物车」就是这样）
    private func justAddToCart() {
        if !pickedSpec.isEmpty { store.setCartSpec(product.id, pickedSpec) }
        store.addCart(product.id)
        app.show(Tr("已加入购物车"))
    }

    /// 加入购物车：提示一下 → 关掉详情页 → **自动跳到「购物车」那个 tab**
    /// （用户报的「购物车不会自动跳转到购物车」就是这里）
    private func addToCart() {
        if !pickedSpec.isEmpty { store.setCartSpec(product.id, pickedSpec) }
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
    /// 下单用哪个规格（商品详情页选好传进来）
    private let spec: String
    @State private var group: Bool
    @State private var count = 1
    /// 这次下单用哪条地址（空 = 用默认那条）
    @State private var pickedAddrId = ""
    @State private var showAddrList = false
    /// 优惠券 / 备注 / 发票（对齐京东结算页）
    @State private var couponOff: Double = 0
    @State private var couponTitle = ""
    @State private var showCoupon = false
    @State private var remark = ""
    @State private var invoice = ""
    @State private var showInvoice = false
    /// 会员中心（结算页点「PLUS会员」那行进）
    @State private var showVip = false
    /// 支付方式选择 / 星言支付收银台
    @State private var showPayWay = false
    @State private var showXYPay = false

    init(product: DDProduct, group: Bool, spec: String = "") {
        self.product = product
        self.spec = spec
        _group = State(initialValue: group)
    }

    /// 单价：拼单关着就只有一个价（product.price）
    private var unit: Double { (DDStore.groupOn && !group) ? product.orig : product.price }
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    /* 拼单开着才选方式；关着就直接按这个价买（京东那样） */
                    if DDStore.groupOn {
                        VStack(spacing: 0) {
                            pick(Tr("发起拼单") + "（\(product.grp)人团）", Tr("按拼单价，人满发货"), true)
                            HairLine(inset: 14)
                            pick(Tr("单独购买"), Tr("按单买价，不用等人"), false)
                        }
                        .background(DDColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    /* 优惠券 / 发票 / 备注 / 配送 / 支付方式（京东结算页那几行） */
                    VStack(spacing: 0) {
                        payRow(Tr("优惠券"), couponOff > 0 ? ("-¥" + moneyFmt(couponOff)) : Tr("不使用"), red: couponOff > 0) {
                            showCoupon = true
                        }
                        HairLine(inset: 14)
                        /* 会员立减（京东 PLUS 那行）：开着就减，没开就提示开通 */
                        payRow(Tr("PLUS会员"),
                               memberOff > 0
                                 ? ("-¥" + moneyFmt(memberOff))
                                 : (DDStore.groupOn ? Tr("未开通") : Tr("未开通 · 立省 ¥" + moneyFmt(wouldSave))),
                               red: memberOff > 0) { showVip = true }
                        HairLine(inset: 14)
                        payRow(Tr("发票"), invoice.isEmpty ? Tr("不开发票") : invoice, red: false) { showInvoice = true }
                        HairLine(inset: 14)
                        payRow(Tr("配送"), Tr("快递 · 包邮"), red: false) { }
                        HairLine(inset: 14)
                        payRow(Tr("支付方式"), store.payWay, red: false) { showPayWay = true }
                    }
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 10) {
                        Text(Tr("备注")).font(pf(14)).foregroundColor(DDColor.ink)
                        TextField(Tr("给商家留言（可不填）"), text: $remark)
                            .font(pf(13.5))
                    }
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack {
                        Text(Tr("合计")).font(pf(14)).foregroundColor(DDColor.sub)
                        Spacer(minLength: 0)
                        DDPrice(value: payable, size: 20)
                    }
                    .padding(.horizontal, 4)
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            Button { submit() } label: {
                Text((DDStore.groupOn && group) ? Tr("发起拼单") : Tr("立即支付"))
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
        .sheet(isPresented: $showCoupon) {
            DDCouponSheet(total: payable) { c in
                couponOff = c?.off ?? 0
                couponTitle = c?.title ?? ""
                if let c = c { store.useCoupon(c.id) }
            }
        }
        .sheet(isPresented: $showInvoice) {
            DDInvoiceSheet(title: $invoice).ddLight()
        }
        .sheet(isPresented: $showVip) {
            DDVipPageView().environmentObject(app)
        }
        /* 支付方式：星言支付 / 微信支付（示范的两条；名字走后台 payName） */
        .confirmationDialog(Tr("支付方式"), isPresented: $showPayWay, titleVisibility: .visible) {
            if XYPay.on { Button(XYPay.name) { store.payWay = XYPay.name } }
            Button(Tr("微信支付")) { store.payWay = "微信支付" }
        }
        /* 星言支付收银台：验过（指纹/面容 或 支付密码）才真下单 */
        .sheet(isPresented: $showXYPay) {
            XYPaySheet(amount: payable, target: product.title,
                       note: (DDStore.groupOn && group ? Tr("发起拼单") : Tr("立即购买")) + " ×" + String(count),
                       onSuccess: { doSubmit() })
                .environmentObject(app)
        }
        .ddLight()
    }

    /// 这一单的商品金额（不含优惠）
    private var goodsAmount: Double {
        let u = product.specList.first { $0.name == spec }?.price ?? unit
        return u * Double(count)
    }

    /// 会员立减（不是会员 = 0）
    private var memberOff: Double { store.vipOff(goodsAmount) }
    /// 不是会员的话，开通能省这么多（结算页那行提示用）
    private var wouldSave: Double { (goodsAmount * (1 - DDStore.vipRate) * 100).rounded() / 100 }

    /// 应付 = 单价×数量 − 优惠券 − 会员立减（运费包邮，先都按 0）
    private var payable: Double {
        max(0, goodsAmount - couponOff - memberOff)
    }

    private func payRow(_ l: String, _ r: String, red: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack {
                Text(l).font(pf(14)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(r).font(pf(13.5)).foregroundColor(red ? DDColor.red : DDColor.sub)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DDColor.sub.opacity(0.55))
            }
            .padding(.horizontal, 14).frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        /* 选了星言支付：先走收银台（指纹/面容 或 支付密码），验过了才真下单 */
        if XYPay.on, store.payWay == XYPay.name {
            showXYPay = true
            return
        }
        doSubmit()
    }

    /// 真正下单（星言支付验过之后也走这里）
    private func doSubmit() {
        /* 拼单关着：不管从哪儿进来都按「直接买」下单 */
        let o = store.place(pid: product.id, count: count, group: DDStore.groupOn && group, spec: spec,
                            address: chosenAddr, remark: remark.trimmingCharacters(in: .whitespaces),
                            freight: 0, couponOff: couponOff, invoice: invoice, memberOff: memberOff,
                            payWay: store.payWay, paying: true)
        /* 星言支付 = 当场付掉，直接推到「待发货」+ 一条「付款成功」服务通知 */
        if XYPay.on, store.payWay == XYPay.name { store.pay(o.id) }
        dismiss()
        app.show(doneText)
    }

    private var doneText: String {
        (XYPay.on && store.payWay == XYPay.name) ? Tr("支付成功") : Tr("订单已提交，去付款")
    }
}

/* ---------------------------------------------------------- 我的订单 */

struct DDOrdersView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    @State private var filter = 0
    /// 点订单卡进详情（京东那套）
    @State private var detailOrder: DDOrder?
    /// 待付款订单「立即付款」走不走星言支付收银台
    @State private var payWithXY: DDOrder? = nil

    /// 拼单关了就把「拼团中」换成「待付款」（京东那排）
    private var names: [String] {
        DDStore.groupOn ? ["全部", "拼团中", "待发货", "待收货", "已完成"]
                        : ["全部", "待付款", "待发货", "待收货", "已完成"]
    }

    private var list: [DDOrder] {
        switch filter {
        case 1: return store.orders.filter { DDStore.groupOn ? $0.status == "grouping" : $0.status == "paying" }
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
        .sheet(item: $detailOrder) { o in
            DDOrderDetailView(orderId: o.id).environmentObject(app)
        }
        /* 星言支付收银台（待付款那一单） */
        .sheet(item: $payWithXY) { o in
            XYPaySheet(amount: o.total, target: o.title,
                       note: Tr("订单付款 · ") + o.statusText,
                       onSuccess: {
                           store.pay(o.id)
                           app.show(Tr("支付成功"))
                       })
                .environmentObject(app)
        }
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
            if o.canPay {
                Text(Tr("还剩 ") + String(format: "%02d:%02d", o.payLeft / 60, o.payLeft % 60) + Tr(" 未付款"))
                    .font(pf(11.5)).foregroundColor(DDColor.red)
            }
            HStack(alignment: .top, spacing: 10) {
                DDThumb(em: o.em, size: 62, radius: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(o.title).font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                    if o.group, DDStore.groupOn {
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
                    if o.canPay {
                        Button { store.cancelOrder(o.id) } label: { smallBtn(Tr("取消订单"), false) }
                            .buttonStyle(.plain)
                        Button { payOrder(o) } label: { smallBtn(Tr("立即付款"), true) }
                            .buttonStyle(.plain)
                    }
                if o.status == "grouping", DDStore.groupOn {
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
                    if o.status == "done" && !o.reviewed {
                        Button { store.reorder(o); app.show(Tr("已加入购物车")) } label: { smallBtn(Tr("再来一单"), false) }
                            .buttonStyle(.plain)
                    }
                    Button { store.removeOrder(o.id) } label: { smallBtn(Tr("删除"), false) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        /* 点卡片任意位置 → 订单详情（里面那颗小按钮仍然能点，Button 优先） */
        .contentShape(Rectangle())
        .onTapGesture { detailOrder = o }
    }

    private func smallBtn(_ t: String, _ filled: Bool) -> some View {
        Text(t)
            .font(pf(12.5))
            .foregroundColor(filled ? .white : DDColor.ink)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(filled ? DDColor.red : DDColor.page))
    }

    /// 付这一单：选了星言支付就先过收银台（指纹/面容 或 支付密码）
    private func payOrder(_ o: DDOrder) {
        if XYPay.on, store.payWay == XYPay.name {
            payWithXY = o
            return
        }
        store.pay(o.id)
        app.show(Tr("支付成功"))
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
    /// 排序："" 综合 / "sales" 销量 / "priceUp" 价格升序 / "priceDown" 价格降序
    @State private var sort = ""
    /// 只看有货（至少一个规格还有库存）
    @State private var onlyStock = false

    private var kw: String { q.trimmingCharacters(in: .whitespaces) }

    /* 热搜榜：词全是从**真商品**里数出来的（分类 / 标签 / 店铺），按"有几件商品"排，
       谁的商品多谁靠前 —— 不编关键词（以前那 6 个是写死的）。 */
    private var hot: [String] {
        var score: [String: Int] = [:]
        for p in store.live {
            for k in ([p.cate, p.shop] + p.tags) where !k.isEmpty {
                score[k, default: 0] += 1
            }
        }
        return score.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(10).map { $0.key }
    }

    /// 联想词：打了几个字 → 从分类 / 标签 / 店铺 / 标题里挑含它的（最多 6 条）
    private var suggest: [String] {
        let k = kw
        guard !k.isEmpty else { return [] }
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, t != k, !out.contains(t), out.count < 6 { out.append(t) }
        }
        for p in store.live where p.cate.localizedCaseInsensitiveContains(k) { add(p.cate) }
        for p in store.live {
            for t in p.tags where t.localizedCaseInsensitiveContains(k) { add(t) }
        }
        for p in store.live where p.shop.localizedCaseInsensitiveContains(k) { add(p.shop) }
        for p in store.live where p.title.localizedCaseInsensitiveContains(k) { add(p.title) }
        return out
    }

    /// 结果：先按词筛，再「只看有货」，最后排序
    private var result: [DDProduct] {
        var list = store.search(kw)
        if onlyStock { list = list.filter { $0.inStock } }
        switch sort {
        case "sales":     list.sort { $0.salesNum > $1.salesNum }
        case "priceUp":   list.sort { $0.price < $1.price }
        case "priceDown": list.sort { $0.price > $1.price }
        default: break
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if kw.isEmpty { idle } else { found }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }

    private var searchBar: some View {
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
                        .onSubmit { store.pushHistory(kw) }
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
    }

    /// 还没打字：搜索历史 + 热搜榜
    private var idle: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if !store.history.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
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
                }
                DDSearchHotBoard(words: hot) { w in pick(w) }
                Spacer().frame(height: 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(DDColor.page)
    }

    /// 打了字：联想词 + 排序筛选条 + 结果
    private var found: some View {
        VStack(spacing: 0) {
            if !suggest.isEmpty {
                DDSuggestList(words: suggest) { w in pick(w) }
            }
            DDSearchFilterBar(sort: sort, onlyStock: onlyStock,
                              onSort: { sort = $0 },
                              onStock: { onlyStock.toggle() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(result) { p in
                        Button {
                            store.pushHistory(kw)
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

    /// 点了热搜 / 联想词：填进输入框 + 记一条历史
    private func pick(_ w: String) {
        q = w
        store.pushHistory(w)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }
}

/* ---------------------------------------------------------- 公共小条 */

/// 商城里的「左滑删除」行（消息 tab 的服务通知用）
/// ⚠ 和会话列表**同一套**手势层（ChatsView 的 RowSwipeCatcher）：
///    SwiftUI 的 DragGesture 在 iOS 26 SDK 下会把 ScrollView 的竖滑吃掉（踩过），
///    UIKit 的 pan 能声明「和滚动同时识别」，竖向照常滚，横向才算左滑。
struct DDSwipeRow<Content: View>: View {
    var onTap: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dx: CGFloat = 0
    @State private var start: CGFloat = 0
    private var actW: CGFloat { UIConfig.num("mallSwipeW", 84) }

    var body: some View {
        ZStack(alignment: .trailing) {
            content()
                .offset(x: dx)
            Button { onDelete() } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash.fill").font(.system(size: 16))
                    Text(Tr("删除")).font(pf(12))
                }
                .foregroundColor(.white)
                .frame(width: actW)
                .frame(maxHeight: .infinity)
                .background(DDColor.red)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(dx < -4 ? 1 : 0)
            .allowsHitTesting(dx <= -actW * 0.55)
        }
        .padding(.horizontal, 10)
        /* 手势层盖在内容上（宽度跟着滑开量收，露出来的删除键才点得到） */
        .overlay(alignment: .leading) {
            RowSwipeCatcher(
                onTap: { _ in
                    if dx != 0 { close() } else { onTap() }
                },
                onBegan: { start = dx },
                onChanged: { v in
                    var x = min(0, start + v)                       // 只能往左
                    if x < -actW { x = -(actW + min(26, (-x - actW) * 0.25)) }   // 拉过头有一点阻尼
                    dx = x
                },
                onEnded: { _, vx in
                    let open = vx <= -260 || (-dx > actW * 0.45 && vx < 260)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dx = open ? -actW : 0
                    }
                }
            )
            .frame(width: max(0, L.width - 20 + dx))
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { dx = 0 }
    }
}

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
