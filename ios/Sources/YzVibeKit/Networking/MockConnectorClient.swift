import Foundation
import UIKit

/// 离线 Mock：返回设计稿里的示例数据，并模拟一次流式回复与审批事件。
public final class MockConnectorClient: ConnectorClient, @unchecked Sendable {
    public init() {}
    /// 改过选项的会话（真实连接器会返回权威的完整会话，这里用它模拟）。
    private var configured: [String: Session] = [:]

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
    public func respond(device: Device, approvalId: String, decision: ApprovalDecision, remember: ApprovalSuggestion?) async throws {}
    public func sync(device: Device) async throws -> SyncSnapshot {
        SyncSnapshot(sessions: MockData.sessions, approvals: MockData.approvals, agents: ["claude": .fallback(for: .claude), "codex": .fallback(for: .codex)],
                     rules: [ApprovalRule(id: "r1", tool: "Bash", match: "prefix", value: "npm test", description: "本会话内放行以 npm test 开头的命令")],
                     push: PushStatus(ready: false, missing: "推送密钥 .p8、teamId"))
    }
    public func rules(device: Device, sessionId: String?) async throws -> [ApprovalRule] { try await sync(device: device).rules }
    public func deleteRule(device: Device, id: String) async throws {}
    public func registerPush(device: Device, token: String, environment: String) async throws -> PushStatus { PushStatus(ready: true, registeredDevices: 1, environment: environment) }
    public func unregisterPush(device: Device) async throws {}
    public func registerLiveActivity(device: Device, sessionId: String, token: String) async throws {}
    public func reconnect(device: Device) {}
    public func sendMessage(device: Device, sessionId: String, text: String, attachments: [String], mode: SendMode) async throws -> (queued: Bool, item: QueuedMessage?) {
        let busy = MockData.sessions.first { $0.id == sessionId }?.status == .running
        return busy && mode != .now ? (true, QueuedMessage(text: text, attachments: attachments)) : (false, nil)
    }
    public func cancelQueued(device: Device, sessionId: String, itemId: String) async throws {}
    public func diff(device: Device, sessionId: String, scope: String) async throws -> WorkingDiff {
        WorkingDiff(branch: "main", head: "a1b2c3d 上一次提交",
                    files: [DiffFile(path: "src/components/map/YtMarker.tsx", status: "已修改", added: 42, removed: 8,
                                     diff: "diff --git a/src/components/map/YtMarker.tsx\n-const tone = props.tone\n+const tone = props.tone ?? defaultTone\n Ok"),
                            DiffFile(path: "src/components/map/YtMarker.test.tsx", status: "新增", untracked: true, added: 31, removed: 0,
                                     diff: "新文件 YtMarker.test.tsx\n+import { describe } from 'vitest'\n+describe('YtMarker', () => {})")],
                    totals: .init(files: 2, added: 73, removed: 8))
    }
    public func commands(device: Device, sessionId: String) async throws -> CommandCatalog {
        CommandCatalog(app: [SlashCommand(name: "new", args: "[提示词]", description: "在同一目录新建一个会话", kind: "app", source: "YzVibe", action: "new-session"),
                             SlashCommand(name: "diff", description: "看这个目录现在有哪些改动", kind: "app", source: "YzVibe", action: "diff")],
                       agentCommands: [SlashCommand(name: "compact", args: "[要保留的重点]", description: "压缩上下文", source: "Claude Code 内置")],
                       skills: [SlashCommand(name: "code-review", description: "审查当前改动", kind: "skill", source: "个人 skill")],
                       reported: true)
    }

    public func approvals(device: Device) async throws -> [Approval] { MockData.approvals.filter { $0.deviceId == device.id } }
    public func attachment(device: Device, id: String) async throws -> Data {
        // 演示用：一张带 id 后四位的色块图
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: fmt).image { ctx in
            UIColor(hue: CGFloat(abs(id.hashValue % 360)) / 360, saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        return img.jpegData(compressionQuality: 0.8) ?? Data()
    }
    public func quota(device: Device, agent: AgentKind) async throws -> QuotaInfo {
        try await Task.sleep(nanoseconds: 300_000_000)
        if agent == .codex { return QuotaInfo(agent: "codex", unavailable: "Codex 非交互模式暂无额度接口") }
        return QuotaInfo(agent: "claude", source: "oauth", fetchedAt: .now, limits: [
            QuotaLimit(id: "session", label: "当前会话（5 小时）", percent: 24, resetsAt: .now.addingTimeInterval(3600 * 2)),
            QuotaLimit(id: "weekly_all", label: "本周（所有模型）", percent: 26, resetsAt: .now.addingTimeInterval(86400 * 4)),
            QuotaLimit(id: "weekly_fable", label: "本周（Fable）", percent: 45, resetsAt: .now.addingTimeInterval(86400 * 4)),
        ], extraUsage: .init(enabled: false, usedCredits: 0, monthlyLimit: 100, percent: 0, currency: "USD"))
    }
    public func capabilities(device: Device) async throws -> [String: AgentCapabilities] {
        ["claude": .fallback(for: .claude), "codex": .fallback(for: .codex)]
    }
    public func configure(device: Device, sessionId: String, patch: [String: String?]) async throws -> Session {
        var s = configured[sessionId] ?? MockData.sessions.first { $0.id == sessionId } ?? Session(id: sessionId, deviceId: device.id, agent: .claude, cwd: "", title: "会话")
        if let m = patch["mode"], let raw = m, let mode = SessionMode(rawValue: raw) { s.mode = mode }
        if let v = patch["model"] { s.model = v }
        if let v = patch["effort"] { s.effort = v }
        configured[sessionId] = s
        return s
    }
    public func upload(device: Device, data: Data, mime: String, filename: String) async throws -> String { UUID().uuidString }
    public func listFiles(device: Device, sessionId: String, path: String) async throws -> [FileEntry] { MockData.files }

    public func fileInfo(device: Device, sessionId: String, path: String) async throws -> FileInfo {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return FileInfo(name: name, path: path, displayPath: path,
                        kind: MockData.files.first { $0.path == path }?.kind ?? .code,
                        size: 1280, mime: "text/plain", textual: true, inCwd: true)
    }

    public func download(device: Device, sessionId: String, path: String) async throws -> Data {
        Data((try await preview(device: device, sessionId: sessionId, path: path)).utf8)
    }

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

    public func listDirectories(device: Device, path: String?) async throws -> DirectoryListing {
        let base = path ?? "/Users/yuki"
        let names: [String] = base.hasSuffix("YzVibe") ? ["android", "connector", "design", "docs", "ios", "miniprogram", "shared"]
            : base.hasSuffix("aigc") ? ["YzVibe", "yukiTrace", "lobehub"] : ["devops", "Documents", "Downloads"]
        let parent = base == "/" ? nil : (base as NSString).deletingLastPathComponent
        return DirectoryListing(path: base, parent: parent, home: "/Users/yuki", entries: names.map { .init(name: $0, path: base + "/" + $0) })
    }
    public func makeDirectory(device: Device, parent: String, name: String) async throws -> String { parent + "/" + name }

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
