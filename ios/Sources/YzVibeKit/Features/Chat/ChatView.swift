import SwiftUI
import PhotosUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let sessionId: String
    @State private var draft = ""
    @State private var showFiles = false
    @State private var showUsage = false
    @State private var pending: [PendingImage] = []

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
                .scrollDismissesKeyboard(.immediately)
                .onTapGesture { hideKeyboard() }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: messages.last?.text.count) { _, _ in scrollToBottom(proxy, animated: false) }
                .onAppear { scrollToBottom(proxy, animated: false) }
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
                Button { showUsage = true } label: { UsageGauge(fraction: session?.usage?.turn.contextFraction) }
                Button { showFiles = true } label: { Image(systemName: "folder") }
                if let s = session { Chip.agent(s.agent, suffix: s.model.map { store.capabilities(for: s).label(forModel: $0) }) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { hideKeyboard() } label: { Label("收起", systemImage: "keyboard.chevron.compact.down") }
            }
        }
        .task(id: sessionId) { await store.loadMessages(sessionId) }
        .sheet(isPresented: $showFiles) { NavigationStack { FilesView(session: session) } }
        .sheet(isPresented: $showUsage) { if let s = session { UsageSheet(sessionId: s.id).presentationDetents([.large]) } }
    }

    // 选项胶囊的绑定：本地乐观更新 + PATCH 到连接器（AppStore.patchSession）
    private var modeBinding: Binding<SessionMode> {
        Binding(get: { session?.mode ?? .normal }, set: { m in Task { await store.setMode(m, for: sessionId) } })
    }
    private var modelBinding: Binding<String?> {
        Binding(get: { session?.model }, set: { m in Task { await store.setModel(m, for: sessionId) } })
    }
    private var effortBinding: Binding<String?> {
        Binding(get: { session?.effort }, set: { e in Task { await store.setEffort(e, for: sessionId) } })
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = messages.last else { return }
        if animated { withAnimation(Motion.quick) { proxy.scrollTo(last.id, anchor: .bottom) } } else { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            InputBar(text: $draft, pending: $pending, placeholder: "发消息给 \(session?.agent.displayName ?? "Agent")…", onSend: {
                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                let images = pending
                guard !t.isEmpty || !images.isEmpty else { return }
                draft = ""; pending = []
                Task {
                    // 图片已在选择时缩到 1568px；这里逐张上传，拿到 id 后连同文字一起发
                    var ids: [String] = []
                    for img in images {
                        if let id = await store.upload(img.data, mime: "image/jpeg", filename: "photo.jpg", for: sessionId) {
                            store.cacheAttachment(img.image, id: id); ids.append(id)
                        }
                    }
                    await store.send(t, in: sessionId, attachments: ids)
                }
            }) {
                if let s = session { SessionOptionsRow(agent: s.agent, caps: store.capabilities(for: s), mode: modeBinding, model: modelBinding, effort: effortBinding) }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(stops: [.init(color: p.surface.opacity(0), location: 0), .init(color: p.surface.opacity(0.92), location: 0.35), .init(color: p.surface, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
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
            HStack { Spacer(minLength: 60); UserBubble(message: message) }
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

/// 用户气泡：图片缩略图（点开全屏）+ 文字。
struct UserBubble: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let message: Message
    @State private var viewing: AttachmentRef?

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !message.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.attachments, id: \.self) { id in
                        AttachmentThumb(id: id, sessionId: message.sessionId, size: message.attachments.count == 1 ? 200 : 110)
                            .onTapGesture { if store.attachmentImages[id] != nil { viewing = AttachmentRef(id: id) } }
                    }
                }
            }
            if !message.text.isEmpty {
                Text(message.text)
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
        .fullScreenCover(item: $viewing) { ref in
            if let img = store.attachmentImages[ref.id] { ImageViewer(image: img) }
        }
    }
}

struct AttachmentRef: Identifiable { let id: String }

/// 附件缩略图：先看本地缓存，没有就从连接器拉；拉不到显示占位。
struct AttachmentThumb: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let id: String
    let sessionId: String
    var size: CGFloat = 110

    var body: some View {
        ZStack {
            if let img = store.attachmentImages[id] {
                Image(uiImage: img).resizable().scaledToFill()
            } else if store.failedAttachments.contains(id) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 18)).foregroundStyle(p.labelTertiary)
                    Text("图片不可用").font(.yzCaption).foregroundStyle(p.labelTertiary)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .background(p.fillSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 1))
        .task(id: id) { await store.loadAttachment(id, for: sessionId) }
    }
}

struct AssistantBubble: View {
    @Environment(\.palette) private var p
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.text.isEmpty {
                MarkdownText(text: message.text).foregroundStyle(p.label).textSelection(.enabled)
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

/// 玻璃输入条：上面是文本框，下面一行是相机 + 会话选项胶囊（accessory）+ 发送。
/// 选好待发送的图片（已缩放为 JPEG）。
struct PendingImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let image: UIImage
    static func == (a: PendingImage, b: PendingImage) -> Bool { a.id == b.id }
}

struct InputBar<Accessory: View>: View {
    @Environment(\.palette) private var p
    @Binding var text: String
    @Binding var pending: [PendingImage]
    let placeholder: String
    let onSend: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    @FocusState private var focused: Bool
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var preparing = 0

    private var empty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && pending.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            if !pending.isEmpty || preparing > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pending) { img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img.image).resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Button { pending.removeAll { $0.id == img.id } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.black.opacity(0.6))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                        ForEach(0..<preparing, id: \.self) { _ in
                            ProgressView().frame(width: 72, height: 72).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.fill))
                        }
                    }
                    .padding(.horizontal, 8).padding(.top, 8)
                }
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .focused($focused)
                .padding(.horizontal, 12).padding(.top, 8)
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.labelSecondary)
                        .frame(width: 36, height: 36).background(Circle().fill(p.fill))
                }
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    pickerItems = []
                    preparing += items.count
                    Task {
                        for item in items {
                            // 选择时就缩到 1568px 长边转 JPEG：省流量、省 token，也避免原图超过 5MB 被 API 拒绝
                            if let raw = try? await item.loadTransferable(type: Data.self), let (data, _, _) = await ImagePrep.forUpload(raw), let ui = UIImage(data: data) {
                                pending.append(PendingImage(data: data, image: ui))
                            }
                            preparing = max(0, preparing - 1)
                        }
                    }
                }
                accessory()
                Spacer(minLength: 0)
                Button(action: onSend) {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(p.brandInk)
                        .frame(width: 40, height: 40)
                        .liquidGlass(in: Circle(), tint: p.brand, interactive: true)
                        .background(Circle().fill(p.brand.opacity(0.85)))
                }
                .disabled(empty)
                .opacity(empty ? 0.5 : 1)
            }
        }
        .padding(8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

extension InputBar where Accessory == EmptyView {
    init(text: Binding<String>, pending: Binding<[PendingImage]>, placeholder: String, onSend: @escaping () -> Void) {
        self.init(text: text, pending: pending, placeholder: placeholder, onSend: onSend, accessory: { EmptyView() })
    }
}
