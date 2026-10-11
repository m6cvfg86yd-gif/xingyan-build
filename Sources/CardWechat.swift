import SwiftUI

/* ============================================================
   好友名片 · 微信版（后台 data/ui.json 里 cardStyle = "wechat" 才走这一版）
   骨架照微信 iOS「详细资料」页：
     · 导航：‹ 返回 + 右上「…」
     · 头部（白底）：大头像 + 名字 + 微信号 + 地区
     · 分组：设置备注和标签 / 朋友权限
     · 朋友圈：一行，右侧最多三张缩略图
     · 分组：更多信息
     · 底部：绿色大按钮「发消息」+「音视频通话」
   老的两版（old / new）一个字都没动，随时能把 cardStyle 切回去。
   尺寸和颜色都能在服务器 data/ui.json 里调（改完重开 App 生效）：
     cardWechatBg、cardWechatGreen、cardWechatAvatar、cardWechatNameSize、
     cardWechatThumb、cardWechatRowH、cardWechatBtnH、cardWechatRadius
   ============================================================ */

struct ContactCardWechat: View {
    let name: String
    let wxId: String
    let region: String
    let avatarPath: String
    let isEyes: Bool
    /// 「设置备注和标签」右侧那点小字（微信显示你给他打的标签）
    let remarkLine: String
    /// 「朋友权限」右侧的小字
    let permLine: String
    /// 「更多信息」右侧的小字（共同群聊 / 来源 / 添加时间）
    let moreLine: String
    /// 朋友圈那一行要说的话：对方设了可见范围、这区间里又没动态时才非空
    let momentsHint: String
    let thumbs: [String]
    let isBot: Bool
    /// self / friend / incoming / requested / none
    let relation: String

    let onClose: () -> Void
    let onAvatar: () -> Void
    let onMessage: () -> Void
    let onVoice: () -> Void
    let onVideo: () -> Void
    let onAICall: () -> Void
    let onMoments: () -> Void
    let onRemark: () -> Void
    let onPerm: () -> Void
    let onMore: () -> Void
    let onMenu: () -> Void
    let onApply: () -> Void
    let onAgree: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// 点「音视频通话」先问一句（微信也是先出「语音通话 / 视频通话」）
    @State private var askCall = false

    /* ---------------- 颜色 / 尺寸：全走后台键 ---------------- */
    private var green: Color { UIConfig.color("cardWechatGreen", 0x07C160, 0x07C160) }
    private var pageBg: Color { UIConfig.color("cardWechatBg", 0xEDEDED, 0x111111) }
    private var cardBg: Color { scheme == .dark ? Color(hex: 0x252525) : Color.white }
    private var ink: Color { scheme == .dark ? Color(hex: 0xEDEDED) : Color(hex: 0x191919) }
    private var gray: Color { scheme == .dark ? Color(hex: 0x7F7F7F) : Color(hex: 0x888888) }
    private var hair: Color { scheme == .dark ? Color(white: 1, opacity: 0.08) : Color(hex: 0xE6E6E6) }
    private var avatarSize: CGFloat { UIConfig.num("cardWechatAvatar", 64) }
    private var nameSize: CGFloat { UIConfig.num("cardWechatNameSize", 20) }
    private var thumbSize: CGFloat { UIConfig.num("cardWechatThumb", 40) }
    private var rowH: CGFloat { UIConfig.num("cardWechatRowH", 54) }
    private var btnH: CGFloat { UIConfig.num("cardWechatBtnH", 46) }
    private var radius: CGFloat { UIConfig.num("cardWechatRadius", 8) }

    var body: some View {
        VStack(spacing: 0) {
            nav
            ScrollView {
                VStack(spacing: 0) {
                    header
                    gap
                    card {
                        row(Tr("设置备注和标签"), remarkLine, onRemark)
                        hairline
                        row(Tr("朋友权限"), permLine, onPerm)
                    }
                    gap
                    momentsRow
                    gap
                    card {
                        row(Tr("更多信息"), moreLine, onMore)
                    }
                    gap
                    buttons
                    Spacer(minLength: 28)
                }
            }
            .background(pageBg)
        }
        .background(pageBg.ignoresSafeArea())
        .confirmationDialog(Tr("音视频通话"), isPresented: $askCall, titleVisibility: .visible) {
            Button(Tr("语音通话")) { onVoice() }
            Button(Tr("视频通话")) { onVideo() }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    /* ---------------------------------------------------------- 骨架 */

    private var nav: some View {
        NavBar(title: "", back: { onClose() }) {
            Button { onMenu() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17))
                    .foregroundColor(ink)
                    .frame(width: 44, height: L.navH)
            }
            .buttonStyle(.plain)
        }
        .background(pageBg)
    }

    /// 头部：大头像 + 名字 / 微信号 / 地区（微信就是这样一块白的）
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if isEyes {
                    JarvisEyesAvatar(size: avatarSize)
                        .frame(width: avatarSize, height: avatarSize)
                } else {
                    Avatar(path: avatarPath, size: avatarSize, radius: radius)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onAvatar() }

            VStack(alignment: .leading, spacing: 7) {
                Text(name)
                    .font(pf(nameSize, .semibold))
                    .foregroundColor(ink)
                    .lineLimit(2)
                Text(wxId)
                    .font(pf(14))
                    .foregroundColor(gray)
                    .lineLimit(1)
                Text(Tr("地区") + "：" + region)
                    .font(pf(14))
                    .foregroundColor(gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(cardBg)
    }

    /// 「朋友圈」一行：右边最多三张缩略图；没动态时写那句话
    private var momentsRow: some View {
        Button { onMoments() } label: {
            HStack(spacing: 10) {
                Text(Tr("朋友圈"))
                    .font(pf(16))
                    .foregroundColor(ink)
                Spacer(minLength: 8)
                if !thumbs.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(thumbs.prefix(3).indices, id: \.self) { i in
                            RemoteImage(path: thumbs[i])
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                } else {
                    Text(momentsHint.isEmpty ? Tr("暂无朋友圈动态") : Tr(momentsHint))
                        .font(pf(13.5))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .background(cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 底部：绿色大按钮「发消息」+「音视频通话」（按关系变：机器人 / 陌生人 / 待同意…）
    private var buttons: some View {
        VStack(spacing: 0) {
            Button { onMessage() } label: {
                Text(Tr("发消息"))
                    .font(pf(17, .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: btnH)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(green))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Button { secondTap() } label: {
                Text(secondTitle)
                    .font(pf(17, .medium))
                    .foregroundColor(secondEnabled ? green : gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: btnH)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cardBg))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(secondEnabled ? green : hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!secondEnabled)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(cardBg)
    }

    private var secondTitle: String {
        if isBot { return Tr("语音通话") }
        switch relation {
        case "friend", "self": return Tr("音视频通话")
        case "incoming":       return Tr("同意好友申请")
        case "requested":      return Tr("已发送好友申请")
        default:               return Tr("添加到通讯录")
        }
    }

    /// 「已发送好友申请」那一颗不给点
    private var secondEnabled: Bool { relation != "requested" }

    private func secondTap() {
        if isBot { onAICall(); return }
        switch relation {
        case "friend", "self": askCall = true
        case "incoming":       onAgree()
        case "requested":      break
        default:               onApply()
        }
    }

    /* ---------------------------------------------------------- 小零件 */

    private func row(_ title: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Text(title)
                    .font(pf(16))
                    .foregroundColor(ink)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value)
                        .font(pf(14))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .background(cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    private var hairline: some View {
        Rectangle().fill(hair).frame(height: 0.6).padding(.leading, 16)
    }

    /// 分组之间那条底色缝（微信用的就是这种灰底 + 白卡片）
    private var gap: some View {
        Rectangle().fill(pageBg).frame(height: 8)
    }
}
