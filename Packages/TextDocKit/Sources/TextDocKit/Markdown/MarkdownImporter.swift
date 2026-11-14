import Foundation

/// Parses the Markdown subset produced by ``MarkdownExporter``.
///
/// Supported: ATX headings, paragraphs, bullet and numbered lists, block quotes,
/// fenced code with a language, images with a `width` title, dividers and
/// checklists. Unsupported syntax is kept as paragraph text rather than rejected.
public struct MarkdownImporter: Sendable {
    /// Width assigned to an image whose Markdown has no `width=` title.
    public var defaultImageWidth: Double

    /// Creates an importer with a fallback image width in points.
    public init(defaultImageWidth: Double = 320) {
        self.defaultImageWidth = defaultImageWidth
    }

    /// Parses Markdown into a fresh document with generated block identities.
    public func parse(_ markdown: String, title: String = "", now: Date = Date()) -> TextDocument {
        var parser = Parser(defaultImageWidth: defaultImageWidth)
        let blocks = parser.parse(markdown)
        return TextDocument(title: title, blocks: blocks, createdAt: now, updatedAt: now)
    }
}

// MARK: - Parser

private struct Parser {
    let defaultImageWidth: Double
    var blocks: [TextBlock] = []
    var paragraphLines: [String] = []

    mutating func parse(_ markdown: String) -> [TextBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = strippingCarriageReturn(lines[index])

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = MarkdownSyntax.fenceOpening(line) {
                flushParagraph()
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = strippingCarriageReturn(lines[index])
                    if MarkdownSyntax.isFenceClosing(candidate, length: fence.length) {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                let text = codeLines.joined(separator: "\n")
                blocks.append(TextBlock(kind: .code(text: text, language: fence.language)))
                continue
            }

            // The exporter escapes block-like paragraph lines; consume them
            // before any block-syntax check so the text survives verbatim.
            if line.hasPrefix("\\") {
                paragraphLines.append(MarkdownSyntax.unescapeParagraphLine(line))
                index += 1
                continue
            }

            if let heading = MarkdownSyntax.heading(from: line) {
                flushParagraph()
                blocks.append(TextBlock(kind: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }

            if MarkdownSyntax.isDivider(line) {
                flushParagraph()
                blocks.append(TextBlock(kind: .divider))
                index += 1
                continue
            }

            if let first = MarkdownSyntax.checklistItem(from: line) {
                flushParagraph()
                var items = [ChecklistItem(text: first.text, isChecked: first.isChecked)]
                index += 1
                while index < lines.count,
                      let next = MarkdownSyntax.checklistItem(from: strippingCarriageReturn(lines[index])) {
                    items.append(ChecklistItem(text: next.text, isChecked: next.isChecked))
                    index += 1
                }
                blocks.append(TextBlock(kind: .checklist(items: items)))
                continue
            }

            if let first = MarkdownSyntax.bulletItem(from: line) {
                flushParagraph()
                var items = [first]
                index += 1
                while index < lines.count,
                      let next = MarkdownSyntax.bulletItem(from: strippingCarriageReturn(lines[index])) {
                    items.append(next)
                    index += 1
                }
                blocks.append(TextBlock(kind: .bulletList(items: items.map { ListItem(text: $0) })))
                continue
            }

            if let first = MarkdownSyntax.numberedItem(from: line) {
                flushParagraph()
                var items = [first]
                index += 1
                while index < lines.count,
                      let next = MarkdownSyntax.numberedItem(from: strippingCarriageReturn(lines[index])) {
                    items.append(next)
                    index += 1
                }
                blocks.append(TextBlock(kind: .numberedList(items: items.map { ListItem(text: $0) })))
                continue
            }

            if let image = MarkdownSyntax.image(from: line) {
                flushParagraph()
                blocks.append(
                    TextBlock(
                        kind: .image(
                            assetName: image.assetName,
                            width: image.width ?? defaultImageWidth
                        )
                    )
                )
                index += 1
                continue
            }

            if MarkdownSyntax.quoteContent(from: line) != nil {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count,
                      let content = MarkdownSyntax.quoteContent(from: strippingCarriageReturn(lines[index])) {
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(TextBlock(kind: .quote(text: quoteLines.joined(separator: "\n"))))
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private mutating func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        let text = paragraphLines.joined(separator: "\n")
        paragraphLines.removeAll(keepingCapacity: true)
        if !text.isEmpty {
            blocks.append(TextBlock(kind: .paragraph(text: text)))
        }
    }

    private func strippingCarriageReturn(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }
}
