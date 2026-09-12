import Foundation

enum ConnectionRecovery: Equatable {
    case reconnecting, addressUnavailable, authenticationRequired
    var title: String {
        switch self {
        case .reconnecting: "正在重连"
        case .addressUnavailable: "原地址不可用"
        case .authenticationRequired: "连接凭据需要更新"
        }
    }
    var detail: String {
        switch self {
        case .reconnecting: "网络暂时中断，正在自动尝试恢复。"
        case .addressUnavailable: "Cloudflare 返回隧道不可用。地址可能已失效，也可能是电脑端隧道离线；请找回设备或更新地址。"
        case .authenticationRequired: "电脑已响应，但当前配对凭据无效。请重新配对。"
        }
    }
    static func classify(_ error: Error) -> Self {
        if case ConnectorError.unauthorized = error { return .authenticationRequired }
        if case ConnectorError.server(_, "tunnel_unavailable", _) = error { return .addressUnavailable }
        return .reconnecting
    }
    static func isUnavailableTunnel(_ response: HTTPURLResponse, data: Data) -> Bool {
        guard let host = response.url?.host, host.hasSuffix(".trycloudflare.com"),
              [502, 503, 530].contains(response.statusCode) else { return false }
        let text = String(decoding: data.prefix(32_768), as: UTF8.self).lowercased()
        return text.contains("1033") || text.contains("tunnel not found")
    }
}
