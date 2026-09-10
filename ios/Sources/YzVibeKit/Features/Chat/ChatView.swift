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
    @State private var openFile: FileRef?
    @State private var showDiff = false
    @State private var showCommands = false
    @State private var newSessionSeed: String?

    private var session: Session? { store.session(sessionId) }
    private var messages: [Message] { store.messages[sessionId] ?? [] }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    messageList
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 140)
                }
                .scrollDismissesKeyboard(.immediately)
                .onTapGesture { hideKeyboard() }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: queued.count) { _, _ in scrollToBottom(proxy) }
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
                Button { showDiff = true } label: { Image(systemName: "plusminus.circle") }
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
        .sheet(isPresented: $showDiff) { NavigationStack { SessionDiffView(sessionId: sessionId) } }
        .sheet(isPresented: $showCommands) { CommandPaletteView(sessionId: sessionId) { run($0) } }
        .sheet(item: Binding(get: { newSessionSeed.map { FileRef(path: $0) } }, set: { if $0 == nil { newSessionSeed = nil } })) { seed in
            NewSessionView(presetCwd: session?.cwd, presetAgent: session?.agent, presetFirstMessage: seed.path.isEmpty ? nil : seed.path)
        }
        .sheet(item: $openFile) { ref in NavigationStack { FileViewerView(session: session, path: ref.path) } }
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

    @ViewBuilder
    private var messageList: some View {
        LazyVStack(spacing: 14) {
            ForEach(messages) { m in
                MessageRow(message: m, onOpenFile: { openFile = FileRef(path: $0) }).id(m.id)
            }
            // 正忙时发的消息排在这里，本轮结束会自动接上
            if session?.queuePaused == true, !queued.isEmpty {
                VStack(spacing: 8) {
                    Text("队列已暂停，请检查会话后继续").font(.yzFootnote)
                    Button("继续队列") { Task { await store.resumeQueue(in: sessionId) } }
                }
            }
            ForEach(queued) { item in
                QueuedBubble(item: item) { Task { await store.cancelQueued(item.id, in: sessionId) } }
                    .id("queued-" + item.id)
            }
        }
    }

    private var queued: [QueuedMessage] { session?.queue ?? [] }
    private var busy: Bool { session?.status == .running || session?.status == .waitingApproval }

    /// 发出去（或排队）。图片在选择时已经缩过，这里逐张上传拿 id。
    private func submit(_ mode: SendMode) {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pending
        guard !t.isEmpty || !images.isEmpty else { return }
        draft = ""; pending = []
        Task {
            var ids: [String] = []
            for img in images {
                if let id = await store.upload(img.data, mime: "image/jpeg", filename: "photo.jpg", for: sessionId) {
                    store.cacheAttachment(img.image, id: id); ids.append(id)
                }
            }
            let queued = await store.send(t, in: sessionId, attachments: ids, mode: mode)
            if queued { store.toast = session?.queuePaused == true ? "已加入暂停的队列" : "已排队，本轮结束后自动发送" }
        }
    }

    /// 命令面板选中一条：手机端命令就地执行，其余的填进输入框（Codex 的 skill 只能当提示词插进去）。
    private func run(_ cmd: SlashCommand) {
        guard cmd.isApp else {
            let prefix = cmd.insertAsText ? "参考 skill「\(cmd.name)」：" : "/\(cmd.name) "
            draft = draft.isEmpty ? prefix : draft + (draft.hasSuffix(" ") ? "" : " ") + prefix
            return
        }
        switch cmd.action {
        case "new-session": newSessionSeed = ""
        case "stop": Task { await store.stop(sessionId) }
        case "diff": showDiff = true
        case "files": showFiles = true
        case "usage": showUsage = true
        case "rules": store.toast = "在「我 › 安全 › 审批规则」里管理"
        case "model", "effort", "mode": store.toast = "在输入框上面那排胶囊里切换"
        default: store.toast = "这个命令还没实现"
        }
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
            InputBar(text: $draft, pending: $pending,
                     placeholder: busy ? "会排在当前任务后面…" : "发消息给 \(session?.agent.displayName ?? "Agent")…",
                     sendHint: busy ? .queue : .send,
                     onSend: { submit(.auto) },
                     onSendNow: busy ? { submit(.now) } : nil,
                     onCommands: { showCommands = true }) {
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

/// 聊天里点开的文件（正文里的路径链接）。
struct FileRef: Identifiable, Hashable { let path: String; var id: String { path } }

/// 一条消息：用户气泡 / 助手卡 / 审批卡。
struct MessageRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let message: Message
    var onOpenFile: ((String) -> Void)?

    var body: some View {
        switch message.role {
        case .user:
            HStack { Spacer(minLength: 60); UserBubble(message: message) }
        case .assistant, .tool:
            HStack { AssistantBubble(message: message, onOpenFile: onOpenFile); Spacer(minLength: 40) }
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
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let message: Message
    var onOpenFile: ((String) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.text.isEmpty {
                MarkdownText(text: message.text, onOpenFile: onOpenFile, onCopy: { _ in store.toast = "已复制代码" })
                    .foregroundStyle(p.label).textSelection(.enabled)
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

/// 玻璃输入条：上面是文本框，下面一行是相机 + 会话选项胶囊（accessory）+ 发送。
/// 选好待发送的图片（已缩放为 JPEG）。
struct PendingImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let image: UIImage
    static func == (a: PendingImage, b: PendingImage) -> Bool { a.id == b.id }
}

struct InputBar<Accessory: View>: View {
    enum SendHint { case send, queue }
    @Environment(\.palette) private var p
    @Binding var text: String
    @Binding var pending: [PendingImage]
    let placeholder: String
    var sendHint: SendHint = .send
    let onSend: () -> Void
    /// 非空时长按发送键可以插队并打断当前这一轮。
    var onSendNow: (() -> Void)? = nil
    var onCommands: (() -> Void)? = nil
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
                if let onCommands {
                    Button(action: onCommands) {
                        Image(systemName: "slash.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.labelSecondary)
                            .frame(width: 36, height: 36).background(Circle().fill(p.fill))
                    }
                }
                accessory()
                Spacer(minLength: 0)
                Button(action: onSend) {
                    Image(systemName: sendHint == .queue ? "text.line.first.and.arrowtriangle.forward" : "arrow.up")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(p.brandInk)
                        .frame(width: 40, height: 40)
                        .liquidGlass(in: Circle(), tint: p.brand, interactive: true)
                        .background(Circle().fill(p.brand.opacity(0.85)))
                }
                .disabled(empty)
                .opacity(empty ? 0.5 : 1)
                .contextMenu {
                    if let onSendNow {
                        Button { onSend() } label: { Label("排队发送", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button(role: .destructive) { onSendNow() } label: { Label("立即发送（打断当前任务）", systemImage: "bolt.fill") }
                    }
                }
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

/// 排队中的消息：本轮结束会自动发出去，点 × 可以撤掉。
struct QueuedBubble: View {
    @Environment(\.palette) private var p
    let item: QueuedMessage
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 6) {
                    if !item.text.isEmpty {
                        Text(item.text).font(.system(size: 16)).foregroundStyle(p.labelSecondary).multilineTextAlignment(.trailing)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                        Text(item.deliveryState == "uncertain" ? "发送结果待确认，检查历史后移除" : item.deliveryState == "dispatching" ? "正在发送" : "排队中")
                            .font(.yzCaption).fontWeight(.semibold)
                    }
                    .foregroundStyle(p.labelTertiary)
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(p.labelTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous)
                    .fill(p.fill)
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous)
                            .strokeBorder(p.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
        }
    }
}
