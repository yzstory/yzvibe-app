import Foundation
import Network

/// 局域网里发现的一台连接器。
public struct DiscoveredConnector: Sendable, Hashable, Identifiable {
    /// Bonjour TXT 里的 `id=`，和 `/health` 的 connectorId 是同一个值；靠它认出「还是那台电脑」。
    public var connectorId: String?
    public var name: String
    /// `http://host:port`，可以直接当 base 用。
    public var base: String
    public var id: String { base }

    public init(connectorId: String?, name: String, base: String) {
        self.connectorId = connectorId; self.name = name; self.base = base
    }
}

/// 同一 Wi-Fi 下直接发现连接器（连接器用 dns-sd 广播 `_yzvibe._tcp`，TXT 带 `id` / `name`）。
///
/// 为什么需要：临时隧道地址每次重开都变，电脑重启一次手机就连不上；没配 APNs 的话
/// 连「悄悄推一条新地址」都做不到。只要手机和电脑还在一个网络里，这里就能把新地址找回来，
/// 不用重新扫码。
public final class LANDiscovery: @unchecked Sendable {
    public static let shared = LANDiscovery()
    public static let serviceType = "_yzvibe._tcp"

    private let queue = DispatchQueue(label: "icu.yzvibe.discovery")

    public init() {}

    /// 浏览 `timeout` 秒，返回这段时间里发现并解析出地址的连接器。
    /// 第一次调用会触发系统的「本地网络」权限弹窗；用户拒绝就只会返回空数组。
    public func discover(timeout: TimeInterval = 3) async -> [DiscoveredConnector] {
        let box = Box()
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        // 只要 IPv4：解析出来的 IPv6 链路本地地址带 %en0 作用域，拼不成能用的 URL
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results { self?.resolve(r, params: params, into: box) }
        }
        browser.start(queue: queue)
        try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
        browser.cancel()
        box.cancelPending()
        return box.all()
    }

    /// 解析一条浏览结果：连一下拿到真实 host:port（Bonjour 只给服务名）。
    private func resolve(_ result: NWBrowser.Result, params: NWParameters, into box: Box) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }
        var connectorId: String?
        if case let .bonjour(txt) = result.metadata { connectorId = txt["id"] }
        guard box.beginResolving(name) else { return }

        let conn = NWConnection(to: result.endpoint, using: params)
        box.track(conn)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint,
                   let base = Self.base(host: host, port: port) {
                    box.add(DiscoveredConnector(connectorId: connectorId, name: name, base: base))
                }
                conn.cancel()
            case .failed, .waiting:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// `NWEndpoint.Host` → base URL。IPv6 要加方括号，带 `%en0` 作用域的地址直接放弃。
    static func base(host: NWEndpoint.Host, port: NWEndpoint.Port) -> String? {
        switch host {
        case .name(let n, _):
            return "http://\(n):\(port.rawValue)"
        case .ipv4(let a):
            let s = "\(a)".split(separator: "%").first.map(String.init) ?? ""
            return s.isEmpty ? nil : "http://\(s):\(port.rawValue)"
        case .ipv6(let a):
            let raw = "\(a)"
            guard !raw.contains("%") else { return nil }
            return "http://[\(raw)]:\(port.rawValue)"
        @unknown default:
            return nil
        }
    }

    /// 浏览期间的共享状态：已解析的结果、正在解析的服务名、待取消的连接。
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var found: [String: DiscoveredConnector] = [:]
        private var resolving: Set<String> = []
        private var connections: [NWConnection] = []

        func beginResolving(_ name: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return resolving.insert(name).inserted
        }
        func add(_ c: DiscoveredConnector) {
            lock.lock(); defer { lock.unlock() }
            found[c.base] = c
        }
        func track(_ conn: NWConnection) {
            lock.lock(); defer { lock.unlock() }
            connections.append(conn)
        }
        func cancelPending() {
            lock.lock(); let list = connections; connections = []; lock.unlock()
            for c in list { c.cancel() }
        }
        func all() -> [DiscoveredConnector] {
            lock.lock(); defer { lock.unlock() }
            return Array(found.values).sorted { $0.name < $1.name }
        }
    }
}
