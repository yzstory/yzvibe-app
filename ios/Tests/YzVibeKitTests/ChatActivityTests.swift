import Foundation
import Testing
@testable import YzVibeKit

@Suite struct ChatActivityTests {
    private func message(_ id: String, role: MessageRole = .assistant, text: String = "", calls: Int = 0) -> Message {
        Message(id: id, sessionId: "s", role: role, text: text,
                toolCalls: (0..<calls).map { ToolCall(id: "\(id)-\($0)", name: "read", detail: "file.swift", state: .done) })
    }

    @Test func manyMessagesBecomeOneStableActivityAndKeepFinalAnswer() {
        let steps = (0..<40).map { message("m\($0)", calls: 2) }
        let rows = ChatTimelineRow.make([message("user", role: .user, text: "检查项目")] + steps + [message("answer", text: "完成")])
        #expect(rows.count == 3)
        guard case .activity(let group) = rows[1] else { Issue.record("Expected activity"); return }
        #expect(group.calls.count == 80)
        #expect(group.id == ChatTimelineRow.make(Array(steps.prefix(1)))[0].id)
        #expect(rows[2].id == "answer")
    }
    @Test func approvalsUsersAttachmentsAndNarrativeKeepTheirBoundaries() {
        var approval = message("approval", role: .system); approval.approvalId = "a"
        var attachment = message("image"); attachment.attachments = ["image"]
        let rows = ChatTimelineRow.make([message("first", calls: 1), approval, message("second", calls: 1),
            message("note", text: "已检查依赖"), attachment, message("user", role: .user, text: "继续"), message("third", calls: 1)])
        #expect(rows.count == 7)
        #expect(rows.map(\.id) == ["activity-first", "approval", "activity-second", "note", "image", "user", "activity-third"])
    }
    @Test func emptyBubblesDisappearAndThinkingJoinsTools() {
        var thinking = message("thinking"); thinking.thinking = "检查依赖"; thinking.streaming = true
        let rows = ChatTimelineRow.make([message("tool", calls: 1), message("empty"), thinking])
        #expect(rows.count == 1)
        guard case .activity(let group) = rows[0] else { Issue.record("Expected activity"); return }
        #expect(group.messages.last?.thinking == "检查依赖")
    }
    @Test func mixedTextAndToolsKeepNarrativeInsideActivity() {
        let rows = ChatTimelineRow.make([message("mixed", text: "现在检查构建", calls: 2)], groupsMixedContent: true)
        guard case .activity(let group) = rows[0] else { Issue.record("Expected activity"); return }
        #expect(group.summary == "现在检查构建")
        #expect(group.messages[0].text == "现在检查构建")
    }
    @Test func otherAgentsKeepAnswersThatShareTheToolMessageVisible() {
        let rows = ChatTimelineRow.make([message("answer", text: "已修复并通过测试", calls: 2)])
        guard case .message(let reply) = rows[0] else { Issue.record("Expected visible reply"); return }
        #expect(reply.text == "已修复并通过测试")
    }
    @Test func legacyMessagesDecodeAndNewProgressSurvivesRoundTrip() throws {
        let legacy = try JSONDecoder.yz.decode(Message.self, from: Data(#"{"id":"old","role":"assistant","text":"ok"}"#.utf8))
        #expect(legacy.thinking.isEmpty)
        var value = message("new", calls: 1); value.thinking = "检查"
        value.createdAt = Date(timeIntervalSince1970: 100)
        value.toolCalls[0].subagents = [SubagentProgress(id: "Scout", name: "Scout", agent: "scout", status: "running", task: "Audit", detail: "read", toolCount: 4, durationMs: 12000, updatedAt: Date(timeIntervalSince1970: 100))]
        let copy = try JSONDecoder.yz.decode(Message.self, from: JSONEncoder.yz.encode(value))
        #expect(copy == value)
        #expect(copy.toolCalls[0].subagents[0].elapsed(at: Date(timeIntervalSince1970: 110), live: true) == 22)
        #expect(copy.toolCalls[0].subagents[0].elapsed(at: Date(timeIntervalSince1970: 110), live: false) == 12)
    }
    @Test func waitingStatusPrioritizesConnectionApprovalAndChildren() {
        var tool = ToolCall(name: "task", detail: "Audit", state: .done)
        tool.subagents = [SubagentProgress(id: "a", name: "A", agent: "scout", status: "running", task: "Audit", detail: "read", toolCount: 2, durationMs: 4000, updatedAt: .now)]
        func progress(_ status: SessionStatus, connected: Bool = true) -> ChatRunProgress {
            ChatRunProgress(status: status, connected: connected, startedAt: .now, calls: [tool], streamingText: false)
        }
        #expect(progress(.running).title == "等待 1 个子代理")
        #expect(progress(.waitingApproval).title == "等待你的确认")
        #expect(!progress(.waitingApproval).animates)
        #expect(progress(.running, connected: false).title == "连接已断开，等待同步")
        #expect(!progress(.running, connected: false).animates)
    }
}
