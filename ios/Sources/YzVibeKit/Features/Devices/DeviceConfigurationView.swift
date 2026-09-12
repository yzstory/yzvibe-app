import SwiftUI

struct DeviceConfiguration {
    var name: String
    var address: String
    var port: String
    init(_ device: Device) {
        name = device.name; address = device.host; port = String(device.port)
    }
    func applying(to device: Device) -> Device? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !address.isEmpty,
              let port = Int(port), (1...65535).contains(port),
              var url = URLComponents(string: address.contains("://") ? address : "http://\(address)"),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, !host.contains(" "),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        if !address.contains("://") && url.port == nil { url.port = port }
        guard let raw = url.url?.absoluteString, let base = EndpointAddress.url(raw)?.absoluteString else { return nil }
        var updated = device
        updated.name = name
        updated.host = base.hasSuffix("/") ? String(base.dropLast()) : base
        updated.port = url.port ?? (url.scheme == "https" ? 443 : 80)
        if updated.baseURL != device.baseURL {
            updated.endpoints = [updated.host] + EndpointAddress.candidates(device).filter { !EndpointAddress.matches($0, updated.host) }
            updated.online = false
        }
        return updated
    }
}

struct DeviceConfigurationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    let device: Device
    @State private var configuration: DeviceConfiguration
    @State private var failure: String?
    private var current: Device { store.device(device.id) ?? device }
    private var busy: Bool { store.switchingDevices.contains(device.id) }
    init(device: Device) {
        self.device = device
        _configuration = State(initialValue: DeviceConfiguration(device))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("设备名称") { TextField("名称", text: $configuration.name) }
                Section {
                    LabeledContent("认证方式", value: "设备 Token · Bearer")
                    LabeledContent("凭据", value: store.isDemo ? "演示模式" : store.client.authenticationConfigured(device: current) ? "已保存于钥匙串" : "未找到，请重新配对")
                } header: { Text("连接认证") } footer: {
                    Text("扫码时已自动配置 Token。切换同一台电脑的地址会沿用凭据，无需重新填写；认证失败时重新扫码配对。")
                }
                Section("选择连接") {
                    ForEach(EndpointAddress.candidates(current), id: \.self) { address in
                        Button {
                            configuration.address = address
                            failure = nil
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(EndpointAddress.label(address)).foregroundStyle(p.label)
                                    Text(address).font(.caption).foregroundStyle(p.labelSecondary)
                                    if let reason = EndpointAddress.unavailableReason(address) { Text(reason).font(.caption).foregroundStyle(p.labelSecondary) }
                                }
                                Spacer()
                                if EndpointAddress.matches(configuration.applying(to: current)?.baseURL?.absoluteString, address) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.brand)
                                }
                            }
                        }.disabled(busy || EndpointAddress.unavailableReason(address) != nil)
                    }
                }
                Section {
                    TextField("IP、域名或完整 URL", text: $configuration.address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    if !configuration.address.contains("://") {
                        LabeledContent("端口") {
                            TextField("19876", text: $configuration.port)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                } header: { Text("连接地址") } footer: {
                    Text("也可手填新地址。保存前会核对电脑身份与 Token；成功后优先使用所选地址，不可达时自动尝试备用地址。")
                }
                if let failure { Section { Text(failure).foregroundStyle(p.danger) } }
                if configuration.applying(to: current) == nil {
                    Section { Text("请填写名称和有效的 HTTP / HTTPS 地址，端口范围为 1–65535。").foregroundStyle(p.danger) }
                }
            }
            .paperBackground().navigationTitle("设备配置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let updated = configuration.applying(to: current), let address = updated.baseURL?.absoluteString else { return }
                        Task {
                            failure = nil
                            do { try await store.switchEndpoint(device.id, address: address, name: updated.name); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }.disabled(configuration.applying(to: current) == nil || busy)
                }
            }
            .overlay { if busy { ProgressView("正在验证连接…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
            .interactiveDismissDisabled(busy)
        }
    }
}
