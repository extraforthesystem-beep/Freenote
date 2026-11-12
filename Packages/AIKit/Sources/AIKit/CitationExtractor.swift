import Foundation

/// Finds where generated sentences came from in the original note text.
public enum CitationExtractor {
    /// Citations for the sentences of `output` that appear in `source`.
    ///
    /// Matching ignores case, diacritics and width, and keeps source order.
    /// The result is empty when nothing matches.
    public static func citations(matching output: String, in source: String) -> [AICitation] {
        guard !source.isEmpty, !output.isEmpty else { return [] }
        let sentences = SentenceSplitter.sentences(in: output)
            .map(strippingListMarkers)
            .filter { !$0.isEmpty }
        return citations(forSentences: sentences, in: source)
    }

    /// Citations for known source sentences, in source order.
    ///
    /// Sentences are located from the previous match onward, with a fallback
    /// to the start of the source. Duplicate offsets are dropped.
    public static func citations(forSentences sentences: [String], in source: String) -> [AICitation] {
        guard !source.isEmpty else { return [] }

        var result: [AICitation] = []
        var seenOffsets = Set<Int>()
        var searchStart = source.startIndex

        for sentence in sentences {
            let needle = strippingListMarkers(sentence)
            guard !needle.isEmpty else { continue }
            let match = range(of: needle, in: source, from: searchStart)
                ?? range(of: needle, in: source, from: source.startIndex)
            guard let match else { continue }

            let citation = AICitation(range: match, in: source)
            if seenOffsets.insert(citation.utf16Offset).inserted {
                result.append(citation)
                searchStart = match.upperBound
            }
        }

        return result.sorted { $0.utf16Offset < $1.utf16Offset }
    }

    /// The first citation for `substring`, or nil when it is not in `source`.
    public static func citation(for substring: String, in source: String) -> AICitation? {
        let needle = strippingListMarkers(substring)
        guard !needle.isEmpty, let match = range(of: needle, in: source, from: source.startIndex) else {
            return nil
        }
        return AICitation(range: match, in: source)
    }

    private static func range(
        of needle: String,
        in source: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        source.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            range: start..<source.endIndex
        )
    }

    /// Removes leading bullet markers so "• Sentence" matches "Sentence".
    private static func strippingListMarkers(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, "•*-–—".contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
