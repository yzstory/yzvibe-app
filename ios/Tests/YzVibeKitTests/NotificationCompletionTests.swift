import Foundation
import Testing
@testable import YzVibeKit

@MainActor struct NotificationCompletionTests {
    @Test func onlyFinalCompletionNotifiesAndChatKeepsEveryPart() {
        let store = AppStore(), device = MockData.macStudio
        let old = Settings.load(); defer { old.save() }
        store.settings.notifyOnReply = true
        store.sessions = [Session(id: "s", deviceId: device.id, agent: .codex, cwd: "/tmp", title: "任务")]
        var notices: [String] = []
        store.postCompletionNotification = { _, body, _ in notices.append(body) }
        store.handle(.messageDelta(sessionId: "s", messageId: "p", text: "正在处理"), device: device)
        store.handle(.messageDone(sessionId: "s", messageId: "p"), device: device)
        store.handle(.messageDelta(sessionId: "s", messageId: "f", text: "最终结果"), device: device)
        store.handle(.messageDone(sessionId: "s", messageId: "f"), device: device)
        #expect(notices.isEmpty)
        let completion = RunCompletion(sessionId: "s", runId: "r", messageId: "f", text: "最终结果", remote: false)
        store.handle(.runCompleted(completion), device: device)
        store.handle(.runCompleted(completion), device: device)
        #expect(notices == ["任务\n最终结果"])
        #expect(store.messages["s"]?.map(\.text) == ["正在处理", "最终结果"])
        store.handle(.runCompleted(RunCompletion(sessionId: "s", runId: "remote", messageId: "f", text: "远程", remote: true)), device: device)
        store.settings.notifyOnReply = false
        store.handle(.runCompleted(RunCompletion(sessionId: "s", runId: "off", messageId: "f", text: "关闭", remote: false)), device: device)
        #expect(notices.count == 1)
    }
}
