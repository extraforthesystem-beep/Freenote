import Foundation

/// Reads a page number typed into the find bar or the Go to Page sheet.
nonisolated enum PageNumberQuery {
    /// The 1-based page for a pure page-number query, or nil.
    ///
    /// Accepts `12`, `p12`, `p.12`, `page 12` and `pg 12`, ignoring case and
    /// surrounding space. A query with other words, page 0 or a page past the
    /// end is not a page query.
    static func page(in query: String, pageCount: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        var rest = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()[...]
        for keyword in ["page", "pg", "p"] where rest.hasPrefix(keyword) {
            rest = rest.dropFirst(keyword.count)
            break
        }
        rest = rest.drop(while: { $0 == "." || $0.isWhitespace })
        guard !rest.isEmpty,
              rest.allSatisfy({ $0.isNumber }),
              let value = Int(rest),
              (1...pageCount).contains(value)
        else { return nil }
        return value
    }
}
