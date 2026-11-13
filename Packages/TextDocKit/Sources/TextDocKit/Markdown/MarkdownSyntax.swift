import Foundation

/// The small Markdown subset shared by ``MarkdownExporter`` and ``MarkdownImporter``.
///
/// Keeping recognition in one place is what makes the round trip reliable: the
/// exporter escapes exactly the paragraph lines the importer would otherwise
/// treat as block syntax.
enum MarkdownSyntax {
    /// `## Heading` -> `(2, "Heading")`; requires a space after the hashes.
    static func heading(from line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        if rest.isEmpty { return (level, "") }
        guard rest.first == " " else { return nil }
        return (level, String(rest.dropFirst()))
    }

    /// Three or more `-`, `*` or `_` characters, optionally indented.
    static func isDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, let marker = trimmed.first,
              marker == "-" || marker == "*" || marker == "_"
        else { return false }
        return trimmed.allSatisfy { $0 == marker }
    }

    /// `- [ ] Text` or `- [x] Text`; also accepts `*` as the bullet.
    static func checklistItem(from line: String) -> (text: String, isChecked: Bool)? {
        let characters = Array(line)
        guard characters.count >= 5 else { return nil }
        guard characters[0] == "-" || characters[0] == "*" else { return nil }
        guard characters[1] == " ", characters[2] == "[", characters[4] == "]" else { return nil }

        let isChecked: Bool
        switch characters[3] {
        case " ": isChecked = false
        case "x", "X": isChecked = true
        default: return nil
        }

        if characters.count == 5 { return ("", isChecked) }
        guard characters[5] == " " else { return nil }
        return (String(characters.dropFirst(6)), isChecked)
    }

    /// `- Item`, `* Item` or `+ Item`.
    static func bulletItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    /// `1. Item` or `1) Item`.
    static func numberedItem(from line: String) -> String? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }

    /// A line starting with `>`, with one optional following space removed.
    static func quoteContent(from line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        var rest = line.dropFirst()
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        return String(rest)
    }

    /// `![alt](asset "width=320")`, with an optional title and angle-bracket
    /// destinations for names containing spaces.
    static func image(from line: String) -> (assetName: String, width: Double?)? {
        guard line.hasPrefix("!["), line.hasSuffix(")") else { return nil }
        guard let altEnd = line.firstIndex(of: "]") else { return nil }
        let parenthesis = line.index(after: altEnd)
        guard parenthesis < line.endIndex, line[parenthesis] == "(" else { return nil }

        let start = line.index(after: parenthesis)
        let end = line.index(before: line.endIndex)
        guard start <= end else { return nil }
        let inside = String(line[start..<end]).trimmingCharacters(in: .whitespaces)
        guard !inside.isEmpty else { return nil }

        let destination: String
        let title: String?
        if inside.hasPrefix("<") {
            guard let close = inside.firstIndex(of: ">") else { return nil }
            destination = String(inside[inside.index(after: inside.startIndex)..<close])
            let remainder = inside[inside.index(after: close)...].trimmingCharacters(in: .whitespaces)
            title = remainder.isEmpty ? nil : remainder
        } else {
            let parts = inside.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let first = parts.first else { return nil }
            destination = String(first)
            title = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil
        }

        guard !destination.isEmpty else { return nil }
        return (destination, width(fromTitle: title))
    }

    /// An opening code fence: three or more backticks with an optional language.
    static func fenceOpening(_ line: String) -> (length: Int, language: String?)? {
        var index = line.startIndex
        var spaces = 0
        while index < line.endIndex, line[index] == " ", spaces < 3 {
            spaces += 1
            index = line.index(after: index)
        }

        var ticks = 0
        while index < line.endIndex, line[index] == "`" {
            ticks += 1
            index = line.index(after: index)
        }
        guard ticks >= 3 else { return nil }

        let info = line[index...].trimmingCharacters(in: .whitespaces)
        return (ticks, info.isEmpty ? nil : info)
    }

    /// A closing fence: a run of backticks at least as long as the opening one.
    static func isFenceClosing(_ line: String, length: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= length else { return false }
        return trimmed.allSatisfy { $0 == "`" }
    }

    /// Whether a paragraph line would be mistaken for block syntax.
    static func isBlockStart(_ line: String) -> Bool {
        heading(from: line) != nil
            || isDivider(line)
            || checklistItem(from: line) != nil
            || bulletItem(from: line) != nil
            || numberedItem(from: line) != nil
            || image(from: line) != nil
            || quoteContent(from: line) != nil
            || fenceOpening(line) != nil
    }

    /// Removes the escape backslash the exporter puts in front of block-like
    /// paragraph lines. A doubled leading backslash is one literal backslash;
    /// any other backslash is literal text.
    static func unescapeParagraphLine(_ line: String) -> String {
        guard line.hasPrefix("\\") else { return line }
        let rest = String(line.dropFirst())
        if rest.hasPrefix("\\") { return rest }
        return isBlockStart(rest) ? rest : line
    }

    /// Reads the `width=...` Markdown image title, if present.
    private static func width(fromTitle title: String?) -> Double? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let prefix = "width="
        guard trimmed.hasPrefix(prefix) else { return nil }
        return Double(trimmed.dropFirst(prefix.count))
    }
}
