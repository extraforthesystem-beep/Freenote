import AudioKit
import Foundation
import NoteCore
import Observation
import PencilKit
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
    private let spotlight = SpotlightIndexer()
    /// Notebook titles seen by the last indexing pass, for Spotlight entries.
    private var notebookTitles: [UUID: String] = [:]
    /// A one-line message about pages re-read because the recogniser changed;
    /// the library takes it once and shows it.
    private var pendingRecognitionNotice: String?
    /// The newest PDF text extraction for page marks; a new page or query
    /// replaces it instead of stacking another one.
    @ObservationIgnored private var pdfMarksTask: (key: PDFMarksKey, task: Task<[PageMatchMark], Never>)?

    private(set) var hits: [SearchHit] = []
    private(set) var isIndexing = false
    private(set) var indexedPages = 0
    private(set) var totalPages = 0
    private(set) var lastError: String?
    /// Sources and notebooks the library search looks at.
    var filter = SearchFilter.all
    /// The library search's edit-date choice; turned into a date at each search,
    /// so "Today" means today even in a long session.
    var dateRange = SearchDateRange.anyTime

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

        for notebook in notebooks {
            notebookTitles[notebook.id] = notebook.title
        }

        do {
            try await index.load()
        } catch {
            lastError = error.localizedDescription
        }

        // One index file write per batch of pages, not one per page.
        let batch = index
        await batch.beginDeferringWrites()
        var reReadAfterUpdate = 0
        var published: [PageSearchRecord] = []
        pages: for notebook in notebooks {
            let audio = await audioTranscripts(for: notebook.id, store: store)
            for (offset, pageID) in notebook.pageOrder.enumerated() {
                if Task.isCancelled { break pages }
                if let page = try? await store.loadPage(pageID, in: notebook.id) {
                    // A stored record from an older recogniser is re-read below;
                    // count it so the library can say what changed.
                    if let existing = await index.record(for: notebook.id, pageID: pageID),
                       existing.recognitionVersion != recognizer.recognitionVersion {
                        reReadAfterUpdate += 1
                    }
                    do {
                        if let record = try await index.update(
                            page: page,
                            in: notebook.id,
                            pageIndex: offset + 1,
                            transcriptText: AudioTranscriptIndex.text(
                                for: page,
                                clips: audio.clips,
                                transcripts: audio.transcripts
                            ),
                            using: recognizer,
                            assetsDirectory: store.assetsDirectoryURL(for: notebook.id)
                        ) {
                            published.append(record)
                        }
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
                indexedPages += 1
                if indexedPages % Self.pagesPerWrite == 0, batch === index {
                    try? await batch.flushDeferredWrites()
                }
            }
        }
        await endDeferringWrites(of: batch)
        pendingRecognitionNotice = Self.recognitionNotice(pages: reReadAfterUpdate)
        await publish(published)
        await seedSpotlightIfNeeded()
    }

    /// Whether every indexed page has been offered to system search once.
    private static let spotlightSeedKey = "noteapp.search.spotlightSeeded"

    /// A sentence for the library when a new recogniser re-read stored pages.
    private static func recognitionNotice(pages: Int) -> String? {
        guard pages > 0 else { return nil }
        return pages == 1
            ? "1 page was read again with the updated handwriting recogniser."
            : "\(pages) pages were read again with the updated handwriting recogniser."
    }

    /// The notice from the last full pass, if any; cleared so it shows once.
    func takeRecognitionNotice() -> String? {
        defer { pendingRecognitionNotice = nil }
        return pendingRecognitionNotice
    }

    /// Adds or replaces the pages' system-search entries when that is enabled.
    private func publish(_ records: [PageSearchRecord]) async {
        guard AppSettings.spotlightIndexingEnabled, !records.isEmpty else { return }
        try? await spotlight.index(records, notebookTitles: notebookTitles)
    }

    /// Publishes the whole index once, so pages recognised by an earlier build
    /// appear in system search without waiting to be edited again.
    private func seedSpotlightIfNeeded() async {
        let defaults = UserDefaults.standard
        guard AppSettings.spotlightIndexingEnabled else {
            defaults.removeObject(forKey: Self.spotlightSeedKey)
            return
        }
        guard !defaults.bool(forKey: Self.spotlightSeedKey) else { return }
        let records = await index.allRecords()
        guard !records.isEmpty else { return }
        try? await spotlight.index(records, notebookTitles: notebookTitles)
        defaults.set(true, forKey: Self.spotlightSeedKey)
    }

    /// Ends a batch of index writes. An index that `reset()` replaced
    /// meanwhile is dropped unwritten, so its records cannot come back.
    private func endDeferringWrites(of batch: SearchIndex) async {
        guard batch === index else { return }
        try? await batch.endDeferringWrites()
    }

    /// How many pages an indexing pass recognises between index file writes:
    /// few enough that a pass cut short loses little work.
    private static let pagesPerWrite = 25

    /// Re-indexes one notebook after it is closed.
    func index(notebook: NotebookManifest, store: LibraryStore) async {
        guard AppSettings.handwritingRecognitionEnabled else { return }
        notebookTitles[notebook.id] = notebook.title
        do {
            try await index.load()
        } catch {
            lastError = error.localizedDescription
        }
        let batch = index
        await batch.beginDeferringWrites()
        var published: [PageSearchRecord] = []
        let audio = await audioTranscripts(for: notebook.id, store: store)
        for (offset, pageID) in notebook.pageOrder.enumerated() {
            if Task.isCancelled { break }
            guard let page = try? await store.loadPage(pageID, in: notebook.id) else { continue }
            if let record = try? await index.update(
                page: page,
                in: notebook.id,
                pageIndex: offset + 1,
                transcriptText: AudioTranscriptIndex.text(
                    for: page,
                    clips: audio.clips,
                    transcripts: audio.transcripts
                ),
                using: recognizer,
                assetsDirectory: store.assetsDirectoryURL(for: notebook.id)
            ) {
                published.append(record)
            }
            if (offset + 1) % Self.pagesPerWrite == 0, batch === index {
                try? await batch.flushDeferredWrites()
            }
        }
        await endDeferringWrites(of: batch)
        await publish(published)
    }

    /// The clips and saved transcripts of one notebook, for adding spoken words
    /// to the pages that were written during a recording.
    private func audioTranscripts(
        for notebookID: UUID,
        store: LibraryStore
    ) async -> (clips: [AudioClip], transcripts: [UUID: Transcript]) {
        let root = NotebookAudio.audioDirectory(for: store, notebookID: notebookID)
        let clips = (try? await AudioClipStore(rootURL: root).list()) ?? []
        let stored = (try? await TranscriptStore(
            rootURL: root.appendingPathComponent("transcripts", isDirectory: true)
        ).list()) ?? []
        let transcripts = Dictionary(
            stored.compactMap { transcript in
                transcript.clipID.map { ($0, transcript) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        return (clips, transcripts)
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmed
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        var filter = filter
        filter.editedAfter = dateRange.start()
        let found = await index.search(SearchQuery(trimmed), filter: filter)
        // A newer query started while this one was reading the index.
        guard trimmed == currentQuery else { return }
        hits = found
    }

    /// The same engine, scoped to one notebook and returned to the caller instead
    /// of replacing the library-wide `hits`. Used by the in-notebook search panel.
    func search(
        _ query: String,
        in notebookID: UUID,
        sources: Set<PageTextSource> = Set(PageTextSource.allCases),
        dateRange: SearchDateRange = .anyTime
    ) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let filter = SearchFilter(sources: sources, notebookIDs: [notebookID], editedAfter: dateRange.start())
        return await index.search(SearchQuery(trimmed), filter: filter)
    }

    /// Every place on a page that matches `highlight`, in page coordinates.
    func pageMarks(
        for highlight: SearchHighlight,
        page: Page,
        strokes: [StrokeRecord],
        assetsDirectory: URL?
    ) async -> [PageMatchMark] {
        let query = SearchQuery(highlight.query)
        guard !query.isEmpty else { return [] }
        var marks: [PageMatchMark] = []
        if highlight.sources.contains(.handwriting), AppSettings.handwritingRecognitionEnabled {
            let ink = await recognizer.inkBounds(matching: query.positiveTerms, in: strokes)
            marks += ink.map { PageMatchMark(rect: $0) }
        }
        if highlight.sources.contains(.typedText) {
            marks += PageMatchLocator.typedTextMarks(for: query, in: page)
        }
        if highlight.sources.contains(.pdf) {
            marks += await pdfMarks(for: query, page: page, assetsDirectory: assetsDirectory)
        }
        return marks
    }

    /// PDF text extraction for a page's marks, one at a time: the newest page and
    /// query cancels the extraction still running, so flipping pages with a
    /// search open never stacks full extractions.
    private func pdfMarks(
        for query: SearchQuery,
        page: Page,
        assetsDirectory: URL?
    ) async -> [PageMatchMark] {
        let key = PDFMarksKey(pageID: page.id, query: query)
        if let pending = pdfMarksTask, pending.key == key {
            return await pending.task.value
        }
        pdfMarksTask?.task.cancel()
        // PDF text extraction is slow on big pages; keep it off the main actor.
        let task = Task.detached(priority: .userInitiated) {
            PageMatchLocator.pdfMarks(for: query, in: page, assetsDirectory: assetsDirectory)
        }
        pdfMarksTask = (key, task)
        let marks = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if pdfMarksTask?.key == key { pdfMarksTask = nil }
        return marks
    }

    private struct PDFMarksKey: Hashable {
        var pageID: UUID
        var query: SearchQuery
    }

    /// The words written with Apple Pencil in the search pad.
    func recognizeQuery(in drawing: PKDrawing) async -> String? {
        await recognizer.text(in: drawing)
    }

    /// True when a search that has not been superseded is waiting on the index.
    var hasCurrentQuery: Bool {
        !currentQuery.isEmpty
    }

    func clearError() {
        lastError = nil
    }

    /// All readable text on a page: typed text boxes first, then the single best
    /// reading of the handwriting. Used by the on-device AI panel, not by the
    /// search index, which keeps the broader `indexableContent`.
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

        if !page.strokes.isEmpty {
            // The stroke-to-PencilKit bridge is the expensive part, so it runs
            // off the main actor: the AI sheet is animating in while this starts.
            let strokes = page.strokes
            let recognised = await Task.detached(priority: .userInitiated) { [recognizer] in
                await recognizer.recognizedText(for: strokes)
            }.value
            if let recognised {
                let trimmed = recognised.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
            }
        }
        return parts.joined(separator: "\n")
    }

    func removeNotebook(_ notebookID: UUID) async {
        try? await index.removeNotebook(notebookID)
        try? await spotlight.removeNotebook(notebookID)
        notebookTitles[notebookID] = nil
    }

    /// Publishes every indexed page, or withdraws them all, when the Spotlight
    /// setting changes. Recognition being off means there is nothing to publish.
    func updateSpotlight(enabled: Bool) async {
        let defaults = UserDefaults.standard
        guard enabled, AppSettings.handwritingRecognitionEnabled else {
            defaults.removeObject(forKey: Self.spotlightSeedKey)
            try? await spotlight.removeAll()
            return
        }
        let records = await index.allRecords()
        guard !records.isEmpty else { return }
        try? await spotlight.index(records, notebookTitles: notebookTitles)
        defaults.set(true, forKey: Self.spotlightSeedKey)
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
        pendingRecognitionNotice = nil
        try? await spotlight.removeAll()
    }

    func removePage(_ pageID: UUID, notebookID: UUID) async {
        try? await index.remove(pageID: pageID, notebookID: notebookID)
        try? await spotlight.remove(pageID: pageID, notebookID: notebookID)
        hits.removeAll { $0.notebookID == notebookID && $0.pageID == pageID }
    }
}
