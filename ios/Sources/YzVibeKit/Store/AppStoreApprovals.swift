import Foundation

public struct TrustedApprovalResult: Codable, Sendable {
    public var session: Session
    public var approvals: [Approval]
}

@MainActor extension AppStore {
    func trustSession(from approvalId: String) async {
        guard let approval = approvals.first(where: { $0.id == approvalId && $0.status == .pending }),
              approval.questions.isEmpty,
              let device = device(approval.deviceId) ?? device(session(approval.sessionId)?.deviceId ?? "") else { return }
        do {
            let result = try await client.trustApproval(device: device, approvalId: approvalId)
            guard result.session.id == approval.sessionId, result.session.mode == .trust else {
                throw ConnectorError.network("连接器未确认 Trust 模式，请刷新后重试。")
            }
            for resolved in result.approvals where resolved.sessionId == approval.sessionId {
                if let i = approvals.firstIndex(where: { $0.id == resolved.id }) { approvals[i] = resolved }
            }
            if let i = sessions.firstIndex(where: { $0.id == approval.sessionId }) {
                sessions[i].mode = .trust
                sessions[i].pendingApprovals = approvals.filter { $0.sessionId == approval.sessionId && $0.status == .pending }.count
                if sessions[i].status == .waitingApproval && sessions[i].pendingApprovals == 0 { sessions[i].status = .running }
            }
            toast = "已信任此会话，当前操作继续执行"
        } catch { toast = error.localizedDescription }
    }
}
