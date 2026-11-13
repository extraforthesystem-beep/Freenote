import Foundation
import NoteCore

/// Splits a search field's text into `tag:` filters and the rest.
///
/// `tag:work notes` asks for notebooks tagged "work" whose text contains
/// "notes"; `tag:work` alone is a filter, not a search. Tags are a second axis
/// over folders (04 #5): they narrow the library and the search, and never
/// replace either.
struct TagQuery: Equatable {
    var tags: [String] = []
    var text: String = ""

    init(_ raw: String) {
        var words: [String] = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            let word = String(token)
            if word.count > 4, word.lowercased().hasPrefix("tag:") {
                let tag = String(word.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty { tags.append(tag) }
            } else {
                words.append(word)
            }
        }
        text = words.joined(separator: " ")
    }

    /// The tags, lowercased, for a case-insensitive comparison with the stored
    /// labels.
    var tagKeys: Set<String> {
        Set(tags.map { $0.lowercased() })
    }

    /// A notebook satisfies the query when it carries every requested tag.
    func matches(notebookTags: [String]) -> Bool {
        let keys = tagKeys
        guard !keys.isEmpty else { return true }
        return keys.isSubset(of: Set(notebookTags.map { $0.lowercased() }))
    }
}

/// One tag row in the library sidebar: its label and how many notebooks carry
/// it. Prefixes are collapsed case-insensitively so "Work" and "work" count as
/// one row; the first spelling seen is the one shown.
struct TagSummary: Identifiable, Hashable {
    let key: String
    let name: String
    let count: Int

    var id: String { key }

    static func summaries(notebooks: [NotebookManifest], tags: (UUID) -> [String]) -> [TagSummary] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for notebook in notebooks {
            // A notebook that carries the same label twice (by case) counts once.
            var seen: Set<String> = []
            for tag in tags(notebook.id) {
                let key = tag.lowercased()
                guard seen.insert(key).inserted else { continue }
                counts[key, default: 0] += 1
                if names[key] == nil { names[key] = tag }
            }
        }
        return counts
            .map { TagSummary(key: $0.key, name: names[$0.key] ?? $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
