#if DEBUG
import Foundation

/// Deterministic offline fixture for reviewing the long-running OMP conversation on a simulator.
@MainActor enum OmpActivityPreview {
    static func configure(_ store: AppStore) {
        let start = Date.now.addingTimeInterval(-260)
        store.sessions[0] = Session(id: "s1", deviceId: "d1", agent: .omp, cwd: "~/devops/aigc/yukiTrace",
            title: "本项目有哪些值得优化的地方", status: .running, updatedAt: start)
        store.approvals = []
        var task = ToolCall(id: "task", name: "task", detail: "Audit build, dependency, and deployment hygiene", state: .running)
        task.subagents = [
            SubagentProgress(id: "BuildHygieneScout", name: "BuildHygieneScout", agent: "scout", status: "running",
                task: "检查构建、依赖与部署配置", detail: "正在读取 package.json", toolCount: 12, durationMs: 241000, updatedAt: .now),
            SubagentProgress(id: "DatabaseScout", name: "DatabaseScout", agent: "scout", status: "completed",
                task: "检查数据库查询", detail: "检查完成", toolCount: 8, durationMs: 162000, updatedAt: .now),
        ]
        var steps = [Message(id: "task-message", sessionId: "s1", role: .assistant, text: "已确认图片在服务端生成了缩略图，正在等待构建检查结果。", toolCalls: [task], createdAt: start)]
        steps[0].thinking = "先核对现有缩略图和缓存实现，再确认构建配置中是否还有重复工作。"
        for i in 0..<18 {
            let shell = i % 3 == 0
            let call = ToolCall(id: "read-\(i)", name: shell ? "bash" : "read",
                detail: shell ? "rg --files src" : "src/app/page.tsx", state: .done)
            let message = Message(id: "tool-message-\(i)", sessionId: "s1", role: .assistant, text: "",
                toolCalls: [call], createdAt: start.addingTimeInterval(Double(i)))
            steps.append(message)
        }
        store.messages["s1"] = [Message(id: "user", sessionId: "s1", role: .user, text: "本项目有哪些值得优化的地方", createdAt: start)] + steps
    }
}
#endif
