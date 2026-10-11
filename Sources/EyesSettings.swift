import SwiftUI

/* ============================================================
   小星（会话页顶栏那颗眼睛）的三档开关（2026-10-12 加）

     开启小星   ¥40 一次性买断（走零钱）—— 眼睛会动（眨眼 / 瞟 / 呼吸）
     静态小星   免费 —— 照样画出来，但两段无限循环动画不跑（省电、看着安静）
     关闭小星   免费 —— 顶栏不画；「我 → 服务」里补一个「AI 助手」入口

   档位存在服务端（GET / POST /api/me/eyes），换设备也跟着账号走；
   管理侧（/api/ops/eyes）能免费给某个用户开。
   入口：我 → 设置 → 通用 → 更多 → 显示小星。
   ============================================================ */

@MainActor
final class EyesStore: ObservableObject {
    static let shared = EyesStore()

    /// on / static / off（认不出来按 on，和服务器默认一致）
    @Published var tier = "on"
    @Published var paid = false
    @Published var price: Double = 40
    @Published var balance: Double = 0
    @Published var loaded = false

    /// 顶栏要不要画小星
    var eyesOn: Bool { tier != "off" }
    /// 眼睛要不要动（只有「开启」那档才跑无限动画）
    var animated: Bool { tier == "on" }

    func apply(_ info: API.EyesInfo) {
        tier = info.tier
        paid = info.paid ?? false
        price = info.price ?? 40
        balance = info.balance ?? balance
        loaded = true
    }

    /// 拉一次当前档位（登录后 / 进前台时调，别频繁调）
    func refresh() async {
        if let info = try? await API.shared.eyesState() { apply(info) }
    }

    /// 切档位。返回 nil = 成功；否则是给用户看的错误文字（比如零钱不够）
    func set(_ want: String) async -> String? {
        do {
            apply(try await API.shared.eyesSet(want))
            DiagLog.shared.note("小星档位改成 \(want)")
            return nil
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "设置失败，再试一次"
            DiagLog.shared.note("小星档位改 \(want) 失败：\(msg)")
            return msg
        }
    }
}

struct EyesSettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var eyes = EyesStore.shared
    /// 选「开启」但还没付费 → 先弹这个确认（¥40 一次性）
    @State private var confirmOn = false
    @State private var busy = false
    /// 点「进入 AI 助手」整页打开小星自己的对话页
    @State private var botChat: Chat? = nil

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("显示小星"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    GroupCard {
                        tierRow("on", Tr("开启小星"), priceText, Tr("会动"))
                        HairLine(inset: 16)
                        tierRow("static", Tr("静态小星"), Tr("免费"), Tr("不动"))
                        HairLine(inset: 16)
                        tierRow("off", Tr("关闭小星"), Tr("免费"), Tr("不显示"))
                    }
                    .padding(.top, 10)

                    Text(Tr("小星是会话页左上角那颗眼睛：会眨眼、会瞟、会呼吸。\n选「静态」照样看得到它，只是不跑动画；选「关闭」顶栏就不画了，\n这时「我 → 服务」里会出现「AI 助手」入口。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 4)

                    GroupCard {
                        HStack(spacing: 12) {
                            Text(Tr("零钱余额")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Text("¥" + moneyFmt(eyes.balance))
                                .font(pfMoney(16))
                                .foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                    .padding(.top, 4)

                    /* 关了顶栏那颗眼睛以后，进 AI 助手的地方就在这儿（用户要求的那条） */
                    Button {
                        openAI()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .medium))
                            Text(Tr("进入 AI 助手"))
                                .font(pf(16, .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.green))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Spacer().frame(height: 30)
                }
                .padding(.top, 6)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { if !eyes.loaded { await eyes.refresh() } }
        .confirmationDialog(Tr("开启小星（¥40，一次性，用零钱支付）"),
                            isPresented: $confirmOn, titleVisibility: .visible) {
            Button(Tr("确认支付 ¥") + moneyFmt(eyes.price)) { Task { await choose("on") } }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("买断之后一直有效，不再重复收费。"))
        }
        .fullScreenCover(item: $botChat) { c in
            BotChatView(chat: c).environmentObject(app)
        }
    }

    /// 开启小星那档的价格文字：付过钱就写「已开启」
    private var priceText: String {
        if eyes.tier == "on" && eyes.paid { return Tr("已开启") }
        if eyes.tier == "on" && !eyes.paid { return "¥" + moneyFmt(eyes.price) + Tr(" 一次性（还没付费）") }
        return "¥" + moneyFmt(eyes.price) + Tr(" 一次性")
    }

    private func tierRow(_ id: String, _ title: String, _ value: String, _ tag: String) -> some View {
        Button {
            if id == "on" && !eyes.paid && eyes.tier != "on" {
                confirmOn = true              // 要花钱：先让用户确认
            } else if id != eyes.tier {
                Task { await choose(id) }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(16.5)).foregroundColor(C.label)
                    Text(value + " · " + tag).font(pf(12.5)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                if eyes.tier == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(C.green)
                }
                if busy && eyes.tier != id {
                    ProgressView().scaleEffect(0.75)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .disabled(busy)
    }

    private func choose(_ want: String) async {
        busy = true
        let err = await eyes.set(want)
        busy = false
        if let err = err { app.show(err) }
        else {
            app.me = try? await API.shared.me()      // 付了钱余额会变，顺手刷新
            app.show(want == "on" ? Tr("小星已开启") : (want == "static" ? Tr("已切成静态小星") : Tr("已关闭小星")))
        }
    }

    /// 「进入 AI 助手」：整页打开小星自己的对话页（和顶栏那颗眼睛点开的是同一页）
    private func openAI() {
        if let bot = app.chats.first(where: { $0.botRank == 0 }) { botChat = bot; return }
        Task {
            await app.loadChats()
            if let b = app.chats.first(where: { $0.botRank == 0 }) { botChat = b }
            else { app.show(Tr("AI 助手还没准备好，稍后再试")) }
        }
    }
}
