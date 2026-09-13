import Foundation
import Testing
@testable import YzVibeKit

@MainActor struct ApprovalActionTests {
    private func fixture() -> (AppStore, ResyncStubClient, Approval) {
        let client = ResyncStubClient(), device = MockData.macStudio
        let store = AppStore(client: client, seedMock: false)
        store.devices = [device]
        store.sessions = [Session(id: "s", deviceId: device.id, agent: .codex, cwd: "/fixture", title: "task", mode: .normal),
                          Session(id: "other", deviceId: device.id, agent: .codex, cwd: "/fixture", title: "other", mode: .normal)]
        let approval = Approval(id: "a", sessionId: "s", deviceId: device.id, kind: .shell, summary: "pwd", detail: "pwd", risk: .low)
        store.approvals = [approval]
        return (store, client, approval)
    }

    @Test func trustUpdatesOnlyConfirmedSessionAndApprovals() async throws {
        let (store, client, approval) = fixture()
        var session = try #require(store.session("s")); session.mode = .trust
        var allowed = approval; allowed.status = .allowed
        client.trustResult = TrustedApprovalResult(session: session, approvals: [allowed])
        await store.trustSession(from: approval.id)
        #expect(client.trustRequests == [approval.id])
        #expect(store.session("s")?.mode == .trust)
        #expect(store.session("other")?.mode == .normal)
        #expect(store.approvals.first?.status == .allowed)
        #expect(store.settings.defaults(for: .codex).mode == .normal, "Trust is scoped to this session, not future sessions")
    }

    @Test func failedTrustDoesNotOptimisticallyAllowOrSwitchMode() async {
        let (store, client, approval) = fixture()
        await store.trustSession(from: approval.id)
        #expect(client.trustRequests.count == 1)
        #expect(store.session("s")?.mode == .normal)
        #expect(store.approvals.first?.status == .pending)
        #expect(store.toast != nil)
    }

    @Test func staleCardsAndQuestionsCannotTriggerTrust() async throws {
        let (store, client, approval) = fixture()
        store.approvals[0].status = .allowed
        await store.trustSession(from: approval.id)
        store.approvals[0].status = .pending
        store.approvals[0].questions = try JSONDecoder().decode([ApprovalQuestion].self, from: Data(#"[{"id":"q","header":"Choice","question":"Which?"}]"#.utf8))
        await store.trustSession(from: approval.id)
        #expect(client.trustRequests.isEmpty)
        #expect(store.session("s")?.mode == .normal)
    }
}
