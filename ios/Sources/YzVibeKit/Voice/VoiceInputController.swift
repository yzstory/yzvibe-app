import Foundation
import Observation

@Observable @MainActor
final class VoiceInputController {
    enum Phase: Equatable { case idle, preparing, recording, finishing }
    private(set) var phase: Phase = .idle
    private(set) var sessionId: String?
    private(set) var level: Float = 0
    private(set) var seconds = 0
    var cancelArmed = false
    private(set) var hasTranscript = false
    var issue: String?
    var active: Bool { phase != .idle }
    @ObservationIgnored private let provider: any SpeechRecognitionProvider
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var original = ""
    @ObservationIgnored private var lastWritten = ""
    @ObservationIgnored private var read: (() -> String)?
    @ObservationIgnored private var write: ((String) -> Void)?

    init(provider: any SpeechRecognitionProvider = AppleSpeechRecognitionProvider()) { self.provider = provider }

    func start(sessionId: String, configuration: SpeechRecognitionConfiguration = .init(),
               read: @escaping () -> String, write: @escaping (String) -> Void) {
        guard !active else { return }
        let id = UUID(); generation = id
        self.sessionId = sessionId; self.read = read; self.write = write
        original = read(); lastWritten = original
        issue = nil; seconds = 0; level = 0; cancelArmed = false; hasTranscript = false
        phase = .preparing
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await provider.start(configuration: configuration) { [weak self] event in
                    guard let self, self.generation == id, self.active else { return }
                    self.receive(event)
                }
                guard generation == id, phase == .preparing else { return }
                phase = .recording
                timer = Task { [weak self] in
                    for second in 1...60 {
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        guard let self, self.generation == id, self.phase == .recording else { return }
                        self.seconds = second
                        if second == 60 { self.finish() }
                    }
                }
            } catch {
                guard generation == id, active else { return }
                if !(error is CancellationError) { issue = error.localizedDescription }
                complete()
            }
        }
    }
    func finish() {
        guard active, phase != .finishing else { return }
        if phase == .preparing { complete(); return }
        phase = .finishing; level = 0; timer?.cancel()
        provider.finish()
        let id = generation
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, self.generation == id, self.phase == .finishing else { return }
            self.complete(notifyEmpty: true)
        }
    }
    /// Navigation/background/interruption retains the most recent partial result, with no microphone left running.
    func suspend(sessionId: String? = nil) {
        guard active, sessionId == nil || self.sessionId == sessionId else { return }
        complete()
    }
    func cancel() {
        guard active else { return }
        if read?() == lastWritten { write?(original) }
        hasTranscript = false
        complete()
    }
    private func receive(_ event: SpeechRecognitionEvent) {
        switch event {
        case .level(let value): if phase == .recording { level = value }
        case .transcript(let text, let final):
            // Never overwrite a concurrent typed edit or externally restored draft.
            guard read?() == lastWritten else {
                issue = "草稿已被编辑，语音输入已停止。"; complete(); return
            }
            if !text.isEmpty {
                lastWritten = original + (original.isEmpty || original.last?.isWhitespace == true ? "" : "\n") + text
                write?(lastWritten); hasTranscript = true
            }
            if final { complete(notifyEmpty: true) }
        case .interrupted:
            issue = "录音已中断，已识别的文字已保留。"; complete()
        case .failure(let message):
            issue = message; complete()
        }
    }
    private func complete(notifyEmpty: Bool = false) {
        if notifyEmpty && !hasTranscript && issue == nil { issue = "没有识别到文字，请靠近麦克风后重试。" }
        generation = UUID(); phase = .idle; level = 0; cancelArmed = false
        startTask?.cancel(); startTask = nil
        deadline?.cancel(); deadline = nil; timer?.cancel(); timer = nil
        provider.cancel(); read = nil; write = nil
    }
}
