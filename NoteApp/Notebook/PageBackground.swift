import Foundation
import InkKit
import NoteCore
import SwiftUI

/// The full page background — paper and elements — drawn by InkKit. The ink is
/// left to the canvas on top.
struct PaperBackground: View {
    let page: Page
    let assetsDirectory: URL?

    var body: some View {
        if let image = PageBackgroundCache.image(for: page, assetsDirectory: assetsDirectory) {
            Image(inkImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Color.white
        }
    }
}

@MainActor
enum PageBackgroundCache {
    private static let cache: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func image(for page: Page, assetsDirectory: URL?) -> InkImage? {
        let key = cacheKey(for: page, assetsDirectory: assetsDirectory)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = PageRenderer.image(
            strokes: [],
            pageSize: CGSize(width: page.width, height: page.height),
            template: page.template,
            elements: page.elements,
            assetsDirectory: assetsDirectory,
            scale: 2
        ) else { return nil }

        let cost = Int(page.width * page.height * 4 * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func cacheKey(for page: Page, assetsDirectory: URL?) -> NSString {
        let elements = page.elements
            .map { "\($0.id.uuidString)-\($0.zIndex)-\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: ",")
        return "\(page.id.uuidString)-\(page.width)x\(page.height)-\(page.template)-\(elements)-\(assetsDirectory?.path ?? "")" as NSString
    }
}
