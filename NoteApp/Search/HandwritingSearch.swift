import Foundation
import NoteCore
import Observation
import SearchKit

/// Owns the handwriting index and the one recogniser the app uses.
@MainActor
@Observable
final class HandwritingSearch {
    /// Replaced by `reset()`, so the index actor can be dropped and rebuilt.
    private var index: SearchIndex
    /// The folder the index file lives in.
    private let indexRoot: URL
    private let recognizer = PencilKitRecognizer()

    private(set) var hits: [SearchHit] = []
    private(set) var isIndexing = false
    private(set) var indexedPages = 0
    private(set) var totalPages = 0
    private(set) var lastError: String?

    /// The query the newest `search(_:)` call was asked to answer. A result whose
    /// query is no longer the current one is dropped, so a slow older search can
    /// never overwrite the hits for what the user is typing now.
    private var currentQuery = ""

    init(root: URL) {
        let indexRoot = root.appendingPathComponent("cache", isDirectory: true)
        self.indexRoot = indexRoot
        self.index = SearchIndex(root: indexRoot)
    }

    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(indexedPages) / Double(totalPages)
    }

    /// Walks the library and recognises only pages whose ink or recogniser version changed.
    func indexAll(notebooks: [NotebookManifest], store: LibraryStore) async {
        guard AppSettings.handwritingRecognitionEnabled else { return }
        guard !isIndexing else { return }
        isIndexing = true
        lastError = nil
        indexedPages = 0
        totalPages = notebooks.reduce(0) { $0 + $1.pageOrder.count }
        defer { isIndexing = false }

        do {
            try await index.load()
        } catch {
            lastError = error.localizedDescription
        }

        for notebook in notebooks {
            for (offset, pageID) in notebook.pageOrder.enumerated() {
                if Task.isCancelled { return }
                if let page = try? await store.loadPage(pageID, in: notebook.id) {
                    do {
                        _ = try await index.update(
                            page: page,
                            in: notebook.id,
                            pageIndex: offset + 1,
                            using: recognizer,
                            assetsDirectory: store.assetsDirectoryURL(for: notebook.id)
                        )
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
                indexedPages += 1
            }
        }
    }

    /// Re-indexes one notebook after it is closed.
    func index(notebook: NotebookManifest, store: LibraryStore) async {
        guard AppSettings.handwritingRecognitionEnabled else { return }
        do {
            try await index.load()
        } catch {
            lastError = error.localizedDescription
        }
        for (offset, pageID) in notebook.pageOrder.enumerated() {
            if Task.isCancelled { return }
            guard let page = try? await store.loadPage(pageID, in: notebook.id) else { continue }
            try? await index.update(
                page: page,
                in: notebook.id,
                pageIndex: offset + 1,
                using: recognizer,
                assetsDirectory: store.assetsDirectoryURL(for: notebook.id)
            )
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmed
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        let found = await index.search(trimmed)
        // A newer query started while this one was reading the index.
        guard trimmed == currentQuery else { return }
        hits = found
    }

    /// The same engine, scoped to one notebook and returned to the caller instead
    /// of replacing the library-wide `hits`. Used by the in-notebook search panel.
    func search(_ query: String, in notebookID: UUID) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await index.search(trimmed, in: notebookID)
    }

    /// True when a search that has not been superseded is waiting on the index.
    var hasCurrentQuery: Bool {
        !currentQuery.isEmpty
    }

    func clearError() {
        lastError = nil
    }

    /// All readable text on a page: typed text boxes first, then recognised
    /// handwriting. Used by the on-device AI panel, not by the search index.
    func noteText(for page: Page) async -> String {
        var parts: [String] = []
        let typed = page.elements.compactMap { element -> String? in
            let text: String
            switch element.content {
            case let .text(value, _, _, _): text = value
            case let .stickyNote(value, _): text = value
            default: return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        parts.append(contentsOf: typed)

        if !page.strokes.isEmpty,
           let recognised = await recognizer.text(for: page.strokes) {
            let trimmed = recognised.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.joined(separator: "\n")
    }

    func removeNotebook(_ notebookID: UUID) async {
        try? await index.removeNotebook(notebookID)
    }

    /// Empties the index: the persisted file is removed and the actor is
    /// replaced, so the dropped records cannot be written back by the next
    /// update. Search hits are cleared with it.
    func reset() async {
        let fileManager = FileManager.default
        // The index writes temporaries next to its file; both go.
        if let names = try? fileManager.contentsOfDirectory(atPath: indexRoot.path) {
            for name in names where name.hasPrefix("search-index") {
                try? fileManager.removeItem(at: indexRoot.appendingPathComponent(name))
            }
        }
        index = SearchIndex(root: indexRoot)
        hits = []
        indexedPages = 0
        totalPages = 0
        lastError = nil
    }

    func removePage(_ pageID: UUID, notebookID: UUID) async {
        try? await index.remove(pageID: pageID, notebookID: notebookID)
        hits.removeAll { $0.notebookID == notebookID && $0.pageID == pageID }
    }
}
