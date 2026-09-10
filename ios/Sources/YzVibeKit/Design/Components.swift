import SwiftUI
import UIKit

// MARK: - 背景：暖纸

/// 页面底色。方向 B 去掉了旧版的三个柔焦装饰球 —— 它们是「不像 iOS」最主要的来源，
/// 也让系统玻璃没法正确折射。现在只保留一层暖纸底，层级完全交给系统的 List / 材质。
public struct AmbientBackground: View {
    @Environment(\.palette) private var p
    public init() {}
    public var body: some View {
        p.surface.ignoresSafeArea()
    }
}

// MARK: - 纸感卡片

/// 内容卡：暖纸白 + 发丝描边 + 几乎不可见的投影。深度靠描边而不是阴影，和系统列表同一个语言。
public struct PaperCard<Content: View>: View {
    @Environment(\.palette) private var p
    var padding: CGFloat
    var radius: CGFloat
    let content: () -> Content
    public init(padding: CGFloat = Spacing.card, radius: CGFloat = Radius.card, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.radius = radius; self.content = content
    }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content()
            .padding(padding)
            .background(shape.fill(p.surfaceElevated))
            .overlay(shape.strokeBorder(p.border, lineWidth: 1))
            .shadow(color: p.shadow.opacity(0.04), radius: 2, y: 1)
    }
}

// MARK: - 分组小标题

public struct Eyebrow: View {
    @Environment(\.palette) private var p
    let text: String
    var color: Color?
    public init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    public var body: some View {
        Text(text.uppercased())
            .font(.yzEyebrow)
            .kerning(0.8)
            .foregroundStyle(color ?? p.labelSecondary)
    }
}

// MARK: - 胶囊标签

/// 方向 B 收敛了强调色：Claude 用品牌橙，其余 Agent 一律中性，避免界面出现五种彩色胶囊。
public enum ChipTone { case claude, codex, custom, sage, brand, fill, danger, warning }

public struct Chip: View {
    @Environment(\.palette) private var p
    let text: String
    let tone: ChipTone
    var icon: String?
    var mono = false
    public init(_ text: String, tone: ChipTone = .fill, icon: String? = nil, mono: Bool = false) {
        self.text = text; self.tone = tone; self.icon = icon; self.mono = mono
    }
    private var colors: (bg: Color, fg: Color, stroke: Color?) {
        switch tone {
        case .claude, .brand: return (p.brandSoft, p.brandText, nil)
        case .codex, .custom, .fill: return (p.fill, p.labelSecondary, nil)
        case .sage: return (p.sageSoft, p.sage, nil)
        case .warning: return (p.amberSoft, p.amberText, nil)
        case .danger: return (p.dangerSoft, p.danger, nil)
        }
    }
    public var body: some View {
        let c = colors
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(.caption2, weight: .semibold)) }
            Text(text).font(mono ? .yzMono : .yzFootnoteStrong)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(c.fg)
        .background(Capsule().fill(c.bg))
        .overlay { if let s = c.stroke { Capsule().strokeBorder(s, lineWidth: 1) } }
        .lineLimit(1)
    }
}

public extension Chip {
    static func agent(_ kind: AgentKind, suffix: String? = nil) -> Chip {
        let text = suffix.map { "\(kind.displayName) · \($0)" } ?? kind.displayName
        switch kind {
        case .claude: return Chip(text, tone: .claude)
        case .codex: return Chip(text, tone: .codex)
        case .custom: return Chip(text, tone: .custom)
        }
    }
    static func mode(_ mode: ConnectionMode) -> Chip {
        switch mode {
        case .local: return Chip(mode.displayName, tone: .sage)
        default: return Chip(mode.displayName, tone: .fill)
        }
    }
}

// MARK: - 状态点

public struct StatusDot: View {
    @Environment(\.palette) private var p
    public enum Tone { case sage, brand, amber, danger, off }
    let tone: Tone
    public init(_ tone: Tone) { self.tone = tone }
    /// 空闲=绿，运行中=品牌橙，待审批/出错=红，已关闭=灰。
    public init(session status: SessionStatus) {
        switch status {
        case .idle: tone = .sage
        case .running: tone = .brand
        case .waitingApproval, .error: tone = .danger
        case .closed: tone = .off
        }
    }
    private var color: Color {
        switch tone {
        case .sage: p.sage
        case .brand: p.brand
        case .amber: p.amber
        case .danger: p.danger
        case .off: p.labelTertiary
        }
    }
    public var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .overlay(Circle().stroke(color.opacity(tone == .off ? 0 : 0.22), lineWidth: 3))
            .accessibilityHidden(true)
    }
}

// MARK: - 代码块 / 路径块

public struct CodeBlock: View {
    @Environment(\.palette) private var p
    let text: String
    var dark = false
    var lines: Int? = 1
    /// 代码语言（围栏 ``` 后面那截），显示在标题栏左侧
    var language: String?
    /// 显示标题栏与「复制」按钮
    var copyable = false
    /// 复制成功后的提示（聊天里用 store.toast，别处可自带）
    var onCopy: ((String) -> Void)?

    public init(_ text: String, dark: Bool = false, lines: Int? = 1,
                language: String? = nil, copyable: Bool = false, onCopy: ((String) -> Void)? = nil) {
        self.text = text; self.dark = dark; self.lines = lines
        self.language = language; self.copyable = copyable; self.onCopy = onCopy
    }

    @State private var copied = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if copyable { header }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.yzMono)
                    .lineLimit(lines)
                    .truncationMode(lines == nil ? .tail : .middle)
                    .textSelection(.enabled)
                    .foregroundStyle(dark ? Color(hex: 0xE8E2DA) : p.labelSecondary)
                    .frame(maxWidth: copyable ? nil : .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .scrollDisabled(!copyable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(dark ? Color(hex: 0x2A2724) : p.fillSecondary)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(dark ? .clear : p.border, lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text(language?.isEmpty == false ? language! : "text")
                .font(.yzCaption)
                .foregroundStyle(dark ? Color(hex: 0xA9A199) : p.labelTertiary)
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = text
                onCopy?(text)
                withAnimation(Motion.quick) { copied = true }
                Task { try? await Task.sleep(nanoseconds: 1_600_000_000); withAnimation(Motion.quick) { copied = false } }
            } label: {
                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.yzCaption)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(dark ? Color(hex: 0xE8E2DA) : p.labelSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(dark ? Color.white.opacity(0.10) : p.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "已复制" : "复制代码")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.top, 7).padding(.bottom, 1)
    }
}

// MARK: - 设置行

/// 放在系统 `List` 里时用 `inset: 0`（List 自己会给行内边距）；放在 PaperCard 里时保留内边距。
public struct SettingRow<Trailing: View>: View {
    @Environment(\.palette) private var p
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 30
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    var inset: CGFloat
    let trailing: () -> Trailing
    public init(icon: String, color: Color, title: String, subtitle: String? = nil,
                inset: CGFloat = Spacing.card, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon; self.color = color; self.title = title
        self.subtitle = subtitle; self.inset = inset; self.trailing = trailing
    }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: glyph, height: glyph)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.yzBody).foregroundStyle(p.label)
                if let subtitle { Text(subtitle).font(.yzFootnote).foregroundStyle(p.labelSecondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 6)
    }
}

public struct SectionCard<Content: View>: View {
    let title: String
    let content: () -> Content
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title).padding(.horizontal, 4)
            PaperCard(padding: 0) { VStack(spacing: 0) { content() }.padding(.vertical, 4) }
        }
    }
}

public struct Divider_: View {
    @Environment(\.palette) private var p
    public init() {}
    public var body: some View { Rectangle().fill(p.border).frame(height: 1).padding(.leading, Spacing.card) }
}
