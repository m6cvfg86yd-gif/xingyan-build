import SwiftUI

/* ============================================================
   发文件用**我们自己这一套**（用户要求：不要苹果那个文件 App 当主入口，
   苹果那套留着，管理里一个开关切回去）。

   这一页列出的是「这个账号发过 / 收到过的文件」——都是已经在我们服务器上的东西，
   点一下就直接发进当前会话（不用再上传一遍，也不会再受"选不到文件"的气）。
   底下留一颗「从「文件」App 里挑」，苹果那套照样能用。
   ============================================================ */

struct MyFilesPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// 选中一个文件：交给聊天页发出去
    var onPick: (API.MyFileItem) -> Void
    /// 点底下那颗按钮：回苹果的文件 App 那套（fileImporter）
    var onSystemPicker: (() -> Void)? = nil

    @State private var files: [API.MyFileItem] = []
    @State private var loading = true
    @State private var q = ""

    private var shown: [API.MyFileItem] {
        let key = q.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return files }
        return files.filter {
            $0.fileName.localizedCaseInsensitiveContains(key)
                || ($0.chatName ?? "").localizedCaseInsensitiveContains(key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("选择文件"), back: { dismiss() })

            /* 搜索框（文件多了全靠它） */
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(C.searchIcon)
                TextField(Tr("搜索文件名"), text: $q)
                    .font(pf(14.5))
                if !q.isEmpty {
                    Button { q = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).foregroundColor(C.searchIcon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(C.searchBg))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if loading {
                Spacer(minLength: 0)
                ProgressView()
                Spacer(minLength: 0)
            } else if shown.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 34)).foregroundColor(C.time)
                    Text(q.isEmpty ? Tr("还没有发过文件。在聊天里发一个，这里就有了。")
                                   : Tr("没有找到这个文件"))
                        .font(pf(14)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { f in
                            Button {
                                onPick(f)
                                dismiss()
                            } label: {
                                row(f)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }

            /* 底下这颗：还是想用苹果那套文件 App 的时候点它 */
            if onSystemPicker != nil {
                Button {
                    onSystemPicker?()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 15))
                        Text(Tr("从「文件」App 里挑")).font(pf(15))
                    }
                    .foregroundColor(C.link)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.cardBg))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task { await load() }
    }

    /// 一行：文件图标（按扩展名给颜色）+ 名字 + 大小/时间/来自哪个会话
    private func row(_ f: API.MyFileItem) -> some View {
        HStack(spacing: 12) {
            Text(f.ext.isEmpty ? "FILE" : f.ext.uppercased())
                .font(pfExact(11, .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fileColor(f.ext)))
            VStack(alignment: .leading, spacing: 3) {
                Text(f.fileName)
                    .font(pf(15.5)).foregroundColor(C.label)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(sizeText(f.bytes ?? 0)).font(pf(12)).foregroundColor(C.subLabel)
                    if let c = f.chatName, !c.isEmpty {
                        Text("·").font(pf(12)).foregroundColor(C.subLabel)
                        Text((f.mine == true ? Tr("发到 ") : Tr("来自 ")) + c)
                            .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "paperplane")
                .font(.system(size: 15)).foregroundColor(C.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.cardBg))
        .contentShape(Rectangle())
    }

    private func fileColor(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "pdf": return Color(hex: 0xE0533D)
        case "doc", "docx": return Color(hex: 0x2B579A)
        case "xls", "xlsx", "csv": return Color(hex: 0x217346)
        case "ppt", "pptx": return Color(hex: 0xD24726)
        case "zip", "rar", "7z": return Color(hex: 0xB8860B)
        case "mp3", "m4a", "wav": return Color(hex: 0x8E44AD)
        case "mp4", "mov", "avi": return Color(hex: 0x1F6FB2)
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return Color(hex: 0x2E9B5B)
        case "txt", "md", "log": return Color(hex: 0x6C7A89)
        default: return Color(hex: 0x8A8A8E)
        }
    }

    private func sizeText(_ b: Int) -> String {
        if b <= 0 { return "" }
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", Double(b) / 1024) }
        return String(format: "%.1f MB", Double(b) / 1024 / 1024)
    }

    private func load() async {
        files = await API.shared.myFiles()
        loading = false
    }
}
