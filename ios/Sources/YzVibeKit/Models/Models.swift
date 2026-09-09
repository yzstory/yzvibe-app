import Foundation

// 与 shared/protocol.md 的数据模型一一对应，三端共用同一份字段。

public enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    case tunnel, local, p2p, tailscale, relay
    public var displayName: String {
        switch self {
        case .tunnel: "Cloudflare Tunnel"
        case .local: "局域网"
        case .p2p: "P2P 直连"
        case .tailscale: "Tailscale"
        case .relay: "自定义 Relay"
        }
    }
}

public enum AgentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex, custom
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .claude: "Claude"; case .codex: "Codex"; case .custom: "自定义" }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case idle, running, waitingApproval = "waiting_approval", error, closed
    public var displayName: String {
        switch self {
        case .idle: "空闲"; case .running: "运行中"; case .waitingApproval: "待审批"; case .error: "出错"; case .closed: "已结束"
        }
    }
}

public struct Device: Identifiable, Codable, Hashable, Sendable {
    /// 与连接器 DEFAULT_PORT 一致（9876 常被 Vibelet 等占用）。
    public static let defaultPort = 19876
    public var id: String
    public var name: String
    public var host: String
    public var port: Int
    public var mode: ConnectionMode
    public var online: Bool
    public var lastSeen: Date
    public var sessionCount: Int
    public var agents: [AgentKind: Int]

    public init(id: String = UUID().uuidString, name: String, host: String, port: Int = Device.defaultPort, mode: ConnectionMode,
                online: Bool = false, lastSeen: Date = .now, sessionCount: Int = 0, agents: [AgentKind: Int] = [:]) {
        self.id = id; self.name = name; self.host = host; self.port = port; self.mode = mode
        self.online = online; self.lastSeen = lastSeen; self.sessionCount = sessionCount; self.agents = agents
    }

    public var endpoint: String { host.contains("://") ? host : "\(host):\(port)" }
    public var baseURL: URL? {
        if host.contains("://") { return URL(string: host) }
        return URL(string: "http://\(host):\(port)")
    }
}

public struct Session: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var deviceId: String
    public var agent: AgentKind
    public var cwd: String
    public var title: String
    public var status: SessionStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var pendingApprovals: Int

    public init(id: String = UUID().uuidString, deviceId: String, agent: AgentKind, cwd: String, title: String,
                status: SessionStatus = .idle, createdAt: Date = .now, updatedAt: Date = .now, pendingApprovals: Int = 0) {
        self.id = id; self.deviceId = deviceId; self.agent = agent; self.cwd = cwd; self.title = title
        self.status = status; self.createdAt = createdAt; self.updatedAt = updatedAt; self.pendingApprovals = pendingApprovals
    }

    /// 工作目录最后一段，用于分组标题。
    public var folderName: String { (cwd as NSString).lastPathComponent }

    enum CodingKeys: String, CodingKey { case id, deviceId, agent, cwd, title, status, createdAt, updatedAt, pendingApprovals }
    /// 连接器返回的 JSON 不带 deviceId，agent 也可能是未知字符串（如 mock），这里都做容错。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        agent = AgentKind(rawValue: try c.decodeIfPresent(String.self, forKey: .agent) ?? "") ?? .custom
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "会话"
        status = SessionStatus(rawValue: try c.decodeIfPresent(String.self, forKey: .status) ?? "") ?? .idle
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        pendingApprovals = try c.decodeIfPresent(Int.self, forKey: .pendingApprovals) ?? 0
    }
}

public enum MessageRole: String, Codable, Sendable { case user, assistant, tool, system }

public struct ToolCall: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable { case running, done, error }
    public var id: String
    public var name: String
    public var detail: String
    public var state: State
    public init(id: String = UUID().uuidString, name: String, detail: String, state: State) {
        self.id = id; self.name = name; self.detail = detail; self.state = state
    }
}

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sessionId: String
    public var role: MessageRole
    public var text: String
    public var attachments: [String]
    public var toolCalls: [ToolCall]
    public var approvalId: String?
    public var createdAt: Date
    public var streaming: Bool

    public init(id: String = UUID().uuidString, sessionId: String, role: MessageRole, text: String, attachments: [String] = [],
                toolCalls: [ToolCall] = [], approvalId: String? = nil, createdAt: Date = .now, streaming: Bool = false) {
        self.id = id; self.sessionId = sessionId; self.role = role; self.text = text; self.attachments = attachments
        self.toolCalls = toolCalls; self.approvalId = approvalId; self.createdAt = createdAt; self.streaming = streaming
    }

    enum CodingKeys: String, CodingKey { case id, sessionId, role, text, attachments, toolCalls, approvalId, createdAt, streaming }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        role = MessageRole(rawValue: try c.decodeIfPresent(String.self, forKey: .role) ?? "") ?? .assistant
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        attachments = try c.decodeIfPresent([String].self, forKey: .attachments) ?? []
        toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls) ?? []
        approvalId = try c.decodeIfPresent(String.self, forKey: .approvalId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        streaming = try c.decodeIfPresent(Bool.self, forKey: .streaming) ?? false
    }
}

public enum ApprovalKind: String, Codable, Sendable {
    case shell, write, network, other
    public var displayName: String {
        switch self { case .shell: "执行 Shell 命令"; case .write: "写入文件"; case .network: "访问网络"; case .other: "调用工具" }
    }
    public var symbol: String {
        switch self { case .shell: "terminal"; case .write: "doc.badge.plus"; case .network: "network"; case .other: "wrench.and.screwdriver" }
    }
}

public enum RiskLevel: String, Codable, Sendable {
    case low, medium, high
    public var displayName: String { switch self { case .low: "低风险"; case .medium: "中风险"; case .high: "高风险" } }
}

public enum ApprovalDecision: String, Codable, Sendable { case allow, deny, allowOnce = "allow_once" }

public struct Approval: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, allowed, denied, expired }
    public var id: String
    public var sessionId: String
    public var deviceId: String
    public var kind: ApprovalKind
    public var summary: String
    public var detail: String
    public var risk: RiskLevel
    public var status: Status
    public var createdAt: Date
    public var expiresAt: Date?

    public init(id: String = UUID().uuidString, sessionId: String, deviceId: String, kind: ApprovalKind, summary: String,
                detail: String, risk: RiskLevel, status: Status = .pending, createdAt: Date = .now, expiresAt: Date? = nil) {
        self.id = id; self.sessionId = sessionId; self.deviceId = deviceId; self.kind = kind; self.summary = summary
        self.detail = detail; self.risk = risk; self.status = status; self.createdAt = createdAt; self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey { case id, approvalId, sessionId, deviceId, kind, summary, detail, risk, status, createdAt, expiresAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .approvalId) ?? c.decode(String.self, forKey: .id)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        kind = ApprovalKind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .other
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? summary
        risk = RiskLevel(rawValue: try c.decodeIfPresent(String.self, forKey: .risk) ?? "") ?? .medium
        status = Status(rawValue: try c.decodeIfPresent(String.self, forKey: .status) ?? "") ?? .pending
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(sessionId, forKey: .sessionId); try c.encode(deviceId, forKey: .deviceId)
        try c.encode(kind, forKey: .kind); try c.encode(summary, forKey: .summary); try c.encode(detail, forKey: .detail)
        try c.encode(risk, forKey: .risk); try c.encode(status, forKey: .status); try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

public struct FileEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case folder, code, markdown, image, other }
    public var id: String { path }
    public var name: String
    public var path: String
    public var kind: Kind
    public var size: Int
    public var modifiedAt: Date
    public var badge: String?
    public init(name: String, path: String, kind: Kind, size: Int = 0, modifiedAt: Date = .now, badge: String? = nil) {
        self.name = name; self.path = path; self.kind = kind; self.size = size; self.modifiedAt = modifiedAt; self.badge = badge
    }
    enum CodingKeys: String, CodingKey { case name, path, kind, size, modifiedAt, badge }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? name
        kind = Kind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .other
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .now
        badge = try c.decodeIfPresent(String.self, forKey: .badge)
    }
}

/// 新建会话表单。
public struct NewSessionRequest: Codable, Sendable {
    public var agent: AgentKind
    public var cwd: String
    public var firstMessage: String?
    public var continueLast: Bool
    public var yolo: Bool
    public init(agent: AgentKind = .claude, cwd: String = "", firstMessage: String? = nil, continueLast: Bool = true, yolo: Bool = false) {
        self.agent = agent; self.cwd = cwd; self.firstMessage = firstMessage; self.continueLast = continueLast; self.yolo = yolo
    }
}

// MARK: - 配对链接 yzvibe://pair?host=…&port=…&token=…&mode=…&name=…

public struct PairingPayload: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var token: String
    public var mode: ConnectionMode
    public var name: String?

    public init(host: String, port: Int = Device.defaultPort, token: String, mode: ConnectionMode = .tunnel, name: String? = nil) {
        self.host = host; self.port = port; self.token = token; self.mode = mode; self.name = name
    }

    /// 解析二维码内容；不合法返回 nil。
    public init?(qrString: String) {
        guard let comps = URLComponents(string: qrString), comps.scheme == "yzvibe", comps.host == "pair" else { return nil }
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let host = q["host"], !host.isEmpty, let token = q["token"], !token.isEmpty else { return nil }
        self.host = host
        self.port = Int(q["port"] ?? "") ?? Device.defaultPort
        self.token = token
        self.mode = ConnectionMode(rawValue: q["mode"] ?? "") ?? .tunnel
        self.name = q["name"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - 相对时间

public enum RelativeTime {
    public static func string(from date: Date, now: Date = .now) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60) 分钟前" }
        if s < 86400 { return "\(s / 3600) 小时前" }
        return "\(s / 86400) 天前"
    }
}
