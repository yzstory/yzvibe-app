import Foundation

@MainActor
extension AppStore {
    func switchEndpoint(_ deviceId: String, address: String, name: String? = nil) async throws {
        guard let original = device(deviceId), let url = EndpointAddress.url(address) else { throw ConnectorError.badURL }
        guard switchingDevices.insert(deviceId).inserted else { throw ConnectorError.network("正在切换连接，请稍候") }
        defer { switchingDevices.remove(deviceId) }
        let changed = !EndpointAddress.matches(original.baseURL?.absoluteString, url.absoluteString)
        var discovered: [String] = []
        if !isDemo && changed {
            discovered = try await client.validateEndpoint(device: original, address: url.absoluteString).endpoints
            try Task.checkCancellation()
        }
        guard var updated = device(deviceId) else { throw ConnectorError.network("此设备已移除") }
        if let name { updated.name = name }
        updated.adopt(base: url.absoluteString)
        updated.endpoints += discovered
        updated.endpoints = EndpointAddress.candidates(updated)
        updateDevice(updated)
        toast = changed ? "已切换连接地址" : "设备配置已保存"
        if !isDemo { await refresh(updated) }
    }
}
