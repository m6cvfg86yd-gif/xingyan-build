import SwiftUI
import UIKit

/* ============================================================
   聊天背景 · 黑白场景的基础背景（6 张）

   · 图片放在服务器的 public/bg 下（/bg/bw1.jpg … bw6.jpg），
     想换图/加图只改服务器上的文件，不用重新出包；
   · 点一张立刻生效（写进 me.chatBackground，聊天页那一层会跟着换）；
   · 下面还留着原来那两条老入口：默认背景 / 从相册选一张。
   · **在聊天页右上「⋯」里进来时**（chatId 有值）：只改**这一个会话**的背景，
     和微信一样（微信也是「设置当前聊天背景」只对当前聊天生效，存在本机）。
   ============================================================ */

/// 每个会话单独设的聊天背景（只存本机，和微信一样）
final class ChatBgStore: ObservableObject {
    static let shared = ChatBgStore()
    /// 变了就 +1：聊天页那一层跟着刷新
    @Published private(set) var version = 0

    private func key(_ chatId: String) -> String { "chris.chatBg." + chatId }

    /// 这个会话单独设的背景（空 = 用全局的）
    func get(_ chatId: String) -> String {
        guard !chatId.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: key(chatId)) ?? ""
    }

    func set(_ chatId: String, _ value: String) {
        guard !chatId.isEmpty else { return }
        if value.isEmpty || value == "auto" {
            UserDefaults.standard.removeObject(forKey: key(chatId))
        } else {
            UserDefaults.standard.set(value, forKey: key(chatId))
        }
        version += 1
    }
}

struct ChatBackgroundSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 有值 = 在某个聊天里点「⋯ → 设置当前聊天背景」进来的：只改这个会话
    var chatId: String = ""

    @State private var picking = false
    @State private var busy = false

    /// 6 张基础背景（黑白/灰阶）
    static let presets: [String] = ["/bg/bw1.jpg", "/bg/bw2.jpg", "/bg/bw3.jpg",
                                    "/bg/bw4.jpg", "/bg/bw5.jpg", "/bg/bw6.jpg"]
    /// 每张下面那行小字（方便一眼分清是哪张）
    static let names: [String] = ["浅灰渐变", "深灰渐变", "细斜纹", "细网格", "磨砂噪点", "同心圆"]

    private var inChat: Bool { !chatId.isEmpty }
    @ObservedObject private var store = ChatBgStore.shared
    /// 现在选中的是哪一张（聊天里=本机给这个会话设的；全局=我资料里的）
    private var current: String {
        if inChat {
            let v = store.get(chatId)
            return v.isEmpty ? "auto" : v
        }
        return app.me?.chatBackground ?? "auto"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Tr("基础背景 · 黑白场景"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                              spacing: 12) {
                        ForEach(Array(Self.presets.enumerated()), id: \.offset) { idx, p in
                            Button { pick(p) } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        RemoteImage(path: p, mode: .fill)
                                            .frame(width: 100, height: 148)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        if current == p {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(C.green, lineWidth: 2.5)
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 19))
                                                .foregroundColor(C.green)
                                                .padding(5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                                       alignment: .topTrailing)
                                        }
                                    }
                                    Text(Tr(Self.names[min(idx, Self.names.count - 1)]))
                                        .font(pf(11.5))
                                        .foregroundColor(C.subLabel)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    Rectangle().fill(C.pageBg).frame(height: 8).padding(.top, 12)

                    VStack(spacing: 0) {
                        Button { pick("auto") } label: {
                            HStack {
                                Text(inChat ? Tr("使用全局背景") : Tr("默认背景"))
                                    .font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                if current == "auto" {
                                    Image(systemName: "checkmark").foregroundColor(C.green)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !inChat {
                        HairLine(inset: 16)

                        Button { picking = true } label: {
                            HStack {
                                Text(Tr("从相册选一张")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(C.subLabel)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        }
                    }
                    .background(C.cardBg)

                    if busy {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 14)
                    }
                }
                .padding(.bottom, 26)
            }
            .background(C.pageBg)
            .navigationTitle(Tr(inChat ? "选择背景图" : "聊天背景"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("完成")) { dismiss() }
                        .foregroundColor(C.label)
                }
            }
        }
        .sheet(isPresented: $picking) {
            PhotoPicker { image in upload(image) }
        }
    }

    /// 点一张基础背景：立刻写进我的资料（聊天页那一层会重新加载）
    private func pick(_ path: String) {
        /* 聊天页进来的：只改这一个会话（存本机，和微信一样） */
        if inChat {
            ChatBgStore.shared.set(chatId, path)
            app.show(path == "auto" ? Tr("已改用全局背景") : Tr("这个聊天的背景换好了"))
            return
        }
        Task {
            busy = true
            await API.shared.changeBackground(path)
            app.me = try? await API.shared.me()
            busy = false
        }
    }

    /// 从相册选一张：还是走原来那套（原图上传 → 当成背景）
    private func upload(_ image: UIImage) {
        Task {
            busy = true
            if let url = try? await API.shared.uploadOriginal(image: image) {
                await API.shared.changeBackground(url)
                app.me = try? await API.shared.me()
                app.show(Tr("聊天背景换好了"))
            }
            busy = false
        }
    }
}
