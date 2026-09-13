import Foundation

/// Provider-neutral contract. A cloud implementation can own capture/transport without changing drafts or sending.
struct SpeechRecognitionConfiguration: Sendable {
    var localeIdentifier = "zh-CN"
    var contextualPhrases: [String] = ["柚子Vibe", "Codex", "Claude", "SwiftUI", "WebSocket", "TestFlight"]
}

enum SpeechRecognitionEvent: Sendable {
    /// A complete replacement transcript for the current recording, not a delta.
    case transcript(String, isFinal: Bool)
    case level(Float)
    case interrupted
    case failure(String)
}

@MainActor
protocol SpeechRecognitionProvider: AnyObject {
    func start(configuration: SpeechRecognitionConfiguration,
               receive: @escaping @MainActor @Sendable (SpeechRecognitionEvent) -> Void) async throws
    /// Stop capture and allow final recognition results to drain.
    func finish()
    /// Release capture and suppress all later results.
    func cancel()
}

enum VoiceInputError: LocalizedError {
    case microphoneDenied, recognitionDenied, unavailable, noInput
    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "请在 iPhone 设置中允许柚子Vibe使用麦克风。"
        case .recognitionDenied: "请在 iPhone 设置中允许柚子Vibe进行语音识别。"
        case .unavailable: "此设备当前无法使用所选语言的端侧识别。请检查系统听写和语言资源，或使用键盘输入。"
        case .noInput: "麦克风暂时不可用，请检查音频设备后重试。"
        }
    }
}
