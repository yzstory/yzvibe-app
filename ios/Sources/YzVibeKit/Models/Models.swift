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

/// 会话模式：三端统一叫 Plan / Normal / Trust，连接器按 Agent 翻译成各自的命令行参数。
public enum SessionMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case plan, normal, trust
    public var id: String { rawValue }
    public var displayName: String { switch self { case .plan: "Plan"; case .normal: "Normal"; case .trust: "Trust" } }
    public var subtitle: String { switch self { case .plan: "只规划"; case .normal: "需审批"; case .trust: "完全信任" } }
    public var symbol: String { switch self { case .plan: "list.bullet.clipboard"; case .normal: "checkmark.shield"; case .trust: "bolt.fill" } }
}

/// 思考强度只是字符串（Claude / Codex 的档位不完全一样），这里只负责显示名。
public enum EffortLevel {
    public static func displayName(_ raw: String?) -> String {
        switch raw {
        case nil, "": "默认"
        case "low": "低"; case "medium": "中"; case "high": "高"; case "xhigh": "极高"; case "max": "最大"; case "ultra": "Ultra"
        default: raw!
        }
    }
}

/// 一个模型选项（连接器 GET /agents 返回；也可能是用户自定义的）。
public struct ModelOption: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?
    public var efforts: [String]?
    public var defaultEffort: String?
    public init(id: String, label: String? = nil, description: String? = nil, efforts: [String]? = nil, defaultEffort: String? = nil) {
        self.id = id; self.label = label ?? id; self.description = description; self.efforts = efforts; self.defaultEffort = defaultEffort
    }
}

/// 某种 Agent 支持的模式 / 模型 / 思考强度（GET /agents）。连接器不可达或版本较旧时用 `fallback(for:)`。
public struct AgentCapabilities: Codable, Hashable, Sendable {
    public struct ModeInfo: Codable, Hashable, Sendable {
        public var flag: String
        public var description: String
        public init(flag: String, description: String) { self.flag = flag; self.description = description }
    }
    public var modes: [String: ModeInfo]
    public var efforts: [String]
    public var models: [ModelOption]
    public var customModel: Bool

    public init(modes: [String: ModeInfo], efforts: [String], models: [ModelOption], customModel: Bool = true) {
        self.modes = modes; self.efforts = efforts; self.models = models; self.customModel = customModel
    }
    enum CodingKeys: String, CodingKey { case modes, efforts, models, customModel }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modes = try c.decodeIfPresent([String: ModeInfo].self, forKey: .modes) ?? [:]
        efforts = try c.decodeIfPresent([String].self, forKey: .efforts) ?? []
        models = try c.decodeIfPresent([ModelOption].self, forKey: .models) ?? []
        customModel = try c.decodeIfPresent(Bool.self, forKey: .customModel) ?? true
    }

    public func modeInfo(_ mode: SessionMode) -> ModeInfo? { modes[mode.rawValue] }
    /// 该模型支持的档位；目录没写就用 Agent 通用档位。
    public func efforts(for model: String?) -> [String] {
        if let model, let m = models.first(where: { $0.id == model }), let e = m.efforts, !e.isEmpty { return e }
        return efforts
    }
    public func label(forModel id: String?) -> String {
        guard let id, !id.isEmpty else { return "默认模型" }
        return models.first { $0.id == id }?.label ?? id
    }

    public static func fallback(for agent: AgentKind) -> AgentCapabilities {
        switch agent {
        case .codex:
            return AgentCapabilities(
                modes: ["plan": .init(flag: "sandbox_mode=read-only", description: "只读沙箱，只分析与规划，不改文件"),
                        "normal": .init(flag: "approvalPolicy=on-request · workspace-write", description: "工作目录内自动执行；需要额外权限时发到手机审批"),
                        "trust": .init(flag: "--dangerously-bypass-approvals-and-sandbox", description: "无沙箱、无确认，完全信任")],
                efforts: ["low", "medium", "high", "xhigh", "max"],
                models: [ModelOption(id: "gpt-5.6-sol", label: "GPT-5.6 Sol"), ModelOption(id: "gpt-5.6-terra", label: "GPT-5.6 Terra"),
                         ModelOption(id: "gpt-5.6-luna", label: "GPT-5.6 Luna"), ModelOption(id: "gpt-5.5", label: "GPT-5.5")])
        case .claude, .custom:
            return AgentCapabilities(
                modes: ["plan": .init(flag: "--permission-mode plan", description: "只读分析并给出计划，批准计划后才开始改动"),
                        "normal": .init(flag: "--permission-prompt-tool", description: "敏感操作发到手机审批"),
                        "trust": .init(flag: "--dangerously-skip-permissions", description: "跳过所有权限检查，不再产生审批")],
                efforts: ["low", "medium", "high", "xhigh", "max"],
                models: [ModelOption(id: "claude-fable-5-1", label: "Fable 5.1"), ModelOption(id: "claude-opus-5", label: "Opus 5"),
                         ModelOption(id: "claude-sonnet-5", label: "Sonnet 5"), ModelOption(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5")])
        }
    }
}

/// 一轮的 token 用量（连接器已把 Claude / Codex 归一）。上下文口径 = input + cacheWrite + cacheRead。
public struct TurnUsage: Codable, Hashable, Sendable {
    public var model: String?
    public var input: Int
    public var cacheWrite: Int
    public var cacheRead: Int
    public var output: Int
    public var thinking: Int
    public var contextTokens: Int?
    public var contextWindow: Int?
    public var costUSD: Double?
    public var durationMs: Int?
    public init(model: String? = nil, input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0, thinking: Int = 0,
                contextTokens: Int? = nil, contextWindow: Int? = nil, costUSD: Double? = nil, durationMs: Int? = nil) {
        self.model = model; self.input = input; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead; self.output = output; self.thinking = thinking
        self.contextTokens = contextTokens; self.contextWindow = contextWindow; self.costUSD = costUSD; self.durationMs = durationMs
    }
    enum CodingKeys: String, CodingKey { case model, input, cacheWrite, cacheRead, output, thinking, contextTokens, contextWindow, costUSD, durationMs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        thinking = try c.decodeIfPresent(Int.self, forKey: .thinking) ?? 0
        contextTokens = try c.decodeIfPresent(Int.self, forKey: .contextTokens)
        contextWindow = try c.decodeIfPresent(Int.self, forKey: .contextWindow)
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
    }
    /// 送进模型的总输入。
    public var totalInput: Int { input + cacheWrite + cacheRead }
    public var contextFraction: Double? {
        guard let t = contextTokens, let w = contextWindow, w > 0 else { return nil }
        return min(1, Double(t) / Double(w))
    }
}

/// 会话累计用量。
public struct TotalUsage: Codable, Hashable, Sendable {
    public var input: Int
    public var cacheWrite: Int
    public var cacheRead: Int
    public var output: Int
    public var thinking: Int
    public var costUSD: Double?
    public var turns: Int
    public init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0, thinking: Int = 0, costUSD: Double? = nil, turns: Int = 0) {
        self.input = input; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead; self.output = output; self.thinking = thinking; self.costUSD = costUSD; self.turns = turns
    }
    enum CodingKeys: String, CodingKey { case input, cacheWrite, cacheRead, output, thinking, costUSD, turns }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        thinking = try c.decodeIfPresent(Int.self, forKey: .thinking) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
        turns = try c.decodeIfPresent(Int.self, forKey: .turns) ?? 0
    }
}

public struct SessionUsage: Codable, Hashable, Sendable {
    public var model: String?
    public var turn: TurnUsage
    public var total: TotalUsage
    public var updatedAt: Date?
    public init(model: String? = nil, turn: TurnUsage, total: TotalUsage, updatedAt: Date? = nil) { self.model = model; self.turn = turn; self.total = total; self.updatedAt = updatedAt }
    enum CodingKeys: String, CodingKey { case model, turn, total, updatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        turn = try c.decodeIfPresent(TurnUsage.self, forKey: .turn) ?? TurnUsage()
        total = try c.decodeIfPresent(TotalUsage.self, forKey: .total) ?? TotalUsage()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// 账号额度（GET /quota）。Claude 来自 api/oauth/usage，含 5 小时 / 本周 / 本周 Fable 等窗口。
public struct QuotaLimit: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var percent: Int
    public var resetsAt: Date?
    public init(id: String, label: String, percent: Int, resetsAt: Date? = nil) { self.id = id; self.label = label; self.percent = percent; self.resetsAt = resetsAt }
}

public struct QuotaInfo: Codable, Hashable, Sendable {
    public struct ExtraUsage: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var usedCredits: Double
        public var monthlyLimit: Double?
        public var percent: Int
        public var currency: String
    }
    public var agent: String
    public var source: String
    public var fetchedAt: Date?
    public var limits: [QuotaLimit]
    public var extraUsage: ExtraUsage?
    public var error: String?
    public var warning: String?
    public var unavailable: String?
    public init(agent: String, source: String = "none", fetchedAt: Date? = nil, limits: [QuotaLimit] = [], extraUsage: ExtraUsage? = nil, error: String? = nil, warning: String? = nil, unavailable: String? = nil) {
        self.agent = agent; self.source = source; self.fetchedAt = fetchedAt; self.limits = limits; self.extraUsage = extraUsage; self.error = error; self.warning = warning; self.unavailable = unavailable
    }
    enum CodingKeys: String, CodingKey { case agent, source, fetchedAt, limits, extraUsage, error, warning, unavailable }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? "claude"
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "none"
        fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt)
        limits = try c.decodeIfPresent([QuotaLimit].self, forKey: .limits) ?? []
        extraUsage = try c.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        warning = try c.decodeIfPresent(String.self, forKey: .warning)
        unavailable = try c.decodeIfPresent(String.self, forKey: .unavailable)
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
    /// 这台电脑的所有可达地址（隧道 / Tailscale / 局域网）。主地址连不上时依次试，
    /// 所以 Cloudflare 临时隧道换地址、电脑重启之后不必重新扫码。
    public var endpoints: [String] = []

    public init(id: String = UUID().uuidString, name: String, host: String, port: Int = Device.defaultPort, mode: ConnectionMode,
                online: Bool = false, lastSeen: Date = .now, sessionCount: Int = 0, agents: [AgentKind: Int] = [:], endpoints: [String] = []) {
        self.id = id; self.name = name; self.host = host; self.port = port; self.mode = mode
        self.online = online; self.lastSeen = lastSeen; self.sessionCount = sessionCount; self.agents = agents; self.endpoints = endpoints
    }

    /// 换一个主地址（故障转移成功，或收到推送下发的新地址时）。
    public mutating func adopt(base: String) {
        guard let u = URL(string: base), let h = u.host else { return }
        if u.scheme == "https" { host = base.hasSuffix("/") ? String(base.dropLast()) : base }
        else { host = h; port = u.port ?? Device.defaultPort }
        endpoints.removeAll { $0 == base }
        endpoints.insert(base, at: 0)
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
    public var runStartedAt: Date? = nil
    public var pendingApprovals: Int
    public var mode: SessionMode
    public var model: String?
    public var effort: String?
    public var usage: SessionUsage?
    /// phone = 手机建的；terminal = 电脑终端里跑过的；sdk = 其他工具以 SDK/headless 方式跑的
    public var source: SessionSource
    public var branch: String?
    /// Agent 正忙时发的消息排在这里，本轮结束自动接上。
    public var queue: [QueuedMessage] = []
    public var queuePaused: Bool = false
    /// 会话开始时的 commit，用来只看「这次会话改了什么」。
    public var baseCommit: String?

    public init(id: String = UUID().uuidString, deviceId: String, agent: AgentKind, cwd: String, title: String,
                status: SessionStatus = .idle, createdAt: Date = .now, updatedAt: Date = .now, pendingApprovals: Int = 0,
                mode: SessionMode = .normal, model: String? = nil, effort: String? = nil, usage: SessionUsage? = nil,
                source: SessionSource = .phone, branch: String? = nil, queue: [QueuedMessage] = [], baseCommit: String? = nil) {
        self.queue = queue; self.baseCommit = baseCommit
        self.id = id; self.deviceId = deviceId; self.agent = agent; self.cwd = cwd; self.title = title
        self.status = status; self.createdAt = createdAt; self.updatedAt = updatedAt; self.pendingApprovals = pendingApprovals
        self.mode = mode; self.model = model; self.effort = effort; self.usage = usage; self.source = source; self.branch = branch
    }

    /// 工作目录最后一段，用于分组标题。
    public var folderName: String { (cwd as NSString).lastPathComponent }

    enum CodingKeys: String, CodingKey { case id, deviceId, agent, cwd, title, status, createdAt, updatedAt, pendingApprovals, mode, model, effort, usage, source, branch, queue, queuePaused, baseCommit, runStartedAt }
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
        runStartedAt = try c.decodeIfPresent(Date.self, forKey: .runStartedAt)
        pendingApprovals = try c.decodeIfPresent(Int.self, forKey: .pendingApprovals) ?? 0
        mode = SessionMode(rawValue: try c.decodeIfPresent(String.self, forKey: .mode) ?? "") ?? .normal
        model = try c.decodeIfPresent(String.self, forKey: .model).flatMap { $0.isEmpty ? nil : $0 }
        effort = try c.decodeIfPresent(String.self, forKey: .effort).flatMap { $0.isEmpty ? nil : $0 }
        queue = try c.decodeIfPresent([QueuedMessage].self, forKey: .queue) ?? []
        queuePaused = try c.decodeIfPresent(Bool.self, forKey: .queuePaused) ?? false
        baseCommit = try c.decodeIfPresent(String.self, forKey: .baseCommit)
        usage = try? c.decodeIfPresent(SessionUsage.self, forKey: .usage)
        source = SessionSource(rawValue: try c.decodeIfPresent(String.self, forKey: .source) ?? "") ?? .phone
        branch = try c.decodeIfPresent(String.self, forKey: .branch).flatMap { $0.isEmpty ? nil : $0 }
    }
}

public enum SessionSource: String, Codable, Sendable {
    case phone, terminal, sdk
    public var displayName: String { switch self { case .phone: "手机"; case .terminal: "终端"; case .sdk: "SDK" } }
}

public enum MessageRole: String, Codable, Sendable { case user, assistant, tool, system }

public struct ToolCall: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable { case running, done, error }
    /// text = 命令输出；diff = 文件改动（按 +/- 着色）
    public enum OutputKind: String, Codable, Sendable { case text, diff }
    public var id: String
    public var name: String
    public var detail: String
    public var state: State
    /// 工具的实际输出。没有它就只能看到「完成」，无法判断该不该批下一步。
    public var output: String?
    public var outputKind: OutputKind
    public var truncated: Bool
    public var exitCode: Int?
    public var files: [String] = []

    public init(id: String = UUID().uuidString, name: String, detail: String, state: State,
                output: String? = nil, outputKind: OutputKind = .text, truncated: Bool = false) {
        self.id = id; self.name = name; self.detail = detail; self.state = state
        self.output = output; self.outputKind = outputKind; self.truncated = truncated
    }

    enum CodingKeys: String, CodingKey { case id, name, detail, state, output, outputKind, truncated, exitCode, files }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        state = State(rawValue: try c.decodeIfPresent(String.self, forKey: .state) ?? "") ?? .running
        output = try c.decodeIfPresent(String.self, forKey: .output)
        outputKind = OutputKind(rawValue: try c.decodeIfPresent(String.self, forKey: .outputKind) ?? "") ?? .text
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
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
    /// 本地乐观追加、还没被连接器确认的消息（不参与编码）。断线重连补数据时用它去重。
    public var isLocal: Bool = false
    public var clientMessageId: String?

    public init(id: String = UUID().uuidString, sessionId: String, role: MessageRole, text: String, attachments: [String] = [],
                toolCalls: [ToolCall] = [], approvalId: String? = nil, createdAt: Date = .now, streaming: Bool = false, isLocal: Bool = false) {
        self.id = id; self.sessionId = sessionId; self.role = role; self.text = text; self.attachments = attachments
        self.toolCalls = toolCalls; self.approvalId = approvalId; self.createdAt = createdAt; self.streaming = streaming; self.isLocal = isLocal
    }

    enum CodingKeys: String, CodingKey { case id, sessionId, role, text, attachments, toolCalls, approvalId, createdAt, streaming, clientMessageId }
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
        clientMessageId = try c.decodeIfPresent(String.self, forKey: .clientMessageId)
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

public struct ApprovalQuestion: Identifiable, Codable, Hashable, Sendable {
    public struct Option: Codable, Hashable, Sendable {
        public var label: String
        public var description: String
    }
    public var id: String
    public var header: String
    public var question: String
    public var isSecret: Bool?
    public var options: [Option]?
}

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
    public var toolName: String?
    /// 连接器给出的「总是允许」选项，点一下就变成一条持久规则。
    public var suggestions: [ApprovalSuggestion]
    public var questions: [ApprovalQuestion] = []

    public init(id: String = UUID().uuidString, sessionId: String, deviceId: String, kind: ApprovalKind, summary: String,
                detail: String, risk: RiskLevel, status: Status = .pending, createdAt: Date = .now, expiresAt: Date? = nil,
                toolName: String? = nil, suggestions: [ApprovalSuggestion] = []) {
        self.toolName = toolName; self.suggestions = suggestions
        self.id = id; self.sessionId = sessionId; self.deviceId = deviceId; self.kind = kind; self.summary = summary
        self.detail = detail; self.risk = risk; self.status = status; self.createdAt = createdAt; self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey { case id, approvalId, sessionId, deviceId, kind, summary, detail, risk, status, createdAt, expiresAt, toolName, suggestions, questions }
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
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        suggestions = try c.decodeIfPresent([ApprovalSuggestion].self, forKey: .suggestions) ?? []
        questions = try c.decodeIfPresent([ApprovalQuestion].self, forKey: .questions) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(sessionId, forKey: .sessionId); try c.encode(deviceId, forKey: .deviceId)
        try c.encode(kind, forKey: .kind); try c.encode(summary, forKey: .summary); try c.encode(detail, forKey: .detail)
        try c.encode(risk, forKey: .risk); try c.encode(status, forKey: .status); try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt); try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encode(suggestions, forKey: .suggestions)
        try c.encode(questions, forKey: .questions)
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

/// 新建会话表单。`mode` 取代了早期的 `yolo` 开关（Trust ≡ 旧 YOLO）。
public struct NewSessionRequest: Codable, Sendable {
    public var agent: AgentKind
    public var cwd: String
    public var firstMessage: String?
    public var continueLast: Bool
    public var mode: SessionMode
    public var model: String?
    public var effort: String?
    public init(agent: AgentKind = .claude, cwd: String = "", firstMessage: String? = nil, continueLast: Bool = true,
                mode: SessionMode = .normal, model: String? = nil, effort: String? = nil) {
        self.agent = agent; self.cwd = cwd; self.firstMessage = firstMessage; self.continueLast = continueLast
        self.mode = mode; self.model = model; self.effort = effort
    }
}

/// 某个 Agent 上次用过的选项，用作下次新建会话的默认值。
public struct SessionOptions: Codable, Hashable, Sendable {
    public var mode: SessionMode
    public var model: String?
    public var effort: String?
    public init(mode: SessionMode = .normal, model: String? = nil, effort: String? = nil) { self.mode = mode; self.model = model; self.effort = effort }
}

/// 目录浏览结果（GET /fs/dirs），用于选择工作目录。
public struct DirectoryListing: Codable, Sendable {
    public struct Entry: Codable, Sendable, Identifiable, Hashable { public var name: String; public var path: String; public var id: String { path } }
    public var path: String
    public var parent: String?
    public var home: String?
    public var entries: [Entry]
    public init(path: String, parent: String?, home: String?, entries: [Entry]) { self.path = path; self.parent = parent; self.home = home; self.entries = entries }
}

// MARK: - 配对链接 yzvibe://pair?host=…&port=…&token=…&mode=…&name=…

public struct PairingPayload: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var token: String
    public var mode: ConnectionMode
    public var name: String?
    /// 连接器报的所有可达地址（JSON 配置里带）。存下来，隧道换地址时能自己接上。
    public var endpoints: [String]?

    public init(host: String, port: Int = Device.defaultPort, token: String, mode: ConnectionMode = .tunnel, name: String? = nil, endpoints: [String]? = nil) {
        self.host = host; self.port = port; self.token = token; self.mode = mode; self.name = name; self.endpoints = endpoints
    }

    /// 解析二维码内容（`yzvibe://pair?…`）；不合法返回 nil。
    public init?(qrString: String) { self.init(text: qrString) }

    /// 通吃四种来源：`yzvibe://pair?…` 深链、连接器给的 https 外链、`yzvibe qr --json` 的 JSON 配置，
    /// 以及夹带在其它文字里的上述任意一种（粘贴时常会带上说明文字）。
    public init?(text raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"), let p = PairingPayload(json: trimmed) { self = p; return }
        for candidate in [trimmed] + PairingPayload.urlCandidates(in: trimmed) {
            if let p = PairingPayload(deepLink: candidate) ?? PairingPayload(webLink: candidate) { self = p; return }
        }
        // 整段文字里夹着一份 JSON
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end,
           let p = PairingPayload(json: String(trimmed[start...end])) { self = p; return }
        return nil
    }

    /// `yzvibe://pair?host=…&port=…&token=…&mode=…&name=…`
    private init?(deepLink: String) {
        guard let comps = URLComponents(string: deepLink), comps.scheme == "yzvibe", comps.host == "pair" else { return nil }
        let q = PairingPayload.query(comps)
        guard let host = q["host"], !host.isEmpty, let token = q["token"], !token.isEmpty else { return nil }
        self.init(host: host, port: Int(q["port"] ?? "") ?? Device.defaultPort, token: token,
                  mode: ConnectionMode(rawValue: q["mode"] ?? "") ?? .tunnel,
                  name: q["name"].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// 连接器落地页外链 `https://<relay>/pair?token=…` 或 `http://<ip>:<port>/pair?token=…`。
    private init?(webLink: String) {
        guard let comps = URLComponents(string: webLink), let scheme = comps.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let linkHost = comps.host, !linkHost.isEmpty,
              comps.path.hasPrefix("/pair"), let token = PairingPayload.query(comps)["token"], !token.isEmpty else { return nil }
        if scheme == "https" {
            var base = "https://\(linkHost)"
            if let port = comps.port { base += ":\(port)" }
            self.init(host: base, port: Device.defaultPort, token: token, mode: .relay, name: nil)
        } else {
            // 明文 http 说明是局域网 / Tailscale 直连，拆成 host + port 走本地连接
            let port = comps.port ?? Device.defaultPort
            self.init(host: linkHost, port: port, token: token,
                      mode: linkHost.hasPrefix("100.") ? .tailscale : .local, name: nil)
        }
    }

    /// `yzvibe qr --json` 输出的配置对象。
    private init?(json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let host = (obj["host"] as? String)?.trimmingCharacters(in: .whitespaces), !host.isEmpty,
              let token = (obj["token"] as? String)?.trimmingCharacters(in: .whitespaces), !token.isEmpty else { return nil }
        let port = (obj["port"] as? Int) ?? Int((obj["port"] as? String) ?? "") ?? Device.defaultPort
        let mode = ConnectionMode(rawValue: (obj["mode"] as? String) ?? "") ?? (host.contains("://") ? .relay : .local)
        let name = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let endpoints = (obj["endpoints"] as? [String])?.filter { !$0.isEmpty }
        self.init(host: host, port: port, token: token, mode: mode, name: name, endpoints: endpoints)
    }

    private static func query(_ comps: URLComponents) -> [String: String] {
        var out: [String: String] = [:]
        for item in comps.queryItems ?? [] where out[item.name] == nil { out[item.name] = item.value ?? "" }
        return out
    }

    /// 从一段文字里挑出可能的链接（粘贴内容常带说明文字或换行）。
    private static func urlCandidates(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "," })
            .map(String.init)
            .filter { $0.hasPrefix("yzvibe://") || $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }
}

/// 单个远程文件的元信息（GET /files/stat），文件查看器用。
public struct FileInfo: Codable, Hashable, Sendable {
    public var name: String
    /// 连接器上的绝对路径（下载 / 再次请求时用这个）
    public var path: String
    /// 展示用路径，主目录缩成 `~`
    public var displayPath: String
    public var kind: FileEntry.Kind
    public var size: Int
    public var modifiedAt: Date
    public var mime: String
    /// 能否按文本预览（图片或超过 2MB 时为 false）
    public var textual: Bool
    /// 是否在会话工作目录内（目录外的文件只读、且限于主目录中的非敏感文件）
    public var inCwd: Bool

    public init(name: String, path: String, displayPath: String, kind: FileEntry.Kind, size: Int = 0,
                modifiedAt: Date = .now, mime: String = "application/octet-stream", textual: Bool = true, inCwd: Bool = true) {
        self.name = name; self.path = path; self.displayPath = displayPath; self.kind = kind
        self.size = size; self.modifiedAt = modifiedAt; self.mime = mime; self.textual = textual; self.inCwd = inCwd
    }

    enum CodingKeys: String, CodingKey { case name, path, displayPath, kind, size, modifiedAt, mime, textual, inCwd }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? name
        displayPath = try c.decodeIfPresent(String.self, forKey: .displayPath) ?? path
        kind = FileEntry.Kind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .other
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .now
        mime = try c.decodeIfPresent(String.self, forKey: .mime) ?? "application/octet-stream"
        textual = try c.decodeIfPresent(Bool.self, forKey: .textual) ?? true
        inCwd = try c.decodeIfPresent(Bool.self, forKey: .inCwd) ?? true
    }

    public var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
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


// MARK: - 审批规则（「以后别再问我」）

/// 审批卡上的「总是允许」按钮：点一下就在连接器上存成一条规则。
public struct ApprovalSuggestion: Codable, Hashable, Sendable, Identifiable {
    public var label: String
    public var match: String        // tool | prefix | exact
    public var value: String?
    public var scope: String        // session | global
    public var ttlMinutes: Int?
    public var id: String { "\(match)|\(value ?? "")|\(scope)|\(ttlMinutes ?? 0)" }

    public init(label: String, match: String, value: String? = nil, scope: String = "session", ttlMinutes: Int? = nil) {
        self.label = label; self.match = match; self.value = value; self.scope = scope; self.ttlMinutes = ttlMinutes
    }
    enum CodingKeys: String, CodingKey { case label, match, value, scope, ttlMinutes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "总是允许"
        match = try c.decodeIfPresent(String.self, forKey: .match) ?? "tool"
        value = try c.decodeIfPresent(String.self, forKey: .value)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "session"
        ttlMinutes = try c.decodeIfPresent(Int.self, forKey: .ttlMinutes)
    }
}

/// 已保存的规则（GET /rules），可以在「我 › 审批规则」里逐条删除。
public struct ApprovalRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var scope: String
    public var sessionId: String?
    public var tool: String?
    public var match: String
    public var value: String?
    public var description: String
    public var createdAt: Date
    public var expiresAt: Date?
    public var hits: Int

    public init(id: String, scope: String = "session", sessionId: String? = nil, tool: String? = nil, match: String = "tool",
                value: String? = nil, description: String = "", createdAt: Date = .now, expiresAt: Date? = nil, hits: Int = 0) {
        self.id = id; self.scope = scope; self.sessionId = sessionId; self.tool = tool; self.match = match
        self.value = value; self.description = description; self.createdAt = createdAt; self.expiresAt = expiresAt; self.hits = hits
    }
    enum CodingKeys: String, CodingKey { case id, scope, sessionId, tool, match, value, description, createdAt, expiresAt, hits }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "session"
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        match = try c.decodeIfPresent(String.self, forKey: .match) ?? "tool"
        value = try c.decodeIfPresent(String.self, forKey: .value)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        hits = try c.decodeIfPresent(Int.self, forKey: .hits) ?? 0
    }
    /// 剩余有效时间的中文说明（就近取整，避免「还剩 29 分钟」这种读起来别扭的结果）。
    public var remaining: String? {
        guard let expiresAt else { return nil }
        let seconds = expiresAt.timeIntervalSinceNow
        if seconds <= 0 { return "已过期" }
        if seconds < 3600 { return "还剩 \(max(1, Int((seconds / 60).rounded()))) 分钟" }
        return "还剩 \(max(1, Int((seconds / 3600).rounded()))) 小时"
    }
}

// MARK: - 远程推送与一次性同步

/// 连接器的推送配置状态（GET /sync 里带回来）。
public struct PushStatus: Codable, Hashable, Sendable {
    public var ready: Bool
    public var missing: String?
    public var registeredDevices: Int
    public var bundleId: String?
    public var environment: String?
    public var configFile: String?

    public init(ready: Bool = false, missing: String? = nil, registeredDevices: Int = 0, bundleId: String? = nil, environment: String? = nil, configFile: String? = nil) {
        self.ready = ready; self.missing = missing; self.registeredDevices = registeredDevices
        self.bundleId = bundleId; self.environment = environment; self.configFile = configFile
    }
    enum CodingKeys: String, CodingKey { case ready, missing, registeredDevices, bundleId, environment, configFile }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        missing = try c.decodeIfPresent(String.self, forKey: .missing)
        registeredDevices = try c.decodeIfPresent(Int.self, forKey: .registeredDevices) ?? 0
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        environment = try c.decodeIfPresent(String.self, forKey: .environment)
        configFile = try c.decodeIfPresent(String.self, forKey: .configFile)
    }
}

/// GET /sync：App 回到前台时一次拿全，避免逐个接口往返。
public struct SyncSnapshot: Codable, Sendable {
    public var streamSync: Bool = false
    public var serverTime: Date
    public var sessions: [Session]
    public var approvals: [Approval]
    public var agents: [String: AgentCapabilities]
    public var rules: [ApprovalRule]
    public var push: PushStatus
    /// 手机上删掉过、连接器不再列出的会话条数（可以在「我」里一键恢复）。
    public var hiddenSessions: Int = 0

    enum CodingKeys: String, CodingKey { case serverTime, sessions, approvals, agents, rules, push, hiddenSessions, streamSync }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime) ?? .now
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        approvals = try c.decodeIfPresent([Approval].self, forKey: .approvals) ?? []
        agents = try c.decodeIfPresent([String: AgentCapabilities].self, forKey: .agents) ?? [:]
        rules = try c.decodeIfPresent([ApprovalRule].self, forKey: .rules) ?? []
        push = try c.decodeIfPresent(PushStatus.self, forKey: .push) ?? PushStatus()
        hiddenSessions = try c.decodeIfPresent(Int.self, forKey: .hiddenSessions) ?? 0
        streamSync = try c.decodeIfPresent(Bool.self, forKey: .streamSync) ?? false
    }
    public init(serverTime: Date = .now, sessions: [Session] = [], approvals: [Approval] = [], agents: [String: AgentCapabilities] = [:], rules: [ApprovalRule] = [], push: PushStatus = PushStatus(), hiddenSessions: Int = 0) {
        self.serverTime = serverTime; self.sessions = sessions; self.approvals = approvals; self.agents = agents; self.rules = rules; self.push = push; self.hiddenSessions = hiddenSessions
    }
}


// MARK: - 待发送队列 / 改动视图 / 命令面板

/// 排在队列里、还没发出去的消息。
public struct QueuedMessage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var deliveryState: String = "queued"
    public var text: String
    public var attachments: [String]
    public var createdAt: Date
    public init(id: String = UUID().uuidString, text: String, attachments: [String] = [], createdAt: Date = .now) {
        self.id = id; self.text = text; self.attachments = attachments; self.createdAt = createdAt
    }
    enum CodingKeys: String, CodingKey { case id, text, attachments, createdAt, deliveryState }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        deliveryState = try c.decodeIfPresent(String.self, forKey: .deliveryState) ?? "queued"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        attachments = try c.decodeIfPresent([String].self, forKey: .attachments) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

/// 发送方式：忙的时候默认排队，也可以插队并打断当前轮。
public enum SendMode: String, Sendable { case auto, queue, now }

public struct DiffFile: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var status: String
    public var staged: Bool
    public var unstaged: Bool
    public var untracked: Bool
    public var added: Int?
    public var removed: Int?
    public var diff: String?
    public var binary: Bool
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }

    public init(path: String, status: String, staged: Bool = false, unstaged: Bool = true, untracked: Bool = false,
                added: Int? = nil, removed: Int? = nil, diff: String? = nil, binary: Bool = false) {
        self.path = path; self.status = status; self.staged = staged; self.unstaged = unstaged; self.untracked = untracked
        self.added = added; self.removed = removed; self.diff = diff; self.binary = binary
    }
    enum CodingKeys: String, CodingKey { case path, status, staged, unstaged, untracked, added, removed, diff, binary }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "已修改"
        staged = try c.decodeIfPresent(Bool.self, forKey: .staged) ?? false
        unstaged = try c.decodeIfPresent(Bool.self, forKey: .unstaged) ?? false
        untracked = try c.decodeIfPresent(Bool.self, forKey: .untracked) ?? false
        added = try c.decodeIfPresent(Int.self, forKey: .added)
        removed = try c.decodeIfPresent(Int.self, forKey: .removed)
        diff = try c.decodeIfPresent(String.self, forKey: .diff)
        binary = try c.decodeIfPresent(Bool.self, forKey: .binary) ?? false
    }
}

/// 工作目录的改动（GET /sessions/:id/diff）。
public struct WorkingDiff: Codable, Sendable {
    public struct Totals: Codable, Sendable, Hashable {
        public var files: Int, added: Int, removed: Int
        public init(files: Int = 0, added: Int = 0, removed: Int = 0) { self.files = files; self.added = added; self.removed = removed }
    }
    public var repo: Bool
    public var reason: String?
    public var branch: String?
    public var head: String?
    public var files: [DiffFile]
    public var totals: Totals
    public var truncated: Bool

    public init(repo: Bool = true, reason: String? = nil, branch: String? = nil, head: String? = nil,
                files: [DiffFile] = [], totals: Totals = Totals(), truncated: Bool = false) {
        self.repo = repo; self.reason = reason; self.branch = branch; self.head = head
        self.files = files; self.totals = totals; self.truncated = truncated
    }
    enum CodingKeys: String, CodingKey { case repo, reason, branch, head, files, totals, truncated }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repo = try c.decodeIfPresent(Bool.self, forKey: .repo) ?? true
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        head = try c.decodeIfPresent(String.self, forKey: .head)
        files = try c.decodeIfPresent([DiffFile].self, forKey: .files) ?? []
        totals = try c.decodeIfPresent(Totals.self, forKey: .totals) ?? Totals()
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }
}

/// 一条斜杠命令 / skill。`kind` 决定点下去是手机自己处理还是发给 Agent。
public struct SlashCommand: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var args: String
    public var description: String
    public var kind: String          // app | agent | skill | prompt
    public var source: String
    public var action: String?       // kind == app 时手机要执行的动作
    public var insertAsText: Bool    // Codex 的 skill 只能当提示词插进消息里

    public var id: String { "\(kind):\(name)" }
    public var isApp: Bool { kind == "app" }
    public var display: String { args.isEmpty ? "/\(name)" : "/\(name) \(args)" }

    public init(name: String, args: String = "", description: String = "", kind: String = "agent", source: String = "", action: String? = nil, insertAsText: Bool = false) {
        self.name = name; self.args = args; self.description = description; self.kind = kind; self.source = source; self.action = action; self.insertAsText = insertAsText
    }
    enum CodingKeys: String, CodingKey { case name, args, description, kind, source, action, insertAsText }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        args = try c.decodeIfPresent(String.self, forKey: .args) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "agent"
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        action = try c.decodeIfPresent(String.self, forKey: .action)
        insertAsText = try c.decodeIfPresent(Bool.self, forKey: .insertAsText) ?? false
    }
}

/// GET /sessions/:id/commands
public struct CommandCatalog: Codable, Sendable {
    public var app: [SlashCommand]
    public var agentCommands: [SlashCommand]
    public var skills: [SlashCommand]
    public var prompts: [SlashCommand]
    public var note: String?
    public var reported: Bool

    public var isEmpty: Bool { app.isEmpty && agentCommands.isEmpty && skills.isEmpty && prompts.isEmpty }
    public init(app: [SlashCommand] = [], agentCommands: [SlashCommand] = [], skills: [SlashCommand] = [], prompts: [SlashCommand] = [], note: String? = nil, reported: Bool = false) {
        self.app = app; self.agentCommands = agentCommands; self.skills = skills; self.prompts = prompts; self.note = note; self.reported = reported
    }
    enum CodingKeys: String, CodingKey { case app, agentCommands, skills, prompts, note, reported }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent([SlashCommand].self, forKey: .app) ?? []
        agentCommands = try c.decodeIfPresent([SlashCommand].self, forKey: .agentCommands) ?? []
        skills = try c.decodeIfPresent([SlashCommand].self, forKey: .skills) ?? []
        prompts = try c.decodeIfPresent([SlashCommand].self, forKey: .prompts) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        reported = try c.decodeIfPresent(Bool.self, forKey: .reported) ?? false
    }
}
