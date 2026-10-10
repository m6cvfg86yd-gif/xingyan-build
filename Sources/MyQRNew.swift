import SwiftUI

/* ============================================================
   我的二维码（重做的高级版）
   · 一张深色金边大卡：上面头像 + 昵称 + 等级，中间一张白色圆角码卡悬浮着
   · 下面两个按钮：保存到相册（绿色渐变）/ 扫一扫（描边）
   · 保存到相册的那张图：头像是**放在码下面**，不盖码
     （这套码是纠错等级 L，正中间盖头像就扫不出来了 —— 旧版这地方是坑）
   ============================================================ */
struct MyQRView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var growth = GrowthStore.shared

    @State private var rows: [String] = []
    @State private var code = ""
    @State private var name = ""
    @State private var username = ""
    @State private var avatar = ""
    @State private var loading = true
    @State private var saved = false
    @State private var showScan = false

    private let gold = Color(hex: 0xF0C24B)
    private let green1 = Color(hex: 0x3ED37F)
    private let green2 = Color(hex: 0x12A05A)

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的二维码"), back: { dismiss() }) {
                Button { saveToAlbum() } label: {
                    Text(saved ? Tr("已存") : Tr("保存"))
                        .font(pf(14.5, .medium))
                        .foregroundColor(rows.isEmpty ? C.subLabel : .white)
                        .padding(.horizontal, 15)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(rows.isEmpty
                                ? AnyShapeStyle(Color.dyn(0xEDEDED, 0x2C2C2E))
                                : AnyShapeStyle(LinearGradient(colors: [green1, green2],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing)))
                        )
                        .padding(.trailing, 14)
                }
                .buttonStyle(.plain)
                .disabled(rows.isEmpty)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    heroCard
                    HStack(spacing: 10) {
                        Button { saveToAlbum() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text(saved ? Tr("已存到相册") : Tr("保存到相册"))
                            }
                            .font(pf(15, .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [green1, green2],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .shadow(color: green2.opacity(0.28), radius: 9, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(rows.isEmpty)

                        Button { showScan = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "qrcode.viewfinder")
                                Text(Tr("扫一扫"))
                            }
                            .font(pf(15, .medium))
                            .foregroundColor(C.green)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background { CardGlassBox(radius: 14) }
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(C.green.opacity(0.5), lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(Tr("用「发现 → 扫一扫」扫这张，就能加我好友；也可以把图存下来发给别人。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .task {
            let r = await API.shared.myQRCode()
            code = r.code
            rows = r.rows
            name = r.user?.name ?? (app.me?.name ?? "")
            username = r.user?.username ?? (app.me?.username ?? "")
            avatar = r.user?.avatarPath ?? (app.me?.avatarPath ?? "")
            loading = false
        }
    }

    /* 深色金边卡：头像 + 昵称 + 等级，中间浮着一张白色码卡 */
    private var heroCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Avatar(path: avatar.isEmpty ? (app.me?.avatarPath ?? "") : avatar, size: 44, radius: 22, circle: true, level: growth.shownLevel)
                    .overlay(Circle().stroke(gold.opacity(0.85), lineWidth: 1.4))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name.isEmpty ? (app.me?.name ?? "") : name)
                            .font(pf(17, .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if growth.shownLevel > 0 {
                            QQLevelBadge(level: growth.shownLevel, size: 13, maxIcons: 3).fixedSize()
                        }
                    }
                    Text(Tr("星言号：") + (username.isEmpty ? "-" : username))
                        .font(pf(12.5))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
                if loading {
                    ProgressView()
                } else if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22))
                            .foregroundColor(C.subLabel)
                        Text(Tr("二维码生成失败，稍后再试"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                    }
                } else {
                    /* 服务端现在出的是纠错等级 H 的码，正中间盖一张方形头像照样扫得出来
                       （微信的个人二维码就是这么放的） */
                    QRCanvas(rows: rows, avatar: avatar)
                        .frame(width: 216, height: 216)
                }
            }
            .frame(width: 244, height: 244)

            Text(Tr("扫一扫，加我为好友"))
                .font(pf(12.5))
                .foregroundColor(.white.opacity(0.62))
        }
        .padding(18)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1C2130), Color(hex: 0x2B2233), Color(hex: 0x14111A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [gold.opacity(0.22), Color.clear],
                               center: .topTrailing, startRadius: 2, endRadius: 230)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /* 保存到相册：一张干净的图（头像在码下面，不盖码） */
    private func saveToAlbum() {
        guard !rows.isEmpty else { return }
        let card = VStack(spacing: 16) {
            QRCanvas(rows: rows, avatar: avatar).frame(width: 520, height: 520)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
            HStack(spacing: 16) {
                Avatar(path: avatar, size: 84, radius: 42, circle: true, level: growth.shownLevel)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.system(size: 28, weight: .semibold)).foregroundColor(.black)
                    Text(Tr("星言号：") + username).font(.system(size: 20)).foregroundColor(.gray)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            Text(Tr("扫一扫，加我为好友")).font(.system(size: 20)).foregroundColor(.gray)
        }
        .padding(40)
        .frame(width: 640)
        .background(Color.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        if let img = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            saved = true
            app.show(Tr("二维码已存到相册"))
            return
        }
        app.show(Tr("保存失败，可以截图"))
    }
}

