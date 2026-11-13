import Foundation
import Observation

/// App-side page bookmarks. Kept out of the notebook file so the document format
/// stays ink-only; this is a view preference like a reading position.
@MainActor
@Observable
final class PageBookmarks {
    private static let defaultsKey = "noteapp.pageBookmarks.v1"

    private var pages: [String: Set<String>] = [:]

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data)
        else { return }
        pages = decoded
    }

    func isBookmarked(notebookID: UUID, pageID: UUID) -> Bool {
        pages[notebookID.uuidString]?.contains(pageID.uuidString) ?? false
    }

    func toggle(notebookID: UUID, pageID: UUID) {
        let notebookKey = notebookID.uuidString
        let pageKey = pageID.uuidString
        var set = pages[notebookKey] ?? []
        if set.contains(pageKey) {
            set.remove(pageKey)
        } else {
            set.insert(pageKey)
        }
        if set.isEmpty {
            pages.removeValue(forKey: notebookKey)
        } else {
            pages[notebookKey] = set
        }
        save()
    }

    func bookmarkedPageIDs(notebookID: UUID) -> Set<UUID> {
        Set((pages[notebookID.uuidString] ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
