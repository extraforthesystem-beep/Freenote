import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Where an image block's file lives.
///
/// A block stores the name its Markdown import gave it, so the file is looked
/// up beside the document files; an absolute path is used as it is.
enum TextDocAssetLocation {
    /// The file URL for `name`, or `nil` when the block has no name.
    nonisolated static func url(named name: String, in directory: URL) -> URL? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if name.hasPrefix("/") {
            return URL(fileURLWithPath: name)
        }
        return directory.appending(path: name, directoryHint: .notDirectory)
    }
}

/// A decoded text-document image and the memory it holds.
final class TextDocDecodedImage {
    let cgImage: CGImage

    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Decoded image-block pictures, keyed by file path.
///
/// A block is a live view, so scrolling it out of the lazy list and back would
/// otherwise decode the file again. Decoding happens off the main actor and the
/// result is kept here, capped so a document with many photos cannot pin
/// hundreds of megabytes on a 4 GB iPad.
final class TextDocImageCache {
    static let shared = TextDocImageCache()

    /// 48 MB of decoded pixels.
    private static let totalCostLimit = 48 * 1_024 * 1_024

    private let cache = NSCache<NSString, TextDocDecodedImage>()

    private init() {
        cache.totalCostLimit = Self.totalCostLimit
    }

    /// The decoded image for a file, when it is already in memory.
    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url.path as NSString)?.cgImage
    }

    /// Adds a decoded image, charging the memory its pixels occupy.
    func store(_ image: CGImage, for url: URL) {
        cache.setObject(
            TextDocDecodedImage(image),
            forKey: url.path as NSString,
            cost: image.bytesPerRow * image.height
        )
    }
}

/// Reads and decodes an image block's file off the main actor.
enum TextDocImageDecoder {
    /// The longest edge an image block is decoded at. A block is at most a
    /// printed page wide, so 2,048 px is sharp and caps one picture at 16 MB of
    /// pixels.
    nonisolated static let maximumPixelSize = 2_048

    /// Decodes the image in `url`, honouring its orientation and capping its
    /// longest edge. `nil` when the file is missing or is not an image.
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

/// An image block's picture, with the file name as its caption.
///
/// The picture is decoded once, off the main actor, and the last one stays up
/// while a new asset loads. While loading, and when the file cannot be read,
/// the block shows the same glyph it always did.
struct TextDocImageBlock: View {
    let assetName: String
    /// The width the block was imported at, in points.
    let width: Double
    let directory: URL

    @State private var image: CGImage?

    private var displayWidth: CGFloat {
        max(CGFloat(width), 44)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: displayWidth, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.s, style: .continuous))

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, AppSpacing.xxs)
        // Keyed by the asset, so a re-render never repeats the decode.
        .task(id: assetName) {
            await load()
        }
    }

    private var caption: String {
        assetName.isEmpty ? "Untitled image" : assetName
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: AppRadius.s, style: .continuous)
            .fill(Color.secondary.opacity(0.07))
            .frame(height: 96)
            .overlay {
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private func load() async {
        guard let url = TextDocAssetLocation.url(named: assetName, in: directory) else {
            image = nil
            return
        }
        if let cached = TextDocImageCache.shared.image(for: url) {
            image = cached
            return
        }
        guard !Task.isCancelled else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            TextDocImageDecoder.decode(fileAt: url)
        }.value
        guard !Task.isCancelled, let decoded else { return }
        TextDocImageCache.shared.store(decoded, for: url)
        image = decoded
    }
}
