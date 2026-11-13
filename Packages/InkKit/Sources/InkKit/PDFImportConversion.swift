import CoreGraphics
import Foundation
import NoteCore
import PDFKit
import PencilKit

// PDFKit hands ink paths as UIBezierPath on iOS and NSBezierPath on macOS;
// only their shared `cgPath` is used here.
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One ink annotation path, already in the notebook's page space.
///
/// The app's pages are y-down with the origin at the top-left corner of the
/// media box; a PDF page is y-up with the origin at its bottom-left. A PDF ink
/// annotation drawn at (30, 60) on a 300 pt tall page therefore lands at
/// (30, 240) here.
public struct PDFInkStroke: Sendable, Hashable {
    public var color: RGBAColor
    /// Line width in page points, already scaled for the page's own rotation.
    public var width: Double
    public var points: [CGPoint]

    public init(color: RGBAColor, width: Double, points: [CGPoint]) {
        self.color = color
        self.width = width
        self.points = points
    }
}

/// One entry of a PDF's table of contents, flattened.
public struct PDFOutlineItem: Sendable, Hashable {
    public var title: String
    /// The PDF page the entry points at, or nil when it points nowhere.
    public var pageIndex: Int?
    /// Nesting level: 0 for a top-level entry.
    public var depth: Int

    public init(title: String, pageIndex: Int?, depth: Int) {
        self.title = title
        self.pageIndex = pageIndex
        self.depth = depth
    }
}

/// The parts of a PDF import that are pure geometry and PDFKit reading, kept
/// out of the app so they can be tested without a notebook or a view.
public enum PDFImportConversion {
    /// Used when an annotation has no usable border width.
    public static let defaultInkWidth: Double = 2

    /// `StrokeTool.engine` for ink that came from a PDF annotation.
    public static let engine = "pdf"

    /// Guard against a collapsed or pathological drawing transform.
    static let minimumWidth: Double = 0.25
    static let maximumWidth: Double = 60
    /// Deeper outlines are cut off rather than walked forever.
    static let maximumOutlineDepth = 16

    // MARK: - Ink annotations

    /// True for an ink annotation whose paths can become editable strokes.
    /// Other annotation types (highlight, underline, links, widgets) stay in
    /// the PDF and keep rendering as part of the page.
    public static func isConvertibleInk(_ annotation: PDFAnnotation) -> Bool {
        guard isInkType(annotation.type) else { return false }
        // Hidden ink stays in the PDF, hidden, rather than becoming visible strokes.
        guard annotation.shouldDisplay else { return false }
        guard let paths = annotation.paths, !paths.isEmpty else { return false }
        return paths.contains { !$0.cgPath.isEmpty }
    }

    /// PDFKit reports an annotation's type as `"Ink"` for one the app made and
    /// `"/Ink"` for one read from a file, depending on the SDK, so the leading
    /// slash and the case are both ignored.
    static func isInkType(_ type: String?) -> Bool {
        guard let type else { return false }
        let name = type.hasPrefix("/") ? String(type.dropFirst()) : type
        return name.caseInsensitiveCompare("Ink") == .orderedSame
    }

    /// The constant opacity (`/CA`) each annotation on `page` is drawn with,
    /// keyed by its bounds (see `rectKey`). An annotation without one, or with
    /// a fully opaque one, is left out.
    ///
    /// PDFKit has no accessor for `/CA`: it reads the name as a widget's
    /// caption string, so a numeric value never reaches
    /// `value(forAnnotationKey:)`. The values come from the PDF page itself and
    /// are matched to the `PDFAnnotation` objects by their bounds.
    static func constantOpacities(in page: PDFPage) -> [String: Double] {
        guard let dictionary = page.pageRef?.dictionary else { return [:] }
        var annots: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Annots", &annots), let annots else {
            return [:]
        }

        var result: [String: Double] = [:]
        let count = CGPDFArrayGetCount(annots)
        for index in 0..<count {
            var object: CGPDFObjectRef?
            guard CGPDFArrayGetObject(annots, index, &object),
                  let object,
                  CGPDFObjectGetType(object) == .dictionary
            else { continue }
            var annotation: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &annotation),
                  let annotation
            else { continue }

            var opacity: CGPDFReal = 1
            guard CGPDFDictionaryGetNumber(annotation, "CA", &opacity),
                  opacity < 1,
                  let bounds = bounds(of: annotation)
            else { continue }
            result[rectKey(bounds)] = Double(max(0, opacity))
        }
        return result
    }

    /// Bounds as a lookup key, to a hundredth of a point: PDFKit's bounds and
    /// the PDF's own `/Rect` are the same numbers.
    static func rectKey(_ rect: CGRect) -> String {
        String(
            format: "%.2f,%.2f,%.2f,%.2f",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }

    /// An annotation's `/Rect` as a rectangle, or nil when it is not four
    /// numbers.
    static func bounds(of annotation: CGPDFDictionaryRef) -> CGRect? {
        var rects: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(annotation, "Rect", &rects),
              let rects,
              CGPDFArrayGetCount(rects) == 4
        else { return nil }

        var values: [CGFloat] = []
        for index in 0..<4 {
            var object: CGPDFObjectRef?
            guard CGPDFArrayGetObject(rects, index, &object), let object else { return nil }
            var real: CGPDFReal = 0
            var integer: CGPDFInteger = 0
            if CGPDFObjectGetValue(object, .real, &real) {
                values.append(CGFloat(real))
            } else if CGPDFObjectGetValue(object, .integer, &integer) {
                values.append(CGFloat(integer))
            } else {
                return nil
            }
        }
        return CGRect(
            x: values[0],
            y: values[1],
            width: values[2] - values[0],
            height: values[3] - values[1]
        )
    }

    /// Every ink annotation path on `page`, mapped into page space.
    ///
    /// A path with several subpaths becomes one `PDFInkStroke` per subpath, so
    /// separate pen lifts are never joined by one stroke. An annotation's
    /// constant opacity (`/CA`), which other apps write for translucent ink,
    /// is folded into the colour's alpha.
    public static func inkStrokes(in page: PDFPage, pageSize: CGSize) -> [PDFInkStroke] {
        guard pageSize.width > 0, pageSize.height > 0 else { return [] }
        let transform = drawingTransform(for: page, pageSize: pageSize)
        let widthScale = widthScale(of: transform)
        let opacities = constantOpacities(in: page)

        var strokes: [PDFInkStroke] = []
        for annotation in page.annotations where isConvertibleInk(annotation) {
            var color = RGBAColor(srgb: annotation.color) ?? .black
            if let opacity = opacities[rectKey(annotation.bounds)] {
                color.a = min(1, max(0, color.a * opacity))
            }
            let lineWidth = annotation.border?.lineWidth ?? 0
            let baseWidth = lineWidth > 0 ? Double(lineWidth) : defaultInkWidth
            let width = min(max(baseWidth * widthScale, minimumWidth), maximumWidth)
            // PDFKit gives ink paths read from a file relative to the
            // annotation's bounds origin. Paths added in memory come back as
            // they were given, so call this on parsed documents only.
            let origin = annotation.bounds.origin

            for path in annotation.paths ?? [] {
                for polyline in polylines(from: path.cgPath) {
                    let points = polyline.compactMap {
                        pagePoint(
                            CGPoint(x: $0.x + origin.x, y: $0.y + origin.y),
                            transform: transform,
                            pageHeight: Double(pageSize.height)
                        )
                    }
                    guard !points.isEmpty else { continue }
                    strokes.append(PDFInkStroke(color: color, width: width, points: points))
                }
            }
        }
        return strokes
    }

    /// The strokes as editable records for one page layer.
    public static func strokeRecords(
        for strokes: [PDFInkStroke],
        layerID: UUID,
        createdAt: Date = Date()
    ) -> [StrokeRecord] {
        let step = 1.0 / 120
        return strokes.compactMap { stroke in
            guard let first = stroke.points.first else { return nil }
            // A dot annotation has a single point. PencilKit needs two ends.
            let points = stroke.points.count == 1 ? [first, first] : stroke.points
            let width = max(stroke.width, minimumWidth)
            let samples = points.enumerated().map { index, point in
                StrokePoint(
                    x: Double(point.x),
                    y: Double(point.y),
                    timeOffset: Double(index) * step,
                    width: width,
                    height: width,
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2,
                    secondaryScale: 1
                )
            }
            return StrokeRecord(
                id: UUID(),
                layerID: layerID,
                tool: StrokeTool(
                    engine: engine,
                    inkType: PKInk.InkType.pen.rawValue,
                    color: stroke.color,
                    width: width
                ),
                createdAt: createdAt,
                randomSeed: UInt32.random(in: 1...UInt32.max),
                points: samples
            )
        }
    }

    // MARK: - Geometry

    /// Maps PDF page space into the unflipped element box the page renderer
    /// draws into, the same way `PageElementRenderer` asks CoreGraphics to draw
    /// the page: media box, rotation applied, aspect fit, centred.
    public static func drawingTransform(for page: PDFPage, pageSize: CGSize) -> CGAffineTransform {
        let box = CGRect(origin: .zero, size: pageSize)
        guard let pageRef = page.pageRef else { return .identity }
        return pageRef.getDrawingTransform(
            .mediaBox,
            rect: box,
            rotate: 0,
            preserveAspectRatio: true
        )
    }

    /// One PDF page-space point in page space (y-down). Nil when the transform
    /// produces something that cannot be drawn.
    public static func pagePoint(
        _ point: CGPoint,
        transform: CGAffineTransform,
        pageHeight: Double
    ) -> CGPoint? {
        let mapped = point.applying(transform)
        let result = CGPoint(x: mapped.x, y: pageHeight - mapped.y)
        guard result.x.isFinite, result.y.isFinite else { return nil }
        return result
    }

    /// How much a drawing transform scales, for line widths.
    static func widthScale(of transform: CGAffineTransform) -> Double {
        let determinant = Double(transform.a * transform.d - transform.b * transform.c)
        let scale = abs(determinant).squareRoot()
        guard scale.isFinite, scale > 0 else { return 1 }
        return scale
    }

    // MARK: - Stored copy

    /// PDF bytes for the notebook's assets: the pages are copied into a fresh
    /// document, which also removes the encryption of an unlocked, password
    /// protected file, and the ink annotations that became strokes are removed
    /// from the given page indices so they cannot render twice.
    ///
    /// Everything else (page content, other annotations, links) is kept.
    public static func data(
        removingInkAnnotationsOn pageIndices: Set<Int>,
        from document: PDFDocument
    ) -> Data? {
        let clean = PDFDocument()
        // A page PDFKit cannot hand back would shift the numbering, so the
        // mapping from source page to copied page is kept.
        var copyIndexBySourceIndex: [Int: Int] = [:]
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            copyIndexBySourceIndex[index] = clean.pageCount
            clean.insert(page, at: clean.pageCount)
        }
        for sourceIndex in pageIndices {
            guard let copyIndex = copyIndexBySourceIndex[sourceIndex],
                  let page = clean.page(at: copyIndex)
            else { continue }
            for annotation in page.annotations where isConvertibleInk(annotation) {
                page.removeAnnotation(annotation)
            }
        }
        return clean.dataRepresentation()
    }

    // MARK: - Path flattening

    /// A path as polylines. Curves are sampled, and a lone point becomes a
    /// two-point line so a dot annotation still renders.
    static func polylines(from path: CGPath) -> [[CGPoint]] {
        var polylines: [[CGPoint]] = []
        var current: [CGPoint] = []

        func finish() {
            if current.count >= 2 {
                polylines.append(current)
            } else if let only = current.first {
                polylines.append([only, only])
            }
            current.removeAll(keepingCapacity: true)
        }

        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                finish()
                current = [element.points[0]]
            case .addLineToPoint:
                current.append(element.points[0])
            case .addQuadCurveToPoint:
                let start = current.last ?? element.points[0]
                appendQuad(
                    from: start,
                    control: element.points[0],
                    to: element.points[1],
                    into: &current
                )
            case .addCurveToPoint:
                let start = current.last ?? element.points[0]
                appendCubic(
                    from: start,
                    control1: element.points[0],
                    control2: element.points[1],
                    to: element.points[2],
                    into: &current
                )
            case .closeSubpath:
                if let first = current.first { current.append(first) }
            @unknown default:
                break
            }
        }
        finish()
        return polylines
    }

    static func appendQuad(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint],
        steps: Int = 8
    ) {
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let inverse = 1 - t
            points.append(
                CGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                )
            )
        }
    }

    static func appendCubic(
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint],
        steps: Int = 12
    ) {
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let inverse = 1 - t
            let a = inverse * inverse * inverse
            let b = 3 * inverse * inverse * t
            let c = 3 * inverse * t * t
            let d = t * t * t
            points.append(
                CGPoint(
                    x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                    y: a * start.y + b * control1.y + c * control2.y + d * end.y
                )
            )
        }
    }

    // MARK: - Outline

    /// The document's table of contents, depth first, in reading order.
    public static func outlineItems(in document: PDFDocument) -> [PDFOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        var items: [PDFOutlineItem] = []

        func visit(_ outline: PDFOutline, depth: Int) {
            guard depth <= maximumOutlineDepth else { return }
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    items.append(
                        PDFOutlineItem(
                            title: title,
                            pageIndex: pageIndex(of: child, in: document),
                            depth: depth
                        )
                    )
                }
                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 0)
        return items
    }

    /// The page an outline entry points at. A destination page is the usual
    /// case; a GoTo action is the other way a PDF can store the target.
    static func pageIndex(of outline: PDFOutline, in document: PDFDocument) -> Int? {
        var page = outline.destination?.page
        if page == nil, let goTo = outline.action as? PDFActionGoTo {
            page = goTo.destination.page
        }
        guard let page else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index
    }
}
