import SwiftUI

// 会话选项控件：模式 / 模型 / 思考强度。聊天页输入条和新建会话页共用；
// 具体每个选项在 Claude / Codex 上是什么含义来自 `AgentCapabilities`（连接器 GET /agents，或 App 内置回退表）。

/// 输入条里的选项胶囊：图标 + 文本 + 上箭头。
struct OptionPill: View {
    @Environment(\.palette) private var p
    enum Tone { case plain, plan, trust }
    let icon: String
    let text: String
    var tone: Tone = .plain

    private var colors: (fg: Color, bg: Color, stroke: Color?) {
        switch tone {
        case .plain: (p.labelSecondary, p.fillSecondary.opacity(0.65), nil)
        case .plan: (p.brandText, p.brandSoft, nil)
        case .trust: (p.danger, p.dangerSoft, nil)
        }
    }
    var body: some View {
        let c = colors
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(.caption, weight: .semibold))
            Text(text).font(.system(.caption, weight: .medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(.caption2, weight: .medium)).opacity(0.6)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .foregroundStyle(c.fg)
        .background(Capsule().fill(c.bg))
        .overlay { if let s = c.stroke { Capsule().strokeBorder(s, lineWidth: 1) } }
    }
}

extension OptionPill.Tone {
    init(_ mode: SessionMode) { switch mode { case .plan: self = .plan; case .normal: self = .plain; case .trust: self = .trust } }
}

/// 模式菜单：Plan / Normal / Trust，附带该 Agent 上的解释与实际参数。
struct ModeMenu: View {
    let agent: AgentKind
    let caps: AgentCapabilities
    @Binding var mode: SessionMode

    var body: some View {
        Menu {
            Section("\(agent.displayName) · 模式") {
                Picker("模式", selection: $mode) {
                    ForEach(SessionMode.allCases) { m in
                        Label {
                            Text("\(m.displayName) · \(m.subtitle)")
                            if let d = caps.modeInfo(m)?.description { Text(d) }
                        } icon: { Image(systemName: m.symbol) }
                        .tag(m)
                    }
                }
            }
            if let flag = caps.modeInfo(mode)?.flag { Button(flag) {}.disabled(true) }
        } label: {
            OptionPill(icon: mode.symbol, text: mode.displayName, tone: .init(mode))
        }
    }
}

/// 模型菜单：连接器目录 + 用户自定义模型 + 「自定义模型…」输入。
struct ModelMenu: View {
    @Environment(AppStore.self) private var store
    let agent: AgentKind
    let caps: AgentCapabilities
    @Binding var model: String?
    @State private var askCustom = false
    @State private var customText = ""

    private var options: [ModelOption] {
        var list = store.modelOptions(for: agent, caps: caps)
        for id in (agent == .omp ? [] : store.settings.customModels(for: agent)) where !list.contains(where: { $0.id == id }) { list.append(ModelOption(id: id)) }
        if agent != .omp, let m = model, !m.isEmpty, !list.contains(where: { $0.id == m }) { list.append(ModelOption(id: m)) }
        return list
    }
    private var selection: Binding<String> { Binding(get: { model ?? "" }, set: { model = $0.isEmpty ? nil : $0 }) }

    var body: some View {
        Menu {
            Section("\(agent.displayName) · 模型") {
                Picker("模型", selection: selection) {
                    Label("默认模型", systemImage: "sparkles").tag("")
                    ForEach(options) { m in
                        Label { Text(m.label); if let d = m.description { Text(d) } } icon: { Image(systemName: "cpu") }.tag(m.id)
                    }
                }
            }
            if caps.customModel {
                Button { customText = model ?? ""; askCustom = true } label: { Label("自定义模型…", systemImage: "pencil") }
            }
        } label: {
            OptionPill(icon: "pencil", text: caps.label(forModel: model))
        }
        .alert("自定义模型", isPresented: $askCustom) {
            TextField("模型 ID，如 claude-opus-5", text: $customText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("使用") {
                let id = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return }
                store.settings.addCustomModel(id, for: agent)
                model = id
            }
            Button("取消", role: .cancel) {}
        } message: { Text("原样传给 \(agent.displayName) 的 --model 参数") }
    }
}

/// 思考强度菜单：档位来自模型目录（同一 Agent 不同模型可能不同），空表示 Agent 默认。
struct EffortMenu: View {
    let agent: AgentKind
    let caps: AgentCapabilities
    let model: String?
    @Binding var effort: String?

    @State private var showing = false

    private var levels: [String] {
        var list = agent == .omp ? [""] : ["", "low", "medium", "high", "xhigh", "max", "ultra"]
        for value in caps.efforts(for: agent == .omp ? (model ?? caps.models.first?.id) : model) where !value.isEmpty && !list.contains(value) { list.append(value) }
        if agent != .omp, let e = effort, !e.isEmpty, !list.contains(e) { list.append(e) }
        return list.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        Button { showing = true } label: {
            OptionPill(icon: "speedometer", text: EffortLevel.displayName(effort))
        }
        .buttonStyle(.plain)
        .onChange(of: model) { _, _ in
            if agent == .omp, let effort, !levels.contains(effort) { self.effort = nil }
        }
        .sheet(isPresented: $showing) {
            EffortDial(levels: levels, effort: $effort)
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
    }
}

/// Preview locally while dragging; send only the settled choice to the connector.
private struct EffortDial: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let levels: [String]
    @Binding var effort: String?
    @State private var index = 0
    @State private var feedback = 0
    @State private var ultraFeedback = 0
    private var selected: String { levels[min(index, levels.count - 1)] }
    private var isUltra: Bool { selected == "ultra" }

    private func select(_ next: Int) {
        let clamped = min(max(next, 0), levels.count - 1)
        guard index != clamped else { return }
        index = clamped
        if isUltra { ultraFeedback += 1 } else { feedback += 1 }
    }
    private func commit() {
        let value: String? = selected.isEmpty ? nil : selected
        if effort != value { effort = value }
    }
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("思考力度").font(.headline)
                Spacer()
                Button("完成") { commit(); dismiss() }.font(.subheadline.weight(.semibold))
            }
            Text(EffortLevel.displayName(selected))
                .font(.title2.weight(.bold)).foregroundStyle(isUltra ? p.brand : p.label)
                .shadow(color: p.brand.opacity(isUltra ? 0.35 : 0), radius: 12)
                .phaseAnimator([0.0, 1.0, 0.0], trigger: ultraFeedback) { content, phase in
                    content.scaleEffect(isUltra && !reduceMotion ? 1 + 0.08 * phase : 1)
                } animation: { _ in .spring(response: 0.28, dampingFraction: 0.7) }
            GeometryReader { geo in
                let travel = max(1, geo.size.width - 56)
                let step = travel / CGFloat(max(1, levels.count - 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(p.fillSecondary)
                    Capsule().fill(p.brand).frame(width: 56 + CGFloat(index) * step)
                        .overlay {
                            if isUltra {
                                Capsule().fill(LinearGradient(colors: [p.brand, .yellow.opacity(0.65), p.brand], startPoint: .leading, endPoint: .trailing))
                                    .allowsHitTesting(false)
                            }
                        }
                        .shadow(color: p.brand.opacity(isUltra ? 0.4 : 0), radius: isUltra ? 16 : 0)
                    if !reduceMotion {
                        Capsule().stroke(p.brand.opacity(0.7), lineWidth: 2)
                            .phaseAnimator([0.0, 1.0, 0.0], trigger: ultraFeedback) { content, phase in
                                content.scaleEffect(x: 1 + 0.025 * phase, y: 1 + 0.4 * phase)
                                    .opacity(!isUltra || phase == 0 ? 0 : 1 - phase * 0.7)
                            } animation: { _ in .easeOut(duration: 0.3) }
                            .allowsHitTesting(false)
                    }
                    HStack {
                        ForEach(levels.indices, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 0) }
                            Circle().fill(i <= index ? p.brandInk.opacity(0.25) : p.labelTertiary.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }.padding(.horizontal, 28)
                    Circle().fill(.white).frame(width: 44, height: 44)
                        .overlay {
                            if isUltra { Image(systemName: "bolt.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(p.brand).accessibilityHidden(true) }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .offset(x: 6 + CGFloat(index) * step)
                }
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        select(Int(((value.location.x - 28) / step).rounded()))
                    }
                    .onEnded { _ in commit() })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("思考力度")
                .accessibilityValue(EffortLevel.displayName(selected))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: select(index + 1)
                    case .decrement: select(index - 1)
                    @unknown default: return
                    }
                    commit()
                }
            }.frame(height: 56)
            HStack {
                Text(EffortLevel.displayName(levels.first))
                Spacer()
                Text(EffortLevel.displayName(levels.last))
            }.font(.caption).foregroundStyle(p.labelSecondary)
        }
        .padding(24)
        .tint(p.brand)
        .onAppear { index = levels.firstIndex(of: effort ?? "") ?? 0 }
        .sensoryFeedback(.selection, trigger: feedback)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.85), trigger: ultraFeedback)
    }
}

/// 三个胶囊排成一行，可横向滚动（窄屏时模型名会被截断在右侧）。
struct SessionOptionsRow: View {
    let agent: AgentKind
    let caps: AgentCapabilities
    @Binding var mode: SessionMode
    @Binding var model: String?
    @Binding var effort: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ModeMenu(agent: agent, caps: caps, mode: $mode)
                ModelMenu(agent: agent, caps: caps, model: $model)
                EffortMenu(agent: agent, caps: caps, model: model, effort: $effort)
            }
        }
        .scrollClipDisabled()
    }
}
