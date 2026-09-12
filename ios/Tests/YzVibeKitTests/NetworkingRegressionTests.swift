import Foundation
import Testing
@testable import YzVibeKit

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var handler: (@Sendable (URLRequest) -> Void)?
    func record(_ request: URLRequest) {
        lock.lock(); requests.append(request); let action = handler; lock.unlock()
        action?(request)
    }
    func onRequest(_ action: @escaping @Sendable (URLRequest) -> Void) { lock.lock(); defer { lock.unlock() }; handler = action }
    func reset() { lock.lock(); defer { lock.unlock() }; requests = []; handler = nil }
    func all() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    func count(host: String) -> Int { all().filter { $0.url?.host == host }.count }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Requests()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.record(request)
        if url.host == "primary.fail" || (url.host == "retry.fail" && url.path != "/health") {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return
        }
        let status = url.host == "server.error" ? 503 : url.host == "unauthorized.test" && url.path != "/health" ? 401 : 200
        let id = url.host == "wrong.identity" ? "different-connector" : "test-connector"
        let body = url.path == "/health" ? "{\"name\":\"Fixture\",\"version\":\"1\",\"agents\":[],\"connectorId\":\"\(id)\"}" : "[]"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct NetworkingRegressionTests {
    @Test func datesAcceptMillisecondsAndWholeSeconds() throws {
        struct Value: Decodable { let date: Date }
        let whole = try JSONDecoder.yz.decode(Value.self, from: Data(#"{"date":"2026-09-10T10:00:00Z"}"#.utf8))
        let fractional = try JSONDecoder.yz.decode(Value.self, from: Data(#"{"date":"2026-09-10T10:00:00.123Z"}"#.utf8))
        #expect(abs(fractional.date.timeIntervalSince(whole.date) - 0.123) < 0.001)
        #expect(throws: DecodingError.self) {
            try JSONDecoder.yz.decode(Value.self, from: Data(#"{"date":"not-a-date"}"#.utf8))
        }
    }

    private func fixture(host: String = "primary.fail", backups: [String] = ["https://backup.good"]) -> (HTTPConnectorClient, Device, URLSession) {
        FixtureProtocol.requests.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        let client = HTTPConnectorClient(session: session, tokenProvider: { _ in "fixture-token" })
        var device = Device(id: "test-connector", name: "test", host: "https://\(host)", port: 443, mode: .relay, online: true)
        device.endpoints = backups
        return (client, device, session)
    }

    @Test func healthActuallySendsARequest() async throws {
        let (client, device, session) = fixture(host: "primary.good")
        defer { session.invalidateAndCancel() }
        let health = try await client.health(device: device)
        #expect(health.name == "Fixture")
        #expect(FixtureProtocol.requests.count(host: "primary.good") == 1)
    }

    @Test func readFailoverChecksIdentityAndRetriesOnce() async throws {
        let (client, device, session) = fixture(backups: ["https://wrong.identity", "https://backup.good"])
        defer { session.invalidateAndCancel() }
        let sessions = try await client.sessions(device: device)
        #expect(sessions.isEmpty)
        #expect(FixtureProtocol.requests.count(host: "primary.fail") == 1)
        #expect(FixtureProtocol.requests.count(host: "wrong.identity") == 1)
        #expect(FixtureProtocol.requests.count(host: "backup.good") == 2)
    }

    @Test func discoveredEndpointReplacesCachedHTTPBase() async throws {
        let (client, original, session) = fixture()
        defer { session.invalidateAndCancel() }
        _ = try await client.sessions(device: original) // caches backup.good
        var updated = original
        updated.adopt(base: "https://discovered.good")
        client.reconnect(device: updated)
        _ = try await client.sessions(device: updated)
        #expect(FixtureProtocol.requests.count(host: "discovered.good") >= 1)
        #expect(FixtureProtocol.requests.count(host: "backup.good") == 2)
    }

    @Test func failedRetryDoesNotRecurse() async {
        let (client, device, session) = fixture(backups: ["https://retry.fail"])
        defer { session.invalidateAndCancel() }
        do { _ = try await client.sessions(device: device); Issue.record("Expected unreachable") }
        catch { #expect(error is ConnectorError) }
        #expect(FixtureProtocol.requests.count(host: "retry.fail") == 2)
    }

    @Test func writeWithLostResponseIsNotReplayed() async {
        let (client, device, session) = fixture()
        defer { session.invalidateAndCancel() }
        do { _ = try await client.sendMessage(device: device, sessionId: "s", text: "run", attachments: [], mode: .auto); Issue.record("Expected unreachable") }
        catch { #expect(error is ConnectorError) }
        #expect(FixtureProtocol.requests.count(host: "primary.fail") == 1)
        #expect(FixtureProtocol.requests.count(host: "backup.good") == 0)
    }

    @Test func serverErrorDoesNotTriggerFailover() async {
        let (client, device, session) = fixture(host: "server.error")
        defer { session.invalidateAndCancel() }
        do { _ = try await client.sessions(device: device); Issue.record("Expected HTTP error") }
        catch { #expect(error is ConnectorError) }
        #expect(FixtureProtocol.requests.count(host: "backup.good") == 0)
    }

    @Test func resyncReplacesAnExistingMessage() async {
        let client = ResyncStubClient()
        client.newMessages = [Message(id: "m2", sessionId: "s1", role: .assistant, text: "partial", toolCalls: [ToolCall(id: "tool", name: "Bash", detail: "test", state: .running)], streaming: true)]
        let store = AppStore(client: client, seedMock: false)
        var device = MockData.macStudio; device.online = true
        store.devices = [device]; store.selectedDeviceId = device.id
        store.sessions = [Session(id: "s1", deviceId: device.id, agent: .claude, cwd: "/p", title: "t")]
        await store.loadMessages("s1")
        client.newMessages = [Message(id: "m2", sessionId: "s1", role: .assistant, text: "finished", toolCalls: [ToolCall(id: "tool", name: "Bash", detail: "test", state: .done, output: "passed")], streaming: false)]
        await store.resync()
        #expect(store.messages["s1"]?.filter { $0.id == "m2" }.count == 1)
        #expect(store.messages["s1"]?.first { $0.id == "m2" }?.text == "finished")
        #expect(store.messages["s1"]?.first { $0.id == "m2" }?.streaming == false)
        #expect(store.messages["s1"]?.first { $0.id == "m2" }?.toolCalls.first?.output == "passed")
        #expect(store.messages["s1"]?.first { $0.id == "m2" }?.toolCalls.first?.state == .done)
    }

    @Test func switchingValidatesExactAddressAndSendsTokenOnlyAfterIdentityMatches() async throws {
        let (client, device, session) = fixture(host: "primary.good")
        defer { session.invalidateAndCancel() }
        #expect(client.authenticationConfigured(device: device))
        _ = try await client.validateEndpoint(device: device, address: "https://selected.good")
        let requests = FixtureProtocol.requests.all()
        #expect(requests.map { $0.url?.host } == ["selected.good", "selected.good"])
        #expect(requests.map { $0.url?.path } == ["/health", "/rules"])
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        #expect(requests.allSatisfy { $0.url?.query == nil })
        _ = try await client.sessions(device: device)
        #expect(FixtureProtocol.requests.count(host: "primary.good") == 1, "Validation alone must not commit a new base")
    }

    @Test func wrongIdentityReceivesNoTokenAndFailedValidationDoesNotFallBack() async {
        for host in ["wrong.identity", "primary.fail", "unauthorized.test"] {
            let (client, device, session) = fixture(host: "primary.good")
            defer { session.invalidateAndCancel() }
            do { _ = try await client.validateEndpoint(device: device, address: "https://\(host)"); Issue.record("Expected validation failure") }
            catch { }
            let requests = FixtureProtocol.requests.all()
            #expect(requests.allSatisfy { $0.url?.host == host })
            if host == "wrong.identity" { #expect(requests.count == 1 && requests[0].value(forHTTPHeaderField: "Authorization") == nil) }
            _ = try? await client.sessions(device: device)
            #expect(FixtureProtocol.requests.count(host: "primary.good") == 1)
            #expect(FixtureProtocol.requests.count(host: "backup.good") == 0)
        }
    }

    @Test func missingTokenCannotPassAnOtherwiseReachableEndpoint() async {
        let (_, device, session) = fixture(host: "primary.good")
        defer { session.invalidateAndCancel() }
        let client = HTTPConnectorClient(session: session, tokenProvider: { _ in nil })
        #expect(!client.authenticationConfigured(device: device))
        do { _ = try await client.validateEndpoint(device: device, address: "https://selected.good"); Issue.record("Expected missing credential") }
        catch ConnectorError.unauthorized { }
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(FixtureProtocol.requests.all().count == 1)
    }

    @Test func staleFailoverCannotUndoAManualSelection() async throws {
        let (client, device, session) = fixture()
        defer { session.invalidateAndCancel() }
        var selected = device; selected.adopt(base: "https://selected.good")
        let chosen = selected
        FixtureProtocol.requests.onRequest { request in
            if request.url?.host == "backup.good", request.url?.path == "/health" { client.reconnect(device: chosen) }
        }
        _ = try await client.sessions(device: device)
        #expect(client.isCurrentEndpoint("https://selected.good", deviceId: device.id))
        #expect(FixtureProtocol.requests.all().filter { $0.url?.host == "backup.good" }.map { $0.url?.path } == ["/health"])
        #expect(FixtureProtocol.requests.all().contains { $0.url?.host == "selected.good" && $0.url?.path == "/sessions" })
    }

    @Test func webSocketUsesTheSelectedHostAndKeepsTokenOutOfURL() throws {
        for base in ["http://192.168.1.8:19876", "https://remote.test"] {
            let request = try #require(ConnectorSocket.connectionRequest(base: URL(string: base)!, token: "fixture-secret"))
            #expect(request.url?.host == URL(string: base)?.host)
            #expect(request.url?.path == "/ws")
            #expect(request.url?.scheme == (base.hasPrefix("https") ? "wss" : "ws"))
            #expect(request.url?.query == nil)
            #expect(!request.url!.absoluteString.contains("fixture-secret"))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
        }
    }
}
