import SwiftUI

/// 轻量 Markdown：围栏代码块（带语言标签与复制按钮）/ 标题 / 列表 / 段落。
/// 段落内的行内代码若看着像文件路径，会变成可点链接，交给 `onOpenFile` 打开远程文件查看器。
struct MarkdownText: View {
    @Environment(\.palette) private var p
    let text: String
    /// 点了正文里的文件路径；不给就不做 linkify
    var onOpenFile: ((String) -> Void)?
    /// 代码块「复制」后的回调（一般用来弹 toast）
    var onCopy: ((String) -> Void)?

    private enum Block { case code(String, String?), heading(String, Int), bullet(String), numbered(String, String), paragraph(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let code, let lang):
                    CodeBlock(code, dark: true, lines: nil, language: lang, copyable: true, onCopy: onCopy)
                case .heading(let t, let level):
                    inline(t).font(level <= 2 ? .yzHeadline : .system(.callout, weight: .semibold)).padding(.top, 4)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(p.labelTertiary).frame(width: 5, height: 5).offset(y: -3)
                        inline(t)
                    }
                case .numbered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").font(.system(.callout)).foregroundStyle(p.labelSecondary).monospacedDigit()
                        inline(t)
                    }
                case .paragraph(let t):
                    inline(t)
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "yzfile",
                  let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "path" })?.value
            else { return .systemAction }
            onOpenFile?(path)
            return .handled
        })
    }

    private func inline(_ s: String) -> Text {
        if var a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            if onOpenFile != nil { a = Self.linkifyPaths(a, tint: p.brand) }
            return Text(a).font(.system(.callout))
        }
        return Text(s).font(.system(.callout))
    }

    /// 把看着像文件路径的行内代码变成 `yzfile://` 链接，点击由下面的 openURL 拦截。
    static func linkifyPaths(_ input: AttributedString, tint: Color) -> AttributedString {
        var out = input
        for run in input.runs where run.inlinePresentationIntent?.contains(.code) == true {
            let raw = String(input[run.range].characters)
            guard let path = FilePathDetector.path(in: raw),
                  let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "yzfile://open?path=\(encoded)") else { continue }
            out[run.range].link = url
            out[run.range].foregroundColor = tint
            out[run.range].underlineStyle = .single
        }
        return out
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]? = nil
        var lang: String? = nil
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"), lang)); code = nil; lang = nil }
                else { flush(); code = []; lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let h = Self.heading(line) { flush(); out.append(.heading(h.text, h.level)); continue }
            if let b = Self.bullet(line) { flush(); out.append(.bullet(b)); continue }
            if let n = Self.numbered(line) { flush(); out.append(.numbered(n.n, n.text)); continue }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"), lang)) }
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

/// 判断一段行内代码是不是文件路径（聊天正文里把它做成可点链接）。
/// 宁可漏判也不要误判：命令、参数、URL、纯标识符都不算。
enum FilePathDetector {
    /// 没有斜杠时，只有这些后缀才认为是文件名
    static let extensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "json", "md", "markdown", "txt", "log",
        "yml", "yaml", "toml", "ini", "cfg", "conf", "plist", "xml", "html", "css", "scss",
        "py", "rb", "go", "rs", "java", "kt", "kts", "c", "h", "cpp", "hpp", "m", "mm", "sh", "zsh",
        "bash", "sql", "csv", "lock", "gradle", "podspec", "xcconfig", "entitlements", "png", "jpg",
        "jpeg", "gif", "webp", "svg", "pdf", "env",
    ]

    /// 返回规范化后的路径，不像路径则返回 nil。
    static func path(in raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉常见的收尾标点（中英文都有）
        while let last = s.last, "。，,；;：:！!？?）)】]」”\"'`".contains(last) { s = String(s.dropLast()) }
        while let first = s.first, "（(【[「“\"'`".contains(first) { s = String(s.dropFirst()) }
        guard !s.isEmpty, s.count <= 240 else { return nil }
        // 命令、参数、URL、glob 一律排除
        guard !s.contains(where: { $0.isWhitespace }) else { return nil }
        guard !s.contains("://"), !s.hasPrefix("-"), !s.contains("*"), !s.contains("?") else { return nil }
        // `a/b` 这种 Markdown 里也可能是「或」的意思，要求至少有一段像文件名或是绝对路径
        let hasSlash = s.contains("/")
        let ext = s.split(separator: ".").count > 1 ? s.split(separator: ".").last.map { $0.lowercased() } : nil
        let knownExt = ext.map { extensions.contains($0) } ?? false
        // 目录（以 / 结尾）也允许点开
        if hasSlash, s.hasSuffix("/") { return String(s.dropLast()) }
        // 点文件（.gitignore / .env.local）没有可识别后缀，但确实是文件
        let isDotfile = s.hasPrefix(".") && !s.hasPrefix("..") && s.count > 1 && !hasSlash
        guard knownExt || isDotfile || (hasSlash && looksLikePathSegment(s)) else { return nil }
        return s
    }

    /// 形如 `src/server`、`~/.yzvibe`、`/etc/hosts`：段之间只有常规文件名字符。
    private static func looksLikePathSegment(_ s: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+@~/")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        // 至少两段，且不是 `and/or` 这种纯词组（要求有 . 或 ~ 或 / 开头之类的路径特征）
        let parts = s.split(separator: "/")
        guard parts.count >= 2 else { return s.hasPrefix("~") || s.hasPrefix("/") }
        return s.hasPrefix("/") || s.hasPrefix("~") || s.hasPrefix(".") || parts.contains { $0.contains(".") }
    }
}
