import Foundation
import UIKit
import Testing
@testable import YzVibeKit

@Suite(.serialized)
@MainActor
struct DeliveryRegressionTests {
    private func fixture(url: URL? = nil) -> (AppStore, QueueStubClient) {
        let client = QueueStubClient()
        let store = AppStore(client: client, seedMock: false, outboxURL: url)
        store.devices = [MockData.macStudio]; store.selectedDeviceId = MockData.macStudio.id
        store.sessions = [Session(id: "delivery-session", deviceId: MockData.macStudio.id, agent: .claude, cwd: "/fixture", title: "fixture")]
        return (store, client)
    }

    @Test func stagingPersistsTextAndImagesBeforeClearingComposer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("outbox.json")
        let (store, _) = fixture(url: url)
        store.chatDrafts["delivery-session"] = ChatDraft(text: "keep me", images: [PendingImage(data: Data([1, 2, 3]), image: UIImage())])
        let id = try #require(store.stageDraft(in: "delivery-session", mode: .auto))
        #expect(store.chatDrafts["delivery-session"]?.text == "")
        let recovered = try OutboxDisk(url: url).load()
        #expect(recovered.first?.id == id)
        #expect(recovered.first?.text == "keep me")
        #expect(recovered.first?.images.first?.data == Data([1, 2, 3]))
    }

    @Test func filesSurviveOutboxReloadAndRestoreToComposer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("outbox.json")
        let (store, _) = fixture(url: url)
        let data = Data("%PDF-1.7 中文文件".utf8)
        store.chatDrafts["delivery-session"] = ChatDraft(text: "read", files: [PendingFile(name: "需求.pdf", mime: "application/pdf", data: data)])
        let id = try #require(store.stageDraft(in: "delivery-session", mode: .auto))
        let saved = try #require(OutboxDisk(url: url).load().first)
        #expect(saved.images.first?.data == data)
        #expect(saved.images.first?.filename == "需求.pdf")
        #expect(saved.images.first?.mime == "application/pdf")
        #expect(store.chatDrafts["delivery-session"]?.files.isEmpty == true)
        let (reloaded, _) = fixture(url: url)
        reloaded.outbox[0].state = .failed
        reloaded.restoreOutgoing(id)
        #expect(reloaded.chatDrafts["delivery-session"]?.files.first?.data == data)
        #expect(reloaded.chatDrafts["delivery-session"]?.files.first?.name == "需求.pdf")
        #expect(reloaded.chatDrafts["delivery-session"]?.images.isEmpty == true)
        #expect(reloaded.outbox.isEmpty)
    }

    @Test func legacyImageOutboxRemainsDecodable() throws {
        let json = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"data\":\"AQID\"}".utf8)
        let image = try JSONDecoder().decode(OutgoingImage.self, from: json)
        #expect(image.data == Data([1, 2, 3]))
        #expect(image.mime == nil && image.filename == nil)
    }

    @Test func failedDiskWriteLeavesComposerUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = fixture(url: root.appendingPathComponent("outbox.json"))
        store.chatDrafts["delivery-session"] = ChatDraft(text: "cannot lose this")
        #expect(store.stageDraft(in: "delivery-session", mode: .auto) == nil)
        #expect(store.chatDrafts["delivery-session"]?.text == "cannot lose this")
        #expect(store.outbox.isEmpty)
    }

    @Test func secondImageFailureNeverSendsPartialMessageAndNeverOverwritesNewDraft() async throws {
        let (store, client) = fixture()
        var uploads = 0, sends = 0
        client.uploadHandler = { _ in uploads += 1; if uploads == 2 { throw ConnectorError.unreachable }; return "upload-one" }
        client.deliveryHandler = { id, _, _ in sends += 1; return DeliveryReceipt(id: id, state: "sent") }
        let id = try #require(store.stageMessage("both pictures", in: "delivery-session", images: [OutgoingImage(data: Data([1])), OutgoingImage(data: Data([2]))], mode: .auto))
        #expect(await store.transmit(id) == .failed)
        #expect(sends == 0)
        #expect(store.outbox.first?.images.count == 2)
        #expect(store.outbox.first?.images.first?.uploadId == "upload-one")
        #expect(store.outbox.first?.state == .failed)
        store.chatDrafts["delivery-session"] = ChatDraft(text: "new draft")
        store.restoreOutgoing(id)
        #expect(store.chatDrafts["delivery-session"]?.text == "new draft")
        #expect(store.outbox.count == 1)
    }

    @Test func lostResponseReconcilesSameIDWithoutSendingAgain() async throws {
        let (store, client) = fixture()
        var receipt: DeliveryReceipt?, sends = 0
        client.receiptHandler = { _ in receipt }
        client.deliveryHandler = { id, _, _ in sends += 1; receipt = DeliveryReceipt(id: id, state: "sent"); throw ConnectorError.unreachable }
        let id = try #require(store.stageMessage("execute once", in: "delivery-session", images: [], mode: .auto))
        #expect(await store.transmit(id) == .failed)
        #expect(store.outbox.first?.state == .uncertain)
        #expect(await store.transmit(id) == .sent)
        #expect(sends == 1)
        #expect(store.outbox.isEmpty)
        #expect(store.messages["delivery-session"]?.first?.clientMessageId == id)
    }

    @Test func uncertainAgentReceiptRemainsVisibleAndCannotDispatchAgain() async throws {
        let (store, client) = fixture()
        var sends = 0
        client.receiptHandler = { id in DeliveryReceipt(id: id, state: "uncertain") }
        client.deliveryHandler = { id, _, _ in sends += 1; return DeliveryReceipt(id: id, state: "sent") }
        let id = try #require(store.stageMessage("check history", in: "delivery-session", images: [], mode: .auto))
        #expect(await store.transmit(id) == .failed)
        #expect(await store.transmit(id) == .failed)
        #expect(sends == 0)
        #expect(store.outbox.first?.state == .uncertain)
        store.restoreOutgoing(id)
        #expect(store.outbox.count == 1)
    }

    @Test func restartingAppRetainsIdentityAndDoesNotAutoSend() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("outbox.json")
        let (original, _) = fixture(url: url)
        let id = try #require(original.stageMessage("persist", in: "delivery-session", images: [], mode: .auto))
        let (reloaded, client) = fixture(url: url)
        var delivered: [String] = []
        client.deliveryHandler = { id, _, _ in delivered.append(id); return DeliveryReceipt(id: id, state: "sent") }
        #expect(reloaded.outbox.first?.id == id)
        #expect(delivered.isEmpty)
        #expect(await reloaded.transmit(id) == .sent)
        #expect(delivered == [id])
        #expect(try OutboxDisk(url: url).load().isEmpty)
    }

    @Test func toolEventsPreserveEvidenceThroughDecodingAndUpdatingExistingCard() throws {
        let (store, _) = fixture()
        let data = Data(#"{"type":"tool.call","sessionId":"delivery-session","messageId":"m","toolId":"t","name":"Shell","input":{"detail":"npm test"},"state":"done","output":"failed assertion","outputKind":"text","truncated":true,"exitCode":1,"files":["test.js"]}"#.utf8)
        store.handle(.toolCall(sessionId: "delivery-session", call: ToolCall(id: "t", name: "Shell", detail: "npm test", state: .running), messageId: "m"), device: MockData.macStudio)
        let event = try #require(ConnectorSocket.parse(data))
        store.handle(event, device: MockData.macStudio)
        let tool = try #require(store.messages["delivery-session"]?.first?.toolCalls.first)
        #expect(tool.output == "failed assertion")
        #expect(tool.truncated)
        #expect(tool.exitCode == 1)
        #expect(tool.files == ["test.js"])
    }

    @Test func orderedSnapshotRepairsMissedTextAndApprovalsBeforeNewDelta() throws {
        let (store, _) = fixture()
        let device = MockData.macStudio
        store.handle(.messageDelta(sessionId: "delivery-session", messageId: "m", text: "old"), device: device)
        let snapshot = EventSnapshot(sessions: store.sessions, approvals: [], messages: ["delivery-session": [Message(id: "m", sessionId: "delivery-session", role: .assistant, text: "full after reconnect")]])
        store.handle(.snapshot(snapshot), device: device)
        store.handle(.messageDelta(sessionId: "delivery-session", messageId: "m", text: " + live"), device: device)
        #expect(store.messages["delivery-session"]?.count == 1)
        #expect(store.messages["delivery-session"]?.first?.text == "full after reconnect + live")
        #expect(store.device(device.id)?.online == true)
    }

    @Test func connectionHandshakeTriggersSnapshotWithoutAppBackgroundTransition() async {
        let (store, client) = fixture()
        store.handle(.disconnected(nil), device: MockData.macStudio)
        store.handle(.connected, device: MockData.macStudio)
        for _ in 0..<10 { await Task.yield() }
        #expect(!client.snapshotRequests.isEmpty)
    }

    @Test func messageLoadingWaitsForOrderedSnapshotToArrive() async {
        let (store, _) = fixture()
        store.handle(.connected, device: MockData.macStudio)
        await store.loadMessages("delivery-session")
        #expect(store.loadingMessages.contains("delivery-session"))
        store.handle(.snapshot(EventSnapshot(sessions: store.sessions, approvals: [], messages: ["delivery-session": []])), device: MockData.macStudio)
        #expect(!store.loadingMessages.contains("delivery-session"))
        #expect(store.messageLoadErrors["delivery-session"] == nil)
    }
}
