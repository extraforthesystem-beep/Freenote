import Foundation
import Observation

/// The pages written on most recently, across every notebook, for the
/// library's Continue rail.
///
/// This is browsing state, not document data: it lives in `UserDefaults`, and
/// the notebook and page files remain the truth. An entry whose notebook or
/// page no longer exists is skipped by the rail.
@MainActor
@Observable
final class PageRecents {
    struct Entry: Codable, Identifiable, Hashable, Sendable {
        let notebookID: UUID
        let pageID: UUID
        var writtenAt: Date

        var id: String { "\(notebookID.uuidString)/\(pageID.uuidString)" }
    }

    private static let defaultsKey = "noteapp.pageRecents.v1"
    /// Enough for the rail and a little history; the oldest fall off.
    private static let limit = 40

    private let defaults: UserDefaults
    private(set) var entries: [Entry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        entries = Array(decoded.prefix(Self.limit))
    }

    /// Records a write to `pageID`, newest first. One page only ever appears
    /// once, so the rail lists distinct pages rather than recent keystrokes.
    /// Writing on the page already at the front changes nothing.
    func record(notebookID: UUID, pageID: UUID, at date: Date = Date()) {
        let entry = Entry(notebookID: notebookID, pageID: pageID, writtenAt: date)
        guard entries.first?.id != entry.id else { return }
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    /// Forgets pages of notebooks that are gone, so the rail does not keep
    /// resolving missing ids.
    func prune(keepingNotebookIDs notebookIDs: Set<UUID>) {
        let kept = entries.filter { notebookIDs.contains($0.notebookID) }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
