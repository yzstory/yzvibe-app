import Foundation

/// Only used by the app's explicit demo mode; never requests microphone access.
@MainActor
final class DemoSpeechRecognitionProvider: SpeechRecognitionProvider {
    private var work: Task<Void, Never>?
    private var receive: (@MainActor @Sendable (SpeechRecognitionEvent) -> Void)?
    private var text = ""
    func start(configuration: SpeechRecognitionConfiguration, receive: @escaping @MainActor @Sendable (SpeechRecognitionEvent) -> Void) async throws {
        cancel(); self.receive = receive; text = ""
        work = Task { [weak self] in
            let words = ["演示转写：", "演示转写：先修复", "演示转写：先修复会话重连，", "演示转写：先修复会话重连，再检查文件预览。"]
            var step = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                self.text = words[min(step / 4, words.count - 1)]
                receive(.transcript(self.text, isFinal: false))
                receive(.level([Float(0.2), 0.6, 0.9, 0.35][step % 4]))
                step += 1
            }
        }
    }
    func finish() { work?.cancel(); work = nil; receive?(.transcript(text, isFinal: true)) }
    func cancel() { work?.cancel(); work = nil; receive = nil }
}
