import Foundation
import Testing
@testable import YzVibeKit

struct ConnectionRecoveryTests {
    @Test func temporaryFailuresDoNotClaimAnExpiredAddress() {
        #expect(ConnectionRecovery.classify(ConnectorError.unreachable) == .reconnecting)
        #expect(ConnectionRecovery.classify(ConnectorError.unauthorized) == .authenticationRequired)
        #expect(ConnectionRecovery.classify(ConnectorError.server(530, "tunnel_unavailable", "offline")) == .addressUnavailable)
    }
    @Test func tunnelClassificationRequiresCloudflareHostAndSpecificFailure() throws {
        func response(_ host: String, _ status: Int) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: URL(string: "https://\(host)/health")!, statusCode: status, httpVersion: nil, headerFields: nil))
        }
        #expect(ConnectionRecovery.isUnavailableTunnel(try response("old.trycloudflare.com", 530), data: Data("<h1>Error 1033</h1>".utf8)))
        #expect(!ConnectionRecovery.isUnavailableTunnel(try response("old.trycloudflare.com", 502), data: Data("Bad Gateway".utf8)))
        #expect(!ConnectionRecovery.isUnavailableTunnel(try response("example.com", 530), data: Data("Error 1033".utf8)))
        #expect(!ConnectionRecovery.isUnavailableTunnel(try response("old.trycloudflare.com", 200), data: Data("1033".utf8)))
    }
    @Test func importingCopiesDocumentBeforeSecurityScopeEnds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("需求.pdf")
        let data = Data("%PDF-1.7".utf8)
        try data.write(to: source)
        let file = try await PendingFile.read(source)
        try FileManager.default.removeItem(at: source)
        #expect(file.name == "需求.pdf")
        #expect(file.mime == "application/pdf")
        #expect(file.data == data)
        await #expect(throws: (any Error).self) { try await PendingFile.read(folder) }
    }
}
