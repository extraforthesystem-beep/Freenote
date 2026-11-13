import Foundation

/// Splits note text into sentences with simple punctuation rules.
///
/// This is deliberately model-free: the deterministic provider and citation
/// extraction must produce identical boundaries on every device.
enum SentenceSplitter {
    /// Words ending in a period that do not end a sentence.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc",
        "fig", "no", "inc", "ltd", "co", "dept", "approx", "est",
    ]

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closingMarks: Set<Character> = ["\"", "'", "”", "’", ")", "]"]

    /// The trimmed sentences of `text`, in source order.
    static func sentences(in text: String) -> [String] {
        ranges(in: text).map { String(text[$0]) }
    }

    /// The trimmed ranges of the sentences of `text`, in source order.
    static func ranges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            // A line break always ends a sentence, even without punctuation.
            if character == "\n" {
                append(text, start..<index, to: &result)
                index = text.index(after: index)
                start = index
                continue
            }

            guard terminators.contains(character) else {
                index = text.index(after: index)
                continue
            }

            // Consume runs such as "?!" and "..." plus a closing quote.
            var end = index
            while end < text.endIndex, terminators.contains(text[end]) {
                end = text.index(after: end)
            }
            while end < text.endIndex, closingMarks.contains(text[end]) {
                end = text.index(after: end)
            }

            let isBoundary = end == text.endIndex || text[end].isWhitespace
            if isBoundary, character == ".", isAbbreviation(endingAt: index, in: text) {
                index = end
                continue
            }

            if isBoundary {
                append(text, start..<end, to: &result)
                start = end
            }
            index = end
        }

        append(text, start..<text.endIndex, to: &result)
        return result
    }

    /// True when the period at `terminator` closes an abbreviation or a decimal.
    private static func isAbbreviation(endingAt terminator: String.Index, in text: String) -> Bool {
        guard terminator > text.startIndex else { return false }
        var cursor = text.index(before: terminator)

        if text[cursor].isNumber {
            let after = text.index(after: terminator)
            return after < text.endIndex && text[after].isNumber
        }

        guard text[cursor].isLetter else { return false }
        let wordEnd = cursor
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous].isLetter else { break }
            cursor = previous
        }
        if cursor == wordEnd, text[cursor].isUppercase {
            return true
        }
        // A single letter directly after another dotted letter is an initialism
        // ("U.S.", "p.m."), not the end of a sentence.
        if cursor == wordEnd, cursor > text.startIndex {
            let dot = text.index(before: cursor)
            if text[dot] == "." {
                let beforeDot = text.index(before: dot)
                if text[beforeDot].isLetter {
                    return true
                }
            }
        }
        return abbreviations.contains(text[cursor...wordEnd].lowercased())
    }

    /// Appends `range` without surrounding whitespace, skipping empty spans.
    private static func append(
        _ text: String,
        _ range: Range<String.Index>,
        to result: inout [Range<String.Index>]
    ) {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }
        while upper > lower, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }
        if lower < upper {
            result.append(lower..<upper)
        }
    }
}
