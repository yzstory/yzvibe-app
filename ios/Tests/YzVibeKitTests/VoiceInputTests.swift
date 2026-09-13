import Foundation
import Testing
@testable import YzVibeKit

@MainActor private final class SpeechStub: SpeechRecognitionProvider {
    var receive: (@MainActor @Sendable (SpeechRecognitionEvent) -> Void)?
    var starts = 0, finishes = 0, cancels = 0
    var error: Error?
    var authorization: CheckedContinuation<Void, Never>?
    var delayAuthorization = false
    func start(configuration: SpeechRecognitionConfiguration, receive: @escaping @MainActor @Sendable (SpeechRecognitionEvent) -> Void) async throws {
        starts += 1; self.receive = receive
        if delayAuthorization { await withCheckedContinuation { authorization = $0 } }
        if let error { throw error }
    }
    func finish() { finishes += 1 }
    func cancel() { cancels += 1 }
}

@Suite(.serialized) @MainActor
struct VoiceInputTests {
    private func ready(_ voice: VoiceInputController) async {
        for _ in 0..<100 where voice.phase == .preparing { await Task.yield() }
    }
    @Test func partialRevisionsReplaceOnlyTheRecordingAndKeepTheOriginalDraft() async {
        let stub = SpeechStub()
        let subject = VoiceInputController(provider: stub)
        var drafts = ["a": "原有文字", "b": "别的会话"]
        subject.start(sessionId: "a", read: { drafts["a"]! }, write: { drafts["a"] = $0 })
        await ready(subject)
        stub.receive?(.transcript("修复", isFinal: false))
        stub.receive?(.transcript("修复连接", isFinal: false))
        #expect(drafts["a"] == "原有文字\n修复连接")
        #expect(drafts["b"] == "别的会话")
        subject.suspend(sessionId: "b")
        #expect(subject.active)
        subject.suspend(sessionId: "a")
        stub.receive?(.transcript("迟到结果", isFinal: true))
        #expect(drafts["a"] == "原有文字\n修复连接")
        #expect(!subject.active && stub.cancels > 0)
    }
    @Test func cancellingRestoresOriginalAndLateEventsCannotChangeIt() async {
        let stub = SpeechStub()
        let subject = VoiceInputController(provider: stub)
        var text = "图片的说明"
        subject.start(sessionId: "a", read: { text }, write: { text = $0 })
        await ready(subject)
        stub.receive?(.transcript("不要的语音", isFinal: false))
        subject.cancel()
        stub.receive?(.transcript("迟到结果", isFinal: true))
        #expect(text == "图片的说明")
        #expect(!subject.hasTranscript)
    }
    @Test func finishDrainsFinalTextBeforeReleasingProvider() async {
        let stub = SpeechStub()
        let voice = VoiceInputController(provider: stub)
        var text = ""
        voice.start(sessionId: "a", read: { text }, write: { text = $0 })
        await ready(voice)
        stub.receive?(.transcript("修", isFinal: false))
        voice.finish()
        #expect(voice.phase == .finishing && stub.finishes == 1)
        stub.receive?(.transcript("修复重连。", isFinal: true))
        #expect(text == "修复重连。")
        #expect(voice.phase == .idle && voice.hasTranscript)
    }
    @Test func interruptionRetainsPartialWithoutAutoRestarting() async {
        let stub = SpeechStub()
        let voice = VoiceInputController(provider: stub)
        var text = ""
        voice.start(sessionId: "a", read: { text }, write: { text = $0 })
        await ready(voice)
        voice.cancelArmed = true
        stub.receive?(.transcript("待办", isFinal: false))
        stub.receive?(.interrupted)
        #expect(text == "待办")
        #expect(!voice.active && !voice.cancelArmed && stub.starts == 1)
        #expect(voice.issue != nil)
    }
    @Test func externalEditIsNeverOverwrittenOrRolledBack() async {
        let stub = SpeechStub()
        let voice = VoiceInputController(provider: stub)
        var text = ""
        voice.start(sessionId: "a", read: { text }, write: { text = $0 })
        await ready(voice)
        stub.receive?(.transcript("临时", isFinal: false))
        text = "手动编辑的新文字"
        stub.receive?(.transcript("迟到识别", isFinal: false))
        voice.cancel()
        #expect(text == "手动编辑的新文字")
        #expect(!voice.active)
    }
    @Test func cancelledPermissionRequestCannotStartRecordingLater() async {
        let stub = SpeechStub(); stub.delayAuthorization = true
        let voice = VoiceInputController(provider: stub)
        var text = "原文"
        voice.start(sessionId: "a", read: { text }, write: { text = $0 })
        for _ in 0..<100 where stub.authorization == nil { await Task.yield() }
        voice.finish()
        stub.authorization?.resume(); stub.authorization = nil
        for _ in 0..<5 { await Task.yield() }
        stub.receive?(.transcript("迟到", isFinal: false))
        #expect(voice.phase == .idle && text == "原文")
    }
    @Test func olderRecordingCannotWriteIntoNewSession() async {
        let stub = SpeechStub()
        let voice = VoiceInputController(provider: stub)
        var a = "", b = ""
        voice.start(sessionId: "a", read: { a }, write: { a = $0 })
        await ready(voice)
        let old = stub.receive
        voice.suspend()
        voice.start(sessionId: "b", read: { b }, write: { b = $0 })
        await ready(voice)
        old?(.transcript("旧", isFinal: true))
        stub.receive?(.transcript("新", isFinal: true))
        #expect(a == "" && b == "新")
    }
    @Test func recognitionFailureKeepsDraftAndDoesNotRetryInCloud() async {
        let stub = SpeechStub(); stub.error = VoiceInputError.unavailable
        let voice = VoiceInputController(provider: stub)
        var text = "原文"
        voice.start(sessionId: "a", read: { text }, write: { text = $0 })
        await ready(voice)
        #expect(voice.phase == .idle && voice.issue != nil)
        #expect(text == "原文" && stub.starts == 1)
    }
}
