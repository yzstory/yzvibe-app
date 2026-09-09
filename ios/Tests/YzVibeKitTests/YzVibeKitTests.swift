import XCTest
@testable import YzVibeKit

final class YzVibeKitTests: XCTestCase {
    func testOKLCHBrandConvertsToWarmRed() {
        let s = OKLCH(0.64, 0.17, 40).srgb
        XCTAssertGreaterThan(s.r, s.g)
        XCTAssertGreaterThan(s.g, s.b)
        XCTAssertEqual(s.r, 0.76, accuracy: 0.06)
    }

    func testOKLCHWhiteAndBlack() {
        let w = OKLCH(1, 0, 0).srgb
        XCTAssertEqual(w.r, 1, accuracy: 0.01)
        let k = OKLCH(0, 0, 0).srgb
        XCTAssertEqual(k.r, 0, accuracy: 0.01)
    }

    func testPairingPayloadParsesQR() throws {
        let p = try XCTUnwrap(PairingPayload(qrString: "yzvibe://pair?host=100.82.203.14&port=9876&token=abc123&mode=tailscale&name=Studio"))
        XCTAssertEqual(p.host, "100.82.203.14")
        XCTAssertEqual(p.port, 9876)
        XCTAssertEqual(p.token, "abc123")
        XCTAssertEqual(p.mode, .tailscale)
        XCTAssertEqual(p.name, "Studio")
    }

    func testPairingPayloadRejectsForeignQR() {
        XCTAssertNil(PairingPayload(qrString: "https://example.com"))
        XCTAssertNil(PairingPayload(qrString: "yzvibe://pair?host=&token=x"))
    }

    func testEventParsing() throws {
        let json = #"{"type":"approval.requested","sessionId":"s1","approvalId":"a9","kind":"shell","summary":"rm -rf dist","detail":"...","risk":"high"}"#
        let ev = try XCTUnwrap(ConnectorSocket.parse(Data(json.utf8)))
        guard case .approvalRequested(let a) = ev else { return XCTFail("wrong event") }
        XCTAssertEqual(a.id, "a9"); XCTAssertEqual(a.risk, .high); XCTAssertEqual(a.kind, .shell)
    }

    @MainActor
    func testStoreGroupsSessionsByFolder() {
        let store = AppStore()
        let groups = store.groupedSessions(store.sessions(for: MockData.macStudio, activeOnly: false, query: ""))
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.sessions.count, 1) // 最近更新的 YzVibe 目录在前
    }

    @MainActor
    func testApprovalRespondUpdatesSession() async {
        let store = AppStore()
        await store.respond("a1", .allow)
        XCTAssertEqual(store.approval("a1")?.status, .allowed)
        XCTAssertEqual(store.session("s1")?.pendingApprovals, 0)
        XCTAssertEqual(store.session("s1")?.status, .running)
    }
}
