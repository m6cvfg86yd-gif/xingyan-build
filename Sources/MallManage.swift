import SwiftUI

/* ============================================================
   拼多多商城的**后台**（放在 App「管理」页里）—— 2026-10-12 用户要求
   「拼多多商城后台给管理（可以上架的 / 换轮播图的）」「商城要的逻辑都要」。

   管理这一页能做的，和商城那一页一一对应：
     · 轮播图：换图 / 加一张 / 删一张（首屏最上面那块就是它）
     · 商品：上架（新增）/ 下架（关掉开关）/ 改价改名字改分类 / 删除
     · 商品图：可以用 emoji 顶，也可以从相册传一张真图（传上去存服务器）

   数据真源都在服务器 data/mall.json（GET /api/mall 读，POST /api/ops/mall 写），
   所以改完**用户那边重开商城就是新的**，不用重新出包。
   ============================================================ */

struct MallAdminSection: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = DDStore.shared

    @State private var editing: DDProduct? = nil
    @State private var adding = false
    @State private var bannerPick = -1        // 正在换第几张轮播图（-1 = 没在换）
    @State private var bannerAdd = false
    @State private var busy = ""

    var body: some View {
        VStack(spacing: 10) {
            nameCard
            bannerCard
            productCard
        }
        .task { await store.refresh() }
        .sheet(item: $editing) { p in
            MallProductSheet(product: p).environmentObject(app)
        }
        .sheet(isPresented: $adding) {
            MallProductSheet(product: nil).environmentObject(app)
        }
        /* 换某一张轮播图：从相册选一张 → 上传 → 存到那一格 */
        .sheet(isPresented: Binding(get: { bannerPick >= 0 },
                                    set: { if !$0 { bannerPick = -1 } })) {
            PhotoPicker { img in
                let idx = bannerPick
                bannerPick = -1
                Task { await setBanner(idx, img) }
            }
        }
        .sheet(isPresented: $bannerAdd) {
            PhotoPicker { img in
                bannerAdd = false
                Task { await setBanner(-1, img) }
            }
        }
    }

    /* ---------------- 商城名 / 标语 ---------------- */

    @State private var nameDraft = ""
    @State private var sloganDraft = ""
    @State private var nameLoaded = false

    private var nameCard: some View {
        VStack(spacing: 0) {
            row(Tr("商城名 / 标语（商城顶栏那两行）"), Tr("改完用户那边重开商城就是新的"))
            HairLine(inset: 16)
            TextField(Tr("商城名（比如 星言商城）"), text: $nameDraft)
                .font(pf(15))
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(C.fieldBg))
                .padding(.horizontal, 16).padding(.top, 10)
            TextField(Tr("标语（比如 拼着买 才便宜）"), text: $sloganDraft)
                .font(pf(15))
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(C.fieldBg))
                .padding(.horizontal, 16).padding(.top, 8)
            Button { Task { await saveName() } } label: {
                Text(Tr("保存商城名"))
                    .font(pf(15, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 21).fill(C.green))
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .padding(.top, 10).padding(.bottom, 12)
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if !nameLoaded { nameDraft = store.mallName; sloganDraft = store.mallSlogan; nameLoaded = true }
        }
        .onChange(of: store.mallName) { v in if !nameLoaded { nameDraft = v } }
    }

    private func saveName() async {
        let n = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { app.show(Tr("商城名不能空")); return }
        await store.opsSetName(n, sloganDraft.trimmingCharacters(in: .whitespaces))
        busy = Tr("商城名已保存")
        app.show(Tr("商城名已保存"))
    }

    /* ---------------- 轮播图 ---------------- */

    private var bannerCard: some View {
        VStack(spacing: 0) {
            row(Tr("轮播图（商城首屏最上面那块）"), Tr("点「换图」从相册挑一张"))
            HairLine(inset: 16)
            if store.banners.isEmpty {
                hint(Tr("还没有轮播图，下面点「加一张轮播图」"))
            } else {
                ForEach(Array(store.banners.enumerated()), id: \.offset) { i, url in
                    if i > 0 { HairLine(inset: 16) }
                    HStack(spacing: 12) {
                        RemoteImage(path: url, icon: "photo")
                            .frame(width: 96, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(Tr("第 ") + String(i + 1) + Tr(" 张"))
                            .font(pf(14)).foregroundColor(C.label)
                        Spacer(minLength: 0)
                        Button { bannerPick = i } label: { pill(Tr("换图"), C.green) }
                            .buttonStyle(.plain)
                        Button { Task { await removeBanner(i) } } label: {
                            pill(Tr("删除"), C.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).frame(height: 70)
                }
            }
            HairLine(inset: 16)
            Button { bannerAdd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundColor(C.green)
                    Text(Tr("加一张轮播图")).font(pf(15.5)).foregroundColor(C.label)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /* ---------------- 商品 ---------------- */

    private var productCard: some View {
        VStack(spacing: 0) {
            row(Tr("商品（上架 / 下架 / 改价 / 删除）"),
                Tr("上架中的 ") + String(store.live.count) + Tr(" 件 · 共 ")
                    + String(store.products.count) + Tr(" 件"))
            if store.products.isEmpty {
                hint(Tr("还没有商品，下面点「上架一件新商品」"))
            } else {
                ForEach(Array(store.products.enumerated()), id: \.element.id) { i, p in
                    HairLine(inset: 16)
                    HStack(spacing: 12) {
                        DDThumb(em: p.em, size: 48, radius: 8, img: p.img)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(pf(14)).foregroundColor(C.label).lineLimit(2)
                            Text("¥" + moneyFmt(p.price) + "　" + Tr("单买 ¥") + moneyFmt(p.orig)
                                 + "　" + p.cate)
                                .font(pf(11.5)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 6) {
                            Toggle("", isOn: Binding(
                                get: { p.live },
                                set: { v in Task { await setOn(p, v) } }))
                                .labelsHidden().tint(C.green)
                                .scaleEffect(0.82)
                            Button { editing = p } label: { pill(Tr("编辑"), C.green) }
                                .buttonStyle(.plain)
                        }
                        Button { Task { await remove(p) } } label: {
                            pill(Tr("删除"), C.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            HairLine(inset: 16)
            Button { adding = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundColor(C.green)
                    Text(Tr("上架一件新商品")).font(pf(15.5)).foregroundColor(C.label)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !busy.isEmpty {
                Text(busy).font(pf(12)).foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /* ---------------- 小零件 ---------------- */

    private func row(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Text(sub).font(pf(12)).foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(pf(13)).foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t).font(pf(12.5)).foregroundColor(c)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(c.opacity(0.12)))
    }

    /* ---------------- 动作 ---------------- */

    private func setBanner(_ idx: Int, _ img: UIImage) async {
        busy = Tr("正在上传图片…")
        guard let url = try? await API.shared.upload(image: img) else {
            busy = Tr("图片上传失败")
            return
        }
        var list = store.banners
        if idx >= 0 && idx < list.count { list[idx] = url } else { list.append(url) }
        await store.opsBanners(list)
        busy = Tr("轮播图已更新")
        app.show(Tr("轮播图已更新"))
    }

    private func removeBanner(_ idx: Int) async {
        var list = store.banners
        guard idx < list.count else { return }
        list.remove(at: idx)
        await store.opsBanners(list)
        busy = Tr("已删掉一张轮播图")
    }

    private func setOn(_ p: DDProduct, _ on: Bool) async {
        var np = p
        np.on = on
        await store.opsSave(np)
        busy = on ? (Tr("已上架：") + p.title) : (Tr("已下架：") + p.title)
    }

    private func remove(_ p: DDProduct) async {
        await store.opsRemove(p.id)
        busy = Tr("已删除：") + p.title
    }
}

/* ---------------------------------------------------------- 上架 / 编辑一件商品 */

struct MallProductSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    /// nil = 上架一件新的
    let product: DDProduct?

    @State private var em = "📦"
    @State private var img = ""
    @State private var title = ""
    @State private var price = ""
    @State private var orig = ""
    @State private var cate = ""
    @State private var shop = ""
    @State private var tags = ""
    @State private var grp = "2"
    @State private var sold = "0"
    @State private var on = true
    @State private var showPick = false
    @State private var saving = false

    private var editing: Bool { product != nil }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: editing ? Tr("编辑商品") : Tr("上架一件新商品"))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        DDThumb(em: em, size: 72, radius: 10, img: img)
                        VStack(alignment: .leading, spacing: 8) {
                            Button { showPick = true } label: {
                                Text(Tr("从相册选一张商品图"))
                                    .font(pf(14)).foregroundColor(C.green)
                            }
                            .buttonStyle(.plain)
                            if !img.isEmpty {
                                Button { img = "" } label: {
                                    Text(Tr("去掉图片（用 emoji）"))
                                        .font(pf(13)).foregroundColor(C.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(Tr("不传图也行，用下面的 emoji 顶"))
                                .font(pf(11.5)).foregroundColor(C.subLabel)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    fld(Tr("图标 emoji（比如 📦）"), $em)
                    fld(Tr("商品名字"), $title)
                    fld(Tr("拼单价（元）"), $price, num: true)
                    fld(Tr("单独购买价（元）"), $orig, num: true)
                    fld(Tr("分类（数码 / 服饰 / 食品…）"), $cate)
                    fld(Tr("店铺名"), $shop)
                    fld(Tr("标签，逗号隔开（百亿补贴,包邮）"), $tags)
                    fld(Tr("几人团（2~9）"), $grp, num: true)
                    fld(Tr("已拼人数（填 10万+ 这种也行）"), $sold)

                    HStack(spacing: 12) {
                        Text(Tr("上架")).font(pf(15.5)).foregroundColor(C.label)
                        Spacer(minLength: 0)
                        Toggle("", isOn: $on).labelsHidden().tint(C.green)
                    }
                    .padding(.horizontal, 16).frame(height: 56)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            Button { Task { await save() } } label: {
                Text(saving ? Tr("正在保存…") : (editing ? Tr("保存") : Tr("上架")))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23)
                        .fill(saving ? C.subLabel : Color(hex: 0xE02A0F)))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .padding(.top, 6)
            .padding(.bottom, max(10, L.safeBottom))
        }
        .background(C.pageBg.ignoresSafeArea())
        .ddLight()
        .onAppear { fill() }
        .sheet(isPresented: $showPick) {
            PhotoPicker { image in
                Task {
                    if let url = try? await API.shared.upload(image: image) {
                        img = url
                        app.show(Tr("图片已上传"))
                    }
                }
            }
        }
    }

    private func fld(_ ph: String, _ text: Binding<String>, num: Bool = false) -> some View {
        TextField(ph, text: text)
            .font(pf(15))
            .keyboardType(num ? .decimalPad : .default)
            .padding(.horizontal, 14).frame(height: 52)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fill() {
        guard let p = product else { return }
        em = p.em
        img = p.img ?? ""
        title = p.title
        price = moneyFmt(p.price)
        orig = moneyFmt(p.orig)
        cate = p.cate
        shop = p.shop
        tags = p.tags.joined(separator: ",")
        grp = String(p.grp)
        sold = p.sold
        on = p.live
    }

    private func save() async {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { app.show(Tr("商品名字不能空")); return }
        saving = true
        let p = DDProduct(id: product?.id ?? "",
                          em: em.trimmingCharacters(in: .whitespaces).isEmpty ? "📦"
                              : em.trimmingCharacters(in: .whitespaces),
                          img: img.isEmpty ? nil : img,
                          title: name,
                          price: Double(price) ?? 0,
                          orig: Double(orig) ?? 0,
                          sold: sold.trimmingCharacters(in: .whitespaces).isEmpty ? "0" : sold,
                          grp: max(2, min(9, Int(grp) ?? 2)),
                          tags: tags.split(separator: ",")
                                  .map { $0.trimmingCharacters(in: .whitespaces) }
                                  .filter { !$0.isEmpty },
                          shop: shop.trimmingCharacters(in: .whitespaces),
                          cate: cate.trimmingCharacters(in: .whitespaces).isEmpty ? "其它"
                                : cate.trimmingCharacters(in: .whitespaces),
                          on: on)
        await store.opsSave(p)
        saving = false
        dismiss()
        app.show(editing ? Tr("商品已保存") : Tr("已上架"))
    }
}
