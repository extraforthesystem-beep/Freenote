import Foundation
import InkKit
import NoteCore
import SwiftUI
#if os(iOS)
import CoreImage
import UIKit
#else
import AppKit
import CoreImage
#endif

/// How page paper is drawn.
///
/// Paper stays paper: a page is white whatever the interface appearance, as it
/// is in GoodNotes, and the PencilKit canvas uses light appearance so black ink
/// stays black. With Dark Paper on and the app in dark mode the page is dark
/// grey, template lines are light, and the canvas uses dark appearance so
/// PencilKit draws the ink light-on-dark for display only; stored stroke
/// colours never change.
///
/// Page images (inactive pages in the seamless scroll, thumbnails, the Mac
/// reader) are rendered here too, so they match the live page: the paper and
/// template are recoloured and the ink layer is inverted, while images and
/// other elements keep their true colours. Exports render through
/// `PageRenderer` with the page's own template, so they are always light paper.
///
/// `nonisolated` because page images are rendered off the main actor.
nonisolated enum PaperAppearance {
    /// The paper of a page in dark paper mode (#1E1E1E).
    static let darkPaper = RGBAColor(r: 0.118, g: 0.118, b: 0.118)
    /// Template lines on dark paper: readable under the ink, never bright.
    static let darkLine = RGBAColor(r: 0.46, g: 0.49, b: 0.54)
    /// Paper with no fill, for rendering the ink on its own.
    private static let clearPaper = RGBAColor(r: 0, g: 0, b: 0, a: 0)

    /// The template with paper and lines swapped for the dark sheet.
    static func template(_ template: PageTemplate, usesDarkPaper: Bool) -> PageTemplate {
        guard usesDarkPaper else { return template }
        var dark = template
        dark.paperColor = darkPaper
        dark.lineColor = darkLine
        return dark
    }

    /// A rendered page. Light paper renders in one pass as before; dark paper
    /// composites a dark sheet (elements in true colour) and inverted ink.
    static func image(page: Page, assetsDirectory: URL?, scale: CGFloat, usesDarkPaper: Bool) -> InkImage? {
        image(
            strokes: page.renderStrokes,
            pageSize: CGSize(width: page.width, height: page.height),
            template: page.template,
            elements: page.visibleElements,
            assetsDirectory: assetsDirectory,
            scale: scale,
            usesDarkPaper: usesDarkPaper
        )
    }

    /// The same render as `PageRenderer.image`, in the chosen paper.
    static func image(
        strokes: [StrokeRecord],
        pageSize: CGSize,
        template: PageTemplate,
        elements: [PageElement] = [],
        assetsDirectory: URL? = nil,
        scale: CGFloat = 2,
        usesDarkPaper: Bool
    ) -> InkImage? {
        guard usesDarkPaper else {
            return PageRenderer.image(
                strokes: strokes,
                pageSize: pageSize,
                template: template,
                elements: elements,
                assetsDirectory: assetsDirectory,
                scale: scale
            )
        }

        guard let paper = PageRenderer.image(
            strokes: [],
            pageSize: pageSize,
            template: self.template(template, usesDarkPaper: true),
            elements: elements,
            assetsDirectory: assetsDirectory,
            scale: scale
        ) else { return nil }

        guard !strokes.isEmpty,
              let ink = PageRenderer.image(
                  strokes: strokes,
                  pageSize: pageSize,
                  template: PageTemplate(
                      kind: "blank",
                      spacing: 0,
                      lineColor: clearPaper,
                      paperColor: clearPaper
                  ),
                  scale: scale
              ),
              let invertedInk = inverted(ink, pageSize: pageSize, scale: scale),
              let combined = composite(paper: paper, ink: invertedInk, pageSize: pageSize, scale: scale)
        else { return paper }
        return combined
    }

    #if os(iOS)
    /// The page slot's own colour, behind a loading page image.
    static func pageBackgroundColor(usesDarkPaper: Bool) -> UIColor {
        guard usesDarkPaper else { return .white }
        return UIColor(
            red: darkPaper.r,
            green: darkPaper.g,
            blue: darkPaper.b,
            alpha: 1
        )
    }
    #endif

    // MARK: - Bitmaps

    /// Core Image is thread safe and the context is reused across renders.
    private static let ciContext = CIContext()

    /// The ink layer with its colours inverted, so stored black ink shows as
    /// light ink on dark paper. Transparency is preserved.
    private static func inverted(_ image: InkImage, pageSize: CGSize, scale: CGFloat) -> InkImage? {
        guard let source = cgImage(of: image),
              let filter = CIFilter(name: "CIColorInvert")
        else { return image }
        filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              let result = ciContext.createCGImage(output, from: output.extent)
        else { return image }
        return platformImage(result, pageSize: pageSize, scale: scale)
    }

    private static func composite(
        paper: InkImage,
        ink: InkImage,
        pageSize: CGSize,
        scale: CGFloat
    ) -> InkImage? {
        guard let paperImage = cgImage(of: paper), let inkImage = cgImage(of: ink) else { return nil }
        let width = paperImage.width
        let height = paperImage.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.draw(paperImage, in: rect)
        context.draw(inkImage, in: rect)
        guard let combined = context.makeImage() else { return nil }
        return platformImage(combined, pageSize: pageSize, scale: scale)
    }

    private static func cgImage(of image: InkImage) -> CGImage? {
        #if os(iOS)
        image.cgImage
        #else
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    private static func platformImage(_ cgImage: CGImage, pageSize: CGSize, scale: CGFloat) -> InkImage {
        #if os(iOS)
        UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #else
        NSImage(cgImage: cgImage, size: pageSize)
        #endif
    }
}

extension RGBAColor {
    /// The light-on-dark counterpart of a colour, for previews drawn over dark
    /// paper while a stroke is caught on an inactive page.
    var forDarkPaper: RGBAColor {
        RGBAColor(r: 1 - r, g: 1 - g, b: 1 - b, a: a)
    }
}

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
    /// The page is drawn on dark paper.
    var usesDarkPaper: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var sharp: (key: String, image: InkImage)?

    private var baseKey: String {
        PageBackgroundCache.baseKey(
            for: page,
            assetsDirectory: assetsDirectory,
            usesDarkPaper: usesDarkPaper
        )
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
            } else if let image = PageBackgroundCache.image(
                for: page,
                assetsDirectory: assetsDirectory,
                usesDarkPaper: usesDarkPaper
            ) {
                Image(inkImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Paper is the page's own colour whatever the appearance.
                AppColor.paper(usesDarkPaper: usesDarkPaper)
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
        let usesDarkPaper = usesDarkPaper
        let rendered = await Task.detached(priority: .userInitiated) {
            PaperAppearance.image(
                strokes: [],
                pageSize: CGSize(width: page.width, height: page.height),
                template: page.template,
                elements: page.visibleElements,
                assetsDirectory: assetsDirectory,
                scale: scale,
                usesDarkPaper: usesDarkPaper
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
    static func image(for page: Page, assetsDirectory: URL?, usesDarkPaper: Bool = false) -> InkImage? {
        let key = baseKey(for: page, assetsDirectory: assetsDirectory, usesDarkPaper: usesDarkPaper)
        if let cached = cached(key: key, scale: baseScale) {
            return cached
        }

        guard let image = PaperAppearance.image(
            strokes: [],
            pageSize: CGSize(width: page.width, height: page.height),
            template: page.template,
            elements: page.visibleElements,
            assetsDirectory: assetsDirectory,
            scale: baseScale,
            usesDarkPaper: usesDarkPaper
        ) else { return nil }

        store(image, key: key, scale: baseScale, page: page)
        return image
    }

    static func removeAll() {
        cache.removeAllObjects()
    }

    static func cached(key: String, scale: CGFloat) -> InkImage? {
        cache.object(forKey: "\(key)@\(scale)" as NSString)
    }

    static func store(_ image: InkImage, key: String, scale: CGFloat, page: Page) {
        let cost = Int(page.width * page.height * scale * scale * 4)
        cache.setObject(image, forKey: "\(key)@\(scale)" as NSString, cost: cost)
    }

    static func baseKey(for page: Page, assetsDirectory: URL?, usesDarkPaper: Bool = false) -> String {
        let elements = page.visibleElements
            .map { "\($0.id.uuidString)-\($0.zIndex)-\($0.updatedAt.timeIntervalSince1970)-\($0.isLocked)" }
            .joined(separator: ",")
        let paper = usesDarkPaper ? "-dark" : ""
        return "\(page.id.uuidString)-\(page.width)x\(page.height)-\(page.template)-\(elements)-\(assetsDirectory?.path ?? "")\(paper)"
    }
}
