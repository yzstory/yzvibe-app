import SwiftUI
import UIKit
import Testing
@testable import YzVibeKit

@MainActor @Observable private final class TimelineViewport { var height: CGFloat = 700 }

private struct TimelineFixture: View {
    let viewport: TimelineViewport
    let store: AppStore
    let id: String
    var body: some View {
        ChatTimelineView(sessionId: id, latestRequest: 0, openFile: .constant(nil))
            .equatable()
            .frame(height: viewport.height)
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(store)
    }
}

@Suite(.serialized) @MainActor
struct ChatTimelineLayoutTests {
    @Test func longHistoryStaysLazyAndLatestSurvivesUpdatesAndViewportChanges() async throws {
        let store = AppStore()
        let id = "layout-test"
        store.messages[id] = (0..<80).map {
            Message(id: "row-\($0)", sessionId: id, role: .user,
                    text: "Message \($0) " + String(repeating: "长会话排版测试 ", count: 20 + $0 % 10))
        }
        let viewport = TimelineViewport()
        let host = UIHostingController(rootView: TimelineFixture(viewport: viewport, store: store, id: id))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func descendants<T: UIView>(_ view: UIView, of type: T.Type) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
        }
        func settle() async throws {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
        }
        try await settle()
        let scroll = try #require(descendants(host.view, of: UIScrollView.self).first)
        #expect(descendants(host.view, of: UITextView.self).count < 40)
        let beforeTyping = scroll.contentOffset.y
        for i in 0..<30 { store.chatDrafts[id, default: ChatDraft()].text = String(repeating: "字", count: i) }
        try await settle()
        #expect(abs(scroll.contentOffset.y - beforeTyping) < 2)

        for height: CGFloat in [400, 700, 400, 700] {
            store.messages[id, default: []].append(
                Message(sessionId: id, role: .user, text: "Latest visible message"))
            viewport.height = height
            try await settle()
            let bottom = scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom
            #expect(abs(bottom - scroll.contentSize.height) < 60)
            let visible = descendants(host.view, of: UITextView.self).filter {
                $0.text.contains("Latest visible message") &&
                $0.convert($0.bounds, to: window).intersects(window.bounds)
            }
            #expect(!visible.isEmpty)
            #expect(descendants(host.view, of: UITextView.self).count < 40)
            // Streaming grows an existing row without changing the message count.
            let last = try #require(store.messages[id]?.indices.last)
            store.messages[id]?[last].text += String(repeating: "\n流式输出继续增长", count: 12)
            try await settle()
            let streamedBottom = scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom
            #expect(abs(streamedBottom - scroll.contentSize.height) < 60)
        }
    }
}
