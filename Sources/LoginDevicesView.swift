import SwiftUI

/* ============================================================
   登录设备管理（微信：我 → 设置 → 账号与安全 → 登录设备管理）
   列表来自服务端 GET /api/devices：每台登录过的设备一条 ——
   设备名 + 系统 + 最后登录时间，当前这台挂一个绿色的「本机」。
   设备名 / 机型 / 系统是 App 每次请求带上来的头（X-Device-Name / -Model / -Os）。
   ============================================================ */
struct LoginDevicesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var list: [API.LoginDevice] = []
    @State private var loading = true
    @State private var confirmLogoutOthers = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("登录设备管理"), back: { dismiss() })

            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        if loading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 62)
                        } else if list.isEmpty {
                            HStack {
                                Text(Tr("还没有设备记录")).font(pf(15)).foregroundColor(C.subLabel)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 62)
                        } else {
                            ForEach(Array(list.enumerated()), id: \.offset) { idx, d in
                                if idx > 0 { HairLine(inset: 16) }
                                deviceRow(d)
                            }
                        }
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 8)

                    /* 别的设备（网页版 / 新手机）要登录时，会显示一个 6 位数字，
                       在这台手机上输进去就能放行 —— 微信的「扫码确认」没有 SDK 时用它代替。 */
                    GroupCard {
                        NavigationLink(value: "pair") {
                            HStack(spacing: 12) {
                                Text(Tr("确认新设备登录")).font(pf(17)).foregroundColor(C.label)
                                Spacer(minLength: 8)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(C.cardBg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(Tr("别的设备（网页版 / 换新手机）登录时会显示一个 6 位数字，点上面那一行输进去就能放行。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)

                    Spacer().frame(height: 8)

                    Button { confirmLogoutOthers = true } label: {
                        HStack(spacing: 12) {
                            Text(Tr("退出其他设备")).font(pf(17)).foregroundColor(C.label)
                            Spacer(minLength: 8)
                            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(C.cardBg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(Tr("退出其他设备以后，别的手机上登录的这个账号会被踢下线，需要重新登录。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        .confirmationDialog(Tr("退出其他设备？"), isPresented: $confirmLogoutOthers, titleVisibility: .visible) {
            Button(Tr("退出"), role: .destructive) {
                Task {
                    if let err = await API.shared.logoutOtherDevices() {
                        app.show(err)
                    } else {
                        app.show(Tr("已退出其他设备"))
                    }
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    /* ---------------------------------------------------------- 一行设备 */

    private func deviceRow(_ d: API.LoginDevice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(deviceTitle(d))
                        .font(pf(16.5))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    if d.current == true {
                        Text(Tr("本机"))
                            .font(pf(11.5))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(C.green))
                    }
                }
                if !deviceSub(d).isEmpty {
                    Text(deviceSub(d))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                Text(Tr("最后登录") + " " + timeText(d.at))
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 62)
        .background(C.cardBg)
    }

    /// 名字优先用设备名（「张三的 iPhone」），没有再退回机型 / 老记录那行描述
    private func deviceTitle(_ d: API.LoginDevice) -> String {
        let name = (d.name ?? "").removingPercentEncoding ?? (d.name ?? "")
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        let model = (d.model ?? "").trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { return model }
        let dev = (d.device ?? "").trimmingCharacters(in: .whitespaces)
        return dev.isEmpty ? Tr("未知设备") : dev
    }

    /// 名字下面那行：系统版本 + 机型（老记录只有 UA 那行「Safari · iOS」）
    private func deviceSub(_ d: API.LoginDevice) -> String {
        let os = (d.os ?? "").trimmingCharacters(in: .whitespaces)
        let model = (d.model ?? "").trimmingCharacters(in: .whitespaces)
        var bits: [String] = []
        if !os.isEmpty { bits.append(os) }
        if !model.isEmpty { bits.append(model) }
        if bits.isEmpty { bits.append((d.device ?? "").trimmingCharacters(in: .whitespaces)) }
        return bits.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 最后登录时间：今天写「今天 20:31」，昨天写「昨天 20:31」，更早写完整日期
    private func timeText(_ ms: Double?) -> String {
        guard let ms = ms, ms > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return Tr("今天") + " " + f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            f.dateFormat = "HH:mm"
            return Tr("昨天") + " " + f.string(from: date)
        }
        f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm" : "yyyy年M月d日"
        return f.string(from: date)
    }

    private func load() async {
        list = await API.shared.devices()
        loading = false
    }
}
