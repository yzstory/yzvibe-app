import SwiftUI
import LocalAuthentication

struct ApprovalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var segment = 0

    private var list: [Approval] { segment == 0 ? store.pendingApprovals : store.resolvedApprovals }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("范围", selection: $segment) {
                        Text("待处理 \(store.pendingApprovals.count)").tag(0)
                        Text("历史").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 4, leading: Spacing.page, bottom: 8, trailing: Spacing.page))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(list) { a in
                    ApprovalCardView(approval: a, showsContext: true)
                        .listRowInsets(EdgeInsets(top: 5, leading: Spacing.page, bottom: 5, trailing: Spacing.page))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if !list.isEmpty {
                    Section {
                        Label("高风险审批默认需要 Face ID 确认，可在「我 › 安全」中调整。", systemImage: "lock")
                            .font(.yzFootnote)
                            .foregroundStyle(p.labelSecondary)
                            .listRowInsets(EdgeInsets(top: 10, leading: Spacing.page, bottom: 20, trailing: Spacing.page))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .paperBackground()
            .navigationTitle("审批")
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView {
                        Label(segment == 0 ? "没有待处理的审批" : "还没有历史记录", systemImage: "checkmark.shield")
                    } description: {
                        Text("Agent 需要执行敏感操作时会出现在这里。")
                    }
                }
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
    @State private var answers: [String: String] = [:]

    private var riskColor: Color { approval.risk == .high ? p.danger : approval.risk == .medium ? p.amber : p.sage }
    private var riskTone: ChipTone { approval.risk == .high ? .danger : approval.risk == .medium ? .warning : .sage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: approval.kind.symbol).font(.system(.footnote, weight: .semibold)).foregroundStyle(riskColor)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(riskColor.opacity(0.14)))
                Text(approval.status == .pending ? (approval.questions.isEmpty ? "需要你的批准" : "需要你的回答") : approval.kind.displayName).font(.yzHeadline).foregroundStyle(p.label)
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
                ForEach(approval.questions) { question in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(question.question).font(.yzBody)
                        ForEach(question.options ?? [], id: \.label) { option in
                            Button { answers[question.id] = option.label } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: answers[question.id] == option.label ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.label)
                                        Text(option.description).font(.yzFootnote).foregroundStyle(p.labelSecondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).foregroundStyle(p.brandText)
                        }
                        let binding = Binding(get: { answers[question.id, default: ""] }, set: { answers[question.id] = $0 })
                        if question.isSecret == true {
                            SecureField("输入回答", text: binding).textFieldStyle(.roundedBorder)
                        } else {
                            TextField("输入回答，也可以直接选择上面的选项", text: binding, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button(approval.questions.isEmpty ? "拒绝" : "取消") { decide(.deny) }.buttonStyle(OutlineButtonStyle(color: p.danger, height: 44))
                    Button { decide(.allow) } label: { Label(approval.questions.isEmpty ? "允许" : "提交回答", systemImage: "checkmark") }.buttonStyle(PrimaryButtonStyle(height: 44))
                        .disabled(!approval.questions.allSatisfy { !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
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
                            Image(systemName: "checkmark.shield").font(.system(.caption, weight: .semibold))
                            Text("总是允许…").font(.yzFootnoteStrong)
                        }
                        .foregroundStyle(p.labelSecondary)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Capsule().strokeBorder(p.border, lineWidth: 1))
                    }
                    .disabled(busy)
                }
            }
        }
        .padding(14)
        .padding(.leading, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(p.surfaceElevated)
        )
        .overlay(alignment: .leading) {
            // 风险色条：贴着卡片左缘，替代旧版的整块玻璃着色
            UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card, style: .continuous)
                .fill(riskColor)
                .frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(p.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var statusChip: some View {
        switch approval.status {
        case .allowed: Chip("已允许", tone: .sage)
        case .denied: Chip("已拒绝", tone: .danger)
        case .expired: Chip("已过期", tone: .fill)
        case .pending: Chip("待处理", tone: .warning)
        }
    }

    private func decide(_ d: ApprovalDecision, remember: ApprovalSuggestion? = nil) {
        busy = true
        Task {
            if d != .deny, approval.risk == .high, store.settings.faceIDForHighRisk {
                guard await BiometricGate.confirm(reason: "确认允许：\(approval.summary)") else { busy = false; return }
            }
            await store.respond(approval.id, d, remember: remember, answers: approval.questions.isEmpty ? nil : answers)
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
