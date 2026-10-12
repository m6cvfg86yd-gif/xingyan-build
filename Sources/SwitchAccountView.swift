import SwiftUI

/* ============================================================
   切换账号（我 → 设置 → 切换账号）—— 逻辑照微信，界面重做一版「高级感」：
   · 顶部一张深色金边卡：本机已登录几个号 + 当前账号（大头像带金圈、等级图标、当前使用中）
   · 下面每个账号一张圆角卡片：头像 + 昵称 + 星言号 + 等级图标 + 「切换」绿色胶囊
   · 右上「管理」→ 其他账号变红「移除」；当前账号标「当前」不给删
   · 最下面虚线卡「添加账号」；令牌分开存钥匙串，切过去秒进
   ============================================================ */
struct SwitchAccountView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var growth = GrowthStore.shared

    @State private var managing = false
    @State private var adding = false
    @State private var busy = ""
    @State private var note = ""

    private var me: String { app.me?.username ?? "" }
    private var cardBg: Color { scheme == .dark ? Color(hex: 0x1B1B1E) : .white }
    private var pageBg: Color { scheme == .dark ? Color(hex: 0x0E0E10) : Color(hex: 0xF2F3F5) }
    private var ink: Color { scheme == .dark ? Color(hex: 0xEDEDED) : Color(hex: 0x1A1A1A) }
    private var gray: Color { scheme == .dark ? Color(hex: 0x8E8E93) : Color(hex: 0x8A8A8E) }
    private var line: Color { scheme == .dark ? Color(white: 1, opacity: 0.08) : Color(hex: 0xE6E6E6) }
    private let gold = Color(hex: 0xF0C24B)

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("切换账号"), back: { dismiss() }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { managing.toggle() }
                } label: {
                    Text(Tr(managing ? "完成" : "管理"))
                        .font(pf(16, managing ? .medium : .regular))
                        .foregroundColor(managing ? C.green : C.label)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard
                    accountsSection
                    addCard
                    if !note.isEmpty {
                        Text(note)
                            .font(pf(13))
                            .foregroundColor(Color(hexString: "#FA5151"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    tip
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(pageBg)
        }
        .background(pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(isPresented: $adding) {
            AccountLoginSheet(mode: .password)
                .environmentObject(app)
        }
    }

    /* ---------------------------------------------------------- 顶部：当前账号 */

    private var headerCard: some View {
        let cur = app.accounts.first(where: { $0.username == me }) ?? app.accounts.first
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(Tr("本机已登录"))
                    .font(pf(12.5))
                    .foregroundColor(.white.opacity(0.6))
                Text(String(app.accounts.count) + Tr(" 个账号"))
                    .font(pf(12.5, .semibold))
                    .foregroundColor(gold)
                Spacer(minLength: 0)
                Text(Tr("最多 3 个"))
                    .font(pf(11.5))
                    .foregroundColor(.white.opacity(0.4))
            }
            if let cur = cur {
                HStack(spacing: 14) {
                    Avatar(path: cur.avatar, size: 56, radius: 28, circle: true, level: levelOf(cur))
                        .overlay(Circle().stroke(gold.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(cur.nickname.isEmpty ? cur.username : cur.nickname)
                                .font(pf(19, .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if levelOf(cur) > 0 {
                                QQLevelBadge(level: levelOf(cur), size: 15, maxIcons: 3)
                                    .fixedSize()
                            }
                        }
                        HStack(spacing: 8) {
                            Text(Tr("当前使用中"))
                                .font(pf(11.5, .medium))
                                .foregroundColor(Color(hex: 0x0E2E20))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(hex: 0x74E0A6)))
                            Text("Lv." + String(max(1, levelOf(cur))))
                                .font(pf(12))
                                .foregroundColor(.white.opacity(0.65))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1C2130), Color(hex: 0x2B2233), Color(hex: 0x14111A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [gold.opacity(0.22), Color.clear],
                               center: .topTrailing, startRadius: 2, endRadius: 220)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /* ---------------------------------------------------------- 账号列表 */

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(Tr(managing ? "点不想用的账号即可移除（当前账号不能移除）" : "点一下直接切过去，不用重新输密码"))
                .font(pf(12.5))
                .foregroundColor(gray)
                .padding(.leading, 4)
            ForEach(app.accounts) { acct in
                accountCard(acct)
            }
        }
    }

    private func accountCard(_ a: SavedAccount) -> some View {
        let current = (a.username == me)
        return Button {
            tap(a, current: current)
        } label: {
            HStack(spacing: 12) {
                Avatar(path: a.avatar, size: 46, radius: 23, circle: true, level: levelOf(a))
                    .overlay(Circle().stroke(current ? gold.opacity(0.7) : line, lineWidth: current ? 1.3 : 0.6))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(a.nickname.isEmpty ? a.username : a.nickname)
                            .font(pf(16.5, .medium))
                            .foregroundColor(ink)
                            .lineLimit(1)
                        if levelOf(a) > 0 {
                            QQLevelBadge(level: levelOf(a), size: 13, maxIcons: 3)
                                .fixedSize()
                        }
                    }
                    Text(Tr("星言号") + "：" + a.username)
                        .font(pf(12.5))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if busy == a.username {
                    ProgressView()
                } else if managing, !current {
                    Text(Tr("移除"))
                        .font(pf(14, .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Color(hex: 0xFA5151)))
                } else if current {
                    Text(Tr("当前"))
                        .font(pf(12.5, .medium))
                        .foregroundColor(C.green)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(Capsule().fill(C.green.opacity(0.12)))
                } else {
                    HStack(spacing: 3) {
                        Text(Tr("切换")).font(pf(13.5, .medium))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(Capsule().fill(C.green))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(current ? gold.opacity(0.45) : line, lineWidth: current ? 1.2 : 0.6)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0 : 0.05), radius: 7, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addCard: some View {
        Button { adding = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(C.green.opacity(0.12)).frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(C.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("添加账号")).font(pf(16.5, .medium)).foregroundColor(ink)
                    Text(Tr("登录另一个星言号，下次点一下就能切"))
                        .font(pf(12.5)).foregroundColor(gray)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(C.arrow)
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundColor(line)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundColor(gray)
            Text(Tr("一个设备最多记 3 个账号；切过去不用重新输密码，令牌分开存在本机钥匙串里。"))
                .font(pf(12))
                .foregroundColor(gray)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /* ---------------------------------------------------------- 干活 */

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


