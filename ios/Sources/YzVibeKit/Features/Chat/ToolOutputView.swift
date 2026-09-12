import SwiftUI

/// 回复内只展示一个入口；调用详情在可手动打开的面板里查看。
struct ToolCallGroup: View {
    @Environment(\.palette) private var p
    let calls: [ToolCall]
    @State private var showingCalls = false

    private var names: String {
        var seen: Set<String> = []
        return calls.map(\.name).filter { seen.insert($0).inserted }.joined(separator: " · ")
    }

    var body: some View {
        Button { showingCalls = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "terminal").foregroundStyle(p.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(calls.count) 次工具调用").font(.yzFootnoteStrong).foregroundStyle(p.label)
                    Text(names).font(.yzCaption).foregroundStyle(p.labelSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if calls.contains(where: { $0.state == .running }) {
                    ProgressView().controlSize(.small).accessibilityLabel("工具运行中")
                }
                let failures = calls.filter { $0.state == .error }.count
                if failures > 0 { Chip("\(failures) 项失败", tone: .danger) }
                Image(systemName: "chevron.right").font(.system(.caption2, weight: .bold)).foregroundStyle(p.labelTertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.fillSecondary))
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开工具调用列表，展开可查看命令")
        .sheet(isPresented: $showingCalls) {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(calls, id: \.id) { ToolCallCard(call: $0) }
                    }
                    .padding(Spacing.page)
                }
                .paperBackground()
                .navigationTitle("\(calls.count) 次工具调用")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showingCalls = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// 调用详情只展示执行命令 / 输入摘要，不渲染工具输出。
struct ToolCallCard: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let call: ToolCall
    @State private var expanded = false

    private var symbol: String {
        switch call.name {
        case "Bash", "PowerShell", "Shell": "terminal"
        case "Read", "Grep", "Glob": "doc.text.magnifyingglass"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": "square.and.pencil"
        case "WebFetch", "WebSearch": "globe"
        default: "wrench.and.screwdriver"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(reduceMotion ? nil : Motion.quick) { expanded.toggle() } } label: { header }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                Divider_().padding(.vertical, 2)
                Text(call.detail.isEmpty ? "无命令详情" : call.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(p.label)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.fillSecondary)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
        .contextMenu {
            Button("复制命令", systemImage: "terminal") { UIPasteboard.general.string = call.detail }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(.footnote, weight: .semibold)).foregroundStyle(p.labelSecondary)
                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.surfaceElevated))
            VStack(alignment: .leading, spacing: 1) {
                Text(call.name).font(.yzFootnote).fontWeight(.semibold).foregroundStyle(p.label)
                Text(call.detail).font(.yzCaption).monospaced().foregroundStyle(p.labelSecondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            switch call.state {
            case .done: Chip(call.outputKind == .diff ? "已改" : "完成", tone: .sage)
            case .running: ProgressView().controlSize(.small)
            case .error: Chip("失败", tone: .danger)
            }
            Image(systemName: "chevron.down").font(.system(.caption2, weight: .bold))
                .foregroundStyle(p.labelTertiary).rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// 输出正文：普通文本用等宽，diff 按 +/- 着色。
struct ToolOutputView: View {
    @Environment(\.palette) private var p
    let text: String
    var kind: ToolCall.OutputKind = .text
    var truncated: Bool = false
    var maxHeight: CGFloat = 260

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : String(line))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .padding(.horizontal, 8).padding(.vertical, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line))
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: maxHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(oklch: 0.20, 0.02, 50)))
            if truncated {
                Text("输出很长，已截断中间部分").font(.yzCaption).foregroundStyle(p.labelTertiary)
            }
        }
    }

    private func color(for line: Substring) -> Color {
        guard kind == .diff else { return Color(oklch: 0.90, 0.02, 80) }
        if line.hasPrefix("+") { return Color(oklch: 0.80, 0.14, 155) }
        if line.hasPrefix("-") { return Color(oklch: 0.75, 0.16, 25) }
        if line.hasPrefix("@@") || line == "…" { return Color(oklch: 0.65, 0.10, 260) }
        return Color(oklch: 0.72, 0.01, 80)
    }

    private func background(for line: Substring) -> Color {
        guard kind == .diff else { return .clear }
        if line.hasPrefix("+") { return Color(oklch: 0.55, 0.10, 155, alpha: 0.18) }
        if line.hasPrefix("-") { return Color(oklch: 0.55, 0.14, 25, alpha: 0.18) }
        return .clear
    }
}
