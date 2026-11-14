import Foundation
import Observation

/// The bookmark file version this build writes and reads. File scope, so the
/// off-main reader can use it: a static member of the `@MainActor` type below
/// would be main-actor isolated.
private nonisolated let pageBookmarkFileVersion = 1

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

    nonisolated struct Entry: Codable {
        var pageID: UUID
        var title: String?
        var createdAt: Date
    }

    nonisolated struct FileContents: Codable {
        /// Bumped only if the bookmark file's shape changes; a newer file is
        /// ignored rather than partly read.
        var version: Int
        var bookmarks: [Entry]
    }

    private static let legacyDefaultsKey = "noteapp.pageBookmarks.v1"

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
    ///
    /// The files are read and decoded off the main actor: there is one
    /// `bookmarks.json` per notebook, and decoding all of them on the main actor
    /// held up the first library frame. A notebook with no file is deliberately
    /// left out of the cache, so `bookmarks(for:)` still migrates the old
    /// UserDefaults list on first use and writes the file exactly as before.
    func prepare(notebookIDs: [UUID]) async {
        let missing = notebookIDs.filter { cache[$0] == nil }
        if !missing.isEmpty {
            let root = root
            let loaded = await Task.detached(priority: .utility) { () -> [UUID: [Bookmark]] in
                var result: [UUID: [Bookmark]] = [:]
                for notebookID in missing {
                    let url = Self.fileURL(root: root, notebookID: notebookID)
                    guard let data = try? Data(contentsOf: url) else { continue }
                    result[notebookID] = Self.decode(data, notebookID: notebookID)
                }
                return result
            }.value
            for (notebookID, bookmarks) in loaded where cache[notebookID] == nil {
                cache[notebookID] = bookmarks
            }
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
            // Already loaded, by `prepare` or by an earlier read: do not touch
            // the file again on the main actor.
            if let cached = cache[notebookID] {
                byNotebook[notebookID] = cached
                continue
            }
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
        Self.fileURL(root: root, notebookID: notebookID)
    }

    /// The same path, callable from the off-main reader.
    nonisolated private static func fileURL(root: URL, notebookID: UUID) -> URL {
        root.appendingPathComponent("notebooks", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("bookmarks.json")
    }

    private func readFile(at url: URL, notebookID: UUID) -> [Bookmark] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return Self.decode(data, notebookID: notebookID)
    }

    /// Decodes one bookmark file with the on-disk format and version rule
    /// unchanged. Separate from the main actor so the launch pass can run it in
    /// a detached task.
    nonisolated private static func decode(_ data: Data, notebookID: UUID) -> [Bookmark] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(FileContents.self, from: data),
              file.version <= pageBookmarkFileVersion
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
            version: pageBookmarkFileVersion,
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
