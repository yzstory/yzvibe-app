import Foundation
import Testing
@testable import YzVibeKit

@Suite @MainActor
struct ActivityOverviewTests {
    @Test func overviewShowsThreeAndPrioritizesApprovals() {
        var sessions = (0..<5).map { Session(id: "s\($0)", deviceId: "d", agent: .codex, cwd: "/p", title: "任务\($0)", status: .running) }
        sessions[4].status = .waitingApproval
        sessions.append(Session(deviceId: "d", agent: .claude, cwd: "/p", title: "暂停的队列", queue: [QueuedMessage(id: "q", text: "later")]))
        let state = SessionActivityAttributes.ContentState.overview(sessions)
        #expect(state.totalTasks == 5)
        #expect(state.tasks?.count == 3)
        #expect(state.tasks?.first?.id == "s4")
        #expect(state.needsApproval)
        #expect(state.startedAt != nil)
        #expect(SessionActivityAttributes.ContentState.overview([]).totalTasks == 0)
    }

    @Test func loadingClearsAfterFailureAndRetry() async {
        let client = QueueStubClient()
        let subject = AppStore(client: client, seedMock: false)
        subject.devices = [MockData.macStudio]; subject.sessions = [MockData.sessions[0]]
        let id = subject.sessions[0].id
        client.messagesHandler = {
            await MainActor.run { #expect(subject.loadingMessages.contains(id)) }
            throw ConnectorError.unreachable
        }
        await subject.loadMessages(id)
        #expect(subject.loadingMessages.isEmpty)
        #expect(subject.messageLoadErrors[id] != nil)
        client.messagesHandler = { [] }
        await subject.loadMessages(id)
        #expect(subject.loadingMessages.isEmpty)
        #expect(subject.messageLoadErrors[id] == nil)
        #expect(subject.messages[id]?.isEmpty == true)
        client.messagesHandler = nil
    }
}
