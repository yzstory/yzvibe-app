import Foundation
import Observation
@preconcurrency import AVFoundation

@MainActor protocol ReplySpeechProvider: AnyObject {
    func speak(_ text: String, completion: @escaping @MainActor () -> Void) throws
    func stop()
}

@Observable @MainActor final class ReplySpeaker {
    private(set) var messageId: String?
    private(set) var sessionId: String?
    var issue: String?
    @ObservationIgnored private let provider: any ReplySpeechProvider
    @ObservationIgnored private var generation = UUID()
    init(provider: any ReplySpeechProvider = AppleReplySpeechProvider()) { self.provider = provider }

    func toggle(text: String, messageId: String, sessionId: String) {
        if self.messageId == messageId && self.sessionId == sessionId { stop(); return }
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let id = UUID(); generation = id
        self.messageId = messageId; self.sessionId = sessionId; issue = nil
        do {
            try provider.speak(text) { [weak self] in
                guard let self, self.generation == id else { return }
                self.stop()
            }
        } catch { issue = "无法开始朗读：\(error.localizedDescription)"; stop() }
    }
    func stop(sessionId: String? = nil) {
        guard sessionId == nil || self.sessionId == sessionId else { return }
        generation = UUID(); messageId = nil; self.sessionId = nil
        provider.stop()
    }
}

@MainActor final class AppleReplySpeechProvider: NSObject, ReplySpeechProvider, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceID: ObjectIdentifier?
    private var completion: (@MainActor () -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var previousAudio: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    override init() { super.init(); synthesizer.delegate = self }

    func speak(_ text: String, completion: @escaping @MainActor () -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        previousAudio = (session.category, session.mode, session.categoryOptions)
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch { stop(); throw error }
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        let containsChinese = text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        utterance.voice = AVSpeechSynthesisVoice(language: containsChinese ? "zh-CN" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let playbackID = ObjectIdentifier(utterance)
        utteranceID = playbackID
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.utteranceID == playbackID else { return }
                    self.completion?()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in
                    guard let self, self.utteranceID == playbackID else { return }
                    self.completion?()
                }
        })
        synthesizer.speak(utterance)
    }
    func stop() {
        utteranceID = nil; completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let previousAudio {
            self.previousAudio = nil
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(previousAudio.0, mode: previousAudio.1, options: previousAudio.2)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completed(ObjectIdentifier(utterance))
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completed(ObjectIdentifier(utterance))
    }
    private nonisolated func completed(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            self.completion?()
        }
    }
}
