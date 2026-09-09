import SwiftUI
import PhotosUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let sessionId: String
    @State private var draft = ""
    @State private var showFiles = false

    private var session: Session? { store.session(sessionId) }
    private var messages: [Message] { store.messages[sessionId] ?? [] }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { m in
                            MessageRow(message: m).id(m.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation(Motion.quick) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .navigationTitle(session?.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(session?.title ?? "会话").font(.yzHeadline).lineLimit(1)
                    Text("\(session?.status.displayName ?? "") · \(session?.folderName ?? "")").font(.yzCaption).foregroundStyle(p.labelSecondary)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session?.status == .running {
                    Button { Task { await store.stop(sessionId) } } label: { Image(systemName: "stop.fill").foregroundStyle(p.danger) }
                }
                Button { showFiles = true } label: { Image(systemName: "folder") }
                if let agent = session?.agent { Chip.agent(agent) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .task(id: sessionId) { await store.loadMessages(sessionId) }
        .sheet(isPresented: $showFiles) { NavigationStack { FilesView(session: session) } }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MockData.quickReplies, id: \.self) { q in
                        Button { Task { await store.send(q, in: sessionId) } } label: {
                            Text(q).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.labelSecondary)
                                .padding(.horizontal, 14).frame(height: 36).background(Capsule().fill(p.fill))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            InputBar(text: $draft, placeholder: "发消息给 \(session?.agent.displayName ?? "Agent")…", onPickImage: { data, mime, name in
                Task {
                    if let id = await store.upload(data, mime: mime, filename: name, for: sessionId) {
                        await store.send(draft.isEmpty ? "（图片）" : draft, in: sessionId, attachments: [id]); draft = ""
                    }
                }
            }) {
                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                draft = ""
                Task { await store.send(t, in: sessionId) }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }
}

/// 一条消息：用户气泡 / 助手卡 / 审批卡。
struct MessageRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let message: Message

    var body: some View {
        switch message.role {
        case .user:
            HStack { Spacer(minLength: 60); UserBubble(text: message.text) }
        case .assistant, .tool:
            HStack { AssistantBubble(message: message); Spacer(minLength: 40) }
        case .system:
            if let aid = message.approvalId, let a = store.approval(aid) {
                ApprovalCardView(approval: a, showsContext: false)
            } else if !message.text.isEmpty {
                Text(message.text).font(.yzFootnote).foregroundStyle(p.labelTertiary)
            }
        }
    }
}

struct UserBubble: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(p.brandInk)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous)
                    .fill(p.brand)
                    .shadow(color: p.brand.opacity(0.25), radius: 9, y: 6)
            )
            .textSelection(.enabled)
    }
}

struct AssistantBubble: View {
    @Environment(\.palette) private var p
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.text.isEmpty {
                Text(message.text).font(.system(size: 16)).foregroundStyle(p.label).textSelection(.enabled)
            }
            ForEach(message.toolCalls, id: \.id) { ToolCallCard(call: $0) }
            if message.streaming {
                HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(p.labelTertiary).frame(width: 6, height: 6) } }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(p.surfaceElevated)
                .shadow(color: p.shadow.opacity(0.07), radius: 10, y: 6)
        )
        .contextMenu { Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text } }
    }
}

struct ToolCallCard: View {
    @Environment(\.palette) private var p
    let call: ToolCall
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelSecondary)
                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.surfaceElevated))
            VStack(alignment: .leading, spacing: 1) {
                Text(call.name).font(.yzFootnote).fontWeight(.semibold).foregroundStyle(p.label)
                Text(call.detail).font(.yzCaption).monospaced().foregroundStyle(p.labelSecondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            switch call.state {
            case .done: Chip("完成", tone: .sage)
            case .running: ProgressView().controlSize(.small)
            case .error: Chip("失败", tone: .danger)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.fillSecondary).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
    }
}

/// 玻璃输入条：相机 + 文本 + 发送。
struct InputBar: View {
    @Environment(\.palette) private var p
    @Binding var text: String
    let placeholder: String
    var onPickImage: ((Data, String, String) -> Void)? = nil
    let onSend: () -> Void
    @FocusState private var focused: Bool
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "camera").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.labelSecondary)
                    .frame(width: 40, height: 40).background(Circle().fill(p.fill))
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
                        onPickImage?(data, isPNG ? "image/png" : "image/jpeg", isPNG ? "photo.png" : "photo.jpg")
                    }
                    pickerItem = nil
                }
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .focused($focused)
                .padding(.leading, 4)
            Button(action: onSend) {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold)).foregroundStyle(p.brandInk)
                    .frame(width: 46, height: 46)
                    .liquidGlass(in: Circle(), tint: p.brand, interactive: true)
                    .background(Circle().fill(p.brand.opacity(0.85)))
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 7)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}
