import SwiftUI

/// Configuration belongs to one connected Mac; keys are never persisted in phone settings.
struct OmpConfigurationSection: View {
    @Environment(AppStore.self) private var store
    let device: Device
    @State private var config: OmpConfiguration?
    @State private var loading = false
    @State private var error: String?
    @State private var editing: OmpConfiguredModel?
    @State private var adding = false

    var body: some View {
        Section {
            if loading { ProgressView("正在读取电脑配置…") }
            if let error { Text(error).foregroundStyle(.red) }
            if let config {
                if config.models.isEmpty {
                    ContentUnavailableView("尚未配置模型", systemImage: "cpu", description: Text("添加 OpenAI 兼容接口，或在这台电脑的 OMP 中配置后刷新。"))
                }
                ForEach(config.models) { model in
                    Button { editing = model } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.label).foregroundStyle(.primary)
                                Text(model.baseUrl.isEmpty ? model.providerId : model.baseUrl).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(model.keyConfigured ? "Key 已配置" : "未配置 Key").font(.caption2).foregroundStyle(.secondary)
                                if let window = model.contextWindow { Text("上下文预算：\(window) tokens").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: model.editable ? "pencil" : "desktopcomputer").foregroundStyle(.secondary)
                        }
                    }.disabled(!model.editable)
                }
                Button { adding = true } label: { Label("添加 OpenAI 兼容模型", systemImage: "plus") }
            }
            Button { Task { await load() } } label: { Label("从电脑刷新", systemImage: "arrow.clockwise") }.disabled(loading)
        } header: { Text(device.name) }
          footer: { Text("只显示这台电脑明确配置的模型，不提供预置模型。保存后同步到终端 OMP；正在运行的任务不受影响。") }
        .task { await load() }
        .sheet(isPresented: $adding) {
            if let config { OmpConfigurationEditor(device: device, config: config, original: nil, didSave: saved) }
        }
        .sheet(item: $editing) { model in
            if let config { OmpConfigurationEditor(device: device, config: config, original: model, didSave: saved) }
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            config = try await store.client.ompConfiguration(device: device)
            if let caps = try? await store.client.capabilities(device: device) { store.capabilities[device.id] = caps }
        } catch { self.error = error.localizedDescription }
    }
    private func saved(_ value: OmpConfiguration) {
        config = value
        store.toast = "已保存到 \(device.name) 的 OMP"
    }
}

private struct OmpConfigurationEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device
    let config: OmpConfiguration
    let original: OmpConfiguredModel?
    let didSave: (OmpConfiguration) -> Void
    @State private var baseUrl = ""
    @State private var key = ""
    @State private var modelName = ""
    @State private var contextWindow = "32768"
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.example.com/v1", text: $baseUrl)
                        .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Base URL")
                } header: { Text("Base URL") }
                  footer: { Text("也可粘贴完整的 /chat/completions 地址，保存时会自动处理。") }
                Section {
                    SecureField(original?.keyConfigured == true ? "已配置，留空保留" : "填写 API Key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                } header: { Text("API Key") }
                  footer: { Text("密钥仅通过 HTTPS 传输到已配对电脑，不保存在手机设置中，也不会回显。修改接口地址时需重新填写。") }
                Section {
                    TextField("例如 qwen3.7-plus", text: $modelName)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(original != nil)
                } header: { Text("Model Name") }
                  footer: { Text("填写接口的模型 ID。已有模型 ID 保持不变，需要其他模型请新增。") }
                Section {
                    TextField("例如 262144（256K）", text: $contextWindow)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("上下文预算 tokens")
                } header: { Text("上下文预算（tokens）") }
                  footer: { Text("填写当前供应商与模型支持的窗口。256K = 262144；这个值决定 OMP 何时压缩上下文，不会提高服务端实际限制。") }
                Section {
                    Label(device.name, systemImage: "desktopcomputer")
                    Text("保存到电脑 OMP，下一轮请求自动加载；终端重开 OMP 后生效。同一供应商的模型共享接口地址和 Key。").font(.footnote).foregroundStyle(.secondary)
                    Text("保存仅同步配置，不代表接口验证成功。新模型暂按纯文本配置，图片和思考参数可在终端按实际能力调整。").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .paperBackground()
            .navigationTitle(original == nil ? "添加 OMP 模型" : "OMP 模型配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { key = ""; dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("保存") }
                    }.disabled(saving || baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelName.isEmpty || (original?.keyConfigured != true && key.isEmpty))
                }
            }
            .onAppear { baseUrl = original?.baseUrl ?? ""; modelName = original?.modelName ?? ""; contextWindow = original.map { $0.contextWindow.map(String.init) ?? "" } ?? "32768" }
            .onDisappear { key = "" }
            .interactiveDismissDisabled(saving)
        }
    }
    private func save() async {
        let windowText = contextWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = Int(windowText)
        guard (windowText.isEmpty && original != nil) || window.map({ (1024...10_000_000).contains($0) }) == true else {
            error = "上下文预算须为 1024–10000000 的整数"; return
        }
        saving = true; error = nil
        defer { saving = false }
        do {
            let input = OmpConfigurationInput(revision: config.revision, providerId: original?.providerId,
                originalModelName: original?.modelName, baseUrl: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines), key: key, modelName: modelName, contextWindow: window)
            let result = try await store.client.saveOmpConfiguration(device: device, input: input)
            key = ""
            // Do not misreport a committed configuration as a failed save when a subsequent refresh fails.
            if let caps = try? await store.client.capabilities(device: device) { store.capabilities[device.id] = caps }
            didSave(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
