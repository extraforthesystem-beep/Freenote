import Foundation
import NoteCore
import Observation

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
        case favourites
        case trash
        case folder(UUID)
    }

    let store: LibraryStore
    let search: HandwritingSearch

    var info: LibraryInfo?
    var folderTree = FolderTree()
    var notebooks: [NotebookManifest] = []
    var trashedNotebooks: [NotebookManifest] = []
    var selectedLocation: Location = .all
    var searchText = ""
    var isLoading = true
    var session: NotebookSession?
    var notice: Notice?

    init(root: URL = AppModel.defaultLibraryRoot()) {
        store = LibraryStore(root: root)
        search = HandwritingSearch(root: root)
    }

    static func defaultLibraryRoot() -> URL {
        let base: URL
        #if os(iOS)
        base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoteApp", isDirectory: true)
        #endif
        return base.appendingPathComponent("Library", isDirectory: true)
    }

    // MARK: - Loading

    func start() async {
        guard isLoading else { return }
        do {
            info = try await store.open()
            await reload()
            Task {
                await search.indexAll(notebooks: notebooks, store: store)
                await search.search(searchText)
            }
        } catch {
            notice = Notice(title: "The library could not be opened", message: error.localizedDescription)
        }
        isLoading = false
    }

    func reload() async {
        do {
            folderTree = try await store.loadFolderTree()
            notebooks = try await store.listNotebooks()
            trashedNotebooks = try await store.listTrash()
        } catch {
            notice = Notice(title: "The library could not be read", message: error.localizedDescription)
        }
    }

    // MARK: - Filtering

    var visibleNotebooks: [NotebookManifest] {
        let filtered: [NotebookManifest]
        switch selectedLocation {
        case .all:
            filtered = notebooks
        case .favourites:
            filtered = notebooks.filter { folderTree.favourites.contains($0.id) }
        case .trash:
            filtered = trashedNotebooks
        case .folder(let folderID):
            filtered = notebooks.filter { folderTree.notebookFolder[$0.id] == folderID }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty
            ? filtered
            : filtered.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return searched.sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedLocationTitle: String {
        switch selectedLocation {
        case .all: "All Notebooks"
        case .favourites: "Favourites"
        case .trash: "Recently Deleted"
        case .folder(let id): folderTree.folder(withID: id)?.name ?? "Folder"
        }
    }

    func isFavourite(_ notebookID: UUID) -> Bool {
        folderTree.favourites.contains(notebookID)
    }

    func folderName(for notebookID: UUID) -> String? {
        guard let folderID = folderTree.notebookFolder[notebookID] else { return nil }
        return folderTree.folder(withID: folderID)?.name
    }

    func notebook(withID id: UUID) -> NotebookManifest? {
        notebooks.first { $0.id == id }
    }

    func pageNumber(notebookID: UUID, pageID: UUID) -> Int? {
        guard let notebook = notebook(withID: notebookID),
              let index = notebook.pageOrder.firstIndex(of: pageID)
        else { return nil }
        return index + 1
    }

    func updateHandwritingSearch(_ query: String) async {
        await search.search(query)
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
        do {
            let manifest = try await store.createNotebook(title: title)
            if case .folder(let folderID) = selectedLocation {
                try await store.setFolder(folderID, forNotebook: manifest.id)
            }
            _ = try await store.addPage(
                to: manifest.id,
                at: 0,
                width: PageDefaults.width,
                height: PageDefaults.height,
                template: PageDefaults.blank
            )
            await reload()
            if let created = notebooks.first(where: { $0.id == manifest.id }) {
                await open(created)
            }
        } catch {
            notice = Notice(title: "Could not create the notebook", message: error.localizedDescription)
        }
    }

    func importPDF(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try await PDFImporter.importPDF(at: url, into: store)
            await reload()
            if let notebook = notebook(withID: imported.id) {
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

    func delete(_ notebook: NotebookManifest) async {
        do {
            try await store.deleteNotebook(notebook.id)
            if session?.notebookID == notebook.id {
                closeNotebook()
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
            await reload()
        } catch {
            notice = Notice(title: "Could not permanently delete the notebook", message: error.localizedDescription)
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

    func open(_ notebook: NotebookManifest, pageID: UUID? = nil) async {
        do {
            let snapshot = try await store.loadNotebook(notebook.id)
            let newSession = NotebookSession(store: store, snapshot: snapshot)
            newSession.onPageDeleted = { [weak self] pageID in
                guard let self else { return }
                Task { await self.search.removePage(pageID, notebookID: notebook.id) }
            }
            session = newSession
            await newSession.loadPage(at: 0)
            if let pageID,
               let index = snapshot.manifest.pageOrder.firstIndex(of: pageID),
               index > 0 {
                await newSession.goToPage(index)
            }
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

    func closeNotebook() {
        guard let closing = session else { return }
        session = nil
        Task {
            await closing.commitPendingSave()
            await reload()
            await search.index(notebook: closing.manifest, store: store)
            if !searchText.isEmpty {
                await search.search(searchText)
            }
        }
    }
}

enum PageDefaults {
    static let width: Double = 595  // A4 at 72 dpi
    static let height: Double = 842
    static let blank = PageTemplate.blank
}

/// One open notebook: the current page, its save state and page operations.
@MainActor
@Observable
final class NotebookSession {
    let store: LibraryStore
    let assetsDirectory: URL?
    var notebookID: UUID { manifest.id }
    private(set) var manifest: NotebookManifest
    private(set) var page: Page?
    private(set) var pageIndex = 0
    private(set) var isLoadingPage = false
    private(set) var isSaving = false
    private(set) var isApplyingTemplate = false
    private(set) var loadError: String?
    /// Bumped after an edit so the current page's thumbnail re-renders.
    private(set) var revision = 0

    private var saveTask: Task<Void, Never>?
    private var pendingPage: Page?
    /// Called after a page file is deleted, so its search record can go too.
    var onPageDeleted: ((UUID) -> Void)?

    init(store: LibraryStore, snapshot: LibraryStore.NotebookSnapshot) {
        self.store = store
        self.assetsDirectory = store.assetsDirectoryURL(for: snapshot.manifest.id)
        self.manifest = snapshot.manifest
    }

    var pageCount: Int { manifest.pageOrder.count }
    var currentPageNumber: Int { min(pageIndex + 1, pageCount) }

    func loadPage(at index: Int) async {
        guard !manifest.pageOrder.isEmpty else {
            page = nil
            pageIndex = 0
            return
        }
        let clamped = min(max(0, index), manifest.pageOrder.count - 1)
        isLoadingPage = true
        do {
            page = try await store.loadPage(manifest.pageOrder[clamped], in: manifest.id)
            pageIndex = clamped
            loadError = nil
        } catch {
            page = nil
            loadError = error.localizedDescription
        }
        isLoadingPage = false
    }

    func goToPage(_ index: Int) async {
        guard index != pageIndex, manifest.pageOrder.indices.contains(index) else { return }
        await commitPendingSave()
        await loadPage(at: index)
    }

    func goToNextPage() async {
        guard pageIndex + 1 < pageCount else { return }
        await commitPendingSave()
        await loadPage(at: pageIndex + 1)
    }

    func goToPreviousPage() async {
        guard pageIndex > 0 else { return }
        await commitPendingSave()
        await loadPage(at: pageIndex - 1)
    }

    func addPage(after current: Bool = true) async {
        do {
            let index = current ? pageIndex + 1 : pageCount
            let newPage = try await store.addPage(
                to: manifest.id,
                at: index,
                width: page?.width ?? PageDefaults.width,
                height: page?.height ?? PageDefaults.height,
                template: page?.template ?? PageDefaults.blank
            )
            await reloadManifest()
            await loadPage(at: index)
            _ = newPage
        } catch {
            // The caller shows the message through AppModel when this is wired.
        }
    }

    func duplicateCurrentPage() async {
        guard let page else { return }
        do {
            _ = try await store.duplicatePage(page.id, in: manifest.id)
            await reloadManifest()
            await loadPage(at: min(pageIndex + 1, max(0, pageCount - 1)))
        } catch {
            // Leave the original page on screen.
        }
    }

    func moveCurrentPage(by offset: Int) async {
        guard pageCount > 1 else { return }
        let destination = pageIndex + offset
        guard manifest.pageOrder.indices.contains(destination) else { return }
        var order = manifest.pageOrder
        order.swapAt(pageIndex, destination)
        do {
            try await store.reorderPages(in: manifest.id, order: order)
            await reloadManifest()
            pageIndex = destination
        } catch {
            // The order on disk is unchanged.
        }
    }

    func deleteCurrentPage() async {
        guard let page else { return }
        do {
            try await store.deletePage(page.id, in: manifest.id)
            onPageDeleted?(page.id)
            await reloadManifest()
            await loadPage(at: min(pageIndex, max(0, pageCount - 1)))
        } catch {
            // Keep the page visible rather than pretending it was deleted.
        }
    }

    /// Changes the printed background of the current page, or of every page.
    func applyTemplate(_ template: PageTemplate, toAllPages: Bool) async {
        await commitPendingSave()
        if toAllPages {
            isApplyingTemplate = true
            defer { isApplyingTemplate = false }
            for pageID in manifest.pageOrder {
                guard var stored = try? await store.loadPage(pageID, in: manifest.id) else { continue }
                stored.template = template
                try? await store.savePage(stored, in: manifest.id)
                ThumbnailCache.invalidate(notebookID: manifest.id, pageID: pageID)
            }
            await loadPage(at: pageIndex)
            revision &+= 1
            return
        }

        guard var updated = page else { return }
        updated.template = template
        page = updated
        revision &+= 1
        ThumbnailCache.invalidate(notebookID: manifest.id, pageID: updated.id)
        do {
            try await store.savePage(updated, in: manifest.id)
        } catch {
            // The old template stays on screen; a later edit saves the new one.
        }
    }

    // MARK: - Page elements

    func addTextElement(_ text: String, fontSize: Double = 16, color: RGBAColor = .black) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var updated = page else { return }
        await commitPendingSave()

        let lines = max(1, trimmed.components(separatedBy: .newlines).count)
        let width = updated.width * 0.7
        let height = max(fontSize * 1.5 * Double(lines) + 16, fontSize * 2)
        let layerID = updated.layers.first?.id ?? UUID()
        updated.elements.append(
            PageElement(
                id: UUID(),
                layerID: layerID,
                frame: ElementFrame(
                    x: (updated.width - width) / 2,
                    y: updated.height * 0.18,
                    width: width,
                    height: height
                ),
                zIndex: (updated.elements.map(\.zIndex).max() ?? 0) + 1,
                updatedAt: Date(),
                content: .text(trimmed, fontName: "System", fontSize: fontSize, color: color)
            )
        )
        await saveEditedPage(updated)
    }

    func addImageElement(data: Data, fileExtension: String) async {
        guard var updated = page else { return }
        await commitPendingSave()

        do {
            let assetName = try await store.addAsset(data, fileExtension: fileExtension, to: manifest.id)
            let pixelSize = ImageSizeReader.size(of: data) ?? CGSize(width: 1000, height: 1000)
            let maxWidth = updated.width * 0.75
            let maxHeight = updated.height * 0.6
            let ratio = min(maxWidth / pixelSize.width, maxHeight / pixelSize.height, 1)
            let width = pixelSize.width * ratio
            let height = pixelSize.height * ratio
            let layerID = updated.layers.first?.id ?? UUID()
            updated.elements.append(
                PageElement(
                    id: UUID(),
                    layerID: layerID,
                    frame: ElementFrame(
                        x: (updated.width - width) / 2,
                        y: updated.height * 0.15,
                        width: width,
                        height: height
                    ),
                    zIndex: (updated.elements.map(\.zIndex).max() ?? 0) + 1,
                    updatedAt: Date(),
                    content: .image(assetName: assetName)
                )
            )
            await saveEditedPage(updated)
        } catch {
            // The caller reports errors through the page's loadError mechanism.
            loadError = error.localizedDescription
        }
    }

    func updateTextElement(_ elementID: UUID, text: String) async {
        guard var updated = page,
              let index = updated.elements.firstIndex(where: { $0.id == elementID })
        else { return }
        guard case let .text(_, fontName, fontSize, color) = updated.elements[index].content else { return }
        updated.elements[index].content = .text(
            text,
            fontName: fontName,
            fontSize: fontSize,
            color: color
        )
        updated.elements[index].updatedAt = Date()
        await saveEditedPage(updated)
    }

    func removeElement(_ elementID: UUID) async {
        guard var updated = page else { return }
        updated.elements.removeAll { $0.id == elementID }
        await saveEditedPage(updated)
    }

    private func saveEditedPage(_ updated: Page) async {
        page = updated
        revision &+= 1
        ThumbnailCache.invalidate(notebookID: manifest.id, pageID: updated.id)
        do {
            try await store.savePage(updated, in: manifest.id)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Called by the canvas whenever the set of strokes changes.
    func strokesChanged(_ strokes: [StrokeRecord]) {
        guard var updated = page else { return }
        updated.strokes = strokes
        page = updated
        revision &+= 1
        ThumbnailCache.invalidate(notebookID: manifest.id, pageID: updated.id)
        scheduleSave(updated)
    }

    /// Called by the canvas after a stroke so a page is never left only in memory.
    func strokesChangedNow(_ strokes: [StrokeRecord]) async {
        strokesChanged(strokes)
        await commitPendingSave()
    }

    private func scheduleSave(_ page: Page) {
        pendingPage = page
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.commitPendingSave()
        }
    }

    func commitPendingSave() async {
        guard let pendingPage else { return }
        saveTask?.cancel()
        saveTask = nil
        self.pendingPage = nil
        isSaving = true
        do {
            try await store.savePage(pendingPage, in: manifest.id)
            if let latest = try? await store.loadManifest(manifest.id) {
                manifest = latest
            }
        } catch {
            // Put the unsaved page back so a later attempt retries it.
            if self.pendingPage == nil { self.pendingPage = pendingPage }
        }
        isSaving = false
    }

    func flushPendingSave() {
        guard let pendingPage else { return }
        self.pendingPage = nil
        let notebookID = manifest.id
        Task { [store] in
            try? await store.savePage(pendingPage, in: notebookID)
        }
    }

    func reloadManifest() async {
        if let latest = try? await store.loadManifest(manifest.id) {
            manifest = latest
        }
    }
}
