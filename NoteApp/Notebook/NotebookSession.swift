import AIKit
import Foundation
import HistoryKit
import InkKit
import NoteCore
import Observation

enum PageDefaults {
    nonisolated static let width: Double = 595  // A4 at 72 dpi
    nonisolated static let height: Double = 842
    nonisolated static let blank = PageTemplate.blank
}

/// One open notebook: the current page, its save state and page operations.
///
/// The in-memory `page` is the truth. Every edit replaces it and queues the
/// whole page for saving; saves run one at a time in the order they were
/// queued, so an older snapshot of the page can never land on disk after a
/// newer one.
@MainActor
@Observable
final class NotebookSession: Identifiable {
    var id: UUID { manifest.id }

    let store: LibraryStore
    let assetsDirectory: URL?
    let audio: NotebookAudio
    let history: VersionHistoryStore
    var notebookID: UUID { manifest.id }
    /// Reloaded after each save; a reload that only moves `updatedAt` is
    /// skipped (see `reloadManifest`), so `manifest.updatedAt` may lag.
    private(set) var manifest: NotebookManifest
    private(set) var page: Page? {
        didSet { syncPageChrome() }
    }
    private(set) var pageIndex = 0
    /// The layer new ink goes to. It is reset when the page has no such layer.
    private(set) var activeLayerID: UUID? {
        didSet { syncPageChrome() }
    }
    /// `page?.id`, and the active layer as it is on the page. `page` changes
    /// with every stroke; these change only when their value does, so the
    /// editor chrome (banners, menus, toolbar) that reads only them is not
    /// rebuilt while writing.
    private(set) var currentPageID: UUID?
    private(set) var activeLayer: Page.Layer?
    private(set) var isLoadingPage = false
    private(set) var isSaving = false
    private(set) var isApplyingTemplate = false
    private(set) var loadError: String?
    /// A short sentence about the last page operation that failed. The editor
    /// shows it and sets it back to nil.
    var errorMessage: String?
    /// Bumped after an edit so the current page's thumbnail re-renders.
    private(set) var revision = 0
    /// Changes whenever pages other than the one on screen are rewritten in
    /// bulk (a template or size applied to every page), so cached renders of
    /// those pages are dropped. Scrolling views key their page images on it.
    private(set) var otherPagesToken = UUID()

    /// The debounce timer for ink.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The newest page not yet handed to the write queue.
    @ObservationIgnored private var pendingPage: Page?
    /// The last queued write; each write waits for the one before it.
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    @ObservationIgnored private var writesInFlight = 0

    /// When each page last got a history snapshot.
    @ObservationIgnored private var lastSnapshotAt: [UUID: Date] = [:]
    /// Saved pages whose newest state has no snapshot yet.
    @ObservationIgnored private var unsnapshotted: [UUID: Page] = [:]
    /// The last queued snapshot; snapshots are written in order, off the main actor.
    @ObservationIgnored private var snapshotChain: Task<Void, Never>?
    static let snapshotInterval: TimeInterval = 120

    /// Called after a page file is deleted, so its search record can go too.
    var onPageDeleted: ((UUID) -> Void)?

    init(
        store: LibraryStore,
        snapshot: LibraryStore.NotebookSnapshot,
        history: VersionHistoryStore
    ) {
        self.store = store
        self.assetsDirectory = store.assetsDirectoryURL(for: snapshot.manifest.id)
        self.audio = NotebookAudio(store: store, notebookID: snapshot.manifest.id)
        self.history = history
        self.manifest = snapshot.manifest
    }

    var pageCount: Int { manifest.pageOrder.count }
    var currentPageNumber: Int { min(pageIndex + 1, pageCount) }

    // MARK: - Last visited page

    private var lastVisitedKey: String { "NotebookSession.lastVisitedPage.\(manifest.id.uuidString)" }

    /// The page the user was last on in this notebook, kept across launches.
    /// It follows the page, not the position, so a reorder elsewhere still
    /// finds it. 0 when unknown.
    var lastVisitedPageIndex: Int {
        guard !manifest.pageOrder.isEmpty,
              let stored = UserDefaults.standard.string(forKey: lastVisitedKey),
              let pageID = UUID(uuidString: stored),
              let index = manifest.pageOrder.firstIndex(of: pageID)
        else { return 0 }
        return min(index, manifest.pageOrder.count - 1)
    }

    /// The notebook's own scroll direction, or nil to follow the app default.
    var pageScrollMode: PageScrollMode? { manifest.pageScrollMode }

    func setPageScrollMode(_ mode: PageScrollMode?) async {
        guard mode != manifest.pageScrollMode else { return }
        do {
            try await store.setPageScrollMode(mode, for: manifest.id)
            await reloadManifest()
        } catch {
            errorMessage = "The scrolling direction could not be saved."
        }
    }

    private func rememberVisitedPage() {
        guard let page else { return }
        UserDefaults.standard.set(page.id.uuidString, forKey: lastVisitedKey)
    }

    // MARK: - Layers

    /// Assigns the derived chrome state only when it changes: an
    /// observable property notifies on every assignment.
    private func syncPageChrome() {
        let pageID = page?.id
        if currentPageID != pageID { currentPageID = pageID }
        var layer: Page.Layer?
        if let page, let activeLayerID {
            layer = page.layers.first { $0.id == activeLayerID }
        }
        if activeLayer != layer { activeLayer = layer }
    }

    /// Ink the canvas may show and edit: every stroke on a visible layer, in
    /// paint order. `page.strokes` is kept in render order, so a filter is enough.
    var visibleStrokes: [StrokeRecord] {
        guard let page else { return [] }
        let visible = Set(page.layers.filter(\.isVisible).map(\.id))
        return page.strokes.filter { visible.contains($0.layerID) }
    }

    var canDrawOnActiveLayer: Bool {
        guard let activeLayer else { return false }
        return activeLayer.isVisible && !activeLayer.isLocked
    }

    func setActiveLayer(_ layerID: UUID) {
        guard page?.layers.contains(where: { $0.id == layerID }) == true else { return }
        activeLayerID = layerID
    }

    func addLayer() async {
        guard var updated = page else { return }
        let layer = Page.Layer(id: UUID(), name: "Layer \(updated.layers.count + 1)")
        updated.layers.append(layer)
        activeLayerID = layer.id
        await saveEditedPage(updated, failure: "The layer could not be added.")
    }

    func renameLayer(_ layerID: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var updated = page,
              let index = updated.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        updated.layers[index].name = trimmed
        await saveEditedPage(updated, failure: "The layer could not be renamed.")
    }

    func toggleLayerVisibility(_ layerID: UUID) async {
        guard var updated = page,
              let index = updated.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        updated.layers[index].isVisible.toggle()
        if !updated.layers[index].isVisible, activeLayerID == layerID {
            activeLayerID = updated.layers.first(where: { $0.isVisible && !$0.isLocked })?.id
                ?? updated.layers.first(where: { $0.isVisible })?.id
                ?? layerID
        }
        await saveEditedPage(updated, failure: "The layer could not be shown or hidden.")
    }

    func toggleLayerLock(_ layerID: UUID) async {
        guard var updated = page,
              let index = updated.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        updated.layers[index].isLocked.toggle()
        await saveEditedPage(updated, failure: "The layer could not be locked or unlocked.")
    }

    /// Deletes a layer and moves its ink and elements to the layer below it.
    /// The last layer cannot be deleted.
    func deleteLayer(_ layerID: UUID) async {
        guard var updated = page, updated.layers.count > 1,
              let index = updated.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        let fallbackIndex = index == 0 ? 1 : index - 1
        let fallbackID = updated.layers[fallbackIndex].id
        for strokeIndex in updated.strokes.indices where updated.strokes[strokeIndex].layerID == layerID {
            updated.strokes[strokeIndex].layerID = fallbackID
        }
        for elementIndex in updated.elements.indices where updated.elements[elementIndex].layerID == layerID {
            updated.elements[elementIndex].layerID = fallbackID
        }
        updated.layers.remove(at: index)
        updated.strokes = StrokeOrder.renderOrder(updated.strokes, layerOrder: updated.layers.map(\.id))
        activeLayerID = fallbackID
        await saveEditedPage(updated, failure: "The layer could not be deleted.")
    }

    func moveLayer(_ layerID: UUID, by offset: Int) async {
        guard var updated = page,
              let index = updated.layers.firstIndex(where: { $0.id == layerID })
        else { return }
        let destination = index + offset
        guard updated.layers.indices.contains(destination) else { return }
        updated.layers.swapAt(index, destination)
        updated.strokes = StrokeOrder.renderOrder(updated.strokes, layerOrder: updated.layers.map(\.id))
        await saveEditedPage(updated, failure: "The layer could not be moved.")
    }

    // MARK: - Pages

    func loadPage(at index: Int) async {
        // Whatever is queued for the page on screen goes to disk first, so the
        // page read below (possibly the same one) is current.
        let leaving = page?.id
        await commitPendingSave()
        guard !manifest.pageOrder.isEmpty else {
            if let leaving { snapshotUnsaved(pageID: leaving, reason: "closed page") }
            page = nil
            pageIndex = 0
            return
        }
        let clamped = min(max(0, index), manifest.pageOrder.count - 1)
        isLoadingPage = true
        do {
            var loaded = try await store.loadPage(manifest.pageOrder[clamped], in: manifest.id)
            if let leaving, leaving != loaded.id {
                snapshotUnsaved(pageID: leaving, reason: "closed page")
                // Which tape is held up belongs to the page on screen, not the
                // page being read.
                revealedTapeIDs.removeAll()
            }
            // Older files may hold strokes out of layer order; fix it in memory.
            // It reaches disk with the next edit.
            loaded.strokes = StrokeOrder.renderOrder(loaded.strokes, layerOrder: loaded.layers.map(\.id))
            page = loaded
            pageIndex = clamped
            if activeLayerID == nil || !loaded.layers.contains(where: { $0.id == activeLayerID }) {
                activeLayerID = loaded.layers.first(where: { $0.isVisible && !$0.isLocked })?.id
                    ?? loaded.layers.first?.id
            }
            loadError = nil
            rememberVisitedPage()
        } catch {
            page = nil
            loadError = error.localizedDescription
        }
        isLoadingPage = false
    }

    /// Maps a PDF-page destination to the notebook page holding that PDF page.
    /// PDF imports keep the same order, so the offset from the current page is
    /// enough; a hand-arranged notebook returns nil rather than the wrong page.
    func notebookPageIndex(forPDFPage pdfIndex: Int, from page: Page) -> Int? {
        guard let element = page.elements.first(where: {
            if case .pdfPage = $0.content { return true }
            return false
        }), case let .pdfPage(_, currentIndex) = element.content else {
            return nil
        }
        let target = pageIndex + (pdfIndex - currentIndex)
        return manifest.pageOrder.indices.contains(target) ? target : nil
    }

    func goToPage(_ index: Int) async {
        guard index != pageIndex, manifest.pageOrder.indices.contains(index) else { return }
        await loadPage(at: index)
    }

    func goToNextPage() async {
        guard pageIndex + 1 < pageCount else { return }
        await loadPage(at: pageIndex + 1)
    }

    func goToPreviousPage() async {
        guard pageIndex > 0 else { return }
        await loadPage(at: pageIndex - 1)
    }

    func addPage(after current: Bool = true) async {
        guard await commitSucceeded() else {
            errorMessage = "A new page could not be added because this page is not saved yet."
            return
        }
        do {
            let index = current ? pageIndex + 1 : pageCount
            _ = try await store.addPage(
                to: manifest.id,
                at: index,
                width: page?.width ?? PageDefaults.width,
                height: page?.height ?? PageDefaults.height,
                template: page?.template ?? PageDefaults.blank
            )
            await reloadManifest()
            await loadPage(at: index)
        } catch {
            errorMessage = "A new page could not be added."
        }
    }

    /// Inserts already-built pages — a PDF import — at `index`, writes them and
    /// shows the first one. Returns how many were inserted.
    ///
    /// The current page is committed first so its newest ink is on disk before
    /// the manifest is rewritten. Pages are written one file at a time and then
    /// placed in the order, so a crash in between leaves orphan page files the
    /// next open recovers rather than a manifest entry with no page.
    @discardableResult
    func insertPages(
        _ pages: [Page],
        at index: Int,
        onProgress: ((_ written: Int, _ total: Int) -> Void)? = nil
    ) async -> Int {
        guard !pages.isEmpty else { return 0 }
        guard await commitSucceeded() else {
            errorMessage = "The pages could not be added because this page is not saved yet."
            return 0
        }
        do {
            for (written, page) in pages.enumerated() {
                try await store.savePage(page, in: manifest.id)
                onProgress?(written + 1, pages.count)
            }
            await reloadManifest()

            var order = manifest.pageOrder
            let insertedIDs = pages.map(\.id)
            let insertedSet = Set(insertedIDs)
            order.removeAll { insertedSet.contains($0) }
            let position = min(max(0, index), order.count)
            order.insert(contentsOf: insertedIDs, at: position)
            try await store.reorderPages(in: manifest.id, order: order)
            await reloadManifest()
            await loadPage(at: position)
            return pages.count
        } catch {
            // The page files that were written are on disk already and the
            // manifest lists them, so show what is really there.
            await reloadManifest()
            errorMessage = "The pages could not be added to this notebook."
            return 0
        }
    }

    func duplicateCurrentPage() async {
        guard let page else { return }
        // The copy is made from the file, so the newest ink must be in it.
        guard await commitSucceeded() else {
            errorMessage = "The page could not be duplicated because it is not saved yet."
            return
        }
        do {
            _ = try await store.duplicatePage(page.id, in: manifest.id)
            await reloadManifest()
            await loadPage(at: min(pageIndex + 1, max(0, pageCount - 1)))
        } catch {
            errorMessage = "The page could not be duplicated."
        }
    }

    func moveCurrentPage(by offset: Int) async {
        guard pageCount > 1 else { return }
        // A save reloads the manifest; let it finish before reordering.
        await commitPendingSave()
        let destination = pageIndex + offset
        guard manifest.pageOrder.indices.contains(destination) else { return }
        var order = manifest.pageOrder
        order.swapAt(pageIndex, destination)
        do {
            try await store.reorderPages(in: manifest.id, order: order)
            await reloadManifest()
            pageIndex = destination
            rememberVisitedPage()
        } catch {
            errorMessage = "The page could not be moved."
        }
    }

    func deleteCurrentPage() async {
        guard let page else { return }
        // Drop what is queued for this page: saving it after the delete would
        // put the page file back as an orphan.
        saveTask?.cancel()
        saveTask = nil
        let dropped = pendingPage?.id == page.id ? pendingPage : nil
        if dropped != nil { pendingPage = nil }
        await commitPendingSave()  // waits for writes already queued
        do {
            try await store.deletePage(page.id, in: manifest.id)
            unsnapshotted[page.id] = nil
            lastSnapshotAt[page.id] = nil
            onPageDeleted?(page.id)
            await reloadManifest()
            self.page = nil
            await loadPage(at: min(pageIndex, max(0, pageCount - 1)))
        } catch {
            // Keep the page and its unsaved ink.
            if let dropped, pendingPage == nil { scheduleSave(dropped) }
            errorMessage = "The page could not be deleted."
        }
    }

    /// Changes the printed background of the current page, or of every page.
    func applyTemplate(_ template: PageTemplate, toAllPages: Bool) async {
        if toAllPages {
            await commitPendingSave()
            isApplyingTemplate = true
            defer { isApplyingTemplate = false }
            var failed = 0
            for pageID in manifest.pageOrder where pageID != page?.id {
                do {
                    var stored = try await store.loadPage(pageID, in: manifest.id)
                    stored.template = template
                    try await store.savePage(stored, in: manifest.id)
                    ThumbnailCache.invalidate(notebookID: manifest.id, pageID: pageID)
                } catch {
                    failed += 1
                }
            }
            if failed > 0 {
                errorMessage = failed == 1
                    ? "The background could not be changed on one page."
                    : "The background could not be changed on \(failed) pages."
            }
            otherPagesToken = UUID()
        }

        // The page on screen goes through the ordered save, so ink drawn
        // meanwhile is not lost and an older save cannot undo the change.
        guard var updated = page else { return }
        updated.template = template
        await saveEditedPage(updated, failure: "The page background could not be changed.")
    }

    // MARK: - Page operations

    /// Turns the page and everything on it 90° × `quarterTurns` clockwise.
    /// Negative turns go anticlockwise. Going through the ordered save puts the
    /// turned strokes on the canvas, which rebuilds a drawing whose strokes
    /// changed.
    func rotateCurrentPage(quarterTurns: Int) async {
        guard let current = page else { return }
        let turned = current.rotated(quarterTurns: quarterTurns)
        guard turned != current else { return }
        await saveEditedPage(turned, failure: "The page could not be rotated.")
    }

    /// Empties the page of everything "Delete Specific Items" can clear, keeping
    /// an imported PDF background. The page as it was is snapshotted first, so
    /// the clear can be undone from history.
    func clearCurrentPage() async {
        guard let current = page else { return }
        let cleared = current.cleared()
        guard cleared != current else { return }
        await recordSnapshot(current, reason: "before clear").value
        await saveEditedPage(cleared, failure: "The page could not be cleared.")
    }

    /// Removes every stroke and element of the given kinds. Their ids are kept
    /// as tombstones so a later merge cannot bring them back.
    func deleteItems(of kinds: Set<PageItemKind>) async {
        guard !kinds.isEmpty, let current = page else { return }
        let trimmed = current.removingItems(of: kinds)
        guard trimmed != current else { return }
        await recordSnapshot(current, reason: "before deleting items").value
        await saveEditedPage(trimmed, failure: "The items could not be removed.")
    }

    /// Gives the current page, or every page, a new size. Content stays where it
    /// is; nothing is scaled.
    func resizePages(width: Double, height: Double, toAllPages: Bool) async {
        guard width > 0, height > 0 else { return }

        if toAllPages {
            // Other pages are written straight to the store, so finish the
            // queued save of the current page first.
            await commitPendingSave()
            var failed = 0
            for pageID in manifest.pageOrder where pageID != page?.id {
                do {
                    var stored = try await store.loadPage(pageID, in: manifest.id)
                    stored = stored.resized(width: width, height: height)
                    try await store.savePage(stored, in: manifest.id)
                    ThumbnailCache.invalidate(notebookID: manifest.id, pageID: pageID)
                } catch {
                    failed += 1
                }
            }
            if failed > 0 {
                errorMessage = failed == 1
                    ? "The page size could not be changed on one page."
                    : "The page size could not be changed on \(failed) pages."
            }
            otherPagesToken = UUID()
        }

        // The page on screen goes through the ordered save, so ink drawn
        // meanwhile is not lost and an older save cannot undo the change.
        guard let current = page else { return }
        await saveEditedPage(
            current.resized(width: width, height: height),
            failure: "The page size could not be changed."
        )
    }

    /// How many of each kind the current page holds, for a list that shows the
    /// counts and disables the kinds the page does not have.
    func itemCounts() -> [PageItemKind: Int] {
        guard let page else { return [:] }
        var counts: [PageItemKind: Int] = [:]
        for stroke in page.strokes {
            counts[PageItemKind.of(stroke), default: 0] += 1
        }
        for element in page.elements {
            guard let kind = PageItemKind.of(element) else { continue }
            counts[kind, default: 0] += 1
        }
        return counts
    }

    // MARK: - Page elements

    func addTextElement(
        _ text: String,
        fontSize: Double = 16,
        color: RGBAColor = .black,
        textStyle: TextStyle = .regular
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var updated = page else { return }

        let lines = max(1, trimmed.components(separatedBy: .newlines).count)
        let width = updated.width * 0.7
        let height = max(fontSize * 1.5 * Double(lines) + 16, fontSize * 2)
        let layerID = activeLayerID ?? updated.layers.first?.id ?? UUID()
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
                content: .text(trimmed, fontName: "System", fontSize: fontSize, color: color),
                textStyle: textStyle
            )
        )
        await saveEditedPage(updated, failure: "The text could not be added.")
    }

    func addImageElement(data: Data, fileExtension: String) async {
        guard let pageID = page?.id else { return }

        let assetName: String
        do {
            assetName = try await store.addAsset(data, fileExtension: fileExtension, to: manifest.id)
        } catch {
            errorMessage = "The image could not be added."
            return
        }
        // Ink may have changed while the asset was written; build on the page
        // as it is now, and only if it is still the same page.
        guard var updated = page, updated.id == pageID else { return }
        let pixelSize = ImageSizeReader.size(of: data) ?? CGSize(width: 1000, height: 1000)
        let maxWidth = updated.width * 0.75
        let maxHeight = updated.height * 0.6
        let ratio = min(maxWidth / pixelSize.width, maxHeight / pixelSize.height, 1)
        let width = pixelSize.width * ratio
        let height = pixelSize.height * ratio
        let layerID = activeLayerID ?? updated.layers.first?.id ?? UUID()
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
        await saveEditedPage(updated, failure: "The image could not be added.")
    }

    func addShapeElement(kind: String) async {
        guard var updated = page else { return }

        let width = updated.width * 0.45
        let height = kind == "line" ? 2 : updated.height * 0.25
        let layerID = activeLayerID ?? updated.layers.first?.id ?? UUID()
        updated.elements.append(
            PageElement(
                id: UUID(),
                layerID: layerID,
                frame: ElementFrame(
                    x: (updated.width - width) / 2,
                    y: updated.height * 0.35,
                    width: width,
                    height: max(height, 2)
                ),
                zIndex: (updated.elements.map(\.zIndex).max() ?? 0) + 1,
                updatedAt: Date(),
                content: .shape(
                    kind: kind,
                    stroke: RGBAColor(r: 0.15, g: 0.2, b: 0.3),
                    fill: kind == "line" ? nil : RGBAColor(r: 0.85, g: 0.9, b: 1, a: 0.4),
                    lineWidth: 2
                )
            )
        )
        await saveEditedPage(updated, failure: "The shape could not be added.")
    }

    func updateTextElement(
        _ elementID: UUID,
        text: String,
        textStyle: TextStyle? = nil
    ) async {
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
        if let textStyle {
            updated.elements[index].textStyle = textStyle
        }
        updated.elements[index].updatedAt = Date()
        await saveEditedPage(updated, failure: "The text could not be changed.")
    }

    func removeElement(_ elementID: UUID) async {
        guard var updated = page else { return }
        updated.elements.removeAll { $0.id == elementID }
        updated.deletedElementIDs.insert(elementID)
        revealedTapeIDs.remove(elementID)
        await saveEditedPage(updated, failure: "The item could not be removed.")
    }

    func updateElementFrame(_ elementID: UUID, frame: ElementFrame) async {
        guard var updated = page,
              let index = updated.elements.firstIndex(where: { $0.id == elementID })
        else { return }
        updated.elements[index].frame = frame
        updated.elements[index].updatedAt = Date()
        await saveEditedPage(updated, failure: "The item could not be moved.")
    }

    func setElementLocked(_ elementID: UUID, isLocked: Bool) async {
        guard var updated = page,
              let index = updated.elements.firstIndex(where: { $0.id == elementID })
        else { return }
        updated.elements[index].isLocked = isLocked
        updated.elements[index].updatedAt = Date()
        await saveEditedPage(updated, failure: "The item could not be locked or unlocked.")
    }

    /// Moves an element one step in z-order. +1 is towards the front.
    func moveElement(_ elementID: UUID, by offset: Int) async {
        guard var updated = page else { return }
        var ordered = updated.elements.sorted {
            $0.zIndex == $1.zIndex ? $0.id.uuidString < $1.id.uuidString : $0.zIndex < $1.zIndex
        }
        guard let index = ordered.firstIndex(where: { $0.id == elementID }) else { return }
        let destination = index + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        for (zIndex, element) in ordered.enumerated() {
            if let elementIndex = updated.elements.firstIndex(where: { $0.id == element.id }) {
                updated.elements[elementIndex].zIndex = zIndex
            }
        }
        await saveEditedPage(updated, failure: "The item could not be moved.")
    }

    // MARK: - Sticky notes and tape

    /// The sticky note colours the Insert menu offers, in this order: pink,
    /// peach, yellow, green, mint, blue, lavender, rose, grey, white.
    static let stickyColors: [RGBAColor] = [
        RGBAColor(r: 1.00, g: 0.82, b: 0.88),  // pink
        RGBAColor(r: 1.00, g: 0.88, b: 0.74),  // peach
        RGBAColor(r: 1.00, g: 0.95, b: 0.62),  // yellow
        RGBAColor(r: 0.80, g: 0.94, b: 0.72),  // green
        RGBAColor(r: 0.74, g: 0.95, b: 0.87),  // mint
        RGBAColor(r: 0.76, g: 0.88, b: 0.99),  // blue
        RGBAColor(r: 0.85, g: 0.82, b: 0.98),  // lavender
        RGBAColor(r: 0.98, g: 0.78, b: 0.80),  // rose
        RGBAColor(r: 0.88, g: 0.89, b: 0.91),  // grey
        RGBAColor(r: 1.00, g: 1.00, b: 1.00),  // white
    ]

    /// The tape colours the Insert menu offers: the three the toolbar shows.
    static let tapeColors: [RGBAColor] = [
        RGBAColor(r: 1.00, g: 1.00, b: 1.00),  // white
        RGBAColor(r: 0.90, g: 0.22, b: 0.20),  // red
        RGBAColor(r: 0.98, g: 0.60, b: 0.18),  // orange
    ]

    static let stickyNoteSize = CGSize(width: 200, height: 200)
    static let tapeSize = CGSize(width: 240, height: 36)

    /// Tape pieces held up so the ink under them shows. This is how the page is
    /// being looked at, not part of the page, so it is never saved.
    private(set) var revealedTapeIDs: Set<UUID> = []
    /// A search whose matches the page marks; nil shows no marks.
    var searchHighlight: SearchHighlight?

    /// Adds a sticky note of `stickyNoteSize` at the centre of the page, on the
    /// active layer.
    func insertStickyNote(color: RGBAColor, text: String = "") async {
        guard var updated = page else { return }
        updated.elements.append(
            PageElement(
                id: UUID(),
                layerID: activeLayerID ?? updated.layers.first?.id ?? UUID(),
                frame: Self.centredFrame(size: Self.stickyNoteSize, in: updated),
                zIndex: (updated.elements.map(\.zIndex).max() ?? 0) + 1,
                updatedAt: Date(),
                content: .stickyNote(text, color: color)
            )
        )
        await saveEditedPage(updated, failure: "The sticky note could not be added.")
    }

    /// Adds a piece of tape of `tapeSize` at the centre of the page, on the
    /// active layer. It hides what is under it until it is tapped.
    func insertTape(color: RGBAColor) async {
        guard var updated = page else { return }
        updated.elements.append(
            PageElement(
                id: UUID(),
                layerID: activeLayerID ?? updated.layers.first?.id ?? UUID(),
                frame: Self.centredFrame(size: Self.tapeSize, in: updated),
                zIndex: (updated.elements.map(\.zIndex).max() ?? 0) + 1,
                updatedAt: Date(),
                content: .tape(color: color)
            )
        )
        await saveEditedPage(updated, failure: "The tape could not be added.")
    }

    /// Replaces a sticky note's text, keeping its colour.
    func updateStickyNoteText(_ elementID: UUID, text: String) async {
        guard var updated = page,
              let index = updated.elements.firstIndex(where: { $0.id == elementID }),
              case let .stickyNote(_, color) = updated.elements[index].content
        else { return }
        updated.elements[index].content = .stickyNote(text, color: color)
        updated.elements[index].updatedAt = Date()
        await saveEditedPage(updated, failure: "The note could not be changed.")
    }

    /// Holds a piece of tape up so the ink under it shows, or puts it back.
    func toggleTapeRevealed(_ elementID: UUID) {
        guard let element = page?.elements.first(where: { $0.id == elementID }),
              case .tape = element.content
        else { return }
        if revealedTapeIDs.contains(elementID) {
            revealedTapeIDs.remove(elementID)
        } else {
            revealedTapeIDs.insert(elementID)
        }
    }

    /// A default-sized element kept on the page, centred on it.
    private static func centredFrame(size: CGSize, in page: Page) -> ElementFrame {
        let width = min(size.width, page.width)
        let height = min(size.height, page.height)
        return ElementFrame(
            x: max((page.width - width) / 2, 0),
            y: max((page.height - height) / 2, 0),
            width: width,
            height: height
        )
    }

    // MARK: - Ink

    /// Called by the canvas whenever the set of strokes changes.
    ///
    /// The canvas only shows visible layers. Strokes on hidden layers are kept
    /// from the in-memory page so hiding a layer never deletes its ink, and
    /// known strokes keep their place so the stacking never reshuffles.
    /// Strokes that disappear are tombstoned so a merge cannot bring them back.
    func strokesChanged(_ strokes: [StrokeRecord]) {
        guard var updated = page else { return }
        let shown = Set(updated.layers.filter(\.isVisible).map(\.id))
        let notShown = Set(updated.strokes.map(\.layerID)).subtracting(shown)
        let merge = StrokeOrder.merge(
            existing: updated.strokes,
            canvas: strokes,
            hiddenLayerIDs: notShown,
            layerOrder: updated.layers.map(\.id)
        )
        updated.strokes = merge.strokes
        updated.deletedStrokeIDs.formUnion(merge.removedIDs)
        updated.deletedStrokeIDs.subtract(merge.addedIDs)
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

    // MARK: - Saving

    /// Replaces the page and writes it now, through the ordered queue.
    @discardableResult
    private func saveEditedPage(_ updated: Page, failure: String) async -> Bool {
        page = updated
        revision &+= 1
        ThumbnailCache.invalidate(notebookID: manifest.id, pageID: updated.id)
        pendingPage = updated
        let saved = await commitSucceeded()
        if !saved {
            errorMessage = failure
        }
        return saved
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

    /// Commits and reports whether nothing is left unsaved afterwards.
    private func commitSucceeded() async -> Bool {
        await commitPendingSave()
        return pendingPage == nil
    }

    /// Writes the newest queued page and waits until it, and every write
    /// queued before it, is on disk. With nothing queued it still waits for
    /// writes in flight.
    func commitPendingSave() async {
        saveTask?.cancel()
        saveTask = nil
        guard let toSave = pendingPage else {
            await writeChain?.value
            return
        }
        pendingPage = nil

        let previous = writeChain
        let store = store
        let notebookID = manifest.id
        let write = Task<(any Error)?, Never> {
            await previous?.value
            do {
                try await store.savePage(toSave, in: notebookID)
                return nil
            } catch {
                return error
            }
        }
        writeChain = Task { _ = await write.value }

        writesInFlight += 1
        isSaving = true
        let error = await write.value
        writesInFlight -= 1
        isSaving = writesInFlight > 0

        if error != nil {
            // Put the page back unless something newer replaced it, and retry
            // with the next save.
            if pendingPage == nil { pendingPage = toSave }
            errorMessage = "Your latest changes could not be saved. They are kept and will be retried."
            return
        }
        noteSaved(toSave)
        await reloadManifest()
    }

    /// Writes any pending page and waits until it is on disk, then records a
    /// history snapshot of unsnapshotted changes. Call before the app leaves
    /// the foreground or a notebook closes.
    func flushPendingSave() async {
        await commitPendingSave()
        for pageID in Array(unsnapshotted.keys) {
            snapshotUnsaved(pageID: pageID, reason: "closed notebook")
        }
        await snapshotChain?.value
    }

    // MARK: - History

    /// Records a snapshot at most once per page per `snapshotInterval`; the
    /// newest skipped state is kept for the next one or for leaving the page.
    private func noteSaved(_ saved: Page) {
        let now = Date()
        if let last = lastSnapshotAt[saved.id], now.timeIntervalSince(last) < Self.snapshotInterval {
            unsnapshotted[saved.id] = saved
        } else {
            recordSnapshot(saved, reason: "autosave")
        }
    }

    private func snapshotUnsaved(pageID: UUID, reason: String) {
        guard let saved = unsnapshotted[pageID] else { return }
        recordSnapshot(saved, reason: reason)
    }

    /// Encodes and writes a snapshot off the main actor, then prunes history.
    @discardableResult
    private func recordSnapshot(_ snapshotPage: Page, reason: String) -> Task<Void, Never> {
        lastSnapshotAt[snapshotPage.id] = Date()
        unsnapshotted[snapshotPage.id] = nil
        let previous = snapshotChain
        let history = history
        let notebookID = manifest.id
        let task = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? PageCodec.encode(snapshotPage) else { return }
            _ = try? await history.record(
                data: data,
                notebookID: notebookID,
                pageID: snapshotPage.id,
                reason: reason
            )
            _ = try? await history.prune(keeping: .default)
        }
        snapshotChain = task
        return task
    }

    /// Newest first. Notebook-level snapshots (`pageID == nil`) are included
    /// with the current page so a future whole-notebook history can use them.
    func pageHistory() async -> [VersionSnapshot] {
        guard let page else { return [] }
        await snapshotChain?.value
        let snapshots = (try? await history.list(notebookID: manifest.id)) ?? []
        return snapshots
            .filter { $0.pageID == page.id || $0.pageID == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Replaces the current page with `snapshot`. The page as it was is
    /// snapshotted first, so the restore can itself be undone from history.
    @discardableResult
    func restore(_ snapshot: VersionSnapshot) async -> Bool {
        guard let current = page else { return false }
        guard let data = try? await history.load(snapshot: snapshot),
              var restored = try? PageCodec.decode(data),
              restored.id == current.id
        else {
            loadError = "That version could not be read."
            errorMessage = "That version could not be read."
            return false
        }

        guard await commitSucceeded(), let latest = page, latest.id == current.id else {
            loadError = "The page could not be saved before restoring."
            errorMessage = "The page could not be saved before restoring."
            return false
        }
        await recordSnapshot(latest, reason: "before restore").value

        // Ink and items added since the version are tombstoned, and anything
        // the version brings back is no longer deleted, so a merge agrees.
        let restoredStrokeIDs = Set(restored.strokes.map(\.id))
        let restoredElementIDs = Set(restored.elements.map(\.id))
        restored.deletedStrokeIDs = latest.deletedStrokeIDs
            .union(latest.strokes.map(\.id))
            .union(restored.deletedStrokeIDs)
            .subtracting(restoredStrokeIDs)
        restored.deletedElementIDs = latest.deletedElementIDs
            .union(latest.elements.map(\.id))
            .union(restored.deletedElementIDs)
            .subtracting(restoredElementIDs)
        restored.strokes = StrokeOrder.renderOrder(restored.strokes, layerOrder: restored.layers.map(\.id))
        if activeLayerID == nil || !restored.layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = restored.layers.first(where: { $0.isVisible && !$0.isLocked })?.id
                ?? restored.layers.first?.id
        }

        let saved = await saveEditedPage(restored, failure: "The version could not be restored.")
        if !saved { loadError = "The version could not be restored." }
        return saved
    }

    /// Every page save rewrites the manifest's `updatedAt` and calls this.
    /// Replacing `manifest` re-renders everything that reads it (toolbar,
    /// thumbnail strip, page pill, page scroller), so a reload that changes
    /// nothing else keeps the current value. Nothing reads the session's
    /// `updatedAt`; the library reads its own copy from disk.
    func reloadManifest() async {
        guard let latest = try? await store.loadManifest(manifest.id) else { return }
        var unchanged = latest
        unchanged.updatedAt = manifest.updatedAt
        if unchanged != manifest {
            manifest = latest
        }
    }
}
