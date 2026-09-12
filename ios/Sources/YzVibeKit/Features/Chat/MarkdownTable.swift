import SwiftUI

struct MarkdownTable {
    enum ColumnAlignment: Equatable {
        case leading, center, trailing
        var textAlignment: TextAlignment {
            switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
        }
        var frameAlignment: Alignment {
            switch self { case .leading: .topLeading; case .center: .top; case .trailing: .topTrailing }
        }
    }
    let header: [String]
    let rows: [[String]]
    let alignments: [ColumnAlignment]

    static func parse(_ lines: [String], startingAt index: Int) -> (table: Self, nextIndex: Int)? {
        guard index + 1 < lines.count, lines[index].contains("|") else { return nil }
        let header = cells(lines[index]), separator = cells(lines[index + 1])
        guard !header.isEmpty, separator.count == header.count else { return nil }
        var alignments: [ColumnAlignment] = []
        for cell in separator {
            var dashes = cell[...]
            if dashes.first == ":" { dashes.removeFirst() }
            if dashes.last == ":" { dashes.removeLast() }
            guard dashes.count >= 3, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(cell.hasSuffix(":") ? (cell.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        var rows: [[String]] = [], next = index + 2
        while next < lines.count {
            let line = lines[next].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.contains("|"), !line.hasPrefix("```") else { break }
            var row = Array(cells(line).prefix(header.count))
            row += Array(repeating: "", count: header.count - row.count)
            rows.append(row)
            next += 1
        }
        return (Self(header: header, rows: rows, alignments: alignments), next)
    }

    static func cells(_ raw: String) -> [String] {
        let line = raw.trimmingCharacters(in: .whitespaces)
        var cells: [String] = [], cell = "", escaped = false
        for character in line {
            if escaped {
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                cell.append(character)
                escaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""
            } else { cell.append(character) }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if line.hasPrefix("|") { cells.removeFirst() }
        if cells.last == "", line.hasSuffix("|"), !escaped { cells.removeLast() }
        return cells
    }
}
