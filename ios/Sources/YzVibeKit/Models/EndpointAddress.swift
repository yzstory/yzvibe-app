import Foundation

enum EndpointAddress {
    static func url(_ address: String) -> URL? {
        guard var c = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host, !host.isEmpty, !host.contains(" "),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/",
              c.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        c.scheme = scheme; c.host = host.lowercased(); c.path = ""
        if c.port == (scheme == "https" ? 443 : 80) { c.port = nil }
        return c.url
    }

    static func matches(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second, let a = url(first), let b = url(second) else { return false }
        return a == b
    }

    static func candidates(_ device: Device) -> [String] {
        var seen: Set<String> = []
        return ([device.baseURL?.absoluteString].compactMap { $0 } + device.endpoints).compactMap {
            guard let value = url($0)?.absoluteString, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    static func isLoopback(_ address: String) -> Bool {
        guard let host = url(address)?.host?.lowercased() else { return false }
        return host == "localhost" || host.hasSuffix(".localhost") || host.hasPrefix("127.") || host == "::1" || host == "[::1]"
    }

    static func unavailableReason(_ address: String) -> String? {
        #if !targetEnvironment(simulator)
        if isLoopback(address) { return "回环地址指向手机自己，连接电脑请使用局域网或远程地址。" }
        #endif
        return nil
    }

    static func label(_ address: String) -> String {
        if isLoopback(address) { return "本机回环地址" }
        guard let host = url(address)?.host else { return "连接地址" }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if host.hasSuffix(".local") || (parts.count == 4 && (parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])))) { return "局域网地址" }
        return "远程地址"
    }
}
