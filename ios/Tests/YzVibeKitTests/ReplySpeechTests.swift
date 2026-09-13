import Foundation
import Testing
@testable import YzVibeKit

@Suite struct ReplySpeechTextTests {
    @Test func skipsFencedCommandsLogsAndInlineCodeButRetainsProse() {
        let text = """
        ## 已修复
        使用 `git status` 检查后，结果正常。
        ```sh
        npm test
        ERROR secret log
        ```
        > ~~~log
        > hidden output
        > ~~~
        **全部完成**，查看[说明](https://example.com/docs)。
        ![图片](https://example.com/a.png)
        """
        let result = ReplySpeechText.extract(text)
        #expect(result.contains("已修复"))
        #expect(result.contains("全部完成"))
        #expect(result.contains("说明"))
        for excluded in ["git", "npm", "secret", "hidden", "https", "图片", "```"] { #expect(!result.contains(excluded)) }
    }
    @Test func skipsBareTerminalOutputAndIndentedBlocks() {
        let result = ReplySpeechText.extract("正文\n$ npm test\n2026-09-13 11:00:00 error\n[INFO] hidden\n    let secret = 1\ngit push origin main\n下一步完成。")
        #expect(result == "正文\n下一步完成。")
    }
    @Test func logSectionEndsAtPeerHeadingAndUnclosedFenceDoesNotLeak() {
        let result = ReplySpeechText.extract("# 结果\n成功\n## 日志\n私有输出\n### 明细\n不朗读\n## 后续\n继续\n```log\n隐藏")
        #expect(result == "结果\n成功\n后续\n继续")
    }
    @Test func tableKeepsWordsWithoutSeparatorNoise() {
        let result = ReplySpeechText.extract("| 方案 | 结果 |\n| --- | :---: |\n| 原生 | 完成 |")
        #expect(result.contains("方案"))
        #expect(result.contains("完成"))
        #expect(!result.contains("---"))
        #expect(!result.contains("|"))
    }
}

@MainActor private final class ReplySpeechStub: ReplySpeechProvider {
    var texts: [String] = []
    var completions: [@MainActor () -> Void] = []
    var stops = 0
    var fails = false
    func speak(_ text: String, completion: @escaping @MainActor () -> Void) throws {
        if fails { throw CocoaError(.fileReadUnknown) }
        texts.append(text); completions.append(completion)
    }
    func stop() { stops += 1 }
}

@Suite @MainActor struct ReplySpeakerTests {
    @Test func togglesAndReplacesPlaybackWithoutLateCompletionStoppingNewReply() {
        let stub = ReplySpeechStub(), subject: ReplySpeaker
        subject = ReplySpeaker(provider: stub)
        subject.toggle(text: "一", messageId: "1", sessionId: "a")
        subject.toggle(text: "二", messageId: "2", sessionId: "b")
        stub.completions[0]()
        #expect(subject.messageId == "2")
        subject.stop(sessionId: "a")
        #expect(subject.messageId == "2")
        subject.toggle(text: "二", messageId: "2", sessionId: "b")
        #expect(subject.messageId == nil)
        #expect(stub.texts == ["一", "二"])
    }
    @Test func completionAndFailureClearActiveState() {
        let stub = ReplySpeechStub(), subject: ReplySpeaker
        subject = ReplySpeaker(provider: stub)
        subject.toggle(text: "正文", messageId: "1", sessionId: "a")
        stub.completions[0]()
        #expect(subject.messageId == nil)
        stub.fails = true
        subject.toggle(text: "正文", messageId: "2", sessionId: "a")
        #expect(subject.messageId == nil && subject.issue != nil)
    }
    @Test func emptyTextNeverStartsAudio() {
        let stub = ReplySpeechStub(), subject: ReplySpeaker
        subject = ReplySpeaker(provider: stub)
        subject.toggle(text: " \n", messageId: "1", sessionId: "a")
        #expect(stub.texts.isEmpty)
        #expect(subject.messageId == nil)
    }
}
