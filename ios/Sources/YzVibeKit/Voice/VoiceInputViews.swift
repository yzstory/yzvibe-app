import SwiftUI

/// The target stays outside the horizontally scrolling model options so it never moves under the thumb.
struct VoiceInputButton: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let voice: VoiceInputController
    let begin: () -> Void
    @GestureState private var touching = false
    @State private var pressed = false
    @State private var startedHolding = false
    @State private var translation: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(.callout, weight: .semibold))
            .foregroundStyle(voice.cancelArmed ? p.danger : pressed ? p.brandInk : p.brand)
            .frame(width: 44, height: 44)
            .background(pressed ? p.brand : p.fill, in: Circle())
            .scaleEffect(pressed ? 1.08 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9), value: pressed)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    translation = value.translation.height
                    if !pressed {
                        guard !voice.active else { return }
                        pressed = true; startedHolding = false
                        holdTask = Task { @MainActor in
                            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                            guard pressed else { return }
                            startedHolding = true
                            begin()
                            voice.cancelArmed = translation < -64
                        }
                    }
                    if startedHolding && voice.active {
                        // Hysteresis avoids repeated haptics when the finger rests on the boundary.
                        voice.cancelArmed = VoiceHoldGesture.isCancelling(offset: translation, wasCancelling: voice.cancelArmed)
                    }
                }
                .onEnded { value in
                    holdTask?.cancel(); holdTask = nil
                    if startedHolding {
                        if VoiceHoldGesture.isCancelling(offset: value.translation.height, wasCancelling: voice.cancelArmed) {
                            voice.cancel()
                        } else { voice.finish() }
                    }
                    pressed = false; startedHolding = false; voice.cancelArmed = false
                })
            .onChange(of: touching) { _, down in
                guard !down else { return }
                // onEnded clears pressed first; a cancelled gesture may never deliver onEnded.
                Task { @MainActor in
                    await Task.yield()
                    guard !touching, pressed else { return }
                    holdTask?.cancel(); holdTask = nil
                    if startedHolding { voice.suspend() }
                    pressed = false; startedHolding = false; voice.cancelArmed = false
                }
            }
            .accessibilityElement()
            .accessibilityLabel("按住说话")
            .accessibilityHint("按住录音，上滑取消，松开后可编辑文字。旁白用户请双击并按住。")
            .accessibilityAddTraits(.isButton)
            .sensoryFeedback(.selection, trigger: voice.phase)
            .sensoryFeedback(.selection, trigger: voice.cancelArmed)
            .onDisappear {
                holdTask?.cancel(); holdTask = nil
                if startedHolding { voice.suspend() }
                pressed = false; startedHolding = false
            }
    }
}

/// Shared release/drag decision, including a return zone to resume recording before lifting.
enum VoiceHoldGesture {
    static func isCancelling(offset: CGFloat, wasCancelling: Bool) -> Bool {
        offset < (wasCancelling ? -44 : -64)
    }
}

/// Lives above the conversation, never in its layout or the microphone's hit-test path.
struct VoiceRecordingPanel: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let voice: VoiceInputController
    private var cancelling: Bool { voice.cancelArmed && voice.phase != .finishing }
    private var tint: Color { cancelling ? p.danger : p.brand }
    private var title: String {
        if cancelling { return "松开取消" }
        switch voice.phase {
        case .preparing: return "正在准备麦克风…"
        case .finishing: return "正在完成转写…"
        default: return "松开转文字"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.32)
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ZStack {
                        if cancelling {
                            Image(systemName: "xmark").font(.system(size: 26, weight: .semibold))
                        } else if voice.phase != .recording {
                            ProgressView().tint(p.brandInk)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(0..<19) { i in
                                    Capsule().frame(width: 3, height: 5 + CGFloat(voice.level) * CGFloat(12 + (i * 17 % 31)))
                                }
                            }
                            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: voice.level)
                        }
                    }.frame(height: 42).accessibilityHidden(true)
                    Text("\(voice.seconds)s / 60s").font(.caption.monospacedDigit())
                }
                .foregroundStyle(p.brandInk)
                .frame(width: 220, height: 110)
                .background(tint, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3).fill(tint)
                        .frame(width: 18, height: 18).rotationEffect(.degrees(45)).offset(y: 7)
                }
                .scaleEffect(cancelling ? 0.94 : 1)
                .offset(y: cancelling ? -8 : 0)
                Text(title).font(.headline).foregroundStyle(.white)
                Text(cancelling ? "滑回继续说话" : voice.phase == .finishing ? "文字会留在输入框，不会自动发送" : "上滑取消 · 转写后可编辑")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8))
                Label(cancelling ? "取消本次录音" : "上滑取消", systemImage: cancelling ? "xmark" : "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 22).frame(height: 44)
                    .foregroundStyle(cancelling ? .white : .white.opacity(0.85))
                    .background(cancelling ? p.danger : Color.white.opacity(0.12), in: Capsule())
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9), value: cancelling)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
