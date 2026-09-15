import Foundation

public struct SubagentProgress: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var agent: String
    public var status: String
    public var task: String
    public var detail: String
    public var toolCount: Int
    public var durationMs: Double
    public var updatedAt: Date

    var isRunning: Bool { status == "running" || status == "pending" }
    var statusLabel: String {
        switch status {
        case "pending": "等待开始"
        case "running": "运行中"
        case "completed": "已完成"
        case "failed": "失败"
        case "aborted": "已中断"
        default: "状态待确认"
        }
    }
    func elapsed(at date: Date, live: Bool) -> TimeInterval {
        max(0, durationMs / 1000) + (isRunning && live ? max(0, date.timeIntervalSince(updatedAt)) : 0)
    }
}

/// A presentation-only grouping. Original message IDs, contents and approval boundaries stay intact.
enum ChatTimelineRow: Identifiable {
    case message(Message)
    case activity(ChatActivity)

    var id: String {
        switch self { case .message(let message): message.id; case .activity(let group): group.id }
    }

    static func make(_ messages: [Message], groupsMixedContent: Bool = false) -> [ChatTimelineRow] {
        var rows: [ChatTimelineRow] = []
        var pending: [Message] = []
        func flush() {
            if !pending.isEmpty { rows.append(.activity(ChatActivity(messages: pending))); pending.removeAll(keepingCapacity: true) }
        }
        for message in messages {
            let assistant = message.role == .assistant || message.role == .tool
            let emptyText = message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if assistant && emptyText && message.thinking.isEmpty && message.toolCalls.isEmpty && message.attachments.isEmpty { continue }
            if assistant && message.approvalId == nil && message.attachments.isEmpty
                && ((!message.toolCalls.isEmpty && (emptyText || groupsMixedContent)) || (emptyText && !message.thinking.isEmpty)) {
                pending.append(message)
            } else {
                flush(); rows.append(.message(message))
            }
        }
        flush()
        return rows
    }
}

struct ChatActivity: Identifiable {
    let messages: [Message]
    var id: String { "activity-" + (messages.first?.id ?? "") }
    var calls: [ToolCall] { messages.flatMap(\.toolCalls) }
    var subagents: [SubagentProgress] { calls.flatMap(\.subagents) }
    var summary: String {
        if let text = messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text { return text }
        var seen: Set<String> = []
        let names = calls.map(\.name).filter { seen.insert($0).inserted }.joined(separator: " · ")
        return names.isEmpty ? "模型提供的思考内容" : names
    }
}

struct ChatRunProgress {
    let status: SessionStatus
    let connected: Bool
    let startedAt: Date
    let calls: [ToolCall]
    let streamingText: Bool

    var animates: Bool { connected && status == .running }
    var title: String {
        if !connected { return "连接已断开，等待同步" }
        if status == .waitingApproval { return "等待你的确认" }
        let agents = calls.flatMap(\.subagents).filter(\.isRunning)
        if !agents.isEmpty { return "等待 \(agents.count) 个子代理" }
        if let tool = calls.last(where: { $0.state == .running }) { return "正在执行 \(tool.name)" }
        return streamingText ? "正在回复" : "正在等待模型回复"
    }
}
