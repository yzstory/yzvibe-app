import SwiftUI

struct ChatActivityCard: View {
    @Environment(\.palette) private var p
    let activity: ChatActivity
    let progress: ChatRunProgress?
    let live: Bool
    var onOpenFile: ((String) -> Void)?
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingDetails = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle").font(.system(.title3)).foregroundStyle(p.labelSecondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("执行过程").font(.yzFootnoteStrong).foregroundStyle(p.label)
                        Text(activity.calls.isEmpty ? "思考记录" : "\(activity.calls.count) 次工具调用")
                            .font(.yzCaption).foregroundStyle(p.labelSecondary)
                    }
                    Spacer(minLength: 4)
                    let failures = activity.calls.filter { $0.state == .error }.count
                    if failures > 0 { Chip("\(failures) 项异常", tone: .danger) }
                    Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold)).foregroundStyle(p.labelTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开执行过程，再展开步骤查看思考、命令和子代理详情")
            Text(activity.summary).font(.yzFootnote).foregroundStyle(p.labelSecondary).lineLimit(2)
            if !activity.subagents.isEmpty {
                let running = activity.subagents.filter(\.isRunning).count
                Label(running > 0 ? "\(running) / \(activity.subagents.count) 个子代理运行中" : "\(activity.subagents.count) 个子代理",
                      systemImage: "person.2")
                    .font(.yzCaption).foregroundStyle(p.labelSecondary)
            }
            if let progress { Divider_(); ChatWaitingView(progress: progress, compact: true) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(p.surfaceElevated))
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let progress { ChatWaitingView(progress: progress) }
                        ForEach(activity.messages) { message in
                            VStack(alignment: .leading, spacing: 10) {
                                if !message.text.isEmpty {
                                    MarkdownText(text: message.text, onOpenFile: onOpenFile, sessionId: message.sessionId)
                                        .foregroundStyle(p.label).textSelection(.enabled)
                                }
                                if !message.thinking.isEmpty { ThinkingDisclosure(text: message.thinking) }
                                ForEach(message.toolCalls, id: \.id) { ToolCallCard(call: $0, live: live) }
                            }
                        }
                    }
                    .padding(Spacing.page)
                }
                .paperBackground()
                .navigationTitle("执行过程 · \(activity.calls.count) 次调用")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingDetails = false } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct ThinkingDisclosure: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(reduceMotion ? nil : Motion.quick) { expanded.toggle() } } label: {
                HStack {
                    Label("思考内容", systemImage: "text.bubble")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.yzFootnote).foregroundStyle(p.labelSecondary).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                Text(text).font(.yzFootnote).foregroundStyle(p.labelSecondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ChatWaitingView: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let progress: ChatRunProgress
    var compact = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !progress.animates || scenePhase != .active)) { timeline in
            HStack(spacing: 10) {
                if progress.animates && !reduceMotion && scenePhase == .active {
                    ProgressView().controlSize(.small).tint(p.brand).accessibilityHidden(true)
                } else {
                    Image(systemName: progress.connected ? "ellipsis" : "wifi.slash").foregroundStyle(p.brand).accessibilityHidden(true)
                }
                Text(progress.title).font(.yzFootnote).foregroundStyle(p.labelSecondary)
                Spacer(minLength: 4)
                if progress.connected {
                    Text(Self.duration(max(0, timeline.date.timeIntervalSince(progress.startedAt))))
                        .font(.yzCaption).monospacedDigit().foregroundStyle(p.labelTertiary)
                        .accessibilityLabel("已等待 " + Self.duration(max(0, timeline.date.timeIntervalSince(progress.startedAt))))
                }
            }
            .padding(compact ? 0 : 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(compact ? Color.clear : p.surfaceElevated))
        }
        .accessibilityElement(children: .combine)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return value < 60 ? "\(value) 秒" : value < 3600 ? "\(value / 60) 分 \(value % 60) 秒" : "\(value / 3600) 时 \(value / 60 % 60) 分"
    }
}

struct SubagentProgressRow: View {
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var scenePhase
    let agent: SubagentProgress
    let live: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !live || !agent.isRunning || scenePhase != .active)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(agent.name, systemImage: "person.crop.circle").font(.yzFootnoteStrong).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(agent.statusLabel).font(.yzCaption).foregroundStyle(p.labelSecondary)
                }
                if !agent.task.isEmpty { Text(agent.task).font(.yzFootnote).textSelection(.enabled) }
                if !agent.detail.isEmpty { Text(agent.detail).font(.yzCaption).foregroundStyle(p.labelSecondary).textSelection(.enabled) }
                Text("\(agent.toolCount) 次工具调用 · \(ChatWaitingView.duration(agent.elapsed(at: timeline.date, live: live)))")
                    .font(.yzCaption).monospacedDigit().foregroundStyle(p.labelTertiary)
            }
            .foregroundStyle(p.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(p.surfaceElevated))
        }
    }
}
