import Foundation

public struct DeliveryReceipt: Codable, Sendable {
    public var id: String
    public var itemId: String?
    public var state: String
}

public enum SendOutcome: Equatable, Sendable { case sent, queued, failed }

struct OutgoingImage: Codable, Identifiable, Sendable {
    var id = UUID()
    var data: Data
    var uploadId: String?
    var mime: String?
    var filename: String?
}

struct OutgoingMessage: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case pending, uploading, sending, uncertain, failed }
    var id = UUID().uuidString
    var deviceId: String
    var sessionId: String
    var text: String
    var images: [OutgoingImage]
    var attachments: [String] = []
    var mode: String
    var createdAt = Date()
    var state: State = .pending
    var issue: String?
    var busy: Bool { state == .uploading || state == .sending }
}

/// Persist before clearing the composer or attempting any network write.
struct OutboxDisk {
    let url: URL
    static var live: Self {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(url: root.appendingPathComponent("YzVibe/outbox.json"))
    }
    func load() throws -> [OutgoingMessage] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder.yz.decode([OutgoingMessage].self, from: Data(contentsOf: url)).map { message in
            var m = message
            if m.state == .sending { m.state = .uncertain }
            else if m.state == .uploading || m.state == .pending { m.state = .failed }
            m.issue = "上次发送未完成；重试会先核对电脑的接收记录。"
            return m
        }
    }
    func save(_ messages: [OutgoingMessage]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.yz.encode(messages).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

public struct TaskRun: Codable, Identifiable, Sendable {
    public var id: String
    public var sessionId: String
    public var status: String
    public var startedAt: Date
    public var endedAt: Date?
    public var summary: String
    public var tools: [ToolCall]
    public var files: [String]
    public var artifacts: [String]
    public var startMessageId: String? = nil
    public var messageIds: [String]? = nil
    public var statusLabel: String {
        switch status { case "running": "进行中"; case "completed": "任务已结束"; case "failed": "执行失败"; default: "执行中断 · 待确认" }
    }

    /// Only attach to explicitly recorded messages. Legacy or unloaded rounds stay in history.
    func anchorMessage(in messages: [Message]) -> String? {
        guard status != "running" else { return nil }
        let ids = Set(messageIds ?? [])
        let owned = messages.filter { $0.sessionId == sessionId && ids.contains($0.id) }
        if let reply = owned.last(where: { $0.role == .assistant }) { return reply.id }
        if let last = owned.last { return last.id }
        return messages.first { $0.sessionId == sessionId && $0.id == startMessageId }?.id
    }
}

public struct EventSnapshot: Codable, Sendable {
    public var sessions: [Session]
    public var approvals: [Approval]
    public var messages: [String: [Message]]
}

public struct ConnectorDiagnostics: Codable, Sendable {
    public struct Agent: Codable, Identifiable, Sendable {
        public var id: String
        public var available: Bool
        public var version: String?
        public var status: String
        public var authentication: String
        public var advice: String
    }
    public struct Push: Codable, Sendable { public var configured: Bool; public var registered: Bool }
    public struct Storage: Codable, Sendable { public var sessions: Int; public var pendingMessages: Int; public var uncertainMessages: Int }
    public var generatedAt: Date
    public var version: String
    public var protocolVersion: Int
    public var agents: [Agent]
    public var push: Push
    public var storage: Storage
    public var privacy: String
}

public struct EndpointCheck: Codable, Identifiable, Sendable {
    public var id: Int
    public var status: String
    public var latencyMs: Int
    public var version: String?
    // Intentionally omits URLs, device names and connector IDs from the export.
}
