import SwiftUI

struct VoiceInputButton: View {
    @Environment(\.palette) private var p
    let voice: VoiceInputController
    let begin: () -> Void
    @State private var pressed = false
    @State private var startedHolding = false
    @State private var beganActive = false
    @State private var cancelling = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: voice.active ? "stop.fill" : "mic.fill")
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(cancelling ? Color.red : voice.active ? p.brand : p.labelSecondary)
            .frame(width: 44, height: 44)
            .background(voice.active || pressed ? p.brand.opacity(0.12) : .clear, in: Circle())
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !pressed {
                        pressed = true; beganActive = voice.active; startedHolding = false; cancelling = false
                        if !beganActive {
                            holdTask = Task { @MainActor in
                                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                                guard pressed else { return }
                                startedHolding = true; begin()
                            }
                        }
                    }
                    if startedHolding && voice.active && !voice.locked {
                        cancelling = value.translation.width < -65
                        if !cancelling && value.translation.height < -65 { voice.lock() }
                    }
                }
                .onEnded { value in
                    holdTask?.cancel(); holdTask = nil
                    if beganActive { voice.finish() }
                    else if startedHolding {
                        if cancelling || value.translation.width < -65 { voice.cancel() }
                        else if value.translation.height < -65 { voice.lock() }
                        else if !voice.locked { voice.finish() }
                    } else if abs(value.translation.width) < 20 && abs(value.translation.height) < 20 {
                        begin(); voice.lock()
                    }
                    pressed = false; cancelling = false
                })
            .overlay(alignment: .top) {
                if cancelling { Text("松开取消").font(.caption2).foregroundStyle(.red).fixedSize().offset(y: -22) }
            }
            .accessibilityElement()
            .accessibilityLabel(voice.active ? "结束语音输入" : "语音输入")
            .accessibilityHint("轻点开始或结束；按住说话，上滑锁定，左滑取消")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if voice.active { voice.finish() } else { begin(); voice.lock() } }
            .sensoryFeedback(.selection, trigger: voice.phase)
            .sensoryFeedback(.selection, trigger: voice.locked)
            .onDisappear { holdTask?.cancel() }
    }
}

struct VoiceRecordingPanel: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let voice: VoiceInputController
    var body: some View {
        HStack(spacing: 12) {
            Button { voice.cancel() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }.accessibilityLabel("取消本次录音")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if voice.phase != .recording { ProgressView().controlSize(.small) }
                    else {
                        HStack(spacing: 3) {
                            ForEach(0..<7) { i in
                                Capsule().fill(p.brand).frame(width: 3, height: 4 + CGFloat(voice.level) * CGFloat([10, 19, 26, 32, 26, 19, 10][i]))
                            }
                        }.frame(width: 42, height: 30)
                            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: voice.level)
                            .accessibilityHidden(true)
                    }
                    Text(voice.phase == .preparing ? "准备端侧识别…" : voice.phase == .finishing ? "正在完成转写…" : "正在听 · \(voice.seconds)s / 60s")
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                }
                Text(voice.locked ? "已锁定录音 · 完成后可编辑" : "上滑锁定 · 左滑取消 · 松开转文字")
                    .font(.caption2).foregroundStyle(p.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { voice.finish() } label: {
                Image(systemName: "checkmark").fontWeight(.semibold).frame(width: 44, height: 44)
                    .background(p.brand, in: Circle()).foregroundStyle(p.brandInk)
            }.disabled(voice.phase == .finishing).accessibilityLabel("完成转写")
        }.padding(10).liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
