import SwiftUI

/* ============================================================
   设置里那三段（账号 / 通用 / 功能）点进去的二级页 —— 照微信那几页做：
     · 账号 → 个人信息与权限（SelfPermView）
     · 通用 → 更多（MoreSettingsView）
     · 功能 → 聊天（ChatSettingsView）/ 音视频通话（CallSettingsView）
   这些页都挂在「我」页那条 navigationDestination 上（key: selfperm / more / setchat / setcall），
   一律**整页 push**（不是 sheet / 半屏），和微信一样。
   ============================================================ */

/// 「设置」里那种一行一项：左边标题、右边小字值、右箭头，点进下一整页
struct SettingRowLink: View {
    let title: String
    var value: String = ""
    let key: String

    var body: some View {
        NavigationLink(value: key) {
            SettingRowLabel(title: title, value: value)
        }
        .buttonStyle(MenuPressStyle())
    }
}

/// 同上一行，但点下去不是跳页（弹窗 / 打开 iOS 设置）
struct SettingRowButton: View {
    let title: String
    var value: String = ""
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            SettingRowLabel(title: title, value: value)
        }
        .buttonStyle(MenuPressStyle())
    }
}

struct SettingRowLabel: View {
    let title: String
    var value: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(pf(17)).foregroundColor(C.label)
            Spacer(minLength: 0)
            if !value.isEmpty {
                Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(C.meCardBg)
        .contentShape(Rectangle())
    }
}

/* ---------------- 账号 → 个人信息与权限 ---------------- */

struct SelfPermView: View {
    @ObservedObject private var lang = LangStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("个人信息与权限"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        SettingRowLink(title: Tr("个人资料"), key: "profile")
                        HairLine(inset: 16)
                        /* 微信这一行点下去就是跳到 iOS 设置里那个 App 的权限页 */
                        SettingRowButton(title: Tr("系统权限管理"), value: Tr("相册 / 相机 / 麦克风")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("隐私"), key: "privacy")
                    }
                    .padding(.top, 8)

                    Text(Tr("App 只在你同意之后才会用相册、相机、麦克风、位置这些权限，随时可以在 iOS 设置里改。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
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
    }
}

/* ---------------- 通用 → 更多 ---------------- */

struct MoreSettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showDiag = false
    /// 「显示小星」那一行右边的小字：现在选的是哪一档
    @ObservedObject private var eyes = EyesStore.shared

    private var eyesValue: String {
        switch eyes.tier {
        case "off":    return Tr("已关闭")
        case "static": return Tr("静态")
        default:       return Tr("开启")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("更多"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        SettingRowLink(title: Tr("未成年人模式"), key: "teen")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("关怀模式"),
                                       value: CareMode.on ? Tr("已开启") : Tr("未开启"),
                                       key: "care")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("我的等级"), key: "level")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("安全分"), key: "score")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("登录设备管理"), key: "devices")
                        HairLine(inset: 16)
                        /* 小星（会话页顶栏那颗眼睛）的三档开关：
                           开启小星 ¥40 一次性 / 静态小星 免费 / 关闭小星 免费 */
                        SettingRowLink(title: Tr("显示小星"), value: eyesValue, key: "eyes")
                        HairLine(inset: 16)
                        /* 微信那套「故障修复」：一列检查项，每项先检测、能修的当场修 */
                        SettingRowLink(title: Tr("故障修复"), key: "health")
                        HairLine(inset: 16)
                        /* 诊断工具（用户要求「在设置里加入全套诊断工具」）：
                           版本 / 机型 / 内存 / 缓存 / 网络 / 上次崩溃 / 聊天页打点，
                           进这一页就能一键上报给开发者 —— 以后出问题不用再靠猜。 */
                        SettingRowButton(title: Tr("诊断工具")) { showDiag = true }
                    }
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
        .sheet(isPresented: $showDiag) {
            DiagView().environmentObject(app)
        }
        /* 「显示小星」右边那行小字要跟账号里的档位一致：进来拉一次 */
        .task { await eyes.refresh() }
    }
}

/* ---------------- 功能 → 聊天 ---------------- */

struct ChatSettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("聊天"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        SettingRowLink(title: Tr("聊天背景"), key: "g.chatbg")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("语音变声"), key: "g.voice")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("聊天记录管理"), key: "g.history")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("存储空间"), key: "g.storage")
                    }
                    .padding(.top, 8)

                    Text(Tr("聊天记录只存在这台手机上，也能在「存储空间」里按会话清理。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
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
    }
}

/* ---------------- 功能 → 音视频通话 ---------------- */

struct CallSettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("音视频通话"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        SettingRowLink(title: Tr("新消息通知"), key: "notify")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("语音变声"), key: "g.voice")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("登录设备管理"), key: "devices")
                    }
                    .padding(.top, 8)

                    Text(Tr("语音通话默认走听筒，通话中点一下扬声器就外放；视频通话默认外放。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
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
    }
}
