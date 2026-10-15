import SwiftUI

/* ============================================================
   收货地址簿（2026-10-14 用户：「收货地址啥的单独开个页面存储，学京东逻辑」）

   京东那套：
     · 「我的 → 收货地址」进一个**独立的地址列表页**：一条地址一行卡片，
       姓名 + 手机号 + 省市区详细地址，默认那条有「默认」小标签
     · 每行右边一支铅笔 → 编辑；编辑页里能删
     · 底部固定一颗「新增收货地址」
     · 下单页顶部显示默认地址，点一下进同一个列表页**挑一条**，选完自动回下单页
   数据存在 DDStore 的地址簿里（跟购物车/收藏一样落本机 dd_mall.json）。
   ============================================================ */

struct DDAddress: Identifiable, Codable, Hashable {
    var id: String
    /// 收货人
    var name: String
    var phone: String
    /// 省市区
    var region: String
    /// 详细地址（街道门牌）
    var detail: String
    var isDefault: Bool

    /// 一行里显示的那串字：省市区 + 详细地址
    var full: String { region + detail }
    /// 信息齐全没（老数据迁移上来可能只有地址）
    var complete: Bool { !name.isEmpty && phone.count >= 6 && (!region.isEmpty || !detail.isEmpty) }
}

/* ---------------------------------------------------------- 地址列表 */

struct DDAddressListView: View {
    @ObservedObject private var store = DDStore.shared
    @Environment(\.dismiss) private var dismiss

    /// 下单页进来时传：点一行就选中它、回上一页（不传就是纯管理）
    private let pick: ((DDAddress) -> Void)?

    /* 显式 init：这个页面在**别的文件**里用（我的 → 收货地址 / 下单页挑地址） */
    init(pick: ((DDAddress) -> Void)? = nil) { self.pick = pick }

    @State private var editing: DDAddress? = nil
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("收货地址"))
            if store.addresses.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(DDColor.sub.opacity(0.7))
                    Text(Tr("还没有收货地址")).font(pf(15)).foregroundColor(DDColor.sub)
                    Text(Tr("加一条，下单时就不用再填了")).font(pf(12.5)).foregroundColor(DDColor.sub.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(store.addresses) { a in
                            card(a)
                        }
                    }
                    .padding(10)
                }
            }
            Button { adding = true } label: {
                Text(Tr("新增收货地址"))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23).fill(DDColor.gradBtn))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.bottom, max(10, L.safeBottom * 0.6))
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
        .sheet(isPresented: $adding) {
            DDAddressEditView(address: nil).ddLight()
        }
        .sheet(item: $editing) { a in
            DDAddressEditView(address: a).ddLight()
        }
    }

    private func card(_ a: DDAddress) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(a.name.isEmpty ? Tr("未填收货人") : a.name)
                        .font(pf(15.5, .medium)).foregroundColor(DDColor.ink)
                    if !a.phone.isEmpty {
                        Text(a.phone).font(pf(13.5)).foregroundColor(DDColor.sub)
                    }
                    if a.isDefault {
                        Text(Tr("默认"))
                            .font(pf(10.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background(RoundedRectangle(cornerRadius: 3).fill(DDColor.red))
                    }
                }
                Text(a.full.isEmpty ? Tr("还没填详细地址") : a.full)
                    .font(pf(13.5)).foregroundColor(DDColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !a.complete {
                    Text(Tr("这条还没填全，点右边铅笔补一下"))
                        .font(pf(11.5)).foregroundColor(DDColor.red)
                }
            }
            Spacer(minLength: 0)
            Button { editing = a } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17))
                    .foregroundColor(DDColor.sub)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let p = pick {
                p(a)
                dismiss()
            } else {
                editing = a
            }
        }
    }
}

/* ---------------------------------------------------------- 新增 / 编辑 */

struct DDAddressEditView: View {
    @ObservedObject private var store = DDStore.shared
    @Environment(\.dismiss) private var dismiss

    /// nil = 新增
    private let address: DDAddress?

    init(address: DDAddress?) { self.address = address }

    @State private var name = ""
    @State private var phone = ""
    @State private var region = ""
    @State private var detail = ""
    @State private var isDefault = false
    @FocusState private var focus: Int?

    private var isNew: Bool { address == nil }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: isNew ? Tr("新增收货地址") : Tr("编辑收货地址"))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    VStack(spacing: 0) {
                        field(Tr("收货人"), $name, 0, keyboard: .default)
                        HairLine(inset: 14)
                        field(Tr("手机号"), $phone, 1, keyboard: .numberPad)
                        HairLine(inset: 14)
                        field(Tr("所在地区（省 市 区）"), $region, 2, keyboard: .default)
                        HairLine(inset: 14)
                        field(Tr("详细地址（街道 门牌）"), $detail, 3, keyboard: .default)
                    }
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Tr("设为默认地址")).font(pf(15)).foregroundColor(DDColor.ink)
                            Text(Tr("下单时优先用这一条")).font(pf(12)).foregroundColor(DDColor.sub)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: $isDefault)
                            .labelsHidden()
                            .tint(DDColor.red)
                    }
                    .padding(14)
                    .background(DDColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !isNew {
                        Button {
                            if let a = address { store.removeAddress(a.id) }
                            dismiss()
                        } label: {
                            Text(Tr("删除这条地址"))
                                .font(pf(15)).foregroundColor(Color(hex: 0xFA5151))
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 14).fill(DDColor.card))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer().frame(height: 10)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            Button { save() } label: {
                Text(Tr("保存"))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23).fill(canSave ? DDColor.gradBtn : LinearGradient(
                        colors: [Color(hex: 0xF0C9BE), Color(hex: 0xE7B7AA)],
                        startPoint: .leading, endPoint: .trailing)))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.top, 6)
            .padding(.bottom, max(10, L.safeBottom * 0.6))
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
        .onAppear {
            guard let a = address else {
                isDefault = store.addresses.isEmpty     // 第一条默认设成默认地址
                return
            }
            name = a.name; phone = a.phone; region = a.region; detail = a.detail; isDefault = a.isDefault
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.trimmingCharacters(in: .whitespaces).count >= 6
            && !(region + detail).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ label: String, _ text: Binding<String>, _ idx: Int,
                       keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Text(label).font(pf(15)).foregroundColor(DDColor.ink)
                .frame(width: 132, alignment: .leading)
            TextField("", text: text)
                .font(pf(15))
                .keyboardType(keyboard)
                .focused($focus, equals: idx)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = phone.trimmingCharacters(in: .whitespaces)
        let r = region.trimmingCharacters(in: .whitespaces)
        let d = detail.trimmingCharacters(in: .whitespaces)
        if var a = address {
            a.name = n; a.phone = p; a.region = r; a.detail = d; a.isDefault = isDefault
            store.updateAddress(a)
        } else {
            store.addAddress(DDAddress(id: "", name: n, phone: p, region: r, detail: d, isDefault: isDefault))
        }
        dismiss()
    }
}
