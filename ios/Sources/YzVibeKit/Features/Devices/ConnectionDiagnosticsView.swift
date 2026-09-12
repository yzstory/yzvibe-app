import SwiftUI

struct ConnectionDiagnosticsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device
    @State private var checks: [EndpointCheck] = []
    @State private var report: ConnectorDiagnostics?
    @State private var busy = false
    @State private var checkedAt: Date?
    @State private var failure: String?
    @State private var addresses: [String] = []
    @State private var switchingAddress: String?
    @State private var switchFailure: String?
    @State private var authentication = "尚未验证"
    private var current: Device { store.device(device.id) ?? device }
    private var switching: Bool { store.switchingDevices.contains(device.id) }
    private var exportText: String {
        struct Export: Encodable {
            var checkedAt: Date?
            var endpoints: [EndpointCheck]
            var connector: ConnectorDiagnostics?
            var connectorRequest: String
        }
        let value = Export(checkedAt: checkedAt, endpoints: checks, connector: report, connectorRequest: failure == nil ? "ok" : "failed")
        let encoder = JSONEncoder.yz; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "诊断记录无法导出"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("电脑", value: current.name)
                LabeledContent("连接状态", value: (store.device(device.id)?.online ?? false) ? "在线" : "离线")
                if let date = checkedAt { LabeledContent("检查时间") { Text(date, style: .time) } }
                if let error = store.connectionErrors[device.id] { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                if checks.isEmpty { Text(busy ? "正在检查地址…" : "尚未检查").foregroundStyle(.secondary) }
                ForEach(checks) { check in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(addresses.indices.contains(check.id) ? EndpointAddress.label(addresses[check.id]) : "连接地址")
                            Spacer()
                            Text(label(check.status)).font(.footnote)
                        }
                        if addresses.indices.contains(check.id) {
                            let address = addresses[check.id]
                            Text(address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let reason = EndpointAddress.unavailableReason(address) {
                                Text(reason).font(.footnote).foregroundStyle(.secondary)
                            } else if EndpointAddress.matches(current.baseURL?.absoluteString, address) {
                                Label("当前使用", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.tint)
                            } else {
                                Button {
                                    Task { await switchConnection(address) }
                                } label: {
                                    if switchingAddress == address { ProgressView("正在验证并切换…") }
                                    else { Label("使用此连接", systemImage: "arrow.left.arrow.right") }
                                }.disabled(busy || switching).buttonStyle(.borderless)
                            }
                        }
                        Text("\(check.latencyMs) ms" + (check.version.map { " · 连接器 \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !checks.isEmpty && !checks.contains(where: { $0.status == "reachable" }) {
                    Text("请确认电脑与连接器正在运行。同一 Wi-Fi 下可返回设备页使用「在局域网里找」。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let switchFailure { Text(switchFailure).font(.footnote).foregroundStyle(.red) }
            } header: {
                Text("地址与身份")
            } footer: {
                Text("切换前验证电脑身份和设备 Token，成功后保留配对与会话。优先使用所选地址，断线时自动尝试备用地址。")
            }
            Section("连接认证") {
                LabeledContent("认证方式", value: "设备 Token · Bearer")
                LabeledContent("手机凭据", value: store.client.authenticationConfigured(device: current) ? "已保存于钥匙串" : "未配置")
                LabeledContent("认证检查", value: authentication)
                Text("配对时自动生成每台手机独立的 Token，用于 HTTP 和 WebSocket 连接。凭据失效时请重新配对。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let report {
                Section("连接器与 Agent") {
                    LabeledContent("连接器版本", value: report.version)
                    ForEach(report.agents) { agent in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(agent.id, value: agent.available ? "可运行 \(agent.version ?? "")" : "不可用")
                            Text(agent.advice).font(.footnote).foregroundStyle(.secondary)
                            Text(agent.authentication == "logged_in" ? "本机已登录" : agent.authentication == "logged_out" ? "本机未登录" : "登录状态未知")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("通知与待办") {
                    LabeledContent("电脑推送配置", value: report.push.configured ? "已配置" : "未配置")
                    LabeledContent("此手机推送注册", value: report.push.registered ? "已注册" : "未注册")
                    LabeledContent("待发送消息", value: String(report.storage.pendingMessages))
                    LabeledContent("接收结果待确认", value: String(report.storage.uncertainMessages))
                    Text("已配置不代表实际送达；可在电脑运行 yzvibe push --test 验证通知。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if let failure {
                Section("连接器诊断") {
                    Text(failure)
                    Text("若提示接口不存在，请更新电脑连接器。身份不符时请核对设备地址；凭据无效时重新配对。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button { Task { await inspect() } } label: {
                    if busy { ProgressView() } else { Label("重新检查", systemImage: "arrow.clockwise") }
                }.disabled(busy || switching)
                ShareLink(item: exportText) { Label("导出诊断", systemImage: "square.and.arrow.up") }.disabled(checkedAt == nil || busy || switching)
            } footer: {
                Text("导出内容仅含检查状态、版本和数量，排除地址、设备名称、配对凭据、账户与会话正文。")
            }
        }
        .paperBackground().navigationTitle("连接诊断").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .interactiveDismissDisabled(switching)
        .task { await inspect() }
    }

    private func switchConnection(_ address: String) async {
        switchingAddress = address; switchFailure = nil
        defer { switchingAddress = nil }
        do {
            try await store.switchEndpoint(device.id, address: address)
            await inspect()
        } catch {
            switchFailure = "切换未完成，原连接已保留。\(error.localizedDescription)"
        }
    }

    private func inspect() async {
        guard !busy else { return }
        busy = true; failure = nil; report = nil; checks = []
        authentication = store.client.authenticationConfigured(device: current) ? "尚未验证" : "未配置"
        let device = current
        addresses = Array(EndpointAddress.candidates(device).prefix(6))
        defer { busy = false; checkedAt = .now }
        for (index, address) in addresses.enumerated() {
            guard !Task.isCancelled else { return }
            checks.append(await store.client.checkEndpoint(device: device, address: address, index: index))
        }
        do {
            report = try await store.client.diagnostics(device: device)
            authentication = "验证通过"
        } catch ConnectorError.unauthorized {
            authentication = "凭据无效 · 请重新配对"
            failure = ConnectorError.unauthorized.localizedDescription
        } catch { failure = error.localizedDescription }
    }
    private func label(_ status: String) -> String {
        switch status {
        case "reachable": "可达 · 身份一致"
        case "identity_mismatch": "身份不符"
        case "invalid_address": "地址格式错误"
        case "http_error": "服务响应异常"
        case "loopback": "手机无法使用"
        default: "暂时不可达"
        }
    }
}
