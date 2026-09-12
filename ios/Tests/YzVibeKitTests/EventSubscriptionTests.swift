import Testing
@testable import YzVibeKit

struct EventSubscriptionTests {
    @Test func cancelledSubscriberDoesNotTerminateReplacement() async {
        let channel = ConnectorEventChannel()
        let original = channel.stream()
        let consumer = Task {
            for await _ in original { }
        }
        consumer.cancel()
        await consumer.value

        let replacement = channel.stream()
        channel.yield(.messageDelta(sessionId: "s", messageId: "m", text: "实时回复"))
        channel.finish() // 有界消费：发生回归时失败，不会永久挂起测试。
        var texts: [String] = []
        for await event in replacement {
            if case .messageDelta(_, _, let text) = event { texts.append(text) }
        }
        #expect(texts == ["实时回复"])
    }

    @Test func lateCancellationOfOldSubscriberDoesNotAffectNewOne() async {
        let channel = ConnectorEventChannel()
        let original = channel.stream()
        let replacement = channel.stream()
        let consumer = Task { for await _ in original { } }
        consumer.cancel()
        await consumer.value

        channel.yield(.messageDelta(sessionId: "s", messageId: "m", text: "第一段"))
        channel.yield(.messageDelta(sessionId: "s", messageId: "m", text: "第二段"))
        channel.yield(.messageDone(sessionId: "s", messageId: "m"))
        channel.finish()
        var texts: [String] = []
        var completed = false
        for await event in replacement {
            if case .messageDelta(_, _, let text) = event { texts.append(text) }
            if case .messageDone = event { completed = true }
        }
        #expect(texts == ["第一段", "第二段"])
        #expect(completed)
    }
}
