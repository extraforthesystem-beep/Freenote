import AIKit
import Foundation
import HistoryKit
import NoteCore
import Observation
import SearchKit

/// Everything the library screen needs: the store, the tree and the open notebook.
/// The files on disk are the truth; this object only mirrors them for SwiftUI.
@MainActor
@Observable
final class AppModel {
    struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    enum Location: Hashable {
        case all
        case recents
        case favourites
        case trash
        case folder(UUID)
        case textDocuments
        case whiteboards
        case studySets
    }

    /// How the library grid is ordered. Persisted so it survives a relaunch.
    enum SortOrder: String, CaseIterable, Identifiable {
        case dateModified
        case dateCreated
        case name

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateModified: "Date Modified"
            case .dateCreated: "Date Created"
            case .name: "Name"
            }
        }

        var symbol: String {
            switch self {
            case .dateModified: "clock.arrow.circlepath"
            case .dateCreated: "calendar"
            case .name: "textformat.abc"
            }
        }
    }

    /// One folder with the full path used by move menus.
    struct FolderPath: Identifiable, Hashable {
        var id: UUID
        var name: String
        /// The path from the root, separated by " / ".
        var path: String
        var depth: Int
    }

    private static let sortOrderKey = "library.sortOrder"
    private static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    let store: LibraryStore
    let search: HandwritingSearch
    let bookmarks = PageBookmarks()
    let outline = PageOutline()
    let study: StudyModel
    let textDocs: TextDocModel
    let boards: BoardModel
    let ai = AIService()
    let history: VersionHistoryStore

    var info: LibraryInfo?
    var folderTree = FolderTree()
    var notebooks: [NotebookManifest] = []
    var trashedNotebooks: [NotebookManifest] = []
    var selectedLocation: Location = .all
    var searchText = ""
    var isLoading = true
    /// Set when the library itself cannot be opened; the library shows a retry screen.
    var loadError: String?
    var notice: Notice?
    /// Notebooks on disk whose `notebook.json` could not be read.
    var unreadableNotebookCount = 0

    var sortOrder: SortOrder {
        didSet {
            guard sortOrder != oldValue else { return }
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }

    /// Open notebooks. The library is hidden while one of these is active.
    var tabs: [NotebookSession] = []
    var activeNotebookID: UUID?
    var isShowingLibrary = false
    var splitNotebookID: UUID?

    private var hasStarted = false
    private var announcedUnreadableCount = 0
    private var searchTask: Task<Void, Never>?

    var session: NotebookSession? {
        tabs.first { $0.notebookID == activeNotebookID }
    }

    var splitSession: NotebookSession? {
        tabs.first { $0.notebookID == splitNotebookID }
    }

    var isSplitView: Bool {
        splitNotebookID != nil && splitSession != nil && session != nil
    }

    init(root: URL = AppModel.defaultLibraryRoot()) {
        store = LibraryStore(root: root)
        search = HandwritingSearch(root: root)
        study = StudyModel(root: root.appendingPathComponent("StudySets", isDirectory: true))
        textDocs = TextDocModel(root: root.appendingPathComponent("TextDocs", isDirectory: true))
        boards = BoardModel(rootURL: root.appendingPathComponent("Boards", isDirectory: true))
        history = VersionHistoryStore(
            root: root.deletingLastPathComponent()
                .appendingPathComponent("History", isDirectory: true)
        )
        let stored = UserDefaults.standard.string(forKey: Self.sortOrderKey)
        sortOrder = stored.flatMap(SortOrder.init(rawValue:)) ?? .dateModified
    }

    static func defaultLibraryRoot() -> URL {
        let base: URL
        #if os(iOS)
        base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
        return base.appendingPathComponent("Library", isDirectory: true)
    }

    // MARK: - Loading

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        loadError = nil
        do {
            info = try await store.open()
            await reload()
            await purgeExpiredTrash()
            await study.load()
            await textDocs.load()
            await boards.load()
            Task {
                _ = try? await history.prune(keeping: .default)
            }
            Task {
                LibraryCovers.pruneStaleCovers(store: store)
            }
            Task {
                await search.indexAll(notebooks: notebooks, store: store)
                await search.search(searchText)
            }
        } catch {
            // A failed open is recoverable: the library shows this message with a
            // retry button instead of an empty grid.
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Re-runs the whole load after a failure.
    func retryLoad() async {
        hasStarted = false
        isLoading = true
        loadError = nil
        await start()
    }

    func reload() async {
        do {
            folderTree = try await store.loadFolderTree()
            let listing = try await store.scanNotebooks()
            let trash = try await store.scanTrash()
            notebooks = listing.manifests
            trashedNotebooks = trash.manifests
            unreadableNotebookCount = listing.unreadableCount + trash.unreadableCount
            announceUnreadableIfNeeded()
        } catch {
            notice = Notice(title: "The library could not be read", message: error.localizedDescription)
        }
    }

    /// One notice when unreadable files appear, not one on every reload.
    private func announceUnreadableIfNeeded() {
        guard unreadableNotebookCount > 0 else {
            announcedUnreadableCount = 0
            return
        }
        guard unreadableNotebookCount != announcedUnreadableCount else { return }
        announcedUnreadableCount = unreadableNotebookCount
        let count = unreadableNotebookCount
        notice = Notice(
            title: count == 1 ? "1 notebook couldn’t be read" : "\(count) notebooks couldn’t be read",
            message: "The other notebooks are fine. A damaged notebook file stays on disk untouched until it is repaired."
        )
    }

    private func purgeExpiredTrash() async {
        guard let purged = try? await store.purgeExpiredTrash(olderThan: Self.trashRetention) else { return }
        guard !purged.isEmpty else { return }
        let gone = Set(purged)
        trashedNotebooks.removeAll { gone.contains($0.id) }
    }

    // MARK: - Filtering

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !trimmedQuery.isEmpty }

    /// True while the query should span every notebook instead of just the sidebar row.
    private var searchesWholeLibrary: Bool {
        isSearching && selectedLocation != .trash
    }

    var visibleNotebooks: [NotebookManifest] {
        let query = trimmedQuery
        if selectedLocation == .trash {
            let searched = query.isEmpty
                ? trashedNotebooks
                : trashedNotebooks.filter { SearchQuery(query).matches($0.title) }
            // Newest deletion first, so the item the user just removed is on top.
            return searched.sorted {
                ($0.deletedAt ?? $0.updatedAt) > ($1.deletedAt ?? $1.updatedAt)
            }
        }

        // A search looks through the whole library; the sidebar row only shapes the
        // browsing list.
        if !query.isEmpty {
            let parsed = SearchQuery(query)
            let editedAfter = search.dateRange.start() ?? .distantPast
            return sorted(notebooks.filter { parsed.matches($0.title) && $0.updatedAt >= editedAfter })
        }

        switch selectedLocation {
        case .recents:
            // Recent always means most recently edited, whatever the grid sort is.
            return notebooks.sorted { $0.updatedAt > $1.updatedAt }.prefix(12).map { $0 }
        case .favourites:
            return sorted(notebooks.filter { folderTree.favourites.contains($0.id) })
        case .folder(let folderID):
            let containing = descendantFolderIDs(of: folderID)
            return sorted(notebooks.filter { folderTree.notebookFolder[$0.id].map(containing.contains) ?? false })
        case .textDocuments, .whiteboards, .studySets:
            return []
        case .all, .trash:
            return sorted(notebooks)
        }
    }

    private func sorted(_ list: [NotebookManifest]) -> [NotebookManifest] {
        switch sortOrder {
        case .dateModified:
            return list.sorted { $0.updatedAt > $1.updatedAt }
        case .dateCreated:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return list.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    var selectedLocationTitle: String {
        switch selectedLocation {
        case .all: "All Notebooks"
        case .recents: "Recent"
        case .favourites: "Favourites"
        case .trash: "Recently Deleted"
        case .folder(let id): folderTree.folder(withID: id)?.name ?? "Folder"
        case .textDocuments: "Text Documents"
        case .whiteboards: "Whiteboards"
        case .studySets: "Study Sets"
        }
    }

    /// True for the sidebar rows that show a different document type, not notebooks.
    var showsNotebookLibrary: Bool {
        switch selectedLocation {
        case .textDocuments, .whiteboards, .studySets: false
        case .all, .recents, .favourites, .trash, .folder: true
        }
    }

    func isFavourite(_ notebookID: UUID) -> Bool {
        folderTree.favourites.contains(notebookID)
    }

    func isOpen(_ notebookID: UUID) -> Bool {
        tabs.contains { $0.notebookID == notebookID }
    }

    func folderID(of notebook: NotebookManifest) -> UUID? {
        folderTree.notebookFolder[notebook.id]
    }
    /// The notebook's folder and all of its subfolders.
    func descendantFolderIDs(of folderID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [folderID]
        var added = true
        while added {
            added = false
            for folder in folderTree.folders where folder.parentID.map(result.contains) == true {
                if result.insert(folder.id).inserted { added = true }
            }
        }
        return result
    }

    func notebookCount(inFolder folderID: UUID) -> Int {
        let containing = descendantFolderIDs(of: folderID)
        return folderTree.notebookFolder.values.filter(containing.contains).count
    }

    func folderName(for notebookID: UUID) -> String? {
        guard let folderID = folderTree.notebookFolder[notebookID] else { return nil }
        return folderTree.folder(withID: folderID)?.name
    }

    /// Every folder as an indented full path, siblings sorted by name, so a move
    /// menu shows two "Notes" folders with their parents.
    var folderPaths: [FolderPath] {
        var result: [FolderPath] = []
        func walk(parent: UUID?, depth: Int, prefix: String) {
            guard depth < 12 else { return }
            let children = folderTree.folders
                .filter { $0.parentID == parent }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for folder in children {
                let path = prefix + folder.name
                result.append(FolderPath(id: folder.id, name: folder.name, path: path, depth: depth))
                walk(parent: folder.id, depth: depth + 1, prefix: path + " / ")
            }
        }
        walk(parent: nil, depth: 0, prefix: "")
        return result
    }

    func notebook(withID id: UUID) -> NotebookManifest? {
        notebooks.first { $0.id == id }
    }

    func pageNumber(notebookID: UUID, pageID: UUID) -> Int? {
        guard let notebook = notebooks.first(where: { $0.id == notebookID }),
              let index = notebook.pageOrder.firstIndex(of: pageID)
        else { return nil }
        return index + 1
    }

    /// Runs the library search again, e.g. after the filter changed.
    func refreshHandwritingSearch() {
        updateHandwritingSearch(searchText)
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchText = ""
        Task { await search.search("") }
    }

    // MARK: - Handwriting search

    /// Debounced entry point: one cancellable task per keystroke burst, and a
    /// result is only adopted when it still answers the current query.
    func updateHandwritingSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Task { await search.search("") }
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.search.search(trimmed)
        }
    }

    // MARK: - Maintenance

    /// Throws away the handwriting index and recognises every notebook again.
    /// With recognition switched off the index is only emptied.
    func rebuildSearchIndex() async {
        await search.reset()
        guard AppSettings.handwritingRecognitionEnabled else { return }
        await search.indexAll(notebooks: notebooks, store: store)
        if !searchText.isEmpty {
            await search.search(searchText)
        }
    }

    /// Drops every cached cover and page thumbnail, and lets the next library
    /// pass draw them again.
    ///
    /// Covers are cached twice: rendered images on disk in the library's cache
    /// folder, and in memory keyed by the notebook's `updatedAt` (so a memory
    /// entry can never outlive the content it was drawn from). The disk folder
    /// is deleted here; the page strip's in-memory thumbnails are invalidated
    /// page by page. Both are rebuilt lazily when the library or the strip next
    /// asks for an image.
    func regenerateThumbnails() async {
        let covers = store.cacheDirectoryURL.appendingPathComponent("covers", isDirectory: true)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: covers)
        }.value

        for notebook in notebooks {
            for pageID in notebook.pageOrder {
                ThumbnailCache.invalidate(notebookID: notebook.id, pageID: pageID)
            }
        }
        await reload()
    }

    func tags(for notebookID: UUID) -> [String] {
        folderTree.tags[notebookID] ?? []
    }

    func setTags(_ tags: [String], for notebook: NotebookManifest) async {
        let cleaned = Array(
            Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        ).sorted()
        do {
            try await store.setTags(cleaned, forNotebook: notebook.id)
            await reload()
        } catch {
            notice = Notice(title: "Could not save tags", message: error.localizedDescription)
        }
    }

    // MARK: - Notebooks

    func createNotebook(title: String = "Untitled Notebook") async {
        var createdID: UUID?
        do {
            let manifest = try await store.createNotebook(title: title)
            createdID = manifest.id
            // The first page follows the New Notebooks settings; a template id
            // that no longer exists in the catalog falls back to a blank page.
            let size = AppSettings.newNotebookPageSize
            _ = try await store.addPage(
                to: manifest.id,
                at: 0,
                width: size.width,
                height: size.height,
                template: AppSettings.newNotebookTemplate
            )
            // The folder link comes last: if anything above failed, the notebook
            // would otherwise be filed despite never having been built properly.
            if case .folder(let folderID) = selectedLocation {
                try await store.setFolder(folderID, forNotebook: manifest.id)
            }
            await reload()
            if let created = notebooks.first(where: { $0.id == manifest.id }) {
                await open(created)
            }
        } catch {
            if let createdID {
                await discardCreation(createdID)
            }
            notice = Notice(title: "Could not create the notebook", message: error.localizedDescription)
        }
    }

    /// Removes a half-created notebook after a failed create.
    private func discardCreation(_ notebookID: UUID) async {
        try? await store.deleteNotebook(notebookID)
        try? await store.purgeNotebook(notebookID)
        _ = try? await store.setFolder(nil, forNotebook: notebookID)
        await reload()
    }

    func importPDF(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try await PDFImporter.importPDF(at: url, into: store)
            await reload()
            if let notebook = notebooks.first(where: { $0.id == imported.id }) {
                await open(notebook)
            }
        } catch {
            notice = Notice(title: "Could not import the PDF", message: error.localizedDescription)
        }
    }

    func rename(_ notebook: NotebookManifest, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != notebook.title else { return }
        do {
            try await store.renameNotebook(notebook.id, title: trimmed)
            await reload()
        } catch {
            notice = Notice(title: "Could not rename the notebook", message: error.localizedDescription)
        }
    }

    func duplicate(_ notebook: NotebookManifest) async {
        do {
            let copy = try await store.duplicateNotebook(notebook.id)
            if let folderID = folderTree.notebookFolder[notebook.id] {
                try await store.setFolder(folderID, forNotebook: copy.id)
            }
            if isFavourite(notebook.id) {
                _ = try await store.toggleFavourite(copy.id)
            }
            let notebookTags = tags(for: notebook.id)
            if !notebookTags.isEmpty {
                try await store.setTags(notebookTags, forNotebook: copy.id)
            }
            await reload()
        } catch {
            notice = Notice(title: "Could not duplicate the notebook", message: error.localizedDescription)
        }
    }

    func delete(_ notebook: NotebookManifest) async {
        do {
            try await store.deleteNotebook(notebook.id)
            if let open = tabs.first(where: { $0.notebookID == notebook.id }) {
                closeTab(open)
            }
            await search.removeNotebook(notebook.id)
            await reload()
        } catch {
            notice = Notice(title: "Could not delete the notebook", message: error.localizedDescription)
        }
    }

    func restore(_ notebook: NotebookManifest) async {
        do {
            try await store.restoreNotebook(notebook.id)
            await reload()
        } catch {
            notice = Notice(title: "Could not restore the notebook", message: error.localizedDescription)
        }
    }

    func purge(_ notebook: NotebookManifest) async {
        do {
            try await store.purgeNotebook(notebook.id)
            LibraryCovers.removeCachedCovers(for: notebook.id, store: store)
            await reload()
        } catch {
            notice = Notice(title: "Could not permanently delete the notebook", message: error.localizedDescription)
        }
    }

    /// Empties Recently Deleted for good.
    func emptyTrash() async {
        do {
            let trashed = trashedNotebooks
            _ = try await store.emptyTrash()
            for notebook in trashed {
                LibraryCovers.removeCachedCovers(for: notebook.id, store: store)
            }
            await reload()
        } catch {
            notice = Notice(title: "Could not empty the trash", message: error.localizedDescription)
        }
    }

    func setCover(_ name: String?, for notebook: NotebookManifest) async {
        do {
            try await store.setCover(name, for: notebook.id)
            await reload()
        } catch {
            notice = Notice(title: "Could not change the cover", message: error.localizedDescription)
        }
    }

    func toggleFavourite(_ notebook: NotebookManifest) async {
        do {
            _ = try await store.toggleFavourite(notebook.id)
            await reload()
        } catch {
            notice = Notice(title: "Could not update favourites", message: error.localizedDescription)
        }
    }

    func move(_ notebook: NotebookManifest, to folderID: UUID?) async {
        do {
            try await store.setFolder(folderID, forNotebook: notebook.id)
            await reload()
        } catch {
            notice = Notice(title: "Could not move the notebook", message: error.localizedDescription)
        }
    }

    /// Moves a notebook by its id, as dropped from a card onto a sidebar folder.
    @discardableResult
    func moveNotebook(withID notebookID: UUID, to folderID: UUID?) async -> Bool {
        guard let notebook = notebook(withID: notebookID) else { return false }
        await move(notebook, to: folderID)
        return true
    }

    // MARK: - Folders

    func createFolder(named name: String, parentID: UUID?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await store.createFolder(name: trimmed, parentID: parentID)
            await reload()
        } catch {
            notice = Notice(title: "Could not create the folder", message: error.localizedDescription)
        }
    }

    func renameFolder(_ folder: Folder, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        do {
            try await store.renameFolder(folder.id, name: trimmed)
            await reload()
        } catch {
            notice = Notice(title: "Could not rename the folder", message: error.localizedDescription)
        }
    }

    func setFolderAppearance(
        _ folder: Folder,
        colorName: String?,
        iconName: String?
    ) async {
        do {
            try await store.setFolderAppearance(
                folder.id,
                colorName: colorName,
                iconName: iconName
            )
            await reload()
        } catch {
            notice = Notice(title: "Could not change the folder", message: error.localizedDescription)
        }
    }

    func moveFolder(_ folder: Folder, to parentID: UUID?) async {
        do {
            try await store.moveFolder(folder.id, to: parentID)
            await reload()
        } catch {
            notice = Notice(title: "Could not move the folder", message: error.localizedDescription)
        }
    }

    func deleteFolder(_ folder: Folder) async {
        do {
            try await store.deleteFolder(folder.id)
            if selectedLocation == .folder(folder.id) {
                selectedLocation = .all
            }
            await reload()
        } catch {
            notice = Notice(title: "Could not delete the folder", message: error.localizedDescription)
        }
    }

    // MARK: - Notebook session

    /// Opens `notebook`; with `highlighting`, the page marks that search's matches.
    func open(_ notebook: NotebookManifest, pageID: UUID? = nil, highlighting query: SearchHighlight? = nil) async {
        if let existing = tabs.first(where: { $0.notebookID == notebook.id }) {
            existing.searchHighlight = query
            activeNotebookID = existing.notebookID
            isShowingLibrary = false
            // Page one is a valid target: a search hit there used to be ignored.
            if let pageID, let index = existing.manifest.pageOrder.firstIndex(of: pageID) {
                await existing.goToPage(index)
            }
            return
        }

        // With tabs off, the notebook replaces the one on screen. The close path
        // saves the outgoing page first, so nothing in it is lost.
        if !AppSettings.openDocumentsAsNewTabs,
           let active = session,
           active.notebookID != notebook.id {
            await active.flushPendingSave()
            closeTab(active)
        }

        do {
            let snapshot = try await store.loadNotebook(notebook.id)
            let newSession = NotebookSession(store: store, snapshot: snapshot, history: history)
            newSession.onPageDeleted = { [weak self] pageID in
                guard let self else { return }
                Task { await self.search.removePage(pageID, notebookID: notebook.id) }
            }
            newSession.searchHighlight = query
            tabs.append(newSession)
            activeNotebookID = newSession.notebookID
            isShowingLibrary = false

            // A requested page wins; otherwise reopen where the user stopped reading.
            let requested = pageID.flatMap { snapshot.manifest.pageOrder.firstIndex(of: $0) }
            let lastPage = max(0, snapshot.manifest.pageOrder.count - 1)
            let target = requested ?? min(max(0, newSession.lastVisitedPageIndex), lastPage)
            await newSession.loadPage(at: target)

            if !snapshot.orphanPageIDs.isEmpty || !snapshot.missingPageIDs.isEmpty {
                notice = Notice(
                    title: "Some pages needed attention",
                    message: "\(snapshot.orphanPageIDs.count) page file(s) were not listed and \(snapshot.missingPageIDs.count) listed page(s) were missing. Nothing was deleted."
                )
            }
        } catch {
            notice = Notice(title: "Could not open the notebook", message: error.localizedDescription)
        }
    }

    func activateTab(_ notebookID: UUID) {
        activeNotebookID = notebookID
        isShowingLibrary = false
    }

    /// Shows the library. The active notebook's pending page is saved before the
    /// grid is reloaded, so the card metadata is never a keystroke behind.
    func showLibrary() {
        let active = session
        isShowingLibrary = true
        guard let active else { return }
        Task {
            await active.flushPendingSave()
            await reload()
        }
    }

    func showActiveTab() {
        if session != nil {
            isShowingLibrary = false
        }
    }

    func toggleSplit(with notebookID: UUID) {
        splitNotebookID = splitNotebookID == notebookID ? nil : notebookID
    }

    func closeSplit() {
        splitNotebookID = nil
    }

    func closeTab(_ closing: NotebookSession) {
        tabs.removeAll { $0.notebookID == closing.notebookID }
        if splitNotebookID == closing.notebookID {
            splitNotebookID = nil
        }
        if activeNotebookID == closing.notebookID {
            activeNotebookID = tabs.first(where: { $0.notebookID != splitNotebookID })?.notebookID
                ?? tabs.first?.notebookID
            if activeNotebookID == splitNotebookID {
                splitNotebookID = nil
            }
        }
        if tabs.isEmpty {
            isShowingLibrary = true
        }
        Task {
            // Persist the last page and stop any recording before the notebook
            // leaves the session list.
            await closing.flushPendingSave()
            await closing.audio.stopRecording()
            await reload()
            await search.index(notebook: closing.manifest, store: store)
            if !searchText.isEmpty {
                await search.search(searchText)
            }
        }
    }

    func closeNotebook() {
        guard let closing = session else { return }
        closeTab(closing)
    }

    /// Closes every open notebook after saving the page each one was showing.
    func closeAllTabs() async {
        let closing = tabs
        tabs.removeAll()
        activeNotebookID = nil
        splitNotebookID = nil
        isShowingLibrary = true
        for tab in closing {
            await tab.flushPendingSave()
            await tab.audio.stopRecording()
        }
        await reload()
    }
}
