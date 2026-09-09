import Foundation

/// 离线 Mock：返回设计稿里的示例数据，并模拟一次流式回复与审批事件。
public final class MockConnectorClient: ConnectorClient, @unchecked Sendable {
    public init() {}

    public func health(device: Device) async throws -> HealthInfo {
        try await Task.sleep(nanoseconds: 300_000_000)
        return HealthInfo(name: device.name, version: "0.1.0", agents: ["claude", "codex"])
    }

    public func pair(_ payload: PairingPayload) async throws -> Device {
        try await Task.sleep(nanoseconds: 600_000_000)
        return Device(name: payload.name ?? "新配对的电脑", host: payload.host, port: payload.port, mode: payload.mode, online: true)
    }

    public func sessions(device: Device) async throws -> [Session] {
        MockData.sessions.filter { $0.deviceId == device.id }
    }

    public func createSession(device: Device, request: NewSessionRequest) async throws -> Session {
        try await Task.sleep(nanoseconds: 500_000_000)
        let title = request.firstMessage?.isEmpty == false ? request.firstMessage! : "新会话"
        return Session(deviceId: device.id, agent: request.agent, cwd: request.cwd, title: String(title.prefix(24)), status: .running)
    }

    public func messages(device: Device, sessionId: String, after cursor: String?) async throws -> [Message] {
        MockData.messages(for: sessionId)
    }

    public func send(device: Device, sessionId: String, text: String, attachments: [String]) async throws {}
    public func stop(device: Device, sessionId: String) async throws {}
    public func respond(device: Device, approvalId: String, decision: ApprovalDecision) async throws {}

    public func approvals(device: Device) async throws -> [Approval] { MockData.approvals.filter { $0.deviceId == device.id } }
    public func upload(device: Device, data: Data, mime: String, filename: String) async throws -> String { UUID().uuidString }
    public func listFiles(device: Device, sessionId: String, path: String) async throws -> [FileEntry] { MockData.files }

    public func preview(device: Device, sessionId: String, path: String) async throws -> String {
        """
        export function YtMarker({ tone }: Props) {
          return (
            <span className="yt-marker"
              style={{ background: tone }} />
          )
        }
        """
    }

    public func events(device: Device) -> AsyncStream<ConnectorEvent> {
        AsyncStream { cont in
            let task = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let mid = UUID().uuidString
                for chunk in ["收到。", "我会先", "保留 legacy 目录，", "等你批准后再删除。"] {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    cont.yield(.messageDelta(sessionId: "s1", messageId: mid, text: chunk))
                }
                cont.yield(.messageDone(sessionId: "s1", messageId: mid))
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
