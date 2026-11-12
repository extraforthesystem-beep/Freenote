#if os(iOS)
import UIKit

/// Empties the in-memory render caches when iOS warns that memory is low.
///
/// The page images, sharp paper backgrounds, thumbnails, template previews and
/// library covers can hold over 400 MB between them at their cost limits.
/// `NSCache` evicts under pressure on its own schedule, which is not
/// documented to happen at a memory warning; on a 4 GB iPad the warning is the
/// last chance before the app is terminated. Everything here is re-rendered on
/// demand (covers come back from their disk cache), so a purge costs only
/// some re-rendering.
@MainActor
enum MemoryPressure {
    private static var observer: (any NSObjectProtocol)?

    /// Starts listening; later calls do nothing.
    static func purgeCachesOnMemoryWarning() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { purgeCaches() }
        }
    }

    static func purgeCaches() {
        PageImageCache.removeAll()
        PageBackgroundCache.removeAll()
        ThumbnailCache.removeAll()
        TemplateImageCache.removeAll()
        LibraryCovers.removeAllFromMemory()
    }
}
#endif
