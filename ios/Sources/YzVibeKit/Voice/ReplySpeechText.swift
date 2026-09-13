import Foundation

/// Deterministic filtering only: never asks an agent to rewrite a reply.
enum ReplySpeechText {
    static func extract(_ markdown: String) -> String {
        var output: [String] = []
        var fence: Character?
        var fenceLength = 0
        var skippedHeading: Int?
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let unquoted = line.replacingOccurrences(of: #"^(?:>\s*)+"#, with: "", options: .regularExpression)
            if let first = unquoted.first, first == "`" || first == "~" {
                let count = unquoted.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if fence == nil { fence = first; fenceLength = count }
                    else if fence == first && count >= fenceLength { fence = nil }
                    continue
                }
            }
            guard fence == nil else { continue }
            if raw.hasPrefix("    ") || raw.hasPrefix("\t") { continue }
            let headingLevel = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(headingLevel), line.dropFirst(headingLevel).first == " " {
                let title = String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces)
                // Reset at the next heading of equal or greater importance.
                if let level = skippedHeading, headingLevel <= level { skippedHeading = nil }
                if matches(title, #"(?i)^(?:执行命令|命令|日志|工具输出|执行输出|终端输出|commands?|logs?|shell|bash|output)(?:\s|[：:]|$)"#) {
                    skippedHeading = headingLevel; continue
                }
            }
            guard skippedHeading == nil else { continue }
            if matches(unquoted, #"^(?:\$\s|%\s|(?:[\w.-]+@[^\s]+)[#$]\s)"#) { continue }
            if matches(unquoted, #"(?i)^(?:(?:sudo\s+)?(?:git|npm|npx|pnpm|yarn|node|python3?|pip3?|brew|curl|wget|xcodebuild|xcrun|swift|cd|ls|cat|rg|rm|mkdir|docker|ssh|bash|zsh)\s+|(?:/bin/)?(?:bash|zsh)\b)"#) { continue }
            if matches(unquoted, #"(?i)^(?:\[?(?:\d{4}-\d\d-\d\d[ T]|\d\d:\d\d:\d\d)|\[?(?:INFO|DEBUG|TRACE|WARN|ERROR)\]?(?:\s|:)|at\s+\S+\s*\(|Traceback\b|\*\*\s+(?:BUILD|TEST|EXPORT|ARCHIVE)\b)"#) { continue }
            if matches(unquoted, #"^\|?[\s:|\-]+\|?$"#) { continue }
            var text = unquoted
            text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^\n]*?\)"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(`+)[^`]*\1"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"^\s*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                text = String(attributed.characters)
            }
            text = text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " |"))
                .replacingOccurrences(of: "|", with: "，")
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            if !text.isEmpty { output.append(text) }
        }
        return output.joined(separator: "\n")
    }
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
