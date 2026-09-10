import Foundation
#if canImport(ActivityKit)
@preconcurrency import ActivityKit
#endif

/// 灵动岛 / 锁屏实时活动的数据结构。放在 YzVibeKit 里，App 与 Widget 扩展共用。
public struct SessionActivityAttributes: Codable, Hashable, Sendable {
    /// 会变的部分。锁屏时由连接器通过 APNs 直接更新，不需要 App 醒着。
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String            // idle / running / waiting_approval / error
        public var headline: String          // 一句话状态，例如「正在执行 npm test」
        public var pendingApprovals: Int
        public var queued: Int
        public var contextPercent: Int?      // 上下文占用
        public var updatedAt: Date

        public init(status: String, headline: String, pendingApprovals: Int = 0, queued: Int = 0, contextPercent: Int? = nil, updatedAt: Date = .now) {
            self.status = status; self.headline = headline; self.pendingApprovals = pendingApprovals
            self.queued = queued; self.contextPercent = contextPercent; self.updatedAt = updatedAt
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

/// 实时活动的开始 / 更新 / 结束。一次只跟一个会话——就是你当下在等的那个。
@available(iOS 16.2, *)
@MainActor
public enum SessionActivityCenter {
    private static var activity: Activity<SessionActivityAttributes>?
    private static var tokenTask: Task<Void, Never>?

    /// 活动的推送 token：交给连接器后，锁屏状态下的更新由电脑直接推过来。
    public static var onPushToken: ((_ sessionId: String, _ token: String) -> Void)?

    public static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    public static var currentSessionId: String? { activity?.attributes.sessionId }

    /// 会话有进展时调用；没有活动就开一个，已有就更新，会话闲下来且没有待办就结束。
    public static func sync(attributes: SessionActivityAttributes, state: SessionActivityAttributes.ContentState) async {
        guard enabled else { return }
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
            tokenTask?.cancel()
            tokenTask = Task {
                for await data in a.pushTokenUpdates {
                    let hex = data.map { String(format: "%02x", $0) }.joined()
                    await MainActor.run { onPushToken?(attributes.sessionId, hex) }
                }
            }
        } catch {
            activity = nil
        }
    }

    public static func end() async {
        tokenTask?.cancel(); tokenTask = nil
        guard let a = activity else { return }
        activity = nil
        await a.end(nil, dismissalPolicy: .immediate)
    }
}
#endif
