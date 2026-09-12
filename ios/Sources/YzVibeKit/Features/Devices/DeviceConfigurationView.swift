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
        guard let base = url.url?.absoluteString else { return nil }
        var updated = device
        updated.name = name
        updated.host = base.hasSuffix("/") ? String(base.dropLast()) : base
        updated.port = url.port ?? (url.scheme == "https" ? 443 : 80)
        if updated.baseURL != device.baseURL {
            updated.endpoints = [updated.host]
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
    init(device: Device) {
        self.device = device
        _configuration = State(initialValue: DeviceConfiguration(device))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("设备名称") { TextField("名称", text: $configuration.name) }
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
                    Text("完整 URL 使用地址中的端口。保存后自动重连，原配对凭据与会话记录会保留。")
                }
                if configuration.applying(to: device) == nil {
                    Section { Text("请填写名称和有效的 HTTP / HTTPS 地址，端口范围为 1–65535。").foregroundStyle(p.danger) }
                }
            }
            .paperBackground().navigationTitle("设备配置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let updated = configuration.applying(to: device) else { return }
                        store.updateDevice(updated)
                        dismiss()
                        Task { await store.refresh(updated) }
                    }.disabled(configuration.applying(to: device) == nil)
                }
            }
        }
    }
}
