import SwiftUI

/* ============================================================
   我的二维码（2026-10-12 按用户要求重做成微信那种**简单版**）

   就四块，从上到下：
     ① 头像 + 昵称 + 星言号
     ② 一张白底大二维码（小头像摆在正中间 —— 微信就是这个样子；服务器出的码是
        纠错等级 H，中间挡住一小块照样扫得出来）
     ③ 一行小字：扫一扫上面的二维码，加我为朋友
     ④ 两张白卡两行：「保存到相册」「扫一扫」
   不再有深色金边大卡、渐变按钮那一套（用户嫌复杂）。
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

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的二维码"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    /* ① 头像 + 昵称 + 星言号 */
                    VStack(spacing: 10) {
                        Avatar(path: avatar.isEmpty ? (app.me?.avatarPath ?? "") : avatar,
                               size: 62, radius: 31, circle: true, level: growth.shownLevel)
                        Text(name.isEmpty ? (app.me?.name ?? "") : name)
                            .font(pf(18, .medium))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                        Text(Tr("星言号：") + (username.isEmpty ? "-" : username))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                    /* ② 白底大二维码（小头像摆正中间，微信那种） */
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                        if loading {
                            ProgressView()
                        } else if rows.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 22)).foregroundColor(C.subLabel)
                                Text(Tr("二维码生成失败，稍后再试"))
                                    .font(pf(13)).foregroundColor(C.subLabel)
                            }
                        } else {
                            QRCanvas(rows: rows, avatar: avatar)
                                .frame(width: 224, height: 224)
                        }
                    }
                    .frame(width: 264, height: 264)
                    .shadow(color: Color.black.opacity(0.07), radius: 10, y: 3)

                    /* ③ 一行小字 */
                    Text(Tr("扫一扫上面的二维码，加我为朋友"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .padding(.top, 14)

                    /* ④ 两行白卡：保存到相册 / 扫一扫 */
                    GroupCard {
                        Button { saveToAlbum() } label: {
                            qrRow(icon: "square.and.arrow.down",
                                  title: saved ? Tr("已存到相册") : Tr("保存到相册"))
                        }
                        .buttonStyle(.plain)
                        .disabled(rows.isEmpty)
                        HairLine(inset: 16)
                        Button { showScan = true } label: {
                            qrRow(icon: "qrcode.viewfinder", title: Tr("扫一扫"))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 18)

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 16)
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

    /* 白卡里的一行：保存到相册 / 扫一扫 */
    private func qrRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(C.green)
                .frame(width: 24)
            Text(title).font(pf(16.5)).foregroundColor(C.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .contentShape(Rectangle())
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

