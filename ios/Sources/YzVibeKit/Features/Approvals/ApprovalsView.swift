import SwiftUI
import LocalAuthentication

struct ApprovalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            PageScaffold(eyebrow: "全部设备", title: "审批") {
                Image(systemName: "faceid").font(.system(size: 20)).foregroundStyle(p.label)
                    .frame(width: 44, height: 44).liquidGlass(in: Circle())
            } content: {
                SegmentedPills(items: [(0, "待处理 \(store.pendingApprovals.count)"), (1, "历史")], selection: $segment)
                let list = segment == 0 ? store.pendingApprovals : store.resolvedApprovals
                if list.isEmpty {
                    PaperCard {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.shield").font(.system(size: 36, weight: .light)).foregroundStyle(p.sage)
                            Text(segment == 0 ? "没有待处理的审批" : "还没有历史记录").font(.yzHeadline).foregroundStyle(p.label)
                            Text("Agent 需要执行敏感操作时会出现在这里。").font(.yzSubhead).foregroundStyle(p.labelSecondary)
                        }.frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(list) { a in ApprovalCardView(approval: a, showsContext: true) }
                }
                HStack(spacing: 12) {
                    Image(systemName: "lock").foregroundStyle(p.sage)
                    Text("高风险审批默认需要 Face ID 确认，可在「我 › 安全」中调整。").font(.yzFootnote).foregroundStyle(p.labelSecondary)
                }
                .padding(16)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

/// 审批卡：聊天流内嵌与收件箱共用。玻璃底 + 左侧风险色条 + 三个决定。
struct ApprovalCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    let approval: Approval
    var showsContext: Bool
    @State private var busy = false

    private var riskColor: Color { approval.risk == .high ? p.danger : approval.risk == .medium ? p.amber : p.sage }
    private var riskTone: ChipTone { approval.risk == .high ? .danger : approval.risk == .medium ? .claude : .sage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: approval.kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(riskColor)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(riskColor.opacity(0.14)))
                Text(approval.status == .pending ? "需要你的批准" : approval.kind.displayName).font(.yzHeadline).foregroundStyle(p.label)
                Spacer(minLength: 4)
                if approval.status == .pending { Chip(approval.risk.displayName, tone: riskTone) } else { statusChip }
            }
            if showsContext {
                Text("\(store.device(approval.deviceId)?.name ?? "设备") · \(store.session(approval.sessionId)?.title ?? "")").font(.yzFootnote).foregroundStyle(p.labelSecondary)
            } else {
                Text("Agent 想在 \(store.session(approval.sessionId)?.folderName ?? "项目") 中\(approval.kind.displayName)：").font(.yzFootnote).foregroundStyle(p.labelSecondary)
            }
            CodeBlock(showsContext ? approval.summary : approval.detail, dark: !showsContext, lines: showsContext ? 1 : nil)
            if approval.status == .pending {
                HStack(spacing: 8) {
                    Button("拒绝") { decide(.deny) }.buttonStyle(OutlineButtonStyle(color: p.danger, height: 44))
                    Button { decide(.allow) } label: { Label("允许", systemImage: "checkmark") }.buttonStyle(PrimaryButtonStyle(height: 44))
                }
                .disabled(busy)
                // 「以后别再问我」：存成连接器上的规则，同类请求自动放行，可在「我 › 审批规则」里撤销
                if !approval.suggestions.isEmpty {
                    Menu {
                        ForEach(approval.suggestions) { sug in
                            Button { decide(.allow, remember: sug) } label: {
                                Label(sug.label + (sug.ttlMinutes.map { "（\($0) 分钟）" } ?? ""), systemImage: "checkmark.shield")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield").font(.system(size: 12, weight: .semibold))
                            Text("总是允许…").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(p.labelSecondary)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Capsule().strokeBorder(p.border, lineWidth: 1))
                    }
                    .disabled(busy)
                }
            }
        }
        .padding(16)
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(riskColor).frame(width: 4).padding(.vertical, 14) }
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusChip: some View {
        switch approval.status {
        case .allowed: Chip("已允许", tone: .sage)
        case .denied: Chip("已拒绝", tone: .danger)
        case .expired: Chip("已过期", tone: .fill)
        case .pending: Chip("待处理", tone: .claude)
        }
    }

    private func decide(_ d: ApprovalDecision, remember: ApprovalSuggestion? = nil) {
        busy = true
        Task {
            if d != .deny, approval.risk == .high, store.settings.faceIDForHighRisk {
                guard await BiometricGate.confirm(reason: "确认允许：\(approval.summary)") else { busy = false; return }
            }
            await store.respond(approval.id, d, remember: remember)
            busy = false
        }
    }
}

enum BiometricGate {
    static func confirm(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
