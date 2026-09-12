import Foundation
import Testing
@testable import YzVibeKit

@Suite @MainActor
struct QueuedMessageVisibilityTests {
    @Test func dispatchedMessageRemainsVisibleAfterQueueRemoval() throws {
        let store = AppStore(client: QueueStubClient(), seedMock: false)
        let device = MockData.macStudio
        var session = Session(id: "s1", deviceId: device.id, agent: .codex, cwd: "/p", title: "t",
                              status: .running, queue: [QueuedMessage(id: "q1", text: "继续", attachments: ["image1"])])
        store.devices = [device]
        store.sessions = [session]
        let json = #"{"type":"message.added","sessionId":"s1","message":{"id":"m1","sessionId":"s1","role":"user","text":"继续","attachments":["image1"],"createdAt":"2026-09-12T10:00:00Z"}}"#
        let event = try #require(ConnectorSocket.parse(Data(json.utf8)))
        store.handle(event, device: device)
        session.queue = []
        store.handle(.sessionUpdated(session), device: device)
        // 重复收到事件也只能留一个气泡。
        store.handle(event, device: device)
        #expect(store.session("s1")?.queue.isEmpty == true)
        #expect(store.messages["s1"]?.count == 1)
        #expect(store.messages["s1"]?.first?.text == "继续")
        #expect(store.messages["s1"]?.first?.attachments == ["image1"])
    }

    @Test func serverEchoConfirmsLocalBubbleAndPreservesRepeatedMessages() {
        let store = AppStore(client: QueueStubClient(), seedMock: false)
        let device = MockData.macStudio
        store.messages["s1"] = [
            Message(id: "old", sessionId: "s1", role: .user, text: "继续"),
            Message(sessionId: "s1", role: .user, text: "继续", attachments: ["image1"], isLocal: true),
            Message(sessionId: "s1", role: .user, text: "继续", isLocal: true),
        ]
        let confirmed = Message(id: "new", sessionId: "s1", role: .user, text: "继续")
        store.handle(.messageUpdated(confirmed), device: device)
        store.handle(.messageUpdated(confirmed), device: device)
        #expect(store.messages["s1"]?.count == 3)
        #expect(store.messages["s1"]?.last?.id == "new")
        #expect(store.messages["s1"]?.last?.isLocal == false)
        #expect(store.messages["s1"]?[1].isLocal == true)
        store.handle(.messageUpdated(Message(id: "next", sessionId: "s1", role: .user, text: "继续")), device: device)
        #expect(store.messages["s1"]?.count == 4)
    }
}
