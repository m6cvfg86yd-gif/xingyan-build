import SwiftUI
import UniformTypeIdentifiers

/* ============================================================
   「我的二维码」下面那两排点开的两层（2026-10-12 加）

     · QRStyleSheet        —— 换个样式：绿 / 蓝 / 红 / 黄 / 紫 / 黑
     · FaceToFaceFileSheet —— 面对面收照片和文件：把自己的码给对方扫，
                              对方加你为好友后当面把照片、文件发过来（收到的都进聊天）

   （「面对面收红包」直接出示收款码那一页，见 MyQRView 里的 PayCodePage。）
   ============================================================ */

struct QRStyleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: QRInk
    let onPick: (QRInk) -> Void

    private let cols = [GridItem(.adaptive(minimum: 76), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("换个样式"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Tr("挑一个颜色，二维码和「保存到相册」的图片都会用这个色（白底上用深色才扫得出来）。"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .padding(.horizontal, 20).padding(.top, 12)

                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(QRInk.allCases, id: \.rawValue) { ink in
                            Button {
                                onPick(ink)
                                dismiss()
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle().fill(ink.color).frame(width: 52, height: 52)
                                        if ink == current {
                                            Circle().stroke(C.green, lineWidth: 2.5)
                                                .frame(width: 60, height: 60)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(width: 62, height: 62)
                                    Text(Tr(ink.name)).font(pf(13.5))
                                        .foregroundColor(ink == current ? C.green : C.label)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }
}

enum NearbyDropMode {
    case host
    case join(NearbyDropInvite)
}

struct FaceToFaceFileSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let rows: [String]
    let avatar: String
    let name: String
    var ink: Color = .black
    var mode: NearbyDropMode = .host

    @StateObject private var drop = NearbyDropCenter()
    @State private var showScan = false
    @State private var showMedia = false
    @State private var showFiles = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("面对面传照片和视频"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    statusCard

                    if drop.isConnected {
                        connectedActions
                    } else {
                        switch mode {
                        case .host:
                            hostQRCode
                        case .join(let invite):
                            searchingCard(invite)
                        }
                    }

                    instructions

                    if !drop.activity.isEmpty {
                        GroupCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(Tr("传输记录"))
                                    .font(pf(14, .medium))
                                    .foregroundColor(C.label)
                                ForEach(Array(drop.activity.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(pf(13))
                                        .foregroundColor(C.subLabel)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }

                    if !drop.isConnected {
                        Button { showScan = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 16))
                                Text(Tr("我也扫对方的码")).font(pf(16, .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(C.green))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .modifier(BrightenScreen())
        .task {
            switch mode {
            case .host:
                drop.startHosting(name: name.isEmpty ? (app.me?.name ?? "我") : name)
            case .join(let invite):
                drop.join(invite)
            }
        }
        .onDisappear { drop.stop() }
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in
                if let invite = NearbyDropInvite.parse(text) {
                    drop.join(invite)
                } else {
                    handleScanned(text, app: app)
                }
            }
        }
        .sheet(isPresented: $showMedia) {
            MediaPicker(
                onImage: { drop.send(images: [$0]) },
                onVideo: { drop.send(files: [$0]) },
                onLive: { image, video in
                    drop.send(images: [image])
                    drop.send(files: [video])
                },
                maxImages: 9,
                onImages: { drop.send(images: $0) },
                onNotice: { app.show($0) }
            )
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                drop.send(files: urls)
            case .failure(let error):
                app.show("选择文件失败：" + error.localizedDescription)
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(C.green.opacity(0.14)).frame(width: 42, height: 42)
                Image(systemName: drop.isConnected ? "checkmark" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.green)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(drop.isConnected ? Tr("已碰一碰连接") : Tr("正在碰一碰"))
                    .font(pf(16, .medium))
                    .foregroundColor(C.label)
                Text(drop.status)
                    .font(pf(12.5))
                    .foregroundColor(C.subLabel)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var hostQRCode: some View {
        VStack(spacing: 10) {
            Text(Tr("让对方用 App 的「扫一扫」扫这张码"))
                .font(pf(13.5))
                .foregroundColor(C.subLabel)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                if let inv = drop.invite, let image = qrImage(inv.link, size: 512) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 236, height: 236)
            .shadow(color: Color.black.opacity(0.07), radius: 10, y: 3)

            HStack(spacing: 8) {
                Avatar(path: avatar, size: 28, radius: 14, circle: true)
                Text(name.isEmpty ? Tr("我") : name)
                    .font(pf(15, .medium))
                    .foregroundColor(C.label)
            }
        }
    }

    private func searchingCard(_ invite: NearbyDropInvite) -> some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.15)
            Text(Tr("正在连接 ") + invite.name)
                .font(pf(16, .medium))
                .foregroundColor(C.label)
            Text(Tr("请保持对方页面开着；如果找不到，检查两台手机的本地网络权限"))
                .font(pf(12.5))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var connectedActions: some View {
        VStack(spacing: 10) {
            Button { showMedia = true } label: {
                actionRow(icon: "photo.on.rectangle.angled",
                          title: Tr("选择照片 / 视频"),
                          subtitle: Tr("可多选照片，也可以选一个视频"),
                          enabled: true)
            }
            .buttonStyle(.plain)

            Button { showFiles = true } label: {
                actionRow(icon: "folder",
                          title: Tr("选择文件"),
                          subtitle: Tr("从“文件”里选，不经过聊天服务器"),
                          enabled: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, enabled: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(enabled ? C.green : C.subLabel)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(pf(16, .medium)).foregroundColor(C.label)
                Text(subtitle).font(pf(12)).foregroundColor(C.subLabel)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(C.subLabel)
        }
        .padding(.horizontal, 15)
        .frame(height: 66)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var instructions: some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 9) {
                hintRow("1", Tr("双方都打开「面对面传照片和视频」"))
                hintRow("2", Tr("一方扫码，自动建立点对点连接"))
                hintRow("3", Tr("连接后选择照片或视频，原文件直接传到对方手机"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func hintRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(C.green.opacity(0.16)).frame(width: 20, height: 20)
                Text(n).font(.system(size: 11, weight: .semibold)).foregroundColor(C.green)
            }
            Text(text).font(pf(13.5)).foregroundColor(C.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
