import Foundation
import InkKit
import NoteCore
import SwiftUI

/// The full page background — paper and elements — drawn by InkKit. The ink is
/// left to the canvas on top.
///
/// A 2× bitmap is drawn at once so the page never appears blank. When the page
/// is zoomed in, a sharper bitmap for the settled zoom is rendered off the main
/// actor and replaces it.
struct PaperBackground: View {
    let page: Page
    let assetsDirectory: URL?
    /// The page's zoom scale; 1 when the page is shown at its natural size.
    var zoomScale: CGFloat = 1

    @Environment(\.displayScale) private var displayScale
    @State private var sharp: (key: String, image: InkImage)?

    private var baseKey: String {
        PageBackgroundCache.baseKey(for: page, assetsDirectory: assetsDirectory)
    }

    private var targetScale: CGFloat {
        PageBackgroundCache.bucket(zoomScale * displayScale)
    }

    var body: some View {
        let key = baseKey
        Group {
            if let sharp, sharp.key == key {
                Image(inkImage: sharp.image)
                    .resizable()
                    .interpolation(.high)
            } else if let image = PageBackgroundCache.image(for: page, assetsDirectory: assetsDirectory) {
                Image(inkImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Paper is white whatever the appearance.
                Color.white
            }
        }
        .task(id: "\(key)@\(targetScale)") {
            await renderSharp(key: key, scale: targetScale)
        }
    }

    private func renderSharp(key: String, scale: CGFloat) async {
        guard scale > PageBackgroundCache.baseScale else {
            if sharp?.key != key { sharp = nil }
            return
        }
        if let cached = PageBackgroundCache.cached(key: key, scale: scale) {
            sharp = (key, cached)
            return
        }
        // Let a pinch or a run of edits settle before doing the work.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let page = page
        let assetsDirectory = assetsDirectory
        let rendered = await Task.detached(priority: .userInitiated) {
            PageRenderer.image(
                strokes: [],
                pageSize: CGSize(width: page.width, height: page.height),
                template: page.template,
                elements: page.visibleElements,
                assetsDirectory: assetsDirectory,
                scale: scale
            )
        }.value
        guard !Task.isCancelled, let rendered else { return }
        PageBackgroundCache.store(rendered, key: key, scale: scale, page: page)
        sharp = (key, rendered)
    }
}

@MainActor
enum PageBackgroundCache {
    static let baseScale: CGFloat = 2
    /// Sharper than this costs a lot of memory for little visible gain.
    static let maximumScale: CGFloat = 4

    private static let cache: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    /// Rounds a wanted pixel scale to a few steps so small zoom changes reuse
    /// a bitmap.
    static func bucket(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return baseScale }
        let stepped = (scale * 2).rounded(.up) / 2
        return min(max(stepped, baseScale), maximumScale)
    }

    /// The 2× background, rendered synchronously when it is not cached.
    static func image(for page: Page, assetsDirectory: URL?) -> InkImage? {
        let key = baseKey(for: page, assetsDirectory: assetsDirectory)
        if let cached = cached(key: key, scale: baseScale) {
            return cached
        }

        guard let image = PageRenderer.image(
            strokes: [],
            pageSize: CGSize(width: page.width, height: page.height),
            template: page.template,
            elements: page.visibleElements,
            assetsDirectory: assetsDirectory,
            scale: baseScale
        ) else { return nil }

        store(image, key: key, scale: baseScale, page: page)
        return image
    }

    static func cached(key: String, scale: CGFloat) -> InkImage? {
        cache.object(forKey: "\(key)@\(scale)" as NSString)
    }

    static func store(_ image: InkImage, key: String, scale: CGFloat, page: Page) {
        let cost = Int(page.width * page.height * scale * scale * 4)
        cache.setObject(image, forKey: "\(key)@\(scale)" as NSString, cost: cost)
    }

    static func baseKey(for page: Page, assetsDirectory: URL?) -> String {
        let elements = page.visibleElements
            .map { "\($0.id.uuidString)-\($0.zIndex)-\($0.updatedAt.timeIntervalSince1970)-\($0.isLocked)" }
            .joined(separator: ",")
        return "\(page.id.uuidString)-\(page.width)x\(page.height)-\(page.template)-\(elements)-\(assetsDirectory?.path ?? "")"
    }
}
