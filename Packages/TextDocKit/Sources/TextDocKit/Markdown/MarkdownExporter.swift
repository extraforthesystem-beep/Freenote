import Foundation

/// Renders a ``TextDocument`` as Markdown using the subset understood by
/// ``MarkdownImporter``.
///
/// Headings, paragraphs, bullet and numbered lists, quotes, fenced code, images,
/// dividers and checklists are supported. Block style overrides are not part of
/// Markdown and are not emitted.
public struct MarkdownExporter: Sendable {
    /// Whether to prepend the document title as a level-one heading.
    public var includeTitle: Bool

    /// Creates an exporter; the title is omitted by default so a round trip does
    /// not gain an extra heading block.
    public init(includeTitle: Bool = false) {
        self.includeTitle = includeTitle
    }

    /// Renders the document, ending with a newline unless it is empty.
    public func render(_ document: TextDocument) -> String {
        var sections: [String] = []
        if includeTitle, !document.title.isEmpty {
            let title = document.title.replacingOccurrences(of: "\n", with: " ")
            sections.append("# " + title)
        }
        sections.append(contentsOf: document.blocks.map(render(_:)))

        let body = sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return body.isEmpty ? "" : body + "\n"
    }

    // MARK: - Blocks

    private func render(_ block: TextBlock) -> String {
        switch block.kind {
        case let .heading(level, text):
            renderHeading(level: level, text: text)
        case let .paragraph(text):
            escapedParagraph(text)
        case let .bulletList(items):
            items.map { "- " + $0.text }.joined(separator: "\n")
        case let .numberedList(items):
            items.enumerated()
                .map { "\($0.offset + 1). " + $0.element.text }
                .joined(separator: "\n")
        case let .quote(text):
            renderQuote(text)
        case let .code(text, language):
            renderCode(text, language: language)
        case let .image(assetName, width):
            renderImage(assetName: assetName, width: width)
        case .divider:
            "---"
        case let .checklist(items):
            items.map { ($0.isChecked ? "- [x] " : "- [ ] ") + $0.text }
                .joined(separator: "\n")
        }
    }

    private func renderHeading(level: Int, text: String) -> String {
        let clamped = min(max(level, 1), 6)
        let marker = String(repeating: "#", count: clamped)
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return singleLine.isEmpty ? marker : marker + " " + singleLine
    }

    private func renderQuote(_ text: String) -> String {
        lines(of: text)
            .map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
    }

    private func renderCode(_ text: String, language: String?) -> String {
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: text) + 1))
        let info = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let opening = info.isEmpty ? fence : fence + info
        guard !text.isEmpty else { return opening + "\n" + fence }

        // A single trailing newline belongs to the fence line, not the code.
        let body = text.hasSuffix("\n") ? String(text.dropLast()) : text
        return opening + "\n" + body + "\n" + fence
    }

    private func renderImage(assetName: String, width: Double) -> String {
        let alt = assetName
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        let needsBrackets = assetName.contains(where: { $0.isWhitespace || $0 == ")" || $0 == "(" })
        let destination = needsBrackets ? "<\(assetName)>" : assetName
        return "![\(alt)](\(destination) \"width=\(numberText(width))\")"
    }

    // MARK: - Helpers

    /// Escapes lines the importer would otherwise read as block syntax, and
    /// doubles a leading backslash so literal escapes survive too.
    private func escapedParagraph(_ text: String) -> String {
        lines(of: text)
            .map { line in
                if line.hasPrefix("\\") || MarkdownSyntax.isBlockStart(line) {
                    return "\\" + line
                }
                return line
            }
            .joined(separator: "\n")
    }

    /// Splits on newlines, preserving empty lines and returning `[""]` for empty text.
    private func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    private func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    /// Formats a point value without a trailing `.0`.
    private func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
