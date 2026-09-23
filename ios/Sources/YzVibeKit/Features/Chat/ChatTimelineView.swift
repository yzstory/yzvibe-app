import SwiftUI

/// Isolates message observation and scrolling from draft/toolbar updates.
struct ChatTimelineView: View, Equatable {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sessionId: String
    let latestRequest: Int
    @Binding var openFile: FileRef?

    // The binding always belongs to this chat's parent. Store/environment changes
    // still invalidate this view independently of the parent's draft updates.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionId == rhs.sessionId && lhs.latestRequest == rhs.latestRequest
    }

    @State private var pendingScroll: Task<Void, Never>?
    @State private var followsLatest = true
    @State private var nearBottom = true
    @GestureState private var draggingMessages = false
    private let bottomAnchor = "chat-bottom"
    private var session: Session? { store.session(sessionId) }
    private var outgoingCount: Int { store.outbox.filter { $0.sessionId == sessionId }.count }
    struct ScrollUpdate: Equatable {
        var lastMessage: Message?
        var count: Int
        var queueCount: Int
        var outboxCount: Int
        var viewportHeight: CGFloat
        var request: Int
        var followsLatest: Bool
    }
    private var messages: [Message] { store.messages[sessionId] ?? [] }
    @State private var firstVisibleMessageID: String?
    private var visibleMessages: [Message] {
        if let firstVisibleMessageID, let start = messages.firstIndex(where: { $0.id == firstVisibleMessageID }) {
            return Array(messages[start...])
        }
        return Array(messages.suffix(80))
    }
    @State private var historyAnchor: String?
    private var timeline: [ChatTimelineRow] { ChatTimelineRow.make(visibleMessages, groupsMixedContent: session?.agent == .omp) }
    private var runProgress: ChatRunProgress? {
        guard let session, busy else { return nil }
        let start = messages.lastIndex(where: { $0.role == .user }) ?? messages.startIndex
        let current = messages.suffix(from: start)
        return ChatRunProgress(status: session.status, connected: store.device(session.deviceId)?.online == true,
            startedAt: current.first?.createdAt ?? session.updatedAt, calls: current.flatMap(\.toolCalls),
            streamingText: current.contains { $0.streaming && !$0.text.isEmpty })
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                List {
                    messageList
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
                .coordinateSpace(name: "chat-scroll")
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(DragGesture().updating($draggingMessages) { _, state, _ in state = true })
                .onChange(of: draggingMessages) { _, dragging in
                    if dragging { followsLatest = false }
                    else if nearBottom { followsLatest = true }
                }
                .onTapGesture { hideKeyboard() }
                .onChange(of: latestRequest) { _, _ in followsLatest = true }
                .onAppear { firstVisibleMessageID = visibleMessages.first?.id }
                .onChange(of: messages.first?.id) { _, _ in
                    if firstVisibleMessageID == nil { firstVisibleMessageID = visibleMessages.first?.id }
                }
                .task(id: historyAnchor) {
                    guard let historyAnchor else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(historyAnchor, anchor: .top)
                    self.historyAnchor = nil
                }
                // Coalesce streaming bursts without postponing scrolling indefinitely.
                // UIKit's reusable list commits its row layout before this request runs.
                .onChange(of: ScrollUpdate(lastMessage: messages.last, count: messages.count,
                                           queueCount: queued.count, outboxCount: outgoingCount,
                                           viewportHeight: viewport.size.height, request: latestRequest,
                                           followsLatest: followsLatest), initial: true) { _, _ in
                    guard followsLatest, pendingScroll == nil else { return }
                    pendingScroll = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                        pendingScroll = nil
                        guard followsLatest, !draggingMessages else { return }
                        scrollToBottom(proxy, animated: false)
                    }
                }
                .onDisappear {
                    pendingScroll?.cancel()
                    pendingScroll = nil
                }
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

    @ViewBuilder
    private var messageList: some View {
        Group {
            if messages.count > visibleMessages.count {
                Button("加载更早的消息（还有 \(messages.count - visibleMessages.count) 条）") {
                    followsLatest = false
                    historyAnchor = timeline.first?.id
                    firstVisibleMessageID = messages.suffix(visibleMessages.count + 80).first?.id
                }.font(.yzFootnote)
            }
            if store.loadingMessages.contains(sessionId), !messages.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在同步历史…").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                }
            }
            let rows = timeline
            ForEach(rows) { row in
                timelineRow(row, lastID: rows.last?.id).id(row.id)
            }
            if let progress = runProgress {
                if case .activity = rows.last {} else {
                    HStack { ChatWaitingView(progress: progress); Spacer(minLength: 24) }
                }
            }
            ForEach(store.outbox.filter { $0.sessionId == sessionId }) { item in
                OutgoingMessageCard(item: item,
                                    retry: { Task { await store.transmit(item.id) } },
                                    restore: { store.restoreOutgoing(item.id) })
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
            Color.clear.frame(height: 1).id(bottomAnchor)
                .onAppear {
                    nearBottom = true
                    if !draggingMessages { followsLatest = true }
                }
                .onDisappear { nearBottom = false }
        }

    }

    @ViewBuilder
    private func timelineRow(_ row: ChatTimelineRow, lastID: String?) -> some View {
                switch row {
                case .message(let m):
                    MessageRow(message: m, onOpenFile: { openFile = FileRef(path: $0) }).id(m.id)
                case .activity(let group):
                    HStack {
                        ChatActivityCard(activity: group, progress: row.id == lastID ? runProgress : nil,
                            live: busy && store.device(session?.deviceId ?? "")?.online == true,
                            onOpenFile: { openFile = FileRef(path: $0) })
                        Spacer(minLength: 24)
                    }
                }
    }

    private var queued: [QueuedMessage] { session?.queue ?? [] }
    private var busy: Bool { session?.status == .running || session?.status == .waitingApproval }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated && !reduceMotion {
            withAnimation(Motion.quick) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        }
    }

}
