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
    public var rules: [String: [ApprovalRule]] = [:]                       // deviceId → 审批规则
    public var pushStatus: [String: PushStatus] = [:]                      // deviceId → 连接器的推送配置状态
    public var hiddenSessionCount: [String: Int] = [:]                     // deviceId → 被删掉、可一键恢复的会话数
    public private(set) var pushToken: String?
    public private(set) var lastSyncAt: Date?
    /// 点开推送后要打开的会话（SessionsView 消费后清空）。
    public var openSessionRequest: String?
    public var attachmentImages: [String: UIImage] = [:]                   // 上传 id → 图片（会话里展示用）
    public var failedAttachments: Set<String> = []
    public var settings = Settings() { didSet { settings.save() } }
    public var toast: String?
    var chatDrafts: [String: ChatDraft] = [:]
    public private(set) var isDemo: Bool

    public let client: any ConnectorClient
    private let persistence = DevicePersistence()
    private var eventTasks: [String: Task<Void, Never>] = [:]
    private var loadedMessages: Set<String> = []
    /// 每个会话「服务端已确认的最后一条消息」，断线重连后从这里往后补。
    private var syncCursor: [String: String] = [:]
    private var syncing = false
    private var deletingSessionIDs: Set<String> = []
    /// 局域网发现（测试里换成假的）。
    public var lanDiscovery: @Sendable (TimeInterval) async -> [DiscoveredConnector] = { await LANDiscovery.shared.discover(timeout: $0) }

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
        // 隧道换地址后客户端会自己探到能用的那个，这里把它记下来，下次直接用
        client.onEndpointResolved = { [weak store] deviceId, base in
            Task { @MainActor in store?.adoptEndpoint(deviceId, base: base) }
        }
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
    public var allRules: [ApprovalRule] { devices.compactMap { rules[$0.id] }.flatMap { $0 } }
    public func rules(for deviceId: String?) -> [ApprovalRule] { rules[deviceId ?? ""] ?? [] }
    public var push: PushStatus? { pushStatus[selectedDevice?.id ?? ""] }
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
            .filter { !activeOnly || $0.status == .running || $0.status == .waitingApproval || !$0.queue.isEmpty }
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
        if let extra = payload.endpoints, !extra.isEmpty { device.endpoints = extra }
        devices.removeAll { $0.id == device.id || ($0.host == device.host && $0.port == device.port) }
        devices.insert(device, at: 0)
        selectedDeviceId = device.id
        await refresh(device)
        subscribe(device)
        if let t = pushToken ?? PushCenter.shared.token { await registerPush(token: t, environment: PushCenter.shared.environment) }
        toast = "已配对 \(device.name)"
    }

    public func addManual(host: String, port: Int, token: String) async throws {
        try await pair(PairingPayload(host: host, port: port, token: token, mode: host.contains("://") ? .relay : .local))
    }

    func updateDevice(_ updated: Device) {
        guard let index = devices.firstIndex(where: { $0.id == updated.id }) else { return }
        devices[index] = updated
        if !isDemo { client.reconnect(device: updated); subscribe(updated) }
        toast = "设备配置已保存"
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

    // MARK: 断线重同步
    // iOS 把 App 挂起时会悄悄断掉 WebSocket，离线期间的消息、状态、审批都收不到。
    // 回到前台（或收到静默推送）时走这里：立刻重连事件通道，再把落下的数据补齐。

    public func resync() async {
        guard !isDemo, !syncing else { return }
        syncing = true
        defer { syncing = false }
        for d in devices {
            client.reconnect(device: d)
            subscribe(d)
            await syncDevice(d)
            // 所有已知地址都不通：多半是隧道换了地址，去局域网里找一找
            if device(d.id)?.online == false { await reconnectViaLAN(d) }
        }
        lastSyncAt = .now
    }

    private func syncDevice(_ device: Device) async {
        do {
            let snap = try await client.sync(device: device)
            capabilities[device.id] = snap.agents
            pushStatus[device.id] = snap.push
            rules[device.id] = snap.rules
            hiddenSessionCount[device.id] = snap.hiddenSessions

            if let health = try? await client.health(device: device), !health.endpoints.isEmpty {
                if let i = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[i].endpoints = health.endpoints
                }
            }
            let fresh = snap.sessions.map { var s = $0; s.deviceId = device.id; return s }
            sessions.removeAll { $0.deviceId == device.id }
            sessions.append(contentsOf: fresh)

            let pending = snap.approvals.map { var a = $0; a.deviceId = device.id; return a }
            approvals.removeAll { $0.deviceId == device.id && $0.status == .pending }
            approvals.insert(contentsOf: pending, at: 0)
            for a in pending where !(messages[a.sessionId] ?? []).contains(where: { $0.approvalId == a.id }) {
                messages[a.sessionId, default: []].append(Message(sessionId: a.sessionId, role: .system, text: "", approvalId: a.id))
            }

            setDevice(device.id) { $0.online = true; $0.lastSeen = .now
                $0.sessionCount = fresh.filter { $0.status != .closed }.count
                $0.agents = Dictionary(grouping: fresh, by: \.agent).mapValues(\.count) }

            // 已经打开过的会话补上离线期间的新消息
            for sid in loadedMessages where fresh.contains(where: { $0.id == sid }) {
                await catchUpMessages(sid)
            }
            if pushToken == nil, let t = PushCenter.shared.token { await registerPush(token: t, environment: PushCenter.shared.environment) }
        } catch {
            setDevice(device.id) { $0.online = false }
        }
    }

    /// 前台恢复时读取已打开会话的完整快照，更新断线期间发生变化的旧消息。
    private func catchUpMessages(_ sessionId: String) async {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return }
        do {
            var fetched = try await client.messages(device: device, sessionId: sessionId, after: nil)
            guard !fetched.isEmpty else { return }
            for i in fetched.indices { fetched[i].sessionId = sessionId }
            let newest = fetched.last?.createdAt ?? .distantPast
            let pending = (messages[sessionId] ?? []).filter { $0.isLocal && $0.createdAt > newest }
            var merged = fetched + pending
            merged.sort { $0.createdAt < $1.createdAt }
            messages[sessionId] = merged
            syncCursor[sessionId] = fetched.last?.id
        } catch { }
    }

    private func setDevice(_ id: String, _ mutate: (inout Device) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        mutate(&devices[i])
    }

    public func subscribe(_ device: Device) {
        // WS 重连由 client 管理，刷新快照不应反复取消消费者。
        guard eventTasks[device.id] == nil else { return }
        eventTasks[device.id] = Task { [weak self] in
            guard let self else { return }
            for await ev in client.events(device: device) {
                if Task.isCancelled { break }
                handle(ev, device: device)
            }
            if !Task.isCancelled { eventTasks[device.id] = nil }
        }
    }

    /// App 启动：为每台设备刷新并订阅事件；申请通知权限。
    public func start() async {
        guard !isDemo else { return }        // 演示数据里的设备是假的，别去连
        PushCenter.shared.onToken = { [weak self] token, env in Task { @MainActor in await self?.registerPush(token: token, environment: env) } }
        PushCenter.shared.onSilent = { [weak self] in await self?.resync() }
        // 电脑重启或隧道换地址时会静默推一条过来，收到就直接换地址，不用重新扫码
        PushCenter.shared.onEndpoint = { [weak self] info in
            Task { @MainActor in
                guard let self, let id = info.connectorId, let base = info.endpoints.first else { return }
                self.adoptEndpoint(id, base: base, endpoints: info.endpoints)
                await self.resync()
            }
        }
        await PushCenter.shared.start()
        for d in devices { subscribe(d) }
        await resync()
    }

    // MARK: 锁屏 / 灵动岛实时活动

    /// 把会话状态同步到实时活动上。活动的推送 token 交给电脑后，锁屏时也会持续更新。
    public func syncLiveActivity(_ sessionId: String) {
        guard !isDemo, settings.liveActivity else { return }
        guard #available(iOS 16.2, *), let s = session(sessionId) else { return }
        let device = device(s.deviceId)
        let attrs = SessionActivityAttributes(sessionId: s.id, title: s.title, agent: s.agent.displayName,
                                              folder: s.folderName, deviceName: device?.name ?? "电脑")
        let pending = approvals.filter { $0.sessionId == s.id && $0.status == .pending }.count
        let state = SessionActivityAttributes.ContentState(
            status: s.status.rawValue, headline: headline(for: s, pending: pending),
            pendingApprovals: pending, queued: s.queue.count,
            contextPercent: s.usage?.turn.contextFraction.map { Int(($0 * 100).rounded()) })
        Task { @MainActor in
            SessionActivityCenter.onPushToken = { [weak self] sid, token in
                Task { @MainActor in await self?.registerLiveActivity(sessionId: sid, token: token) }
            }
            await SessionActivityCenter.sync(attributes: attrs, state: state)
        }
    }

    private func headline(for s: Session, pending: Int) -> String {
        if pending > 0, let a = approvals.first(where: { $0.sessionId == s.id && $0.status == .pending }) { return "等你批准：\(a.summary)" }
        if s.status == .running {
            if let tool = messages[s.id]?.last(where: { !$0.toolCalls.isEmpty })?.toolCalls.last(where: { $0.state == .running }) {
                return "正在 \(tool.name)：\(tool.detail)"
            }
            return "正在处理…"
        }
        if s.status == .error { return "出错了，去看看" }
        return messages[s.id]?.last(where: { $0.role == .assistant && !$0.text.isEmpty })?.text.prefix(80).description ?? "已完成"
    }

    private func registerLiveActivity(sessionId: String, token: String) async {
        guard let s = session(sessionId), let d = device(s.deviceId) else { return }
        try? await client.registerLiveActivity(device: d, sessionId: sessionId, token: token)
    }

    // MARK: 远程推送

    /// 把 APNs token 交给每一台已配对的电脑；有了它，App 被挂起时审批也能弹到锁屏上。
    public func registerPush(token: String, environment: String) async {
        pushToken = token
        for d in devices {
            if let st = try? await client.registerPush(device: d, token: token, environment: environment) { pushStatus[d.id] = st }
        }
    }

    public func disablePush() async {
        for d in devices { try? await client.unregisterPush(device: d) }
        pushToken = nil
        for k in pushStatus.keys { pushStatus[k]?.registeredDevices = 0 }
    }

    // MARK: 审批规则

    public func loadRules(for device: Device) async {
        if let list = try? await client.rules(device: device, sessionId: nil) { rules[device.id] = list }
    }

    public func deleteRule(_ rule: ApprovalRule, on deviceId: String) async {
        guard let d = device(deviceId) else { return }
        rules[deviceId]?.removeAll { $0.id == rule.id }
        do { try await client.deleteRule(device: d, id: rule.id) }
        catch { toast = error.localizedDescription; await loadRules(for: d) }
    }

    // MARK: 会话与消息

    public func loadMessages(_ sessionId: String) async {
        guard !loadedMessages.contains(sessionId), let s = session(sessionId), let device = device(s.deviceId) else { return }
        do {
            var list = try await client.messages(device: device, sessionId: sessionId, after: nil)
            for i in list.indices { list[i].sessionId = sessionId }
            messages[sessionId] = list
            syncCursor[sessionId] = list.last?.id
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

    /// 连接器确认删除后再移除本地会话，离线或请求失败时保留消息与列表。
    /// 删的只是 YzVibe 的记录，Claude / Codex 自己的 transcript 不动。
    public func deleteSession(_ id: String) async {
        guard let s = session(id) else { return }
        guard deletingSessionIDs.insert(id).inserted else { return }
        defer { deletingSessionIDs.remove(id) }
        if isDemo {
            forgetLocally(id)
            toast = "已删除会话"
            return
        }
        guard let device = device(s.deviceId) else {
            toast = "删除失败：找不到会话所属设备"
            return
        }
        do {
            try await client.deleteSession(device: device, sessionId: id)
            forgetLocally(id)
            hiddenSessionCount[device.id] = (hiddenSessionCount[device.id] ?? 0) + 1
            setDevice(device.id) { $0.sessionCount = max(0, $0.sessionCount - 1) }
            toast = "已删除会话"
        } catch {
            toast = "删除失败：\(error.localizedDescription)"
        }
    }

    /// 把删掉的会话都放回来（终端扫出来的会重新出现）。
    public func restoreHiddenSessions(on deviceId: String) async {
        guard let d = device(deviceId) else { return }
        do {
            let n = try await client.restoreHiddenSessions(device: d)
            hiddenSessionCount[d.id] = 0
            await refresh(d)
            toast = n > 0 ? "已恢复 \(n) 个会话" : "没有可恢复的会话"
        } catch { toast = error.localizedDescription }
    }

    private func forgetLocally(_ id: String) {
        chatDrafts[id] = nil
        sessions.removeAll { $0.id == id }
        messages[id] = nil
        loadedMessages.remove(id)
        syncCursor[id] = nil
        approvals.removeAll { $0.sessionId == id }
    }

    /// 账号剩余额度；失败时返回带 error 的 QuotaInfo，由面板展示。
    public func quota(for session: Session) async -> QuotaInfo {
        guard let device = device(session.deviceId) else { return QuotaInfo(agent: session.agent.rawValue, error: "设备不在线") }
        do { return try await client.quota(device: device, agent: session.agent) }
        catch { return QuotaInfo(agent: session.agent.rawValue, error: error.localizedDescription) }
    }

    // MARK: 会话选项（模式 / 模型 / 思考强度）

    func renameSession(_ sessionId: String, to name: String) async -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf16.count <= 200,
              let session = session(sessionId), let device = device(session.deviceId) else { return false }
        do {
            let updated = try await client.configure(device: device, sessionId: sessionId, patch: ["title": title])
            guard updated.title == title else {
                toast = "连接器尚不支持重命名，请更新电脑端连接器"
                return false
            }
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[index].title = updated.title }
            return true
        } catch {
            toast = error.localizedDescription
            return false
        }
    }

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

    /// Agent 正忙时默认排队（`mode = .auto`），`.now` 会插到队首并打断当前这一轮。
    @discardableResult
    public func send(_ text: String, in sessionId: String, attachments: [String] = [], mode: SendMode = .auto) async -> Bool {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return false }
        let willQueue = s.queuePaused || !s.queue.isEmpty || (mode != .now && (s.status == .running || s.status == .waitingApproval))
        if !willQueue {
            messages[sessionId, default: []].append(Message(sessionId: sessionId, role: .user, text: text, attachments: attachments, isLocal: true))
            setStatus(.running, for: sessionId)
        }
        if let i = sessions.firstIndex(where: { $0.id == sessionId }), sessions[i].title == "新会话" || sessions[i].title.isEmpty, !text.isEmpty {
            sessions[i].title = String(text.prefix(40))
        }
        do {
            let r = try await client.sendMessage(device: device, sessionId: sessionId, text: text, attachments: attachments, mode: mode)
            if r.queued, let item = r.item, let i = sessions.firstIndex(where: { $0.id == sessionId }),
               !sessions[i].queue.contains(where: { $0.id == item.id }) {
                sessions[i].queue.append(item)
            }
            return r.queued
        } catch {
            toast = error.localizedDescription
            return false
        }
    }

    /// 撤掉一条还没发出去的排队消息。
    func sendQueuedNow(_ itemId: String, in sessionId: String) async {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return }
        do {
            _ = try await client.sendQueuedNow(device: device, sessionId: sessionId, itemId: itemId)
            await refresh(device)
        } catch { toast = error.localizedDescription }
    }

    public func resumeQueue(in sessionId: String) async {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return }
        do {
            var updated = try await client.resumeQueue(device: device, sessionId: sessionId)
            updated.deviceId = device.id
            if let i = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[i] = updated }
        } catch { toast = error.localizedDescription }
    }

    public func cancelQueued(_ itemId: String, in sessionId: String) async {
        guard let i = sessions.firstIndex(where: { $0.id == sessionId }), let device = device(sessions[i].deviceId) else { return }
        let backup = sessions[i].queue
        sessions[i].queue.removeAll { $0.id == itemId }
        do { try await client.cancelQueued(device: device, sessionId: sessionId, itemId: itemId) }
        catch { sessions[i].queue = backup; toast = error.localizedDescription }
    }

    // MARK: 改动视图与命令面板

    public func diff(for sessionId: String, scope: String = "working") async -> WorkingDiff? {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return nil }
        do { return try await client.diff(device: device, sessionId: sessionId, scope: scope) }
        catch { toast = error.localizedDescription; return nil }
    }

    public func commands(for sessionId: String) async -> CommandCatalog? {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return nil }
        return try? await client.commands(device: device, sessionId: sessionId)
    }

    // MARK: 地址变化

    /// 换用一个新的连接地址（故障转移探到的，或电脑通过静默推送下发的）。
    /// 连不上了就在局域网里把这台电脑找回来。
    ///
    /// 临时隧道每次重开都是新地址，没配推送时连接器没法主动告诉手机；但只要还在同一个 Wi-Fi，
    /// 它就在广播 `_yzvibe._tcp`。按 connectorId 认人，认准了直接换地址，不用重新扫码。
    @discardableResult
    public func reconnectViaLAN(_ device: Device, quiet: Bool = true) async -> Bool {
        guard !isDemo else { return false }
        let found = await lanDiscovery(3)
        var base = found.first { $0.connectorId == device.id }?.base
        if base == nil {
            // 老连接器的广播里没有 id，只能挨个探 /health 验明正身
            for f in found where f.connectorId == nil {
                var probe = device; probe.adopt(base: f.base)
                guard let h = try? await client.health(device: probe) else { continue }
                if h.connectorId == device.id || (h.connectorId == nil && h.name == device.name) { base = f.base; break }
            }
        }
        guard let base else {
            if !quiet { toast = found.isEmpty ? "同一个 Wi-Fi 下没找到这台电脑" : "找到了别的电脑，但不是这一台" }
            return false
        }
        adoptEndpoint(device.id, base: base)
        if let fresh = self.device(device.id) { await syncDevice(fresh) }
        if !quiet { toast = "已切到局域网地址 \(base)" }
        return true
    }

    public func adoptEndpoint(_ deviceId: String, base: String, endpoints: [String]? = nil) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        if let endpoints { for e in endpoints.reversed() where !devices[i].endpoints.contains(e) { devices[i].endpoints.insert(e, at: 0) } }
        devices[i].adopt(base: base)
        client.reconnect(device: devices[i])
    }

    /// 发送前把本地图片放进缓存，气泡立刻能显示，不用再从连接器拉。
    public func cacheAttachment(_ image: UIImage, id: String) {
        attachmentImages[id] = image
        failedAttachments.remove(id)
    }

    private var loadingAttachments: Set<String> = []

    /// 按需从连接器拉附件；失败记入 failedAttachments，气泡显示占位。
    public func loadAttachment(_ id: String, for sessionId: String) async {
        guard attachmentImages[id] == nil, let s = session(sessionId), let device = device(s.deviceId), loadingAttachments.insert(id).inserted else { return }
        defer { loadingAttachments.remove(id) }
        failedAttachments.remove(id)
        do {
            let data = try await client.attachment(device: device, id: id)
            if let img = UIImage(data: data) { cacheAttachment(img, id: id) } else { failedAttachments.insert(id) }
        } catch is CancellationError { }
        catch { failedAttachments.insert(id) }
    }

    /// 上传图片并返回附件 id。
    public func upload(_ data: Data, mime: String, filename: String, for sessionId: String) async -> String? {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return nil }
        do { return try await client.upload(device: device, data: data, mime: mime, filename: filename) }
        catch { toast = error.localizedDescription; return nil }
    }

    public func stop(_ sessionId: String) async {
        guard let s = session(sessionId), let device = device(s.deviceId) else { return }
        do { try await client.stop(device: device, sessionId: sessionId) }
        catch { toast = error.localizedDescription }
    }

    public func respond(_ approvalId: String, _ decision: ApprovalDecision, remember: ApprovalSuggestion? = nil, answers: [String: String]? = nil) async {
        guard let a = approvals.first(where: { $0.id == approvalId }),
              let device = device(a.deviceId) ?? device(session(a.sessionId)?.deviceId ?? "") ?? selectedDevice else { return }
        do {
            try await client.respond(device: device, approvalId: approvalId, decision: decision, remember: remember, answers: answers)
            if let idx = approvals.firstIndex(where: { $0.id == approvalId }), approvals[idx].status == .pending {
                approvals[idx].status = decision == .deny ? .denied : .allowed
                if let si = sessions.firstIndex(where: { $0.id == a.sessionId }) {
                    sessions[si].pendingApprovals = max(0, sessions[si].pendingApprovals - 1)
                    if sessions[si].status == .waitingApproval && sessions[si].pendingApprovals == 0 {
                        sessions[si].status = .running
                    }
                }
            }
            if remember != nil { await loadRules(for: device) }
        } catch { toast = error.localizedDescription }
    }

    private func setStatus(_ status: SessionStatus, for sessionId: String) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[i].status = status
        sessions[i].updatedAt = .now
    }

    func handle(_ ev: ConnectorEvent, device: Device) {
        switch ev {
        case .sessionCreated(var s):
            s.deviceId = device.id
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
            setDevice(device.id) { $0.sessionCount += 1 }
        case .sessionUpdated(var s):
            s.deviceId = device.id
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s }
        case .sessionRemoved(let sid):
            forgetLocally(sid)
            setDevice(device.id) { $0.sessionCount = max(0, $0.sessionCount - 1) }
        case .sessionStatus(let sid, let st):
            setStatus(st, for: sid)
            setDevice(device.id) { $0.online = true }
            syncLiveActivity(sid)
        case .messageUpdated(let message):
            if let i = messages[message.sessionId]?.firstIndex(where: { $0.id == message.id }) {
                messages[message.sessionId]?[i] = message
            } else { messages[message.sessionId, default: []].append(message) }
        case .messageDelta(let sid, let mid, let text):
            var list = messages[sid, default: []]
            if let i = list.firstIndex(where: { $0.id == mid }) {
                list[i].text += text
            } else {
                list.append(Message(id: mid, sessionId: sid, role: .assistant, text: text, streaming: true))
            }
            messages[sid] = list
            if (session(sid)?.pendingApprovals ?? 0) == 0 { setStatus(.running, for: sid) }
        case .messageDone(let sid, let mid):
            if let i = messages[sid]?.firstIndex(where: { $0.id == mid }) { messages[sid]?[i].streaming = false }
            syncCursor[sid] = mid
            if settings.notifyOnReply, let s = session(sid) { Notifier.post(title: "\(s.agent.displayName) 回复完成", body: s.title, id: "reply-\(mid)") }
        case .toolCall(let sid, let call, let messageId):
            var list = messages[sid, default: []]
            if let i = list.lastIndex(where: { messageId != nil ? $0.id == messageId : $0.role == .assistant }) {
                if let j = list[i].toolCalls.firstIndex(where: { $0.id == call.id }) {
                    list[i].toolCalls[j].state = call.state
                    if !call.name.isEmpty { list[i].toolCalls[j].name = call.name }
                    if !call.detail.isEmpty { list[i].toolCalls[j].detail = call.detail }
                } else { list[i].toolCalls.append(call) }
            } else {
                list.append(Message(id: messageId ?? UUID().uuidString, sessionId: sid, role: .assistant, text: "", toolCalls: [call]))
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
            syncLiveActivity(a.sessionId)
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
    /// 锁屏 / 灵动岛上显示会话状态。
    public var liveActivityRaw: Bool?
    /// 用户手动维护的模型列表（覆盖连接器 / 内置列表）；nil 表示用默认。
    public var modelPresets: [String: [ModelOption]]?
    /// 会话列表里是否显示电脑终端里跑过的会话。
    public var showTerminalSessionsRaw: Bool?
    public init() {}

    public var liveActivity: Bool {
        get { liveActivityRaw ?? true }
        set { liveActivityRaw = newValue }
    }
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
