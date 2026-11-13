import Foundation
import InkKit
import NoteCore

/// First-page renders for library cards.
///
/// Lookups run in three steps: an in-memory cache for the current session, a disk
/// cache keyed by the notebook's page id and `updatedAt`, and finally a render on a
/// background task. Nothing is drawn on the main actor, so scrolling a large library
/// does not stall the frames.
@MainActor
enum LibraryCovers {
    private static let memory: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    /// One shared task per cover, so ten cards showing the same notebook render once.
    private static var inFlight: [String: Task<Data?, Never>] = [:]

    /// A cached image, or nil when the cover has to be produced.
    static func cached(notebook: NotebookManifest) -> InkImage? {
        guard let pageID = notebook.pageOrder.first else { return nil }
        let key = cacheKey(notebookID: notebook.id, pageID: pageID, updatedAt: notebook.updatedAt)
        return memory.object(forKey: key as NSString)
    }

    static func image(
        for notebook: NotebookManifest,
        store: LibraryStore
    ) async -> InkImage? {
        guard let pageID = notebook.pageOrder.first else { return nil }
        let key = cacheKey(notebookID: notebook.id, pageID: pageID, updatedAt: notebook.updatedAt)
        if let cached = memory.object(forKey: key as NSString) { return cached }

        let data: Data?
        if let existing = inFlight[key] {
            data = await existing.value
        } else {
            let diskURL = coversDirectory(store: store).appendingPathComponent("\(key).png")
            let notebookID = notebook.id
            let task = Task<Data?, Never> {
                // The disk cache survives relaunches; the key changes whenever the
                // notebook's content, and therefore its cover, changes.
                let stored: Data? = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: diskURL)
                }.value
                if let stored { return stored }

                guard let page = try? await store.loadPage(pageID, in: notebookID) else { return nil }
                let assets = store.assetsDirectoryURL(for: notebookID)
                return await Task.detached(priority: .utility) { () -> Data? in
                    guard let rendered = PageRenderer.image(
                        strokes: page.renderStrokes,
                        pageSize: CGSize(width: page.width, height: page.height),
                        template: page.template,
                        elements: page.visibleElements,
                        assetsDirectory: assets,
                        scale: 1
                    ) else { return nil }

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
                    return data
                }.value
            }
            inFlight[key] = task
            data = await task.value
            inFlight[key] = nil
        }

        guard let data, let image = InkImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString, cost: cost(of: image))
        return image
    }

    /// Empties the in-memory covers; the disk cache keeps them.
    static func removeAllFromMemory() {
        memory.removeAllObjects()
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

    private static func cacheKey(notebookID: UUID, pageID: UUID, updatedAt: Date) -> String {
        // Whole seconds are enough to tell one cover render from the next.
        let seconds = Int(updatedAt.timeIntervalSince1970)
        return "\(notebookID.uuidString.lowercased())-\(pageID.uuidString.lowercased())-\(seconds)"
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
