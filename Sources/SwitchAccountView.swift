import SwiftUI

/* ============================================================
   切换账号（我 → 设置 → 切换账号）

   2026-10-12 用户要求「对齐微信简洁的」，整页重画：
     · 去掉原来那张金边深色卡、绿色「切换」胶囊、圆角卡片边框和阴影；
     · 就是微信那种**一条一条的分组列表**：头像 56 方角 6 + 名字 17 + 星言号 13 灰，
       整行 84 高、左右 16、行与行之间一条细线（从文字左边开始）；
     · 行里**没有任何标记**（微信不标"当前"）；不搞胶囊、不搞金圈、不加说明文字；
     · 点另一个账号直接切（不用重新输密码），右上「管理」切进移除模式；
     · 最下面「添加账号」和上面同一种行：一个灰底方角块里一个加号 + 「添加账号」。

   逻辑（切换 / 移除 / 添加）和以前完全一样，只换了画法。
   ============================================================ */
struct SwitchAccountView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var growth = GrowthStore.shared

    @State private var managing = false
    @State private var adding = false
    @State private var busy = ""
    @State private var note = ""

    private var me: String { app.me?.username ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("切换账号"), back: { dismiss() }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { managing.toggle() }
                } label: {
                    Text(Tr(managing ? "完成" : "管理"))
                        .font(pf(16))
                        .foregroundColor(managing ? C.green : C.label)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    /* 用户要求「跟微信一模一样」：说明那行小灰字、底下的安全提示、当前账号的
                       「使用中」标记全部去掉 —— 微信这一页就**只有**账号行 + 细线 + 添加账号行。 */
                    /* 一整块分组列表：账号们 + 最后一行「添加账号」，中间全是细线 */
                    GroupCard(bg: C.cardBg) {
                        ForEach(app.accounts) { acct in
                            accountRow(acct)
                            HairLine(inset: 84)
                        }
                        addRow
                    }
                    .padding(.top, 8)

                    if !note.isEmpty {
                        Text(note)
                            .font(pf(13))
                            .foregroundColor(Color(hexString: "#FA5151"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22)
                            .padding(.top, 10)
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
        .sheet(isPresented: $adding) {
            AccountLoginSheet(mode: .password)
                .environmentObject(app)
        }
    }

    /* ---------------------------------------------------------- 一行账号 */

    /// 微信那一行：头像 56（方角 6）+ 名字 17 + 星言号 13 灰，整行 84。
    /// 右边平时什么都不放（微信不标"当前"）；只有管理模式下别的账号才写红色「移除」。
    @ViewBuilder
    private func accountRow(_ a: SavedAccount) -> some View {
        let current = (a.username == me)
        Button {
            tap(a, current: current)
        } label: {
            HStack(spacing: 12) {
                Avatar(path: a.avatar, size: 56, radius: 6, level: levelOf(a))
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 5) {
                    Text(a.nickname.isEmpty ? a.username : a.nickname)
                        .font(pf(17))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(Tr("星言号") + "：" + a.username)
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if busy == a.username {
                    ProgressView()
                } else if managing, !current {
                    Text(Tr("移除"))
                        .font(pf(15))
                        .foregroundColor(C.red)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 最后一行「添加账号」：和上面同一种行，左边一个灰底方角块里一个加号。
    private var addRow: some View {
        Button { adding = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.dyn(0xEDEDED, 0x2C2C2E))
                        .frame(width: 56, height: 56)
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundColor(C.subLabel)
                }
                Text(Tr("添加账号"))
                    .font(pf(17))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /* ---------------------------------------------------------- 干活（和以前一样，没动） */

    /// 这个账号的等级：当前账号用成长系统里的；其他账号看通讯录（是好友才有）
    private func levelOf(_ a: SavedAccount) -> Int {
        if a.username == me { return max(1, growth.shownLevel) }
        if let lv = app.contacts.first(where: { $0.username == a.username })?.qqLevel, lv > 0 { return lv }
        return 0
    }

    private func tap(_ a: SavedAccount, current: Bool) {
        if managing {
            if !current { remove(a) }
            return
        }
        guard !current, busy.isEmpty else { return }
        switchTo(a)
    }

    private func switchTo(_ a: SavedAccount) {
        note = ""
        busy = a.username
        Task {
            let saved = AccountStore.token(for: a.username)
            let ok = await app.quickLogin(token: saved.isEmpty ? nil : saved)
            busy = ""
            if ok {
                dismiss()
            } else {
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
            }
        }
    }

    private func remove(_ a: SavedAccount) {
        AccountStore.remove(username: a.username)
        app.accounts = AccountStore.load()
        app.show(Tr("已移除") + "「" + a.nickname + "」")
        if app.accounts.isEmpty { managing = false }
    }
}
