import Foundation

/// 与设计稿一致的示例数据，供 M1 静态 UI、预览与测试使用。
public enum MockData {
    public static let macStudio = Device(id: "d1", name: "Yuki 的 Mac Studio", host: "100.82.203.14", mode: .tailscale, online: true,
                                         sessionCount: 3, agents: [.claude: 2, .codex: 1])
    public static let macBook = Device(id: "d2", name: "MacBook Pro 16", host: "https://xxxx.trycloudflare.com", mode: .tunnel, online: true,
                                       sessionCount: 1, agents: [.claude: 1])
    public static let macMini = Device(id: "d3", name: "公司 Mac mini", host: "192.168.3.21", mode: .local, online: false,
                                       lastSeen: .now.addingTimeInterval(-7200), sessionCount: 0)
    public static let devices = [macStudio, macBook, macMini]

    public static let sessions: [Session] = [
        Session(id: "s1", deviceId: "d1", agent: .claude, cwd: "~/devops/aigc/yukiTrace", title: "重构地图标记组件并补测试",
                status: .waitingApproval, updatedAt: .now.addingTimeInterval(-180), pendingApprovals: 1,
                usage: SessionUsage(model: "claude-fable-5-1",
                                    turn: TurnUsage(model: "claude-fable-5-1", input: 32, cacheWrite: 741, cacheRead: 127_602, output: 1089, thinking: 210, contextTokens: 128_375, contextWindow: 200_000, costUSD: 0.42, durationMs: 18_400),
                                    total: TotalUsage(input: 1_204, cacheWrite: 41_300, cacheRead: 610_000, output: 6_820, thinking: 900, costUSD: 2.31, turns: 6), updatedAt: .now)),
        Session(id: "s2", deviceId: "d1", agent: .codex, cwd: "~/devops/aigc/yukiTrace", title: "修复 iOS Safari 日期输入溢出",
                status: .idle, updatedAt: .now.addingTimeInterval(-1560)),
        Session(id: "s3", deviceId: "d1", agent: .claude, cwd: "~/devops/aigc/YzVibe", title: "生成 iOS 设计 token",
                status: .running, updatedAt: .now.addingTimeInterval(-60)),
        Session(id: "s4", deviceId: "d2", agent: .claude, cwd: "~/work/api-docs", title: "补充 API 文档",
                status: .waitingApproval, updatedAt: .now.addingTimeInterval(-240), pendingApprovals: 1),
    ]

    public static let approvals: [Approval] = [
        Approval(id: "a1", sessionId: "s1", deviceId: "d1", kind: .shell, summary: "rm -rf src/components/map/legacy/",
                 detail: "rm -rf src/components/map/legacy/\n  marker.old.tsx marker.test.old.tsx\n  marker.snap", risk: .high),
        Approval(id: "a2", sessionId: "s4", deviceId: "d2", kind: .write, summary: "docs/api.md（+142 行）",
                 detail: "写入 docs/api.md，新增 142 行", risk: .low, createdAt: .now.addingTimeInterval(-240)),
    ]

    public static func messages(for sessionId: String) -> [Message] {
        [
            Message(id: "m1", sessionId: sessionId, role: .user, text: "把 yt-marker 拆成独立组件，补上快照测试", createdAt: .now.addingTimeInterval(-200)),
            Message(id: "m2", sessionId: sessionId, role: .assistant, text: "好的，先读现有实现再拆分。",
                    toolCalls: [ToolCall(name: "Read", detail: "src/components/map/marker.tsx", state: .done),
                                ToolCall(name: "Edit", detail: "src/components/map/YtMarker.tsx", state: .done)],
                    createdAt: .now.addingTimeInterval(-150)),
            Message(id: "m3", sessionId: sessionId, role: .system, text: "", approvalId: "a1", createdAt: .now.addingTimeInterval(-30)),
        ]
    }

    public static let files: [FileEntry] = [
        FileEntry(name: "legacy", path: "src/components/map/legacy", kind: .folder, badge: "审批中"),
        FileEntry(name: "YtMarker.tsx", path: "src/components/map/YtMarker.tsx", kind: .code, size: 4300, badge: "已改"),
        FileEntry(name: "YtMarker.test.tsx", path: "src/components/map/YtMarker.test.tsx", kind: .code, size: 1800, badge: "新"),
        FileEntry(name: "README.md", path: "src/components/map/README.md", kind: .markdown, size: 2100, modifiedAt: .now.addingTimeInterval(-86400)),
        FileEntry(name: "marker-preview.png", path: "src/components/map/marker-preview.png", kind: .image, size: 318_000, modifiedAt: .now.addingTimeInterval(-3 * 86400)),
    ]

    public static let quickReplies = ["继续", "LGTM，执行", "解释一下", "撤销上一步"]
    public static let recentFolders = ["~/devops/aigc/yukiTrace", "~/devops/aigc/YzVibe", "~/devops/aigc/lobehub"]
}
