import SwiftUI

// MARK: - 背景：纸感 + 三个装饰球

public struct AmbientBackground: View {
    @Environment(\.palette) private var p
    public init() {}
    public var body: some View {
        ZStack {
            p.surface.ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    Circle().fill(p.brandSoft).frame(width: 360, height: 360).offset(x: -120, y: -140)
                    Circle().fill(p.amberSoft).frame(width: 300, height: 300).offset(x: geo.size.width - 170, y: -40)
                    Circle().fill(p.sageSoft).frame(width: 420, height: 420).offset(x: (geo.size.width - 420) / 2, y: geo.size.height - 160)
                }
                .blur(radius: 60)
                .opacity(p.orbAlpha)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - 纸感卡片

public struct PaperCard<Content: View>: View {
    @Environment(\.palette) private var p
    var padding: CGFloat
    var radius: CGFloat
    let content: () -> Content
    public init(padding: CGFloat = Spacing.card, radius: CGFloat = Radius.card, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.radius = radius; self.content = content
    }
    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(p.surfaceElevated)
                    .shadow(color: p.shadow.opacity(0.05), radius: 1, y: 1)
                    .shadow(color: p.shadow.opacity(0.07), radius: 10, y: 6)
            )
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
            .kerning(1.2)
            .foregroundStyle(color ?? p.labelSecondary)
    }
}

// MARK: - 胶囊标签

public enum ChipTone { case claude, codex, custom, sage, brand, fill, danger }

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
        case .claude: return (p.amberSoft, p.amberText, p.amber.opacity(0.6))
        case .codex: return (p.purpleSoft, p.purple, p.purple.opacity(0.4))
        case .custom: return (p.blueSoft, p.blue, p.blue.opacity(0.4))
        case .sage: return (p.sageSoft, p.sage, p.sage.opacity(0.5))
        case .brand: return (p.brandSoft, p.brand, p.brand.opacity(0.4))
        case .danger: return (p.dangerSoft, p.danger, p.danger.opacity(0.45))
        case .fill: return (p.fill, p.labelSecondary, nil)
        }
    }
    public var body: some View {
        let c = colors
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(mono ? .yzMono : .system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
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
        case .tunnel: return Chip(mode.displayName, tone: .brand)
        case .local: return Chip(mode.displayName, tone: .sage)
        case .p2p, .tailscale, .relay: return Chip(mode.displayName, tone: .custom)
        }
    }
}

// MARK: - 状态点

public struct StatusDot: View {
    @Environment(\.palette) private var p
    public enum Tone { case sage, amber, danger, off }
    let tone: Tone
    public init(_ tone: Tone) { self.tone = tone }
    public init(session status: SessionStatus) {
        switch status {
        case .idle: tone = .sage
        case .running: tone = .amber
        case .waitingApproval, .error: tone = .danger
        case .closed: tone = .off
        }
    }
    private var color: Color {
        switch tone { case .sage: p.sage; case .amber: p.amber; case .danger: p.danger; case .off: p.labelTertiary }
    }
    public var body: some View {
        Circle().fill(color).frame(width: 9, height: 9)
            .overlay(Circle().stroke(color.opacity(tone == .off ? 0 : 0.25), lineWidth: 3))
    }
}

// MARK: - 分段控件（玻璃/胶囊）

public struct SegmentedPills<T: Hashable>: View {
    @Environment(\.palette) private var p
    let items: [(T, String)]
    @Binding var selection: T
    public init(items: [(T, String)], selection: Binding<T>) { self.items = items; _selection = selection }
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selection
                Button { withAnimation(Motion.quick) { selection = item.0 } } label: {
                    Text(item.1)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? p.brand : p.labelSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            Capsule().fill(on ? p.brandSoft : .clear)
                                .overlay(Capsule().strokeBorder(on ? p.brand : .clear, lineWidth: 1.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(p.fill).overlay(Capsule().strokeBorder(p.border, lineWidth: 1)))
    }
}

// MARK: - 代码块 / 路径块

public struct CodeBlock: View {
    @Environment(\.palette) private var p
    let text: String
    var dark = false
    var lines: Int? = 1
    public init(_ text: String, dark: Bool = false, lines: Int? = 1) { self.text = text; self.dark = dark; self.lines = lines }
    public var body: some View {
        Text(text)
            .font(.yzMono)
            .lineLimit(lines)
            .truncationMode(.middle)
            .foregroundStyle(dark ? Color(oklch: 0.92, 0.02, 80) : p.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dark ? Color(oklch: 0.20, 0.02, 50) : p.fillSecondary)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(dark ? .clear : p.border, lineWidth: 1))
            )
    }
}

// MARK: - 设置行

public struct SettingRow<Trailing: View>: View {
    @Environment(\.palette) private var p
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    let trailing: () -> Trailing
    public init(icon: String, color: Color, title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon; self.color = color; self.title = title; self.subtitle = subtitle; self.trailing = trailing
    }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.yzBody).foregroundStyle(p.label)
                if let subtitle { Text(subtitle).font(.yzFootnote).foregroundStyle(p.labelSecondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Spacing.card)
        .frame(minHeight: 56)
    }
}

public struct SectionCard<Content: View>: View {
    let title: String
    let content: () -> Content
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title).padding(.horizontal, 4)
            PaperCard(padding: 0) { VStack(spacing: 0) { content() }.padding(.vertical, 4) }
        }
    }
}

public struct Divider_: View {
    @Environment(\.palette) private var p
    public init() {}
    public var body: some View { Rectangle().fill(p.border).frame(height: 1).padding(.horizontal, Spacing.card) }
}
