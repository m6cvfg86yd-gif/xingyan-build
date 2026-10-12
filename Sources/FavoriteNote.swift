import SwiftUI

/* ============================================================
   收藏里的「写笔记」（2026-10-12 加）

   收藏页右上角一颗「＋」→ 写一条笔记（纯文字，最多 2 万字）→ 存进收藏。
   存的还是同一条通道：POST /api/favorites（kind = text），所以聊天里收藏的
   文字和手写笔记在同一页混排、同一套搜索/筛选/删除，换设备也跟着账号走。

   点开一条文字收藏 = 笔记详情：全文 + 复制 + 编辑 + 删除。
   编辑走「删掉旧的那条、加一条新的」（服务端只有 POST/DELETE 两个口），
   所以改完会排到最前面。
   ============================================================ */

struct FavoriteNoteComposeSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// 编辑时：被编辑那条的 id（空 = 新建）
    let editingId: String
    /// 编辑时：原来的文字
    let initial: String
    /// 存完喊一声，收藏页重新拉一遍
    let onSaved: () -> Void

    @State private var text = ""
    @State private var busy = false
    @State private var msg = ""
    @FocusState private var focused: Bool

    init(editingId: String = "", initial: String = "", onSaved: @escaping () -> Void) {
        self.editingId = editingId
        self.initial = initial
        self.onSaved = onSaved
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: editingId.isEmpty ? Tr("写笔记") : Tr("编辑笔记"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? C.subLabel : C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(Tr("写点什么…（最多 2 万字）"))
                            .font(pf(16)).foregroundColor(C.subLabel)
                            .padding(.horizontal, 14).padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10).padding(.top, 4)
                        .focused($focused)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            HStack(spacing: 10) {
                if !msg.isEmpty {
                    Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Text(String(text.count) + " / 20000")
                    .font(pf(12)).foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 16).padding(.top, 8)

            Spacer(minLength: 0)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }

    private func save() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        busy = true
        msg = ""
        /* 标题取第一行（前 24 个字）——列表里一眼能看出这条是什么 */
        let firstLine = body.split(separator: "\n").first.map(String.init) ?? body
        let title = String(firstLine.prefix(24))
        /* 编辑 = 先删掉旧的那条，再加一条新的 */
        if !editingId.isEmpty { await API.shared.deleteFavorite(editingId) }
        let ok = await API.shared.addFavorite(kind: "text", content: body, title: title, from: "")
        busy = false
        if ok {
            DiagLog.shared.note("收藏：保存了一条笔记（" + String(body.count) + " 字）")
            onSaved()
            dismiss()
        } else {
            msg = Tr("保存失败，再试一次")
        }
    }
}

/// 点开一条文字收藏：全文 + 复制 / 编辑 / 删除
struct FavoriteNoteDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let id: String
    let content: String
    /// 改了 / 删了以后收藏页要重拉
    let onChanged: () -> Void

    @State private var editing = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("笔记"), back: { dismiss() }) {
                Button {
                    UIPasteboard.general.string = content
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Text(copied ? Tr("已复制") : Tr("复制"))
                        .font(pf(15, .medium)).foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                Text(content.isEmpty ? Tr("（空）") : content)
                    .font(pf(16))
                    .foregroundColor(C.label)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    Button { editing = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.pencil").font(.system(size: 15))
                            Text(Tr("编辑这条笔记")).font(pf(16))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(C.label)
                        .padding(.horizontal, 16).frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HairLine(inset: 16)
                    Button { Task { await remove() } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash").font(.system(size: 15))
                            Text(Tr("删除")).font(pf(16))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(C.red)
                        .padding(.horizontal, 16).frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                Spacer().frame(height: 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .sheet(isPresented: $editing) {
            FavoriteNoteComposeSheet(editingId: id, initial: content) {
                onChanged()
                dismiss()
            }
            .environmentObject(app)
        }
    }

    private func remove() async {
        await API.shared.deleteFavorite(id)
        DiagLog.shared.note("收藏：删掉了一条笔记")
        onChanged()
        dismiss()
    }
}
