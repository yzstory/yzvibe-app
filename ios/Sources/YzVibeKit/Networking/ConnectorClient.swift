import Foundation
import UIKit

/// 手机 ⇄ 桌面连接器的抽象（shared/protocol.md）。真实实现走 REST + WebSocket，Mock 用于静态 UI 与测试。
public protocol ConnectorClient: Sendable {
    func health(device: Device) async throws -> HealthInfo
    func pair(_ payload: PairingPayload) async throws -> Device
    func sessions(device: Device) async throws -> [Session]
    func createSession(device: Device, request: NewSessionRequest) async throws -> Session
    func messages(device: Device, sessionId: String, after cursor: String?) async throws -> [Message]
    func send(device: Device, sessionId: String, text: String, attachments: [String]) async throws
    func stop(device: Device, sessionId: String) async throws
    /// 回应审批。`remember` 非空时同时在连接器上存一条规则，以后同类请求自动放行。
    func respond(device: Device, approvalId: String, decision: ApprovalDecision, remember: ApprovalSuggestion?) async throws
    func approvals(device: Device) async throws -> [Approval]
    func listFiles(device: Device, sessionId: String, path: String) async throws -> [FileEntry]
    func preview(device: Device, sessionId: String, path: String) async throws -> String
    /// 单个文件的元信息（GET /files/stat）；path 可以是相对工作目录的路径，也可以是绝对路径或 `~/…`。
    func fileInfo(device: Device, sessionId: String, path: String) async throws -> FileInfo
    /// 下载文件原始字节（GET /files/download）。
    func download(device: Device, sessionId: String, path: String) async throws -> Data
    func upload(device: Device, data: Data, mime: String, filename: String) async throws -> String
    /// 各 Agent 支持的模式 / 模型 / 思考强度（GET /agents），key 为 agent 名。
    func capabilities(device: Device) async throws -> [String: AgentCapabilities]
    /// 改会话的 mode / model / effort（PATCH /sessions/:id）。value 为 nil 表示恢复该项默认。
    func configure(device: Device, sessionId: String, patch: [String: String?]) async throws -> Session
    /// 一次拿全会话 / 待审批 / 能力表 / 规则 / 推送状态（GET /sync），App 回到前台时补数据用。
    func sync(device: Device) async throws -> SyncSnapshot
    /// 已保存的审批规则；sessionId 非空时只看该会话相关的。
    func rules(device: Device, sessionId: String?) async throws -> [ApprovalRule]
    func deleteRule(device: Device, id: String) async throws
    /// 注册 APNs token，让连接器在 App 被挂起时也能叫醒它。
    func registerPush(device: Device, token: String, environment: String) async throws -> PushStatus
    func unregisterPush(device: Device) async throws
    /// 立刻重连事件通道（回到前台时用，不必等指数退避）。
    func reconnect(device: Device)
    /// 目录浏览（GET /fs/dirs），path 为 nil 时列主目录。
    func listDirectories(device: Device, path: String?) async throws -> DirectoryListing
    /// 新建文件夹（POST /fs/mkdir），返回新目录绝对路径。
    func makeDirectory(device: Device, parent: String, name: String) async throws -> String
    /// 账号剩余额度（GET /quota?agent=）。
    func quota(device: Device, agent: AgentKind) async throws -> QuotaInfo
    /// 取回上传过的附件原始数据（GET /uploads/:id）。
    func attachment(device: Device, id: String) async throws -> Data
    /// 服务端事件流；调用方持有并消费。
    func events(device: Device) -> AsyncStream<ConnectorEvent>
}

public struct HealthInfo: Codable, Sendable {
    public var name: String
    public var version: String
    public var agents: [String]
    public var connectorId: String?
    public init(name: String, version: String, agents: [String], connectorId: String? = nil) { self.name = name; self.version = version; self.agents = agents; self.connectorId = connectorId }
}

public enum ConnectorEvent: Sendable {
    case sessionCreated(Session)
    case sessionUpdated(Session)
    case sessionStatus(sessionId: String, status: SessionStatus)
    case messageDelta(sessionId: String, messageId: String, text: String)
    case messageDone(sessionId: String, messageId: String)
    case toolCall(sessionId: String, call: ToolCall)
    case approvalRequested(Approval)
    case approvalResolved(approvalId: String, decision: ApprovalDecision)
    case disconnected(Error?)
}

public enum ConnectorError: LocalizedError, Sendable {
    case badURL, unauthorized, network(String), decoding, unreachable
    public var errorDescription: String? {
        switch self {
        case .badURL: "连接地址不合法"
        case .unauthorized: "Token 无效或已过期，请重新扫码"
        case .network(let m): "网络错误：\(m)"
        case .decoding: "无法解析连接器返回的数据"
        case .unreachable: "手机没有连到二维码里的主机。请确认网络可达，或用 --access=local 重新配对。"
        }
    }
}

// MARK: - 真实实现（M2 联调时补全 WS 解析细节）

public final class HTTPConnectorClient: ConnectorClient, @unchecked Sendable {
    private let session: URLSession
    private let tokenProvider: @Sendable (Device) -> String?

    public init(session: URLSession = .shared, tokenProvider: @escaping @Sendable (Device) -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    private func request(_ device: Device, _ path: String, method: String = "GET", body: (any Encodable)? = nil) throws -> URLRequest {
        guard let base = device.baseURL, let url = URL(string: path, relativeTo: base) else { throw ConnectorError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if let token = tokenProvider(device) { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder.yz.encode(AnyEncodable(body))
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) } catch { throw ConnectorError.unreachable }
        guard let http = resp as? HTTPURLResponse else { throw ConnectorError.network("无响应") }
        if http.statusCode == 401 { throw ConnectorError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.network("HTTP \(http.statusCode)") }
        do { return try JSONDecoder.yz.decode(T.self, from: data) } catch { throw ConnectorError.decoding }
    }

    public func health(device: Device) async throws -> HealthInfo {
        try await perform(request(device, "/health"), as: HealthInfo.self)
    }

    public func pair(_ payload: PairingPayload) async throws -> Device {
        struct PairResponse: Decodable { var deviceToken: String; var deviceName: String?; var connectorId: String? }
        var device = Device(name: payload.name ?? payload.host, host: payload.host, port: payload.port, mode: payload.mode, online: true)
        struct Body: Encodable { var token: String; var phoneName: String }
        let phone = await MainActor.run { UIDevice.current.name }
        let resp = try await perform(request(device, "/pair", method: "POST", body: Body(token: payload.token, phoneName: phone)), as: PairResponse.self)
        if let cid = resp.connectorId { device.id = cid }
        device.name = payload.name ?? resp.deviceName ?? device.name
        TokenStore.shared.save(token: resp.deviceToken, for: device.id)
        return device
    }

    public func sessions(device: Device) async throws -> [Session] {
        try await perform(request(device, "/sessions"), as: [Session].self)
    }

    public func createSession(device: Device, request r: NewSessionRequest) async throws -> Session {
        try await perform(request(device, "/sessions", method: "POST", body: r), as: Session.self)
    }

    public func messages(device: Device, sessionId: String, after cursor: String?) async throws -> [Message] {
        let q = cursor.map { "?after=\($0)" } ?? ""
        return try await perform(request(device, "/sessions/\(sessionId)/messages\(q)"), as: [Message].self)
    }

    public func send(device: Device, sessionId: String, text: String, attachments: [String]) async throws {
        try await socket(for: device).send(["type": "message.send", "sessionId": sessionId, "text": text, "attachments": attachments])
    }

    public func stop(device: Device, sessionId: String) async throws {
        try await socket(for: device).send(["type": "session.stop", "sessionId": sessionId])
    }

    public func respond(device: Device, approvalId: String, decision: ApprovalDecision, remember: ApprovalSuggestion? = nil) async throws {
        var payload: [String: Any] = ["type": "approval.respond", "approvalId": approvalId, "decision": decision.rawValue]
        if let r = remember { payload["remember"] = rememberDict(r) }
        do { try await socket(for: device).send(payload) }
        catch {
            // WS 不通就走 HTTP：审批是不能丢的动作
            struct Body: Encodable { var decision: String; var remember: RememberBody? }
            _ = try await perform(request(device, "/approvals/\(approvalId)", method: "POST",
                                          body: Body(decision: decision.rawValue, remember: remember.map(RememberBody.init))), as: OK.self)
        }
    }

    public func sync(device: Device) async throws -> SyncSnapshot {
        try await perform(request(device, "/sync"), as: SyncSnapshot.self)
    }

    public func rules(device: Device, sessionId: String?) async throws -> [ApprovalRule] {
        let q = sessionId.map { "?sessionId=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0) } ?? ""
        return try await perform(request(device, "/rules\(q)"), as: [ApprovalRule].self)
    }

    public func deleteRule(device: Device, id: String) async throws {
        _ = try await perform(request(device, "/rules/\(id)", method: "DELETE"), as: OK.self)
    }

    public func registerPush(device: Device, token: String, environment: String) async throws -> PushStatus {
        struct Body: Encodable { var token: String; var environment: String; var bundleId: String? }
        struct Resp: Decodable { var ok: Bool; var push: PushStatus? }
        let body = Body(token: token, environment: environment, bundleId: Bundle.main.bundleIdentifier)
        return try await perform(request(device, "/devices/push", method: "POST", body: body), as: Resp.self).push ?? PushStatus()
    }

    public func unregisterPush(device: Device) async throws {
        _ = try await perform(request(device, "/devices/push", method: "DELETE"), as: OK.self)
    }

    public func reconnect(device: Device) { socket(for: device).reconnectNow() }

    public func approvals(device: Device) async throws -> [Approval] {
        var list = try await perform(request(device, "/approvals?status=pending"), as: [Approval].self)
        for i in list.indices { list[i].deviceId = device.id }
        return list
    }

    public func listFiles(device: Device, sessionId: String, path: String) async throws -> [FileEntry] {
        struct Resp: Decodable { var entries: [FileEntry] }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return try await perform(request(device, "/files?sessionId=\(sessionId)&path=\(encoded)"), as: Resp.self).entries
    }

    public func preview(device: Device, sessionId: String, path: String) async throws -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let req = try request(device, "/files/preview?sessionId=\(sessionId)&path=\(encoded)")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw ConnectorError.network("HTTP \(http.statusCode)") }
        return String(decoding: data, as: UTF8.self)
    }

    public func upload(device: Device, data: Data, mime: String, filename: String) async throws -> String {
        struct Resp: Decodable { var id: String }
        var req = try request(device, "/uploads", method: "POST")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.setValue(filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename, forHTTPHeaderField: "X-Filename")
        req.httpBody = data
        return try await perform(req, as: Resp.self).id
    }

    public func listDirectories(device: Device, path: String?) async throws -> DirectoryListing {
        let q = path.map { "?path=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0) } ?? ""
        return try await perform(request(device, "/fs/dirs\(q)"), as: DirectoryListing.self)
    }

    public func makeDirectory(device: Device, parent: String, name: String) async throws -> String {
        struct Body: Encodable { var parent: String; var name: String }
        struct Resp: Decodable { var path: String }
        return try await perform(request(device, "/fs/mkdir", method: "POST", body: Body(parent: parent, name: name)), as: Resp.self).path
    }

    public func capabilities(device: Device) async throws -> [String: AgentCapabilities] {
        try await perform(request(device, "/agents"), as: [String: AgentCapabilities].self)
    }

    public func configure(device: Device, sessionId: String, patch: [String: String?]) async throws -> Session {
        var req = try request(device, "/sessions/\(sessionId)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: patch.mapValues { v -> Any in v ?? NSNull() })
        return try await perform(req, as: Session.self)
    }

    public func quota(device: Device, agent: AgentKind) async throws -> QuotaInfo {
        try await perform(request(device, "/quota?agent=\(agent.rawValue)"), as: QuotaInfo.self)
    }

    public func fileInfo(device: Device, sessionId: String, path: String) async throws -> FileInfo {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return try await perform(request(device, "/files/stat?sessionId=\(sessionId)&path=\(encoded)"), as: FileInfo.self)
    }

    public func download(device: Device, sessionId: String, path: String) async throws -> Data {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let (data, resp) = try await session.data(for: try request(device, "/files/download?sessionId=\(sessionId)&path=\(encoded)"))
        guard let http = resp as? HTTPURLResponse else { throw ConnectorError.network("无响应") }
        if http.statusCode == 401 { throw ConnectorError.unauthorized }
        if http.statusCode == 403 { throw ConnectorError.network("这个文件不在会话工作目录里，出于安全不提供访问") }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.network("HTTP \(http.statusCode)") }
        return data
    }

    public func attachment(device: Device, id: String) async throws -> Data {
        let (data, resp) = try await session.data(for: request(device, "/uploads/\(id)"))
        guard let http = resp as? HTTPURLResponse else { throw ConnectorError.network("无响应") }
        if http.statusCode == 401 { throw ConnectorError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.network("HTTP \(http.statusCode)") }
        return data
    }

    public func events(device: Device) -> AsyncStream<ConnectorEvent> {
        socket(for: device).events
    }

    // MARK: WebSocket

    private var sockets: [String: ConnectorSocket] = [:]
    private let lock = NSLock()

    private func socket(for device: Device) -> ConnectorSocket {
        lock.lock(); defer { lock.unlock() }
        if let s = sockets[device.id] { return s }
        let s = ConnectorSocket(device: device, session: session, token: tokenProvider(device))
        sockets[device.id] = s
        return s
    }
}

/// 单设备的 WS 连接：自动重连（指数退避 ≤ 30s），把 JSON 事件翻译为 `ConnectorEvent`。
final class ConnectorSocket: @unchecked Sendable {
    let events: AsyncStream<ConnectorEvent>
    private let continuation: AsyncStream<ConnectorEvent>.Continuation
    private var task: URLSessionWebSocketTask?
    private let device: Device
    private let session: URLSession
    private let token: String?
    private var backoff: TimeInterval = 1
    private var pingTimer: Timer?
    private var connecting = false

    init(device: Device, session: URLSession, token: String?) {
        self.device = device; self.session = session; self.token = token
        var cont: AsyncStream<ConnectorEvent>.Continuation!
        events = AsyncStream { cont = $0 }
        continuation = cont
        connect()
    }

    /// 回到前台时立刻重连：iOS 挂起 App 时会悄悄断掉 WebSocket，等指数退避太慢。
    func reconnectNow() {
        backoff = 1
        if task?.state == .running {
            task?.sendPing { [weak self] error in if error != nil { self?.restart() } }
        } else {
            restart()
        }
    }

    private func restart() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connect()
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        guard let base = device.baseURL, var comps = URLComponents(url: base.appendingPathComponent("ws"), resolvingAgainstBaseURL: false) else { return }
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        if let token { comps.queryItems = [URLQueryItem(name: "token", value: token)] }
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let t = session.webSocketTask(with: req)
        task = t
        t.resume()
        receive()
        startHeartbeat()
    }

    /// 每 30 秒 ping 一次：中间隧道悄悄断链时，只靠 receive 可能一直不报错。
    private func startHeartbeat() {
        pingTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.task?.sendPing { [weak self] error in
                guard error != nil, let self else { return }
                continuation.yield(.disconnected(error))
                restart()
            }
        }
        pingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg, let data = s.data(using: .utf8), let ev = Self.parse(data) { continuation.yield(ev) }
                backoff = 1
                receive()
            case .failure(let err):
                continuation.yield(.disconnected(err))
                pingTimer?.invalidate()
                let delay = backoff
                backoff = min(backoff * 2, 30)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.connect() }
            }
        }
    }

    func send(_ dict: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        try await task?.send(.string(String(decoding: data, as: UTF8.self)))
    }

    static func parse(_ data: Data) -> ConnectorEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String else { return nil }
        switch type {
        case "session.created", "session.updated":
            guard let raw = obj["session"], let d = try? JSONSerialization.data(withJSONObject: raw), let s = try? JSONDecoder.yz.decode(Session.self, from: d) else { return nil }
            return type == "session.created" ? .sessionCreated(s) : .sessionUpdated(s)
        case "session.status":
            guard let sid = obj["sessionId"] as? String, let st = SessionStatus(rawValue: obj["status"] as? String ?? "") else { return nil }
            return .sessionStatus(sessionId: sid, status: st)
        case "message.delta":
            guard let sid = obj["sessionId"] as? String, let mid = obj["messageId"] as? String else { return nil }
            return .messageDelta(sessionId: sid, messageId: mid, text: obj["text"] as? String ?? "")
        case "message.done":
            guard let sid = obj["sessionId"] as? String, let mid = obj["messageId"] as? String else { return nil }
            return .messageDone(sessionId: sid, messageId: mid)
        case "tool.call":
            guard let sid = obj["sessionId"] as? String, let name = obj["name"] as? String else { return nil }
            let state = ToolCall.State(rawValue: obj["state"] as? String ?? "running") ?? .running
            let inputDict = obj["input"] as? [String: Any] ?? [:]
            let input = (inputDict["detail"] as? String) ?? (inputDict.values.first { $0 is String } as? String) ?? ""
            return .toolCall(sessionId: sid, call: ToolCall(id: obj["toolId"] as? String ?? UUID().uuidString, name: name, detail: input, state: state))
        case "approval.requested":
            guard let sid = obj["sessionId"] as? String, let aid = (obj["approvalId"] ?? obj["id"]) as? String else { return nil }
            let kind = ApprovalKind(rawValue: obj["kind"] as? String ?? "") ?? .other
            let risk = RiskLevel(rawValue: obj["risk"] as? String ?? "") ?? .medium
            return .approvalRequested(Approval(id: aid, sessionId: sid, deviceId: "", kind: kind, summary: obj["summary"] as? String ?? "",
                                               detail: obj["detail"] as? String ?? "", risk: risk))
        case "approval.resolved":
            guard let aid = obj["approvalId"] as? String, let d = ApprovalDecision(rawValue: obj["decision"] as? String ?? "") else { return nil }
            return .approvalResolved(approvalId: aid, decision: d)
        default:
            return nil
        }
    }
}

// MARK: - 编解码

struct OK: Decodable { var ok: Bool? }

struct RememberBody: Encodable {
    var match: String, value: String?, scope: String, ttlMinutes: Int?
    init(_ s: ApprovalSuggestion) { match = s.match; value = s.value; scope = s.scope; ttlMinutes = s.ttlMinutes }
}

func rememberDict(_ s: ApprovalSuggestion) -> [String: Any] {
    var d: [String: Any] = ["match": s.match, "scope": s.scope]
    if let v = s.value { d["value"] = v }
    if let t = s.ttlMinutes { d["ttlMinutes"] = t }
    return d
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

extension JSONEncoder {
    static let yz: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}
extension JSONDecoder {
    static let yz: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

// MARK: - Token 存储（Keychain；找不到 Security 时退回 UserDefaults 仅用于预览）

public final class TokenStore: @unchecked Sendable {
    public static let shared = TokenStore()
    private let service = "icu.yzvibe.device-token"

    public func save(token: String, for deviceId: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: deviceId]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    public func token(for deviceId: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: deviceId, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func remove(for deviceId: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: deviceId]
        SecItemDelete(query as CFDictionary)
    }
}
