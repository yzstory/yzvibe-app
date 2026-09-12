import SwiftUI
import PhotosUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followsLatest = true
    @State private var nearBottom = true
    @GestureState private var draggingMessages = false
    private let bottomAnchor = "chat-bottom"
    let sessionId: String
    private var draft: String {
        get { store.chatDrafts[sessionId]?.text ?? "" }
        nonmutating set { store.chatDrafts[sessionId, default: ChatDraft()].text = newValue }
    }
    @State private var showFiles = false
    @State private var showUsage = false
    private var pending: [PendingImage] {
        get { store.chatDrafts[sessionId]?.images ?? [] }
        nonmutating set { store.chatDrafts[sessionId, default: ChatDraft()].images = newValue }
    }
    @State private var openFile: FileRef?
    @State private var showDiff = false
    @State private var showCommands = false
    @State private var newSessionSeed: String?
    @State private var confirmDelete = false

    private var session: Session? { store.session(sessionId) }
    private var subtitle: String {
        guard let s = session else { return "" }
        return [s.status.displayName, s.agent.displayName, s.folderName].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var messages: [Message] { store.messages[sessionId] ?? [] }

    var body: some View {
        ZStack {
            AmbientBackground()
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            messageList
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 24)
                            Color.clear.frame(height: 1).id(bottomAnchor)
                        }
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.frame(in: .named("chat-scroll")).maxY
                        } action: { bottom in
                            nearBottom = bottom <= viewport.size.height + 60
                            if nearBottom && !draggingMessages { followsLatest = true }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                            if followsLatest { scrollToBottom(proxy, animated: false) }
                        }
                    }
                    .coordinateSpace(name: "chat-scroll")
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(DragGesture().updating($draggingMessages) { _, state, _ in state = true })
                    .onChange(of: draggingMessages) { _, dragging in
                        if dragging { followsLatest = false }
                        else if nearBottom { followsLatest = true }
                    }
                    .onTapGesture { hideKeyboard() }
                    .onChange(of: messages.count) { _, _ in
                        if followsLatest { scrollToBottom(proxy, animated: false) }
                    }
                    .onChange(of: queued.count) { _, _ in
                        if followsLatest { scrollToBottom(proxy, animated: false) }
                    }
                    .onAppear { scrollToBottom(proxy, animated: false) }
                    .overlay(alignment: .bottomTrailing) {
                        if !nearBottom && !followsLatest {
                            Button {
                                followsLatest = true
                                scrollToBottom(proxy)
                            } label: {
                                Label("回到最新", systemImage: "arrow.down")
                                    .font(.yzFootnoteStrong)
                                    .padding(.horizontal, 16).frame(height: 44)
                                    .foregroundStyle(p.brand)
                                    .liquidGlass(in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16).padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .navigationTitle(session?.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(session?.title ?? "会话").font(.yzHeadline).lineLimit(1)
                    Text(subtitle).font(.yzCaption).foregroundStyle(p.labelSecondary).lineLimit(1)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session?.status == .running {
                    Button { Task { await store.stop(sessionId) } } label: { Image(systemName: "stop.circle") }
                        .tint(p.danger)
                        .accessibilityLabel("停止当前任务")
                }
                Button { showUsage = true } label: { UsageGauge(fraction: session?.usage?.turn.contextFraction) }
                    .accessibilityLabel("上下文用量")
                // 其余动作收进菜单：工具栏平铺五个按钮在 iOS 上会挤掉标题
                Menu {
                    Button { showDiff = true } label: { Label("改动", systemImage: "plusminus.circle") }
                    Button { showFiles = true } label: { Label("文件", systemImage: "folder") }
                    Button { showCommands = true } label: { Label("命令与 Skill", systemImage: "slash.circle") }
                    if let s = session, let m = s.model {
                        Section("当前模型") { Text(store.capabilities(for: s).label(forModel: m)) }
                    }
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删除会话", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("更多")
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
        // 上一屏（新建会话表单 / 搜索框）的键盘有时会把输入条顶在半空，进来先收掉
        .onAppear { hideKeyboard() }
        // 会话在别处被删掉时别停在空白页
        .onChange(of: session == nil) { _, gone in if gone { dismiss() } }
        .confirmationDialog("删除会话", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { Task { await store.deleteSession(sessionId) } }
        } message: {
            Text("删除后会停止此会话，并清除 YzVibe 中的消息。电脑上 Claude / Codex 的原始记录会保留，可在「我 › 会话」中重新显示；尚未保存到电脑记录的内容无法恢复。")
        }
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
                QueuedBubble(item: item, onSendNow: { await store.sendQueuedNow(item.id, in: sessionId) }, onCancel: { Task { await store.cancelQueued(item.id, in: sessionId) } })
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

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated && !reduceMotion {
            withAnimation(Motion.quick) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            InputBar(text: Binding(get: { draft }, set: { draft = $0 }), pending: Binding(get: { pending }, set: { pending = $0 }),
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
                            .onTapGesture {
                                if let image = store.attachmentImages[id] { viewing = AttachmentRef(id: id, image: image) }
                                else { Task { await store.loadAttachment(id, for: message.sessionId) } }
                            }
                    }
                }
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.yzBody)
                    .foregroundStyle(p.brandInk)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 26, bottomTrailingRadius: 10, topTrailingRadius: 26, style: .continuous)
                            .fill(p.brand)
                    )
                    .textSelection(.enabled)
            }
        }
        .fullScreenCover(item: $viewing) { ref in
            ImageViewer(image: ref.image)
        }
    }
}

struct AttachmentRef: Identifiable { let id: String; let image: UIImage }

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
                Image(uiImage: img).resizable().scaledToFit()
            } else if store.failedAttachments.contains(id) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(.headline)).foregroundStyle(p.labelTertiary)
                    Text("加载失败，点按重试").font(.yzCaption).foregroundStyle(p.labelSecondary)
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
        .onChange(of: store.lastSyncAt) { _, _ in
            if store.failedAttachments.contains(id) {
                Task { await store.loadAttachment(id, for: sessionId) }
            }
        }
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
                MarkdownText(text: message.text, onOpenFile: onOpenFile, onCopy: { _ in store.toast = "已复制代码" }, sessionId: message.sessionId)
                    .foregroundStyle(p.label).textSelection(.enabled)
            }
            if !message.toolCalls.isEmpty {
                ToolCallGroup(calls: message.toolCalls)
            }
            if message.streaming {
                HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(p.labelTertiary).frame(width: 6, height: 6) } }
            }
        }
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.surfaceElevated))
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

struct ChatDraft {
    var text = ""
    var images: [PendingImage] = []
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
                                    Image(systemName: "xmark.circle.fill").font(.system(.headline)).symbolRenderingMode(.palette)
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
                .font(.system(.callout))
                .focused($focused)
                .padding(.horizontal, 12).padding(.top, 8)
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.system(.subheadline, weight: .semibold)).foregroundStyle(p.labelSecondary)
                        .frame(width: 44, height: 44)
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
                        Image(systemName: "slash.circle").font(.system(.subheadline, weight: .semibold)).foregroundStyle(p.labelSecondary)
                            .frame(width: 44, height: 44)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onSend) {
                    Image(systemName: sendHint == .queue ? "text.line.first.and.arrowtriangle.forward" : "arrow.up")
                        .font(.system(.callout, weight: .bold)).foregroundStyle(p.brandInk)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(p.brand))
                }
                .disabled(empty)
                .opacity(empty ? 0.45 : 1)
                .accessibilityLabel(sendHint == .queue ? "排队发送" : "发送")
                .contextMenu {
                    if let onSendNow {
                        Button { onSend() } label: { Label("排队发送", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button(role: .destructive) { onSendNow() } label: { Label("立即发送（打断当前任务）", systemImage: "bolt.fill") }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                accessory().fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
    let onSendNow: () async -> Void
    @State private var sendingNow = false
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 6) {
                    if !item.text.isEmpty {
                        Text(item.text).font(.system(.callout)).foregroundStyle(p.labelSecondary).multilineTextAlignment(.trailing)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(.caption2, weight: .semibold))
                        Text(item.deliveryState == "uncertain" ? "发送结果待确认，检查历史后移除" : item.deliveryState == "dispatching" ? "正在发送" : "排队中")
                            .font(.yzCaption).fontWeight(.semibold)
                    }
                    .foregroundStyle(p.labelTertiary)
                    if item.deliveryState == "queued" {
                        Button {
                            sendingNow = true
                            Task { await onSendNow(); sendingNow = false }
                        } label: {
                            Label(sendingNow ? "正在发送…" : "立即发送", systemImage: "arrow.up")
                                .font(.yzFootnoteStrong).frame(minHeight: 44)
                        }
                        .tint(p.brand).disabled(sendingNow)
                        Text("中断当前轮并优先执行这条消息")
                            .font(.yzCaption).foregroundStyle(p.labelTertiary)
                    }
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill").font(.system(.headline))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(p.labelTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous)
                    .fill(p.fill)
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous)
                            .strokeBorder(p.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
        }
    }
}
