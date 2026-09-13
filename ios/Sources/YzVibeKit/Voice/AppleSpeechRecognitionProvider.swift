import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// iOS 17+ Apple recognizer. Audio is explicitly restricted to on-device recognition.
@MainActor
final class AppleSpeechRecognitionProvider: SpeechRecognitionProvider {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var ownsAudioSession = false
    private var previousAudio: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    func start(configuration: SpeechRecognitionConfiguration,
               receive: @escaping @MainActor @Sendable (SpeechRecognitionEvent) -> Void) async throws {
        cancel()
        let id = generation
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard id == generation else { throw CancellationError() }
        guard allowed else { throw VoiceInputError.microphoneDenied }
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard id == generation else { throw CancellationError() }
        guard permission == .authorized else { throw VoiceInputError.recognitionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: configuration.localeIdentifier)),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw VoiceInputError.unavailable }
        self.recognizer = recognizer
        let audio = AVAudioSession.sharedInstance()
        previousAudio = (audio.category, audio.mode, audio.categoryOptions)
        do {
            try audio.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            ownsAudioSession = true
            try audio.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.contextualStrings = Array(configuration.contextualPhrases.prefix(100))
            self.request = request
            let engine = AVAudioEngine()
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceInputError.noInput }
            self.engine = engine
            // Only the immutable request is captured by the realtime callback. UI work hops to MainActor.
            node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                request.append(buffer)
                var peak: Float = 0
                if let samples = buffer.floatChannelData?[0] {
                    for i in stride(from: 0, to: Int(buffer.frameLength), by: 8) { peak = max(peak, abs(samples[i])) }
                }
                let level = min(1, peak * 6)
                Task { @MainActor [weak self] in
                    guard self?.generation == id else { return }
                    receive(.level(level))
                }
            }
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor in
                    guard self?.generation == id else { return }
                    if let text { receive(.transcript(text, isFinal: final)) }
                    if failed && !final { receive(.failure("语音识别已停止，已识别的文字已保留。")) }
                }
            }
            for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification,
                         AVAudioSession.routeChangeNotification, .AVAudioEngineConfigurationChange] {
                let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    if name == AVAudioSession.interruptionNotification,
                       (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) != AVAudioSession.InterruptionType.began.rawValue { return }
                    if name == AVAudioSession.routeChangeNotification {
                        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                        guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
                    }
                    Task { @MainActor in
                        guard self?.generation == id else { return }
                        receive(.interrupted)
                    }
                }
                observers.append(token)
            }
            engine.prepare()
            try engine.start()
        } catch { cancel(); throw error }
    }

    func finish() { stopCapture(); request?.endAudio() }
    func cancel() {
        generation = UUID()
        stopCapture()
        task?.cancel(); task = nil; request = nil; recognizer = nil
    }
    private func stopCapture() {
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0); self.engine = nil }
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if ownsAudioSession {
            let audio = AVAudioSession.sharedInstance()
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            if let previousAudio { try? audio.setCategory(previousAudio.0, mode: previousAudio.1, options: previousAudio.2) }
            ownsAudioSession = false; previousAudio = nil
        }
    }
}
