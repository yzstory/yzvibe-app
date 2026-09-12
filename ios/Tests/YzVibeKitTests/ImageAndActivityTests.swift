import Testing
import UIKit
@testable import YzVibeKit

@MainActor
struct ImageAndActivityTests {
    @Test func failedAttachmentCanRecover() async throws {
        let client = ResyncStubClient()
        let store = AppStore(client: client, seedMock: false)
        store.devices = [MockData.macStudio]
        store.sessions = [MockData.sessions[0]]
        let session = store.sessions[0]
        await store.loadAttachment("image", for: session.id)
        #expect(store.failedAttachments.contains("image"))
        client.attachmentData = try #require(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData())
        await store.loadAttachment("image", for: session.id)
        #expect(store.attachmentImages["image"] != nil)
        #expect(!store.failedAttachments.contains("image"))
        await store.loadAttachment("image", for: session.id)
        #expect(client.attachmentRequests == 2)
    }

    @Test func fullScreenImageLaysOutAfterInitiallyZeroBounds() {
        let scroll = ImageScrollView()
        let image = UIImageView()
        scroll.addSubview(image); scroll.imageView = image
        scroll.layoutIfNeeded()
        #expect(image.frame.isEmpty)
        scroll.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        #expect(image.frame.size == scroll.bounds.size)
        scroll.frame.size = CGSize(width: 844, height: 390)
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        #expect(image.frame.size == scroll.bounds.size)
    }

    @Test func imageLinksPreserveSurroundingTextAndIgnoreOtherLinks() {
        let parts = MessageImageLinks.parts("截图：[列表](/tmp/list.png) · ![聊天](https://example.com/chat.jpg?v=1) 和 [文档](/tmp/a.md)")
        var images: [String] = [], text = ""
        for part in parts {
            switch part { case .image(_, let path): images.append(path); case .text(let value): text += value }
        }
        #expect(images == ["/tmp/list.png", "https://example.com/chat.jpg?v=1"])
        #expect(text.contains("[文档](/tmp/a.md)"))
        #expect(text.contains("截图："))
    }

    @Test func activeMeansUpdatedWithinSevenDaysRegardlessOfStatus() {
        let store = AppStore()
        let originalSettings = store.settings
        defer { store.settings = originalSettings }
        store.settings.showTerminalSessions = true
        let device = MockData.macStudio
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        store.sessions = [SessionStatus.idle, .running, .waitingApproval, .error, .closed].map {
            var session = Session(id: $0.rawValue, deviceId: device.id, agent: .codex, cwd: "/p", title: "test", status: $0)
            session.updatedAt = now.addingTimeInterval(-60)
            return session
        }
        var boundary = Session(id: "boundary", deviceId: device.id, agent: .codex, cwd: "/p", title: "test")
        boundary.updatedAt = cutoff
        var old = Session(id: "old-running", deviceId: device.id, agent: .codex, cwd: "/p", title: "test", status: .running, queue: [QueuedMessage(text: "next")])
        old.updatedAt = cutoff.addingTimeInterval(-1)
        store.sessions += [boundary, old]
        #expect(Set(store.sessions(for: device, activeOnly: true, query: "", now: now).map(\.id)) == ["idle", "running", "waiting_approval", "error", "closed", "boundary"])
        #expect(store.sessions(for: device, activeOnly: false, query: "", now: now).count == 7)
    }
}
