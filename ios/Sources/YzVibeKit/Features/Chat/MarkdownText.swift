import SwiftUI

/// 轻量 Markdown：围栏代码块 / 标题 / 列表 / 段落（段落内用系统 AttributedString 解析粗体、行内代码、链接）。
struct MarkdownText: View {
    @Environment(\.palette) private var p
    let text: String

    private enum Block { case code(String), heading(String, Int), bullet(String), numbered(String, String), paragraph(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let code):
                    CodeBlock(code, dark: true, lines: nil)
                case .heading(let t, let level):
                    inline(t).font(level <= 2 ? .yzHeadline : .system(size: 16, weight: .semibold)).padding(.top, 4)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(p.labelTertiary).frame(width: 5, height: 5).offset(y: -3)
                        inline(t)
                    }
                case .numbered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").font(.system(size: 16)).foregroundStyle(p.labelSecondary).monospacedDigit()
                        inline(t)
                    }
                case .paragraph(let t):
                    inline(t)
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a).font(.system(size: 16))
        }
        return Text(s).font(.system(size: 16))
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]? = nil
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let h = Self.heading(line) { flush(); out.append(.heading(h.text, h.level)); continue }
            if let b = Self.bullet(line) { flush(); out.append(.bullet(b)); continue }
            if let n = Self.numbered(line) { flush(); out.append(.numbered(n.n, n.text)); continue }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }

    // MARK: 行首语法（不用正则，兼容 Swift 5 语言模式）

    private static func heading(_ line: String) -> (text: String, level: Int)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return (rest.trimmingCharacters(in: .whitespaces), hashes.count)
    }

    private static func bullet(_ line: String) -> String? {
        guard let f = line.first, "-*•".contains(f), line.dropFirst().first == " " else { return nil }
        return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }

    private static func numbered(_ line: String) -> (n: String, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        var rest = line.dropFirst(digits.count)
        guard let sep = rest.first, ".、)".contains(sep) else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        return (String(digits), rest.trimmingCharacters(in: .whitespaces))
    }
}
