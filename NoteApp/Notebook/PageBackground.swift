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
/// other elements keep their true colours. An imported PDF page, and a custom
/// template, are paper: they are multiplied down to a dim sheet so they never
/// glow white on the dark page, and their text stays dark rather than
/// inverting. Exports render through `PageRenderer` with the page's own
/// template, so they are always light paper.
///
/// `nonisolated` because page images are rendered off the main actor.
nonisolated enum PaperAppearance {
    /// The paper of a page in dark paper mode (#1E1E1E).
    static let darkPaper = RGBAColor(r: 0.118, g: 0.118, b: 0.118)
    /// Template lines on dark paper: readable under the ink, never bright.
    static let darkLine = RGBAColor(r: 0.46, g: 0.49, b: 0.54)
    /// What an imported PDF page or custom template is multiplied by on dark
    /// paper: a dim warm grey sheet. Text and ink stay dark, never inverted.
    static let darkPicture = RGBAColor(r: 0.42, g: 0.41, b: 0.38)
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

        // The PDF page or custom template is the paper of an imported page, so
        // it is dimmed with it; a photo or a sticky note keeps its colours.
        let dimmedPaper = dimmed(
            paper,
            rects: pictureRects(template: template, elements: elements, pageSize: pageSize),
            pageSize: pageSize,
            scale: scale
        )

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
              let combined = composite(paper: dimmedPaper, ink: invertedInk, pageSize: pageSize, scale: scale)
        else { return dimmedPaper }
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

    /// The parts of a dark page that are a picture rather than blank paper: the
    /// imported PDF pages, and a custom template's whole sheet.
    private static func pictureRects(
        template: PageTemplate,
        elements: [PageElement],
        pageSize: CGSize
    ) -> [CGRect] {
        var rects = elements.compactMap { element -> CGRect? in
            guard case .pdfPage = element.content else { return nil }
            return CGRect(
                x: element.frame.x,
                y: element.frame.y,
                width: element.frame.width,
                height: element.frame.height
            )
        }
        if template.customAssetName != nil {
            rects.append(CGRect(origin: .zero, size: pageSize))
        }
        return rects
    }

    /// Multiplies the picture area down to a dim sheet. Multiply keeps dark
    /// text dark — nothing is inverted — while a white page becomes grey.
    private static func dimmed(
        _ image: InkImage,
        rects: [CGRect],
        pageSize: CGSize,
        scale: CGFloat
    ) -> InkImage {
        guard !rects.isEmpty, let source = cgImage(of: image) else { return image }
        let width = source.width
        let height = source.height
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
        else { return image }

        context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setBlendMode(.multiply)
        context.setFillColor(
            CGColor(
                srgbRed: darkPicture.r,
                green: darkPicture.g,
                blue: darkPicture.b,
                alpha: 1
            )
        )
        for rect in rects {
            // A bitmap context counts y from the bottom; page space from the top.
            context.fill(
                CGRect(
                    x: rect.minX * scale,
                    y: (pageSize.height - rect.maxY) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                )
            )
        }
        guard let dimmed = context.makeImage() else { return image }
        return platformImage(dimmed, pageSize: pageSize, scale: scale)
    }

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
/// A cached 2× bitmap is shown at once when there is one. When there is not,
/// the previous image (or the page's paper colour) stays up while the new one
/// renders off the main actor: drawing a PDF page or photo takes tens of
/// milliseconds, and doing that in a view body hitched every element drag.
/// When the page is zoomed in, a sharper bitmap for the settled zoom is
/// rendered off the main actor and replaces it.
struct PaperBackground: View {
    let page: Page
    let assetsDirectory: URL?
    /// The page's zoom scale; 1 when the page is shown at its natural size.
    var zoomScale: CGFloat = 1
    /// The page is drawn on dark paper.
    var usesDarkPaper: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var base: (key: String, image: InkImage)?
    @State private var sharp: (key: String, image: InkImage)?

    private var baseKey: String {
        PageBackgroundCache.baseKey(
            for: page,
            assetsDirectory: assetsDirectory,
            usesDarkPaper: usesDarkPaper
        )
    }

    /// The page's own identity, without its elements: while an element drag
    /// invalidates the image, the last one for this page stays up.
    private var pageKey: String {
        "\(page.id.uuidString)-\(page.width)x\(page.height)-\(page.template)"
    }

    private var targetScale: CGFloat {
        PageBackgroundCache.bucket(zoomScale * displayScale)
    }

    var body: some View {
        let key = baseKey
        Group {
            if let image = image(for: key) {
                Image(inkImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Paper is the page's own colour whatever the appearance.
                AppColor.paper(usesDarkPaper: usesDarkPaper)
            }
        }
        .task(id: "\(key)@\(targetScale)") {
            await renderBase(key: key)
            await renderSharp(key: key, scale: targetScale)
        }
    }

    /// The image to draw now. A cache hit is instant; a miss returns the last
    /// image of this page, and this view never renders one itself.
    private func image(for key: String) -> InkImage? {
        if let sharp, sharp.key == key { return sharp.image }
        if let base, base.key == key { return base.image }
        if let cached = PageBackgroundCache.cached(key: key, scale: PageBackgroundCache.baseScale) {
            return cached
        }
        if let sharp, sharp.key.hasPrefix(pageKey) { return sharp.image }
        if let base, base.key.hasPrefix(pageKey) { return base.image }
        return nil
    }

    private func renderBase(key: String) async {
        guard base?.key != key else { return }
        let scale = PageBackgroundCache.baseScale
        if let cached = PageBackgroundCache.cached(key: key, scale: scale) {
            base = (key, cached)
            return
        }
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
        base = (key, rendered)
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

extension Page {
    /// The page as its paper is drawn: tape is an overlay the user reveals,
    /// not part of the paper. Paper backgrounds and their cache keys use this.
    var withoutTape: Page {
        var page = self
        page.elements.removeAll { element in
            if case .tape = element.content { return true }
            return false
        }
        return page
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

    static func removeAll() {
        cache.removeAllObjects()
    }

    /// Renders the 2× paper of a page the user is likely to open next, off
    /// the main actor, so the page's `PaperBackground` finds it cached.
    ///
    /// An uncached page is rendered off the main actor when it activates, so a
    /// PDF page or photo (tens of milliseconds at 2×: a scanned PDF page is
    /// ~77 ms on an M-class Mac, release, more on a base iPad) would otherwise
    /// show plain paper until its image arrived. Only such pages are
    /// pre-rendered; `page` is the page as drawn (`withoutTape`).
    static func prewarm(_ page: Page, assetsDirectory: URL?, usesDarkPaper: Bool) async {
        let isCostly = page.visibleElements.contains { element in
            switch element.content {
            case .pdfPage, .image: true
            default: false
            }
        }
        guard isCostly else { return }
        let key = baseKey(for: page, assetsDirectory: assetsDirectory, usesDarkPaper: usesDarkPaper)
        guard cached(key: key, scale: baseScale) == nil else { return }
        let scale = baseScale
        let rendered = await Task.detached(priority: .utility) {
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
        guard let rendered, cached(key: key, scale: scale) == nil else { return }
        store(rendered, key: key, scale: scale, page: page)
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
