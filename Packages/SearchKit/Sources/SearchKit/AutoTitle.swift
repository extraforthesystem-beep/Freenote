import Foundation

/// Suggests a short notebook title from a page's text, so a notebook created as
/// "Untitled Notebook" can be named from what was actually written.
public enum AutoTitle {
    /// The first sentence of `text`, cut to `maxLength` at a word boundary.
    ///
    /// Returns nil when the text has no usable title: fewer than two words, no
    /// letters (a page of sums), or nothing but punctuation.
    public static func suggestion(from text: String, maxLength: Int = 48) -> String? {
        guard maxLength > 0 else { return nil }

        let collapsed = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }

        // Prefer the first sentence, but only when it is more than a stub.
        var candidate = collapsed
        if let end = candidate.firstIndex(where: { ".!?".contains($0) }) {
            let sentence = candidate[..<end]
            if sentence.count >= 3 {
                candidate = String(sentence)
            }
        }

        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?•*-–—#"))
        if candidate.count > maxLength {
            let cut = candidate.index(candidate.startIndex, offsetBy: maxLength)
            var shortened = String(candidate[..<cut])
            if let space = shortened.lastIndex(of: " ") {
                shortened = String(shortened[..<space])
            }
            candidate = shortened.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        candidate = candidate.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))

        let words = candidate.split(whereSeparator: \.isWhitespace)
        let letters = candidate.filter(\.isLetter)
        guard words.count >= 2, letters.count >= 4 else { return nil }

        // A sentence written in lower case still reads as a title.
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }
}
