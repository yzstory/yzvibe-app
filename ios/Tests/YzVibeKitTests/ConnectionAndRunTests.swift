import Foundation
import Testing
@testable import YzVibeKit

@MainActor struct ConnectionAndRunTests {
    @Test func deliveryStaysWithItsRoundWhileNewMessagesArrive() throws {
        let json = #"{"id":"r1","sessionId":"s","status":"completed","startedAt":"2026-09-12T09:00:00Z","endedAt":"2026-09-12T09:01:00Z","summary":"done","tools":[],"files":[],"artifacts":[],"startMessageId":"u1","messageIds":["a1","a2"]}"#
        var run = try JSONDecoder.yz.decode(TaskRun.self, from: Data(json.utf8))
        let messages = [Message(id: "u1", sessionId: "s", role: .user, text: "first"),
                        Message(id: "a1", sessionId: "s", role: .assistant, text: "working"),
                        Message(id: "a2", sessionId: "s", role: .assistant, text: "done"),
                        Message(id: "u2", sessionId: "s", role: .user, text: "second"),
                        Message(id: "a3", sessionId: "s", role: .assistant, text: "working again")]
        #expect(run.anchorMessage(in: messages) == "a2")
        #expect(run.anchorMessage(in: Array(messages.prefix(3))) == "a2")
        #expect(run.anchorMessage(in: Array(messages.suffix(2))) == nil, "Unloaded history must not attach to the current round")
        run.status = "running"
        #expect(run.anchorMessage(in: messages) == nil)
    }

    @Test func legacyUnanchoredDeliveryRemainsHistoryOnly() throws {
        let json = #"{"id":"old","sessionId":"s","status":"completed","startedAt":"2026-09-12T09:00:00Z","summary":"old","tools":[],"files":[],"artifacts":[]}"#
        let run = try JSONDecoder.yz.decode(TaskRun.self, from: Data(json.utf8))
        #expect(run.anchorMessage(in: [Message(id: "new", sessionId: "s", role: .assistant, text: "new reply")]) == nil)
    }

    @Test func interruptedWithoutReplyUsesItsOwnRequestOnly() {
        let run = TaskRun(id: "r", sessionId: "s", status: "interrupted", startedAt: .now, summary: "", tools: [], files: [], artifacts: [], startMessageId: "u")
        #expect(run.anchorMessage(in: [Message(id: "u", sessionId: "s", role: .user, text: "request")]) == "u")
        #expect(run.anchorMessage(in: [Message(id: "u", sessionId: "other", role: .user, text: "other")]) == nil)
    }

    @Test func endpointNormalizationDeduplicatesAndRejectsCredentialBearingURLs() {
        let device = Device(name: "Mac", host: "https://remote.test", mode: .relay, endpoints: ["https://REMOTE.test:443/", "http://192.168.1.2:19876", "http://192.168.1.2:19876/"])
        #expect(EndpointAddress.candidates(device) == ["https://remote.test", "http://192.168.1.2:19876"])
        for value in ["https://user:pass@remote.test", "https://remote.test?token=x", "https://remote.test/path", "http://remote.test:0", "file:///tmp/file"] {
            #expect(EndpointAddress.url(value) == nil)
        }
        #expect(EndpointAddress.isLoopback("http://127.0.0.1:19876"))
        #expect(EndpointAddress.isLoopback("http://[::1]:19876"))
        #expect(!EndpointAddress.isLoopback("http://192.168.1.2:19876"))
    }

    @Test func switchKeepsPairingMessagesAndCandidatesAndFailedSwitchLeavesDeviceUntouched() async throws {
        let client = QueueStubClient()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(client: client, seedMock: false, outboxURL: root.appendingPathComponent("outbox.json"))
        let original = Device(id: "computer", name: "Mac", host: "192.168.1.8", mode: .local, online: true)
        let session = Session(id: "s", deviceId: original.id, agent: .codex, cwd: "/fixture", title: "keep")
        let message = Message(id: "m", sessionId: "s", role: .assistant, text: "keep reply")
        store.devices = [original]; store.selectedDeviceId = original.id
        store.sessions = [session]; store.messages["s"] = [message]
        client.sessionsOnServer = [session]; client.messagesHandler = { [message] }
        client.endpointValidation = { device, address in
            #expect(device.id == original.id)
            #expect(address == "https://remote.test")
            return HealthInfo(name: "Mac", version: "0.1.1", agents: [], connectorId: original.id)
        }
        try await store.switchEndpoint(original.id, address: "https://remote.test")
        #expect(store.device(original.id)?.baseURL?.absoluteString == "https://remote.test")
        #expect(store.device(original.id)?.mode == .relay)
        #expect(store.device(original.id)?.endpoints.contains("http://192.168.1.8:19876") == true)
        #expect(store.session("s")?.id == session.id)
        #expect(store.messages["s"]?.first?.text == "keep reply")
        #expect(store.selectedDeviceId == original.id)
        let beforeFailure = store.device(original.id)
        client.endpointValidation = { _, _ in throw ConnectorError.unauthorized }
        do { try await store.switchEndpoint(original.id, address: "https://rejected.test", name: "do not save"); Issue.record("Expected failure") }
        catch ConnectorError.unauthorized { }
        #expect(store.device(original.id) == beforeFailure)
        #expect(store.switchingDevices.isEmpty)
    }
}
