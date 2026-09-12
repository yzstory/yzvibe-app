import SwiftUI

struct ConnectionRecoveryBanner: View {
    @Environment(AppStore.self) private var store
    let deviceId: String
    @State private var configuring = false
    var body: some View {
        if let device = store.device(deviceId), !device.online {
            let state = store.recoveryStates[deviceId] ?? .reconnecting
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if state == .reconnecting { ProgressView().controlSize(.small) }
                    else { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Text(state.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("重试") { Task { await store.refresh(device); await store.probeConnection(device, force: true) } }
                }
                Text(state.detail).font(.caption).foregroundStyle(.secondary)
                if state == .addressUnavailable {
                    HStack {
                        Button("在局域网里找") { Task { await store.reconnectViaLAN(device, quiet: false) } }
                        Button("更新地址") { configuring = true }
                    }.font(.caption.weight(.semibold)).frame(minHeight: 32)
                }
            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .task(id: device.baseURL) { await store.probeConnection(device) }
                .sheet(isPresented: $configuring) { DeviceConfigurationView(device: device) }
        }
    }
}
