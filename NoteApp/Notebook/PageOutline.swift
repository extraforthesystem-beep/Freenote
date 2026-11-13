import Foundation
import Observation

/// User-visible page titles, kept beside the notebook file like bookmarks so
/// the document format stays ink-only.
@MainActor
@Observable
final class PageOutline {
    private static let defaultsKey = "noteapp.pageOutline.v1"
    private var titles: [String: [String: String]] = [:]

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return }
        titles = decoded
    }

    func title(notebookID: UUID, pageID: UUID) -> String? {
        titles[notebookID.uuidString]?[pageID.uuidString]
    }

    func setTitle(_ title: String, notebookID: UUID, pageID: UUID) {
        let notebookKey = notebookID.uuidString
        let pageKey = pageID.uuidString
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            titles[notebookKey]?.removeValue(forKey: pageKey)
            if titles[notebookKey]?.isEmpty == true {
                titles.removeValue(forKey: notebookKey)
            }
        } else {
            var pages = titles[notebookKey] ?? [:]
            pages[pageKey] = cleaned
            titles[notebookKey] = pages
        }
        save()
    }

    func removePage(_ pageID: UUID, notebookID: UUID) {
        let notebookKey = notebookID.uuidString
        titles[notebookKey]?.removeValue(forKey: pageID.uuidString)
        if titles[notebookKey]?.isEmpty == true {
            titles.removeValue(forKey: notebookKey)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(titles) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
