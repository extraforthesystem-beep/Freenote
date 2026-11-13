import CoreGraphics
import Foundation
import NoteCore
import PDFKit

#if os(iOS)
import UIKit
private typealias PlatformBezierPath = UIBezierPath
#else
import AppKit
private typealias PlatformBezierPath = NSBezierPath
#endif

/// Streams pages into a vector PDF file, one page at a time, so memory stays
/// flat however long the notebook is.
///
/// Not thread-safe: create, fill and close it on one task.
public final class VectorPDFWriter {
    private var context: CGContext?
    /// Pages added so far.
    public private(set) var pageCount = 0

    /// Opens a PDF at `url` with document metadata. `nil` when the file cannot
    /// be created.
    public init?(url: URL, title: String?, creator: String?) {
        var info: [String: Any] = [:]
        if let title { info[kCGPDFContextTitle as String] = title }
        if let creator { info[kCGPDFContextCreator as String] = creator }
        guard let context = CGContext(url as CFURL, mediaBox: nil, info as CFDictionary) else {
            return nil
        }
        self.context = context
    }

    /// Appends `page` as one PDF page of the page's own size.
    public func addPage(
        _ page: Page,
        assetsDirectory: URL?,
        includeTemplate: Bool = true,
        includeInk: Bool = true
    ) {
        guard let context else { return }
        var box = CGRect(x: 0, y: 0, width: max(page.width, 1), height: max(page.height, 1))
        let boxData = withUnsafeBytes(of: &box) { Data($0) }
        context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
        VectorPageRenderer.draw(
            page: page,
            in: context,
            assetsDirectory: assetsDirectory,
            includeTemplate: includeTemplate,
            includeInk: includeInk
        )
        context.endPDFPage()
        pageCount += 1
    }

    /// Sets a flat document outline (table of contents): one entry per
    /// `(pageIndex, title)`, `pageIndex` counting the pages added so far from
    /// zero. Call before `close()`.
    ///
    /// Written by Core Graphics rather than `PDFDocument.outlineRoot`, which
    /// PDFKit does not save; PDFKit keeps this outline when it rewrites the
    /// file to add annotations.
    public func setOutline(_ entries: [(pageIndex: Int, title: String)]) {
        guard let context else { return }
        let children: [[String: Any]] = entries.compactMap { entry in
            guard entry.pageIndex >= 0, entry.pageIndex < pageCount else { return nil }
            return [
                "Title": entry.title,
                "Destination": entry.pageIndex + 1,
            ]
        }
        guard !children.isEmpty else { return }
        CGPDFContextSetOutline(
            context,
            ["Children": children] as CFDictionary
        )
    }

    /// Finishes the file. Further pages are ignored.
    public func close() {
        context?.closePDF()
        context = nil
    }

    deinit {
        context?.closePDF()
    }
}

/// PDFKit additions to an exported PDF: editable ink annotations.
public enum VectorPDFAnnotations {
    /// True when a stroke's ink is see-through. Its opacity cannot survive as
    /// an annotation — PDFKit writes an ink annotation's colour as `/C`, which
    /// has no alpha component, and refuses to set the constant opacity `/CA`
    /// (PDFKit reads that name as a widget's caption) — so such strokes are
    /// drawn into the page as vectors instead of becoming annotations.
    public static func isTranslucent(_ record: StrokeRecord) -> Bool {
        record.tool.color.a < 1
    }

    /// Adds one PDF ink annotation per opaque stroke of `strokes` to
    /// `pdfPage`, so other apps can select, move, recolour or erase each
    /// stroke.
    ///
    /// `strokes` are in page points with y down (as stored); `pageHeight` flips
    /// them into PDF space. The border width is the stroke's median ink width.
    /// Translucent strokes — highlighters, and anything drawn with a
    /// see-through colour, see `isTranslucent` — are skipped: an annotation
    /// would come out opaque, so the caller flattens them into the page.
    @discardableResult
    public static func addInkAnnotations(
        for strokes: [StrokeRecord],
        to pdfPage: PDFPage,
        pageHeight: CGFloat
    ) -> Int {
        var added = 0
        for record in strokes {
            guard !isTranslucent(record) else { continue }
            guard let line = VectorPageRenderer.centreLine(for: record) else { continue }
            var points = StrokeOutline.simplified(
                line.points.map { CGPoint(x: $0.x, y: pageHeight - $0.y) },
                tolerance: 0.2
            )
            if points.count == 1 {
                // A dot: a tiny segment so the annotation has a path to draw.
                points.append(CGPoint(x: points[0].x + 0.01, y: points[0].y))
            }

            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max()
            else { continue }
            let pad = line.width / 2 + 1
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -pad, dy: -pad)

            // Ink annotation paths are relative to the annotation's origin.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: points[0].x - bounds.minX, y: points[0].y - bounds.minY))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
            }

            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.color = line.color.inkColor
            let border = PDFBorder()
            border.lineWidth = max(line.width, 0.25)
            annotation.border = border
            annotation.add(PlatformBezierPath(cgPath: path))
            // PDFKit would otherwise sign every stroke with the device
            // owner's full name (/T), which a shared export must not carry.
            annotation.userName = nil
            pdfPage.addAnnotation(annotation)
            added += 1
        }
        return added
    }
}
