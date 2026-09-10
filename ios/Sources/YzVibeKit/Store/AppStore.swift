import Foundation
import Observation
import SwiftUI
import UserNotifications

/// 全局状态：设备、会话、消息、审批。
/// `AppStore.live()` 走真实连接器并持久化设备；`AppStore()`（seedMock）用于预览、测试与演示。
@MainActor
@Observable
public final class AppStore {
    public var devices: [Device] = [] { didSet { if !isDemo { persistence.save(devices) } } }
    public var selectedDeviceId: String? { didSet { UserDefaults.standard.set(selectedDeviceId, forKey: "yz.selectedDevice") } }
    public var sessions: [Session] = []
    public var messages: [String: [Message]] = [:]        // sessionId → messages
    public var approvals: [Approval] = []
    public var capabilities: [String: [String: AgentCapabilities]] = [:]   // deviceId → agent → 能力
    public var attachmentImages: [String: UIImage] = [:]                   // 上传 id → 图片（会话里展示用）
    public var failedAttachments: Set<String> = []
    public var settings = Settings() { didSet { settings.save() } }
    public var toast: String?
    public private(set) var isDemo: Bool

    public let client: any ConnectorClient
    private let persistence = DevicePersistence()
    private var eventTasks: [String: Task<Void, Never>] = [:]
    private var loadedMessages: Set<String> = []

    public init(client: any ConnectorClient = MockConnectorClient(), seedMock: Bool = true) {
        self.client = client
        self.isDemo = seedMock
        self.settings = Settings.load()
        if seedMock { loadDemo() }
    }

    /// 真实连接器 + 本地持久化的设备。
    public static func live() -> AppStore {
        let client = HTTPConnectorClient(tokenProvider: { TokenStore.shared.token(for: $0.id) })
        let store = AppStore(client: client, seedMock: false)
        store.devices = store.persistence.load()
        store.selectedDeviceId = UserDefaults.standard.string(forKey: "yz.selectedDevice") ?? store.devices.first?.id
        return store
    }

    /// 空态里的「加载演示数据」：不联网也能看完整流程。
    public func loadDemo() {
        isDemo = true
        devices = MockData.devices
        selectedDeviceId = MockData.macStudio.id
        sessions = MockData.sessions
        approvals = MockData.approvals
        for s in sessions { messages[s.id] = MockData.messages(for: s.id); loadedMessages.insert(s.id) }
    }

    // MARK: 派生

    public var selectedDevice: Device? { devices.first { $0.id == selectedDeviceId } ?? devices.first }
    public var pendingApprovals: [Approval] { approvals.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt } }
    public var resolvedApprovals: [Approval] { approvals.filter { $0.status != .pending }.sorted { $0.createdAt > $1.createdAt } }
    public func device(_ id: String) -> Device? { devices.first { $0.id == id } }
    public func session(_ id: String) -> Session? { sessions.first { $0.id == id } }
    public func approval(_ id: String) -> Approval? { approvals.first { $0.id == id } }
    /// 某设备上某种 Agent 的能力表；没拿到时用 App 内置的回退表。
    public func capabilities(for agent: AgentKind, on deviceId: String?) -> AgentCapabilities {
        capabilities[deviceId ?? ""]?[agent.rawValue] ?? .fallback(for: agent)
    }
    public func capabilities(for session: Session) -> AgentCapabilities { capabilities(for: session.agent, on: session.deviceId) }
    /// 模型菜单用的列表：用户在「模型列表」里改过就用用户的，否则用连接器 / 内置的。
    public func modelOptions(for agent: AgentKind, caps: AgentCapabilities) -> [ModelOption] {
        settings.modelPresets(for: agent) ?? caps.models
    }

    public func sessions(for device: Device?, activeOnly: Bool, query: String) -> [Session] {
        guard let device else { return [] }
        return sessions
            .filter { $0.deviceId == device.id }
            .filter { !activeOnly || $0.status != .closed }
            .filter { settings.showTerminalSessions || $0.source == .phone }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.cwd.localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 按工作目录分组，保持最近更新的目录在前。
    public func groupedSessions(_ list: [Session]) -> [(cwd: String, sessions: [Session])] {
        var order: [String] = []
        var map: [String: [Session]] = [:]
        for s in list {
            if map[s.cwd] == nil { order.append(s.cwd) }
            map[s.cwd, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }

    // MARK: 设备

    public func pair(_ payload: PairingPayload) async throws {
        var device = try await client.pair(payload)
        device.online = true
        devices.removeAll { $0.id == device.id || ($0.host == device.host && $0.port == device.port) }
        devices.insert(device, at: 0)
        selectedDeviceId = device.id
        await refresh(device)
        subscribe(device)
        toast = "已配对 \(device.name)"
    }

    public func addManual(host: String, port: Int, token: String) async throws {
        try await pair(PairingPayload(host: host, port: port, token: token, mode: host.contains("://") ? .relay : .local))
    }

    public func remove(_ device: Device) {
        devices.removeAll { $0.id == device.id }
        sessions.removeAll { $0.deviceId == device.id }
        approvals.removeAll { $0.deviceId == device.id }
        eventTasks[device.id]?.cancel()
        eventTasks[device.id] = nil
        TokenStore.shared.remove(for: device.id)
        if selectedDeviceId == device.id { selectedDeviceId = devices.first?.id }
    }

    /// 拉取会话 + 待审批，并刷新在线状态与计数。
    public func refresh(_ device: Device) async {
        do {
            let fresh = try await client.sessions(device: device).map { var s = $0; s.deviceId = device.id; return s }
            sessions.removeAll { $0.deviceId == device.id }
            sessions.append(contentsOf: fresh)
            if let caps = try? await client.capabilities(device: device) { capabilities[device.id] = caps }
            let pending = try await client.approvals(device: device)
            approvals.removeAll { $0.deviceId == device.id && $0.status == .pending }
            approvals.insert(contentsOf: pending, at: 0)
            for a in pending where !(messages[a.sessionId] ?? []).contains(where: { $0.approvalId == a.id }) {
                messages[a.sessionId, default: []].append(Message(sessionId: a.sessionId, role: .system, text: "", approvalId: a.id))
            }
            setDevice(device.id) { $0.online = true; $0.lastSeen = .now; $0.sessionCount = fresh.filter { $0.status != .closed }.count
                $0.agents = Dictionary(grouping: fresh, by: \.agent).mapValues(\.count) }
        } catch {
            setDevice(device.id) { $0.online = false }
            if !(error is CancellationError) { toast = error.localizedDescription }
        }
    }

    public func refreshSessions(for device: Device) async { await refresh(device) }

    private func setDevice(_ id: String, _ mutate: (inout Device) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        mutate(&devices[i])
    }

    public func subscribe(_ device: Device) {
        eventTasks[device.id]?.cancel()
        eventTasks[device.id] = Task { [weak self] in
            guard let self else { return }
            for await ev in client.events(device: device) {
                if Task.isCancelled { break }
                handle(ev, device: device)
            }
        }
    }

    /// App 启动：为每台设备刷新并订阅事件；申请通知权限。
    public func start() async {
        if !isDemo { await Notifier.requestPermission() }
        for d in devices {
            subscribe(d)
            if !isDemo { await refresh(d) }
        }
    }

    // MARK: 会话与消息

    public func loadMessages(_ sessionId: String) async {
        guard !loadedMessages.contains(sessionId), let s = session(sessionId), let device = device(s.deviceId) else { return }
        do {
            var list = try await client.messages(device: device, sessionId: sessionId, after: nil)
            for i in list.indices { list[i].sessionId = sessionId }
            messages[sessionId] = list
            loadedMessages.insert(sessionId)
        } catch { toast = error.localizedDescription }
    }

    public func createSession(_ req: NewSessionRequest) async throws -> Session {
        guard let device = selectedDevice else { throw ConnectorError.badURL }
        var s = try await client.createSession(device: device, request: req)
        s.deviceId = device.id
        if !sessions.contains(where: { $0.id == s.id }) { sessions.insert(s, at: 0) }
        var initial: [Message] = []
        if let first = req.firstMessage, !first.isEmpty { initial.append(Message(sessionId: s.id, role: .user, text: first)) }
        messages[s.id] = initial
        loadedMessages.insert(s.id)
        settings.remember(SessionOptions(mode: req.mode, model: req.model, effort: req.effort), for: req.agent)
        return s
    }

    /// 账号剩余额度；失败时返回带 error 的 QuotaInfo，由面板展示。
    public func quota(for session: Session) async -> QuotaInfo {
        guard let device = device(session.deviceId) else { return QuotaInfo(agent: session.agent.rawValue, error: "设备不在线") }
        do { return try await client.quota(device: device, agent: session.agent) }
        catch { return QuotaInfo(agent: session.agent.rawValue, error: error.localizedDescription) }
    }

    // MARK: 会话选项（模式 / 模型 / 思考强度）

    public func setMode(_ mode: SessionMode, for sessionId: String) async {
        await patchSession(sessionId, ["mode": mode.rawValue]) { $0.mode = mode }
    }
    public func setModel(_ model: String?, for sessionId: String) async {
        let m = model?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        await patchSession(sessionId, ["model": m]) { $0.model = m }
    }
    public func setEffort(_ effort: String?, for sessionId: String) async {
        let e = effort?.nilIfEmpty
        await patchSession(sessionId, ["effort": e]) { $0.effort = e }
    }

    /// 先本地乐观更新，再 PATCH；失败时回滚并提示。
    private func patchSession(_ sessionId: String, _ patch: [String: String?], apply: (inout Session) -> Void) async {
        guard let i = sessions.firstIndex(where: { $0.id == sessionId }), let device = device(sessions[i].deviceId) else { return }
        let before = sessions[i]
        apply(&sessions[i])
        settings.remember(SessionOptions(mode: sessions[i].mode, model: sessions[i].model, effort: sessions[i].effort), for: sessions[i].agent)
        do {
            let s = try await client.configure(device: device, sessionId: sessionId, patch: patch)
            if let j = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[j].mode = s.mode; sessions[j].model = s.model; sessions[j].effort = s.effort }
        } catch {
            if let j = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[j].mode = before.mode; sessions[j].model = before.model; sessions[j].effort = before.effort }
            toast = error.localizedDescription
        }
    }

    public func send(_ text: String, in sessionId: String, attachments: [String] = []) async {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return }
        messages[sessionId, default: []].append(Message(sessionId: sessionId, role: .user, text: text, attachments: attachments))
        if let i = sessions.firstIndex(where: { $0.id == sessionId }), sessions[i].title == "新会话" || sessions[i].title.isEmpty, !text.isEmpty {
            sessions[i].title = String(text.prefix(40))
        }
        setStatus(.running, for: sessionId)
        do { try await client.send(device: device, sessionId: sessionId, text: text, attachments: attachments) }
        catch { toast = error.localizedDescription }
    }

    /// 发送前把本地图片放进缓存，气泡立刻能显示，不用再从连接器拉。
    public func cacheAttachment(_ image: UIImage, id: String) { attachmentImages[id] = image }

    /// 按需从连接器拉附件；失败记入 failedAttachments，气泡显示占位。
    public func loadAttachment(_ id: String, for sessionId: String) async {
        guard attachmentImages[id] == nil, !failedAttachments.contains(id), let s = session(sessionId), let device = device(s.deviceId) else { return }
        do {
            let data = try await client.attachment(device: device, id: id)
            if let img = UIImage(data: data) { attachmentImages[id] = img } else { failedAttachments.insert(id) }
        } catch { failedAttachments.insert(id) }
    }

    /// 上传图片并返回附件 id。
    public func upload(_ data: Data, mime: String, filename: String, for sessionId: String) async -> String? {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return nil }
        do { return try await client.upload(device: device, data: data, mime: mime, filename: filename) }
        catch { toast = error.localizedDescription; return nil }
    }

    public func stop(_ sessionId: String) async {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return }
        do { try await client.stop(device: device, sessionId: sessionId); setStatus(.idle, for: sessionId) }
        catch { toast = error.localizedDescription }
    }

    public func respond(_ approvalId: String, _ decision: ApprovalDecision) async {
        guard let idx = approvals.firstIndex(where: { $0.id == approvalId }) else { return }
        let a = approvals[idx]
        approvals[idx].status = decision == .deny ? .denied : .allowed
        if let sIdx = sessions.firstIndex(where: { $0.id == a.sessionId }) {
            sessions[sIdx].pendingApprovals = max(0, sessions[sIdx].pendingApprovals - 1)
            sessions[sIdx].status = decision == .deny ? .idle : .running
        }
        guard let device = device(a.deviceId) ?? device(session(a.sessionId)?.deviceId ?? "") ?? selectedDevice else { return }
        do { try await client.respond(device: device, approvalId: approvalId, decision: decision) }
        catch { toast = error.localizedDescription }
    }

    private func setStatus(_ status: SessionStatus, for sessionId: String) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[i].status = status
        sessions[i].updatedAt = .now
    }

    private func handle(_ ev: ConnectorEvent, device: Device) {
        switch ev {
        case .sessionCreated(var s):
            s.deviceId = device.id
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
            setDevice(device.id) { $0.sessionCount += 1 }
        case .sessionUpdated(var s):
            s.deviceId = device.id
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s }
        case .sessionStatus(let sid, let st):
            setStatus(st, for: sid)
            setDevice(device.id) { $0.online = true }
        case .messageDelta(let sid, let mid, let text):
            var list = messages[sid, default: []]
            if let i = list.firstIndex(where: { $0.id == mid }) {
                list[i].text += text
            } else {
                list.append(Message(id: mid, sessionId: sid, role: .assistant, text: text, streaming: true))
            }
            messages[sid] = list
            setStatus(.running, for: sid)
        case .messageDone(let sid, let mid):
            if let i = messages[sid]?.firstIndex(where: { $0.id == mid }) { messages[sid]?[i].streaming = false }
            if settings.notifyOnReply, let s = session(sid) { Notifier.post(title: "\(s.agent.displayName) 回复完成", body: s.title, id: "reply-\(mid)") }
        case .toolCall(let sid, let call):
            var list = messages[sid, default: []]
            if let i = list.lastIndex(where: { $0.role == .assistant }) {
                if let j = list[i].toolCalls.firstIndex(where: { $0.id == call.id }) {
                    list[i].toolCalls[j].state = call.state
                    if !call.name.isEmpty { list[i].toolCalls[j].name = call.name }
                    if !call.detail.isEmpty { list[i].toolCalls[j].detail = call.detail }
                } else { list[i].toolCalls.append(call) }
            } else {
                list.append(Message(sessionId: sid, role: .assistant, text: "", toolCalls: [call]))
            }
            messages[sid] = list
        case .approvalRequested(var a):
            a.deviceId = device.id
            guard !approvals.contains(where: { $0.id == a.id }) else { return }
            approvals.insert(a, at: 0)
            messages[a.sessionId, default: []].append(Message(sessionId: a.sessionId, role: .system, text: "", approvalId: a.id))
            setStatus(.waitingApproval, for: a.sessionId)
            if let i = sessions.firstIndex(where: { $0.id == a.sessionId }) { sessions[i].pendingApprovals += 1 }
            if settings.notifyOnApproval { Notifier.post(title: "需要你的批准 · \(a.risk.displayName)", body: a.summary, id: "approval-\(a.id)") }
        case .approvalResolved(let aid, let d):
            if let i = approvals.firstIndex(where: { $0.id == aid }), approvals[i].status == .pending {
                approvals[i].status = d == .deny ? .denied : .allowed
                if let s = sessions.firstIndex(where: { $0.id == approvals[i].sessionId }) { sessions[s].pendingApprovals = max(0, sessions[s].pendingApprovals - 1) }
            }
            Notifier.clear(id: "approval-\(aid)")
        case .disconnected:
            setDevice(device.id) { $0.online = false }
        }
    }
}

// MARK: - 设置（UserDefaults）

public struct Settings: Codable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable { case auto, light, dark }
    public var notifyOnApproval = true
    public var notifyOnReply = true
    public var groupByFolder = true
    public var activeOnly = false
    public var appearance: Appearance = .auto
    public var faceIDForHighRisk = true
    /// 用户手输过的模型 ID，按 Agent 分开记（可选是为了兼容旧版本存下的 JSON）。
    public var customModels: [String: [String]]?
    /// 每种 Agent 上次用的模式 / 模型 / 强度，作为新建会话的默认值。
    public var sessionDefaults: [String: SessionOptions]?
    /// 用户手动维护的模型列表（覆盖连接器 / 内置列表）；nil 表示用默认。
    public var modelPresets: [String: [ModelOption]]?
    /// 会话列表里是否显示电脑终端里跑过的会话。
    public var showTerminalSessionsRaw: Bool?
    public init() {}

    public var showTerminalSessions: Bool {
        get { showTerminalSessionsRaw ?? true }
        set { showTerminalSessionsRaw = newValue }
    }
    public func modelPresets(for agent: AgentKind) -> [ModelOption]? { modelPresets?[agent.rawValue] }
    public mutating func setModelPresets(_ list: [ModelOption]?, for agent: AgentKind) {
        var map = modelPresets ?? [:]
        if let list { map[agent.rawValue] = list } else { map.removeValue(forKey: agent.rawValue) }
        modelPresets = map.isEmpty ? nil : map
    }

    public func customModels(for agent: AgentKind) -> [String] { customModels?[agent.rawValue] ?? [] }
    public mutating func addCustomModel(_ id: String, for agent: AgentKind) {
        var list = customModels(for: agent)
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        customModels = (customModels ?? [:]).merging([agent.rawValue: Array(list.prefix(8))]) { $1 }
    }
    public func defaults(for agent: AgentKind) -> SessionOptions { sessionDefaults?[agent.rawValue] ?? SessionOptions() }
    public mutating func remember(_ options: SessionOptions, for agent: AgentKind) {
        guard defaults(for: agent) != options else { return }
        sessionDefaults = (sessionDefaults ?? [:]).merging([agent.rawValue: options]) { $1 }
    }
    public var colorScheme: ColorScheme? {
        switch appearance { case .auto: nil; case .light: .light; case .dark: .dark }
    }
    static func load() -> Settings {
        guard let d = UserDefaults.standard.data(forKey: "yz.settings"), let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "yz.settings") } }
}

// MARK: - 设备持久化（Application Support/devices.json；Token 在 Keychain）

struct DevicePersistence {
    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YzVibe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("devices.json")
    }
    func load() -> [Device] {
        guard let d = try? Data(contentsOf: url), let list = try? JSONDecoder.yz.decode([Device].self, from: d) else { return [] }
        return list.map { var x = $0; x.online = false; return x }
    }
    func save(_ devices: [Device]) {
        if let d = try? JSONEncoder.yz.encode(devices) { try? d.write(to: url, options: .atomic) }
    }
}

// MARK: - 本地通知（后台时提醒审批 / 回复）

enum Notifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    static func post(title: String, body: String, id: String) {
        Task { @MainActor in
            guard UIApplication.shared.applicationState != .active else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
    static func clear(id: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
