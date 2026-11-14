import SearchKit
import SwiftUI

/// A search excerpt with the matched text in bold on the app's search-hit wash,
/// the same colour the page marks use.
struct HighlightedSnippet: View {
    let snippet: String
    let matchRange: Range<String.Index>?
    var lineLimit: Int = 2

    var body: some View {
        Text(attributed)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var text = AttributedString(snippet)
        guard let matchRange else { return text }

        let start = snippet.distance(from: snippet.startIndex, to: matchRange.lowerBound)
        let length = snippet.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
        guard start >= 0, length > 0 else { return text }

        let lower = text.index(text.startIndex, offsetByCharacters: start)
        let upper = text.index(lower, offsetByCharacters: length)
        text[lower..<upper].backgroundColor = AppColor.searchHitFill
        text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        return text
    }
}
