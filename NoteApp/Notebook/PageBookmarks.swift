import Foundation
import Observation

/// App-side page bookmarks with an optional name.
///
/// They are stored in `notebooks/<id>/bookmarks.json`, next to the notebook but
/// outside `notebook.json`, so the document format stays ink-only while a pin
/// still travels with its notebook. Bookmarks written by older builds live in
/// `UserDefaults` under `noteapp.pageBookmarks.v1`; the first touch of a
/// notebook migrates them to the file and never removes the old data, so a
/// build without this code can still read them.
@MainActor
@Observable
final class PageBookmarks {
    struct Bookmark: Identifiable, Hashable, Sendable {
        let notebookID: UUID
        let pageID: UUID
        var title: String?
        var createdAt: Date

        var id: String { "\(notebookID.uuidString)/\(pageID.uuidString)" }
    }

    private struct Entry: Codable {
        var pageID: UUID
        var title: String?
        var createdAt: Date
    }

    private struct FileContents: Codable {
        /// Bumped only if the bookmark file's shape changes; a newer file is
        /// ignored rather than partly read.
        var version: Int
        var bookmarks: [Entry]
    }

    private static let legacyDefaultsKey = "noteapp.pageBookmarks.v1"
    private static let fileVersion = 1

    private let root: URL
    /// Page ids per notebook from the pre-file key. Kept as-is: it is a
    /// migration source, never rewritten or deleted.
    private var legacy: [String: Set<String>] = [:]
    private var cache: [UUID: [Bookmark]] = [:]
    private var allCache: [Bookmark]?

    init(root: URL, defaults: UserDefaults = .standard) {
        self.root = root
        guard let data = defaults.data(forKey: Self.legacyDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data)
        else { return }
        legacy = decoded
    }

    /// Loads (and, where the old UserDefaults key has pages, migrates) every
    /// notebook's bookmarks once. View bodies then only read the cache.
    func prepare(notebookIDs: [UUID]) {
        for notebookID in notebookIDs where cache[notebookID] == nil {
            _ = bookmarks(for: notebookID)
        }
        _ = allBookmarks
    }

    // MARK: - Reading

    func isBookmarked(notebookID: UUID, pageID: UUID) -> Bool {
        bookmarks(for: notebookID).contains { $0.pageID == pageID }
    }

    func bookmarkedPageIDs(notebookID: UUID) -> Set<UUID> {
        Set(bookmarks(for: notebookID).map(\.pageID))
    }

    func bookmark(notebookID: UUID, pageID: UUID) -> Bookmark? {
        bookmarks(for: notebookID).first { $0.pageID == pageID }
    }

    func bookmarks(for notebookID: UUID) -> [Bookmark] {
        if let cached = cache[notebookID] { return cached }
        let url = fileURL(for: notebookID)
        // A file of any age wins over the legacy key, even when it is empty:
        // after a removal the old UserDefaults list must not come back.
        let stored: [Bookmark]
        if FileManager.default.fileExists(atPath: url.path) {
            stored = readFile(at: url, notebookID: notebookID)
        } else {
            stored = migratedBookmarks(for: notebookID)
            if !stored.isEmpty { write(stored, notebookID: notebookID) }
        }
        cache[notebookID] = stored
        return stored
    }

    /// Every bookmark in the library, newest first. Reads the notebook folders
    /// once, then stays cached until the next change.
    var allBookmarks: [Bookmark] {
        if let allCache { return allCache }
        var byNotebook: [UUID: [Bookmark]] = [:]
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: notebooksDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for folder in folders {
            guard let notebookID = UUID(uuidString: folder.lastPathComponent) else { continue }
            let url = folder.appendingPathComponent("bookmarks.json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            byNotebook[notebookID] = readFile(at: url, notebookID: notebookID)
        }
        // Notebooks touched in this session before their file was written, and
        // legacy bookmarks whose notebook has not been opened since the update.
        for (notebookID, list) in cache where byNotebook[notebookID] == nil {
            byNotebook[notebookID] = list
        }
        for (key, pageIDs) in legacy {
            guard let notebookID = UUID(uuidString: key),
                  byNotebook[notebookID] == nil,
                  FileManager.default.fileExists(atPath: notebookDirectory(notebookID).path)
            else { continue }
            byNotebook[notebookID] = pageIDs.compactMap(UUID.init(uuidString:)).map {
                Bookmark(
                    notebookID: notebookID,
                    pageID: $0,
                    title: nil,
                    createdAt: .distantPast
                )
            }
        }
        let all = byNotebook.values.flatMap { $0 }.sorted { $0.createdAt > $1.createdAt }
        allCache = all
        return all
    }

    // MARK: - Writing

    /// Adds the page when it is not bookmarked and removes it when it is.
    func toggle(notebookID: UUID, pageID: UUID) {
        var list = bookmarks(for: notebookID)
        if let index = list.firstIndex(where: { $0.pageID == pageID }) {
            list.remove(at: index)
        } else {
            list.append(Bookmark(notebookID: notebookID, pageID: pageID, title: nil, createdAt: Date()))
        }
        write(list, notebookID: notebookID)
    }

    /// Bookmarks the page, or renames an existing bookmark. An empty name
    /// removes the name but keeps the pin.
    func setTitle(_ title: String?, notebookID: UUID, pageID: UUID) {
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (cleaned?.isEmpty ?? true) ? nil : cleaned
        var list = bookmarks(for: notebookID)
        if let index = list.firstIndex(where: { $0.pageID == pageID }) {
            guard list[index].title != name else { return }
            list[index].title = name
        } else {
            list.append(Bookmark(notebookID: notebookID, pageID: pageID, title: name, createdAt: Date()))
        }
        write(list, notebookID: notebookID)
    }

    func removePage(_ pageID: UUID, notebookID: UUID) {
        var list = bookmarks(for: notebookID)
        guard list.contains(where: { $0.pageID == pageID }) else { return }
        list.removeAll { $0.pageID == pageID }
        write(list, notebookID: notebookID)
    }

    // MARK: - Files

    private var notebooksDirectory: URL {
        root.appendingPathComponent("notebooks", isDirectory: true)
    }

    private func notebookDirectory(_ notebookID: UUID) -> URL {
        notebooksDirectory.appendingPathComponent(notebookID.uuidString.lowercased(), isDirectory: true)
    }

    private func fileURL(for notebookID: UUID) -> URL {
        notebookDirectory(notebookID).appendingPathComponent("bookmarks.json")
    }

    private func readFile(at url: URL, notebookID: UUID) -> [Bookmark] {
        guard let data = try? Data(contentsOf: url),
              let file = try? Self.decoder.decode(FileContents.self, from: data),
              file.version <= Self.fileVersion
        else { return [] }
        return file.bookmarks.map {
            Bookmark(notebookID: notebookID, pageID: $0.pageID, title: $0.title, createdAt: $0.createdAt)
        }
    }

    private func migratedBookmarks(for notebookID: UUID) -> [Bookmark] {
        // `Set` has no order, so a migration is ordered by page id: the same
        // input always writes the same file.
        let pageIDs = (legacy[notebookID.uuidString] ?? [])
            .compactMap(UUID.init(uuidString:))
            .sorted { $0.uuidString < $1.uuidString }
        return pageIDs.map {
            Bookmark(notebookID: notebookID, pageID: $0, title: nil, createdAt: Date())
        }
    }

    private func write(_ list: [Bookmark], notebookID: UUID) {
        cache[notebookID] = list
        allCache = nil
        let file = FileContents(
            version: Self.fileVersion,
            bookmarks: list.map { Entry(pageID: $0.pageID, title: $0.title, createdAt: $0.createdAt) }
        )
        guard let data = try? Self.encoder.encode(file) else { return }
        try? data.write(to: fileURL(for: notebookID), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
