import SwiftUI

/// 导航栏上的小环形表：本轮上下文占窗口的比例。没有数据时显示空环。
struct UsageGauge: View {
    @Environment(\.palette) private var p
    let fraction: Double?
    var body: some View {
        ZStack {
            Circle().stroke(p.border, lineWidth: 2.5)
            Circle().trim(from: 0, to: fraction ?? 0).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: "chart.pie").font(.system(.caption2, weight: .bold)).foregroundStyle(p.labelSecondary)
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("上下文与用量")
    }
    private var color: Color {
        guard let f = fraction else { return p.labelTertiary }
        return f > 0.85 ? p.danger : f > 0.6 ? p.amber : p.sage
    }
}

/// 上下文详情：本轮上下文、账号额度（Claude 含 Fable 本周额度）、本轮 / 累计 token。
struct UsageSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    @State private var quota: QuotaInfo?
    @State private var loadingQuota = false

    private var session: Session? { store.session(sessionId) }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let s = session {
                            header(s)
                            contextCard(s)
                            quotaCard(s)
                            if let u = s.usage { turnCard(u.turn, agent: s.agent); totalCard(u.total, agent: s.agent) }
                            else { emptyCard("还没有完成的对话轮次，发送一条消息后这里会显示 token 用量。") }
                        }
                    }
                    .padding(Spacing.page)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("上下文详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadQuota(force: false) }
        }
    }

    // MARK: 区块

    private func header(_ s: Session) -> some View {
        HStack(spacing: 8) {
            Chip.agent(s.agent)
            Chip(s.usage?.turn.model ?? s.model.map { store.capabilities(for: s).label(forModel: $0) } ?? "默认模型", tone: .fill, mono: true)
            Chip(s.mode.displayName, tone: s.mode == .trust ? .danger : s.mode == .plan ? .custom : .fill)
            Spacer()
        }
    }

    private func contextCard(_ s: Session) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("上下文（最近调用）").font(.yzHeadline).foregroundStyle(p.label)
                    Spacer()
                    if let f = s.usage?.turn.contextFraction { Text("\(Int((f * 100).rounded()))%").font(.yzHeadline).monospacedDigit().foregroundStyle(gaugeColor(f)) }
                    else { Text("--").font(.yzHeadline).foregroundStyle(p.labelTertiary) }
                }
                ProgressBar(fraction: s.usage?.turn.contextFraction ?? 0, color: gaugeColor(s.usage?.turn.contextFraction ?? 0))
                HStack {
                    Text("\(fmt(s.usage?.turn.contextTokens)) / \(fmt(s.usage?.turn.contextWindow))").font(.yzMono).foregroundStyle(p.labelSecondary)
                    Spacer()
                    if let ms = s.usage?.turn.durationMs { Text("本轮 \(String(format: "%.1f", Double(ms) / 1000)) s").font(.yzCaption).foregroundStyle(p.labelTertiary) }
                }
                Text(s.agent == .codex
                     ? "来自最近一次模型调用：输入（已含缓存命中）+ 输出。窗口取自本会话记录；未读取到时显示 --。"
                     : "最近一次调用的输入 + cache 写入 + cache 命中，不含输出。")
                    .font(.yzCaption).foregroundStyle(p.labelTertiary)
            }
        }
    }

    private func quotaCard(_ s: Session) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账号剩余用量").font(.yzHeadline).foregroundStyle(p.label)
                    Spacer()
                    if loadingQuota { ProgressView().controlSize(.small) }
                    else { Button { Task { await loadQuota(force: true) } } label: { Image(systemName: "arrow.clockwise").font(.system(.footnote, weight: .semibold)).foregroundStyle(p.labelSecondary) } }
                }
                if let q = quota {
                    if let u = q.unavailable { Text(u).font(.yzFootnote).foregroundStyle(p.labelSecondary) }
                    else if let e = q.error, q.limits.isEmpty { Text(e).font(.yzFootnote).foregroundStyle(p.danger) }
                    ForEach(q.limits) { l in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(l.label).font(.yzSubhead).foregroundStyle(p.label)
                                Spacer()
                                Text("已用 \(l.percent)%").font(.yzSubhead).monospacedDigit().foregroundStyle(gaugeColor(Double(l.percent) / 100))
                            }
                            ProgressBar(fraction: Double(l.percent) / 100, color: gaugeColor(Double(l.percent) / 100))
                            HStack {
                                Text("剩余 \(max(0, 100 - l.percent))%").font(.yzCaption).foregroundStyle(p.labelSecondary)
                                Spacer()
                                if let r = l.resetsAt { Text("重置 \(resetText(r))").font(.yzCaption).foregroundStyle(p.labelTertiary) }
                            }
                        }
                    }
                    if let x = q.extraUsage, x.enabled {
                        HStack {
                            Text("额外用量（本月）").font(.yzSubhead).foregroundStyle(p.label)
                            Spacer()
                            Text("\(String(format: "%.2f", x.usedCredits)) / \(x.monthlyLimit.map { String(format: "%.0f", $0) } ?? "--") \(x.currency)").font(.yzMono).foregroundStyle(p.labelSecondary)
                        }
                    }
                    if let w = q.warning { Text("接口失败，显示的是最近一次对话时的数据：\(w)").font(.yzCaption).foregroundStyle(p.amberText) }
                    HStack {
                        Text(q.source == "oauth" ? "来源：Claude 账号额度接口" : q.source == "rate_limit_event" ? "来源：最近一次对话的限额事件" : "").font(.yzCaption).foregroundStyle(p.labelTertiary)
                        Spacer()
                        if let t = q.fetchedAt { Text(RelativeTime.string(from: t)).font(.yzCaption).foregroundStyle(p.labelTertiary) }
                    }
                } else if !loadingQuota {
                    Text("点右上角刷新获取").font(.yzFootnote).foregroundStyle(p.labelTertiary)
                }
            }
        }
    }

    private func turnCard(_ t: TurnUsage, agent: AgentKind) -> some View {
        SectionCard("本轮累计 tokens") {
            row("输入 tokens", fmt(t.input))
            Divider_()
            row(agent == .codex ? "cache 写入" : "cache 写入", fmt(t.cacheWrite), dim: agent == .codex)
            Divider_()
            row("cache 命中", fmt(t.cacheRead))
            Divider_()
            row("输出 tokens", fmt(t.output), badge: agent == .codex ? nil : "未计入上下文")
            if t.thinking > 0 { Divider_(); row(agent == .codex ? "其中推理" : "其中思考", fmt(t.thinking), dim: true) }
            if let c = t.costUSD { Divider_(); row("本轮费用（按目录价）", String(format: "$%.4f", c)) }
        }
    }

    private func totalCard(_ t: TotalUsage, agent: AgentKind) -> some View {
        SectionCard("会话累计 · \(t.turns) 轮") {
            row("输入 tokens", fmt(t.input))
            Divider_()
            row("cache 写入", fmt(t.cacheWrite))
            Divider_()
            row("cache 命中", fmt(t.cacheRead))
            Divider_()
            row("输出 tokens", fmt(t.output))
            if let c = t.costUSD { Divider_(); row("累计费用（按目录价）", String(format: "$%.2f", c)) }
            if agent == .codex { Divider_(); row("说明", "Codex 不提供费用估算", dim: true) }
        }
    }

    private func emptyCard(_ text: String) -> some View {
        PaperCard { Text(text).font(.yzFootnote).foregroundStyle(p.labelSecondary).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private func row(_ title: String, _ value: String, badge: String? = nil, dim: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.yzBody).foregroundStyle(dim ? p.labelSecondary : p.label)
            if let badge { Chip(badge, tone: .fill) }
            Spacer()
            Text(value).font(.yzBody).monospacedDigit().foregroundStyle(dim ? p.labelSecondary : p.label)
        }
        .padding(.horizontal, Spacing.card).frame(minHeight: 48)
    }

    // MARK: 工具

    private func loadQuota(force: Bool) async {
        guard let s = session, !loadingQuota else { return }
        loadingQuota = true
        quota = await store.quota(for: s)
        loadingQuota = false
    }
    private func gaugeColor(_ f: Double) -> Color { f > 0.85 ? p.danger : f > 0.6 ? p.amber : p.sage }
    private func fmt(_ n: Int?) -> String {
        guard let n else { return "--" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    private func resetText(_ d: Date) -> String {
        let s = Int(d.timeIntervalSinceNow)
        if s <= 0 { return "即将" }
        if s < 3600 { return "\(s / 60) 分钟后" }
        if s < 86400 { return "\(s / 3600) 小时后" }
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }
}

/// 细进度条。
struct ProgressBar: View {
    @Environment(\.palette) private var p
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.fill)
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 8)
    }
}
