import Foundation
import Testing
@testable import YzVibeKit

@Suite struct MessageCacheTests {
    @Test func diskCacheSurvivesRecreationAndSeparatesDevices() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = MessageCache(directory: dir)
        let message = Message(id: "m", sessionId: "s", role: .assistant, text: "cached reply")
        await cache.save(device: "a", session: "s", messages: [message])
        #expect(await MessageCache(directory: dir).load(device: "a", session: "s") == [message])
        #expect(await cache.load(device: "b", session: "s") == nil)
        await cache.remove(device: "a", session: "s")
        #expect(await cache.load(device: "a", session: "s") == nil)
    }

    @Test func corruptCacheIsIgnoredAndBudgetIsBounded() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = MessageCache(directory: dir, budget: 1800)
        for i in 0..<8 {
            await cache.save(device: "d", session: "s\(i)", messages: [Message(sessionId: "s\(i)", role: .assistant, text: String(repeating: "x", count: 500))])
        }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        let size = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        #expect(size <= 1800)
        #expect(await cache.load(device: "d", session: "s0") == nil)
        for file in files { try Data("broken".utf8).write(to: file) }
        #expect(await cache.load(device: "d", session: "s7") == nil)
    }

    @Test @MainActor func cachedHistoryAppearsBeforeNetworkAndWarmVisitSkipsFetch() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = MessageCache(directory: dir)
        let client = QueueStubClient()
        let store = AppStore(client: client, seedMock: false)
        store.historyCache = cache
        store.devices = [MockData.macStudio]; store.sessions = [MockData.sessions[0]]
        let id = store.sessions[0].id
        let old = Message(id: "m", sessionId: id, role: .assistant, text: "old")
        let fresh = Message(id: "m", sessionId: id, role: .assistant, text: "updated tool result")
        await cache.save(device: store.devices[0].id, session: id, messages: [old])
        client.messagesHandler = {
            await MainActor.run { #expect(store.messages[id] == [old]) }
            return [fresh]
        }
        await store.loadMessages(id)
        #expect(store.messages[id] == [fresh])
        store.leaveMessages(id)
        client.messagesHandler = { Issue.record("Warm visit must not refetch history"); return [] }
        await store.loadMessages(id)
        #expect(store.messages[id] == [fresh])
        client.messagesHandler = nil
    }
    @Test @MainActor func reconnectRefreshesOnlyVisibleHistoryAndRevisitsRefreshStaleHistory() async throws {
        let client = QueueStubClient()
        let store = AppStore(client: client, seedMock: false)
        let device = MockData.macStudio
        let first = Session(id: "first", deviceId: device.id, agent: .codex, cwd: "/p", title: "first")
        let second = Session(id: "second", deviceId: device.id, agent: .codex, cwd: "/p", title: "second")
        store.devices = [device]; store.sessions = [first, second]
        client.messagesHandler = { [] }
        await store.loadMessages(first.id)
        store.leaveMessages(first.id)
        await store.loadMessages(second.id)
        store.handle(.connected, device: device)
        for _ in 0..<100 {
            if !client.snapshotRequests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(client.snapshotRequests == [[second.id]])
        store.handle(.snapshot(EventSnapshot(sessions: [first, second], approvals: [], messages: [second.id: []])), device: device)
        store.leaveMessages(second.id)
        await store.loadMessages(first.id)
        #expect(client.snapshotRequests.last == [first.id])
        store.handle(.snapshot(EventSnapshot(sessions: [first, second], approvals: [], messages: [first.id: []])), device: device)
    }

}
