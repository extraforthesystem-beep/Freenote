import Foundation

/// A parsed search query.
///
/// Syntax:
/// - `word word` — every word must match (words match tolerantly, so misread ink still hits).
/// - `"exact phrase"` — the words in that order, matched exactly.
/// - `a OR b` — either side may match.
/// - `-word` or `-"phrase"` — pages containing it are left out.
public struct SearchQuery: Hashable, Sendable {
    public struct Term: Hashable, Sendable {
        public var text: String
        public var isPhrase: Bool

        public init(_ text: String, isPhrase: Bool = false) {
            self.text = text
            self.isPhrase = isPhrase
        }
    }

    /// Every group must match; a group matches when any one of its terms does.
    public var groups: [[Term]]
    /// A page that contains any of these is not a hit.
    public var excluded: [Term]

    public init(groups: [[Term]], excluded: [Term] = []) {
        self.groups = groups
        self.excluded = excluded
    }

    public init(_ raw: String) {
        var groups: [[Term]] = []
        var excluded: [Term] = []
        var joinNext = false

        for token in Self.tokens(in: raw) {
            if !token.isPhrase, !token.isExcluded, token.text == "OR" {
                joinNext = !groups.isEmpty
                continue
            }
            let term = Term(token.text, isPhrase: token.isPhrase)
            if token.isExcluded {
                excluded.append(term)
            } else if joinNext, !groups.isEmpty {
                groups[groups.count - 1].append(term)
            } else {
                groups.append([term])
            }
            joinNext = false
        }
        self.groups = groups
        self.excluded = excluded
    }

    /// Nothing to look for: no positive terms.
    public var isEmpty: Bool { groups.isEmpty }

    /// Every positive word or phrase, in query order. Used to find the ink on a page.
    public var positiveTerms: [String] {
        groups.flatMap { $0.map(\.text) }
    }

    /// True when `text` satisfies the query, matching exactly (no tolerance).
    /// For short strings such as notebook titles.
    public func matches(_ text: String) -> Bool {
        guard !isEmpty else { return false }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let contains = { (term: Term) in text.range(of: term.text, options: options) != nil }
        return groups.allSatisfy { $0.contains(where: contains) } && !excluded.contains(where: contains)
    }

    // MARK: Tokenising

    private struct Token {
        var text: String
        var isPhrase: Bool
        var isExcluded: Bool
    }

    private static func tokens(in raw: String) -> [Token] {
        var tokens: [Token] = []
        var index = raw.startIndex

        while index < raw.endIndex {
            if raw[index].isWhitespace {
                index = raw.index(after: index)
                continue
            }

            var isExcluded = false
            if raw[index] == "-" {
                let next = raw.index(after: index)
                if next < raw.endIndex, !raw[next].isWhitespace {
                    isExcluded = true
                    index = next
                }
            }

            if isQuote(raw[index]) {
                let start = raw.index(after: index)
                let end = raw[start...].firstIndex(where: isQuote) ?? raw.endIndex
                let phrase = raw[start..<end]
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                if !phrase.isEmpty {
                    tokens.append(Token(text: phrase, isPhrase: true, isExcluded: isExcluded))
                }
                index = end < raw.endIndex ? raw.index(after: end) : end
            } else {
                let end = raw[index...].firstIndex(where: \.isWhitespace) ?? raw.endIndex
                let word = String(raw[index..<end])
                if !word.isEmpty, word != "-" {
                    tokens.append(Token(text: word, isPhrase: false, isExcluded: isExcluded))
                }
                index = end
            }
        }
        return tokens
    }

    /// Straight and curly quotes, since the iPad keyboard types curly ones.
    private static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "\u{201C}" || character == "\u{201D}"
    }
}

/// Narrows which records a search looks at.
public struct SearchFilter: Hashable, Sendable {
    public var sources: Set<PageTextSource>
    /// nil searches every notebook.
    public var notebookIDs: Set<UUID>?
    /// Only pages last edited at or after this moment; nil for any time.
    public var editedAfter: Date?

    public init(
        sources: Set<PageTextSource> = Set(PageTextSource.allCases),
        notebookIDs: Set<UUID>? = nil,
        editedAfter: Date? = nil
    ) {
        self.sources = sources
        self.notebookIDs = notebookIDs
        self.editedAfter = editedAfter
    }

    public static let all = SearchFilter()

    public var isDefault: Bool { self == .all }
}

/// The edit-date choices the search UI offers.
public enum SearchDateRange: String, CaseIterable, Hashable, Sendable {
    case anyTime, today, pastWeek, pastMonth, pastYear

    public var title: String {
        switch self {
        case .anyTime: "Any Time"
        case .today: "Today"
        case .pastWeek: "Past 7 Days"
        case .pastMonth: "Past 30 Days"
        case .pastYear: "Past Year"
        }
    }

    /// The earliest edit date that passes, relative to `now`.
    public func start(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .anyTime: nil
        case .today: calendar.startOfDay(for: now)
        case .pastWeek: calendar.date(byAdding: .day, value: -7, to: now)
        case .pastMonth: calendar.date(byAdding: .day, value: -30, to: now)
        case .pastYear: calendar.date(byAdding: .year, value: -1, to: now)
        }
    }
}
