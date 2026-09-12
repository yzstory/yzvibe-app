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
        for id in store.settings.customModels(for: agent) where !list.contains(where: { $0.id == id }) { list.append(ModelOption(id: id)) }
        if let m = model, !m.isEmpty, !list.contains(where: { $0.id == m }) { list.append(ModelOption(id: m)) }
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

    private var selection: Binding<String> { Binding(get: { effort ?? "" }, set: { effort = $0.isEmpty ? nil : $0 }) }
    private var levels: [String] {
        var list = caps.efforts(for: model)
        if let e = effort, !e.isEmpty, !list.contains(e) { list.append(e) }
        return list
    }

    var body: some View {
        Menu {
            Section("\(agent.displayName) · 思考强度") {
                Picker("思考强度", selection: selection) {
                    Text("默认").tag("")
                    ForEach(levels, id: \.self) { Text("\(EffortLevel.displayName($0)) · \($0)").tag($0) }
                }
            }
        } label: {
            OptionPill(icon: "speedometer", text: EffortLevel.displayName(effort))
        }
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
