import SwiftUI

/// 工具卡：点开能看到命令的真实输出、文件改动的 diff。
/// 只显示「运行中 / 完成」时，在手机上根本没法判断该不该批下一步。
struct ToolCallCard: View {
    @Environment(\.palette) private var p
    let call: ToolCall
    @State private var expanded = false

    private var hasOutput: Bool { !(call.output ?? "").isEmpty }
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
            Button { withAnimation(Motion.quick) { expanded.toggle() } } label: { header }
                .buttonStyle(.plain)
                .disabled(!hasOutput)
            if expanded, let out = call.output, !out.isEmpty {
                Divider_().padding(.vertical, 2)
                ToolOutputView(text: out, kind: call.outputKind, truncated: call.truncated)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.fillSecondary)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.border, lineWidth: 1)))
        .contextMenu {
            if hasOutput { Button("复制输出", systemImage: "doc.on.doc") { UIPasteboard.general.string = call.output } }
            Button("复制命令", systemImage: "terminal") { UIPasteboard.general.string = call.detail }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.labelSecondary)
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
            if hasOutput {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.labelTertiary).rotationEffect(.degrees(expanded ? 0 : -90))
            }
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
                            .font(.system(size: 12, design: .monospaced))
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
