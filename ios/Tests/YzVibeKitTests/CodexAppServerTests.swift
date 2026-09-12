import Foundation
import Testing
@testable import YzVibeKit

@Suite @MainActor
struct CodexAppServerTests {
    @Test func approvalStreamPreservesQuestionsAndRules() throws {
        let json = #"{"type":"approval.requested","approvalId":"a","sessionId":"s1","kind":"other","summary":"回答","risk":"low","questions":[{"id":"q","header":"配色","question":"选哪种颜色？","options":[{"label":"橙色","description":"保留品牌色"}]}],"suggestions":[]}"#
        guard case .approvalRequested(let approval) = ConnectorSocket.parse(Data(json.utf8)) else {
            Issue.record("Missing approval event"); return
        }
        #expect(approval.questions.first?.id == "q")
        #expect(approval.questions.first?.options?.first?.label == "橙色")
        let restored = try JSONDecoder().decode(Approval.self, from: JSONEncoder().encode(approval))
        #expect(restored.questions == approval.questions)
    }

    @Test func interleavedToolsUpdateTheirOriginalBubble() {
        let store = AppStore(), device = MockData.macStudio
        store.messages["s1"] = []
        store.handle(.toolCall(sessionId: "s1", call: ToolCall(id: "shell", name: "Shell", detail: "pwd", state: .running), messageId: "tools"), device: device)
        store.handle(.messageDelta(sessionId: "s1", messageId: "answer", text: "新的回复"), device: device)
        store.handle(.toolCall(sessionId: "s1", call: ToolCall(id: "shell", name: "Shell", detail: "pwd", state: .done), messageId: "tools"), device: device)
        #expect(store.messages["s1"]?.count == 2)
        #expect(store.messages["s1"]?.first?.toolCalls.first?.state == .done)
        #expect(store.messages["s1"]?.last?.toolCalls.isEmpty == true)
    }

    @Test func finalTextCanReplaceStreamedDraftWithoutDuplicatingBubble() {
        let store = AppStore(), device = MockData.macStudio
        store.messages["s1"] = []
        store.handle(.messageDelta(sessionId: "s1", messageId: "answer", text: "草稿"), device: device)
        store.handle(.messageUpdated(Message(id: "answer", sessionId: "s1", role: .assistant, text: "最终回复")), device: device)
        #expect(store.messages["s1"]?.count == 1)
        #expect(store.messages["s1"]?.first?.text == "最终回复")
    }

    @Test func approvalEventDoesNotDuplicateItsSyncedMessage() {
        let store = AppStore(), device = MockData.macStudio
        store.messages["s1"] = []
        let approval = Approval(id: "new-approval", sessionId: "s1", deviceId: device.id,
                                kind: .shell, summary: "pwd", detail: "pwd", risk: .medium)
        store.handle(.messageUpdated(Message(id: "server-message", sessionId: "s1", role: .system,
                                             text: "", approvalId: approval.id)), device: device)
        store.handle(.approvalRequested(approval), device: device)
        #expect(store.messages["s1"]?.count == 1)
        #expect(store.messages["s1"]?.first?.id == "server-message")
    }
}
