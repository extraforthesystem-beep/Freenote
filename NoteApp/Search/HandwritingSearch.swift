import Foundation
import NoteCore
import Observation
import SearchKit

/// Owns the handwriting index and the one recogniser the app uses.
@MainActor
@Observable
final class HandwritingSearch {
    private let index: SearchIndex
    private let recognizer = PencilKitRecognizer()

    private(set) var hits: [SearchHit] = []
    private(set) var isIndexing = false
    private(set) var indexedPages = 0
    private(set) var totalPages = 0
    private(set) var lastError: String?

    init(root: URL) {
        index = SearchIndex(root: root.appendingPathComponent("cache", isDirectory: true))
    }

    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(indexedPages) / Double(totalPages)
    }

    /// Walks the library and recognises only pages whose ink or recogniser version changed.
    func indexAll(notebooks: [NotebookManifest], store: LibraryStore) async {
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
            for pageID in notebook.pageOrder {
                if Task.isCancelled { return }
                if let page = try? await store.loadPage(pageID, in: notebook.id) {
                    do {
                        _ = try await index.update(page: page, in: notebook.id, using: recognizer)
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
        do {
            try await index.load()
        } catch {
            lastError = error.localizedDescription
        }
        for pageID in notebook.pageOrder {
            if Task.isCancelled { return }
            guard let page = try? await store.loadPage(pageID, in: notebook.id) else { continue }
            try? await index.update(page: page, in: notebook.id, using: recognizer)
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        hits = await index.search(trimmed)
    }

    func removeNotebook(_ notebookID: UUID) async {
        try? await index.removeNotebook(notebookID)
    }

    func removePage(_ pageID: UUID, notebookID: UUID) async {
        try? await index.remove(pageID: pageID, notebookID: notebookID)
        hits.removeAll { $0.notebookID == notebookID && $0.pageID == pageID }
    }
}
