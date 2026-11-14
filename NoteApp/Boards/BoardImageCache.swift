import CoreGraphics
import Foundation
import ImageIO

/// A decoded board image and the memory it holds.
final class BoardDecodedImage {
    let cgImage: CGImage

    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Decoded images for the photos inserted into boards, keyed by file path.
///
/// A board item is a live view: panning or zooming rebuilds the item layer, so
/// a photo used to be read and decoded from disk again on every frame it was
/// on screen. Decoding now happens once, off the main actor, and the result is
/// kept here.
///
/// Entries cost their real decoded size and the total is capped at 64 MB, so a
/// board's photos cannot pin hundreds of megabytes on a 4 GB iPad.
///
/// `BoardImageCache.removeAll()` is the hook for the memory-warning purge in
/// `NoteApp/MemoryPressure.swift`.
final class BoardImageCache {
    static let shared = BoardImageCache()

    /// 64 MB of decoded pixels.
    private static let totalCostLimit = 64 * 1_024 * 1_024

    private let cache = NSCache<NSString, BoardDecodedImage>()

    private init() {
        cache.totalCostLimit = Self.totalCostLimit
    }

    /// The decoded image for a file, when it is already in memory.
    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url.path as NSString)?.cgImage
    }

    /// Adds a decoded image, charging the memory its pixels occupy.
    func store(_ image: CGImage, for url: URL) {
        let cost = image.bytesPerRow * image.height
        cache.setObject(BoardDecodedImage(image), forKey: url.path as NSString, cost: cost)
    }

    /// Empties the cache. Called when iOS warns that memory is low.
    static func removeAll() {
        shared.cache.removeAllObjects()
    }
}

/// Reads and decodes a board image off the main actor.
///
/// Returns a `CGImage` so nothing platform-specific crosses back to the main
/// actor; the view builds its own image from it cheaply.
enum BoardImageDecoder {
    /// The longest edge a board photo is decoded at. A photo is inserted at no
    /// more than 480 points and can be zoomed to 4×, so 2,048 px is sharp and
    /// caps one photo at 16 MB of pixels.
    nonisolated static let maximumPixelSize = 2_048

    /// Decodes the image in `url`, honouring its orientation and capping its
    /// longest edge. `nil` when the file is missing or is not an image.
    ///
    /// The image source draws the thumbnail itself, which decodes the pixels
    /// here rather than deferring the work to the first draw on the main actor.
    nonisolated static func decode(fileAt url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
