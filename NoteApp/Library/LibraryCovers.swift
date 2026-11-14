import Foundation
import InkKit
import NoteCore

/// First-page renders for library cards.
///
/// Lookups run in three steps: an in-memory cache for the current session, a disk
/// cache keyed by the notebook's page id and `updatedAt`, and finally a render on a
/// background task. Nothing is drawn or decoded on the main actor, so scrolling a
/// large library does not stall the frames.
@MainActor
enum LibraryCovers {
    private static let memory: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    /// One shared task per cover, so ten cards showing the same notebook render once.
    private static var inFlight: [String: Task<InkImage?, Never>] = [:]

    /// A cached image, or nil when the cover has to be produced.
    static func cached(notebook: NotebookManifest, usesDarkPaper: Bool = false) -> InkImage? {
        guard let pageID = notebook.pageOrder.first else { return nil }
        let key = cacheKey(
            notebookID: notebook.id,
            pageID: pageID,
            updatedAt: notebook.updatedAt,
            usesDarkPaper: usesDarkPaper
        )
        return memory.object(forKey: key as NSString)
    }

    static func image(
        for notebook: NotebookManifest,
        store: LibraryStore,
        usesDarkPaper: Bool = false
    ) async -> InkImage? {
        guard let pageID = notebook.pageOrder.first else { return nil }
        let key = cacheKey(
            notebookID: notebook.id,
            pageID: pageID,
            updatedAt: notebook.updatedAt,
            usesDarkPaper: usesDarkPaper
        )
        if let cached = memory.object(forKey: key as NSString) { return cached }
        // The card that asked may already have scrolled away.
        if Task.isCancelled { return nil }

        // The decode, the render and the disk write all run off the main actor:
        // a cover is a full page image, and decoding one while the grid scrolls
        // costs frames. The card that started a render cancels it when it goes
        // away, so a fling stops producing covers nothing will show.
        let task: Task<InkImage?, Never>
        let startsWork: Bool
        if let existing = inFlight[key] {
            task = existing
            startsWork = false
        } else {
            let diskURL = coversDirectory(store: store).appendingPathComponent("\(key).png")
            let notebookID = notebook.id
            task = Task {
                // The disk cache survives relaunches; the key changes whenever
                // the notebook's content, and therefore its cover, changes.
                if let stored = await storedData(at: diskURL) {
                    if Task.isCancelled { return nil }
                    return await decoded(stored)
                }

                guard let page = try? await store.loadPage(pageID, in: notebookID) else { return nil }
                if Task.isCancelled { return nil }
                let assets = store.assetsDirectoryURL(for: notebookID)
                return await rendered(
                    page: page,
                    assetsDirectory: assets,
                    diskURL: diskURL,
                    usesDarkPaper: usesDarkPaper
                )
            }
            inFlight[key] = task
            startsWork = true
        }

        let image: InkImage?
        if startsWork {
            image = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                // Only the card that started the render cancels it, so a waiting
                // card going away does not take it from the others.
                task.cancel()
            }
        } else {
            image = await task.value
        }
        inFlight[key] = nil

        if Task.isCancelled { return nil }
        guard let image else { return nil }
        memory.setObject(image, forKey: key as NSString, cost: cost(of: image))
        return image
    }

    /// Reads a cached cover off the main actor.
    nonisolated private static func storedData(at url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }

    /// Decodes a cached cover off the main actor.
    nonisolated private static func decoded(_ data: Data) async -> InkImage? {
        await Task.detached(priority: .userInitiated) {
            InkImage(data: data)
        }.value
    }

    /// Renders the notebook's first page off the main actor, writes the disk
    /// cache and returns the image. Cancellation is checked between the render
    /// and the write, so a cover for a vanished card is not encoded or stored.
    ///
    /// Dark paper covers go through `PaperAppearance`, the app's one dark-paper
    /// renderer: dark sheet, light template lines, ink inverted for display, the
    /// same picture the editor shows. The cache key carries the paper, so the
    /// white render of the same page stays cached beside it.
    nonisolated private static func rendered(
        page: Page,
        assetsDirectory: URL,
        diskURL: URL,
        usesDarkPaper: Bool
    ) async -> InkImage? {
        await Task.detached(priority: .utility) { () -> InkImage? in
            guard !Task.isCancelled else { return nil }
            guard let rendered = PaperAppearance.image(
                strokes: page.renderStrokes,
                pageSize: CGSize(width: page.width, height: page.height),
                template: page.template,
                elements: page.visibleElements,
                assetsDirectory: assetsDirectory,
                scale: 1,
                usesDarkPaper: usesDarkPaper
            ) else { return nil }
            if Task.isCancelled { return rendered }

            let data: Data?
            #if os(iOS)
            data = rendered.pngData()
            #else
            data = rendered.tiffRepresentation
            #endif
            if let data {
                try? FileManager.default.createDirectory(
                    at: diskURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: diskURL, options: .atomic)
            }
            return rendered
        }.value
    }

    /// Empties the in-memory covers; the disk cache keeps them.
    static func removeAllFromMemory() {
        memory.removeAllObjects()
    }

    /// Bumped whenever every cover is thrown away, so every card's cover task id
    /// changes and the visible grid draws its covers again even though no
    /// notebook changed.
    private(set) static var generation = 0

    /// Empties the memory cache and asks every card to load its cover again.
    static func invalidateAll() {
        memory.removeAllObjects()
        generation &+= 1
    }

    /// Forgets every render of a notebook, for when it leaves the library.
    static func removeCachedCovers(for notebookID: UUID, store: LibraryStore) {
        let directory = coversDirectory(store: store)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        let prefix = notebookID.uuidString.lowercased()
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Drops renders nothing has asked for in a while. Every page save produces a
    /// new key, so without this the cover folder only grows.
    ///
    /// Lists and stats every cached cover, so it runs off the main actor.
    nonisolated static func pruneStaleCovers(store: LibraryStore, olderThan age: TimeInterval = 7 * 24 * 60 * 60) {
        let directory = coversDirectory(store: store)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-age)
        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func cacheKey(
        notebookID: UUID,
        pageID: UUID,
        updatedAt: Date,
        usesDarkPaper: Bool = false
    ) -> String {
        // Whole seconds are enough to tell one cover render from the next.
        let seconds = Int(updatedAt.timeIntervalSince1970)
        let paper = usesDarkPaper ? "-dark" : ""
        return "\(notebookID.uuidString.lowercased())-\(pageID.uuidString.lowercased())-\(seconds)\(paper)"
    }

    nonisolated private static func coversDirectory(store: LibraryStore) -> URL {
        store.cacheDirectoryURL.appendingPathComponent("covers", isDirectory: true)
    }

    private static func cost(of image: InkImage) -> Int {
        #if os(iOS)
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        #else
        let pixels = image.size.width * image.size.height
        #endif
        return Int(pixels * 4)
    }
}
