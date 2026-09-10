import Foundation
import Testing
@testable import YzVibeKit

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func record(_ url: URL) { lock.lock(); defer { lock.unlock() }; urls.append(url) }
    func reset() { lock.lock(); defer { lock.unlock() }; urls = [] }
    func count(host: String) -> Int { lock.lock(); defer { lock.unlock() }; return urls.filter { $0.host == host }.count }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Requests()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.record(url)
        if url.host == "primary.fail" || (url.host == "retry.fail" && url.path != "/health") {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return
        }
        let status = url.host == "server.error" ? 503 : 200
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
}
