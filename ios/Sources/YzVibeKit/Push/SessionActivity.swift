import Foundation
#if canImport(ActivityKit)
@preconcurrency import ActivityKit
#endif

/// 灵动岛 / 锁屏实时活动的数据结构。放在 YzVibeKit 里，App 与 Widget 扩展共用。
public struct SessionActivityAttributes: Codable, Hashable, Sendable {
    public struct TaskSummary: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var agent: String
        public var status: String
        public var startedAt: Date
    }
    /// 会变的部分。锁屏时由连接器通过 APNs 直接更新，不需要 App 醒着。
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String            // idle / running / waiting_approval / error
        public var headline: String          // 一句话状态，例如「正在执行 npm test」
        public var pendingApprovals: Int
        public var queued: Int
        public var contextPercent: Int?      // 上下文占用
        public var updatedAt: Date
        public var tasks: [TaskSummary]?
        public var totalTasks: Int?
        public var startedAt: Date?

        public init(status: String, headline: String, pendingApprovals: Int = 0, queued: Int = 0, contextPercent: Int? = nil, updatedAt: Date = .now) {
            self.status = status; self.headline = headline; self.pendingApprovals = pendingApprovals
            self.queued = queued; self.contextPercent = contextPercent; self.updatedAt = updatedAt
        }

        public static func overview(_ sessions: [Session], now: Date = .now) -> Self {
            let active = sessions.filter { $0.status == .running || $0.status == .waitingApproval }
                .sorted {
                    if ($0.status == .waitingApproval) != ($1.status == .waitingApproval) { return $0.status == .waitingApproval }
                    let left = $0.runStartedAt ?? $0.updatedAt, right = $1.runStartedAt ?? $1.updatedAt
                    return left == right ? $0.id < $1.id : left < right
                }
            let pending = active.reduce(0) { $0 + max($1.pendingApprovals, $1.status == .waitingApproval ? 1 : 0) }
            var state = Self(status: pending > 0 ? "waiting_approval" : active.isEmpty ? "idle" : "running",
                             headline: active.isEmpty ? "这一轮忙完啦" : "\(active.count) 个任务进行中", pendingApprovals: pending,
                             queued: active.reduce(0) { $0 + $1.queue.count }, updatedAt: now)
            state.tasks = active.prefix(3).map { TaskSummary(id: $0.id, title: String($0.title.prefix(60)), agent: $0.agent.displayName,
                                                           status: $0.status.rawValue, startedAt: $0.runStartedAt ?? $0.updatedAt) }
            state.totalTasks = active.count
            state.startedAt = active.filter { $0.status == .running }.map { $0.runStartedAt ?? $0.updatedAt }.min()
            return state
        }

        public var needsApproval: Bool { pendingApprovals > 0 || status == "waiting_approval" }
        public var isRunning: Bool { status == "running" }
        public var symbol: String { needsApproval ? "exclamationmark.shield.fill" : isRunning ? "bolt.horizontal.fill" : "checkmark.circle.fill" }
        public var shortStatus: String { needsApproval ? "待批准" : isRunning ? "运行中" : "空闲" }
    }

    public var sessionId: String
    public var title: String
    public var agent: String
    public var folder: String
    public var deviceName: String

    public init(sessionId: String, title: String, agent: String, folder: String, deviceName: String) {
        self.sessionId = sessionId; self.title = title; self.agent = agent; self.folder = folder; self.deviceName = deviceName
    }
}

#if canImport(ActivityKit)
extension SessionActivityAttributes: ActivityAttributes {}

/// 实时活动的开始 / 更新 / 结束。汇总当前电脑的运行任务，共用一个灵动岛入口。
@available(iOS 16.2, *)
@MainActor
public enum SessionActivityCenter {
    private static var activity: Activity<SessionActivityAttributes>?
    private static var tokenTask: Task<Void, Never>?
    private static var updateTask: Task<Void, Never>?

    /// 活动的推送 token：交给连接器后，锁屏状态下的更新由电脑直接推过来。
    public static var onPushToken: ((_ sessionId: String, _ token: String) -> Void)?

    public static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    public static var currentSessionId: String? { activity?.attributes.sessionId }

    /// 会话有进展时调用；没有活动就开一个，已有就更新，会话闲下来且没有待办就结束。
    public static func sync(attributes: SessionActivityAttributes, state: SessionActivityAttributes.ContentState) async {
        let previous = updateTask
        let task = Task { @MainActor in
            await previous?.value
            await performSync(attributes: attributes, state: state)
        }
        updateTask = task
        await task.value
    }

    private static func performSync(attributes: SessionActivityAttributes, state: SessionActivityAttributes.ContentState) async {
        guard enabled else { return }
        if activity == nil {
            activity = Activity<SessionActivityAttributes>.activities.first(where: { $0.attributes.sessionId == attributes.sessionId && ($0.activityState == .active || $0.activityState == .stale) })
            if let activity { observeToken(activity) }
        }
        if let a = activity, a.activityState == .ended || a.activityState == .dismissed { activity = nil }
        let idle = !state.isRunning && !state.needsApproval && state.queued == 0
        if let a = activity, a.attributes.sessionId == attributes.sessionId {
            if idle { await end() } else { await a.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(600))) }
            return
        }
        guard !idle else { return }
        await end()
        do {
            let a = try Activity.request(attributes: attributes,
                                         content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(600)),
                                         pushType: .token)
            activity = a
            observeToken(a)
        } catch {
            activity = nil
        }
    }

    private static func observeToken(_ a: Activity<SessionActivityAttributes>) {
        tokenTask?.cancel()
        if let token = a.pushToken { onPushToken?(a.attributes.sessionId, token.map { String(format: "%02x", $0) }.joined()) }
        tokenTask = Task {
            for await data in a.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                onPushToken?(a.attributes.sessionId, data.map { String(format: "%02x", $0) }.joined())
            }
        }
    }

    public static func stopAll() async {
        let previous = updateTask
        let task = Task { @MainActor in await previous?.value; await end() }
        updateTask = task
        await task.value
    }

    public static func end() async {
        tokenTask?.cancel(); tokenTask = nil
        activity = nil
        for a in Activity<SessionActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
#endif
