import CoreGraphics
import Foundation
import NoteCore
import PDFKit

/// A place on a page to mark for a search, in page coordinates.
public struct PageMatchMark: Hashable, Sendable {
    public var rect: CGRect
    /// Degrees, for a text box that is rotated on the page.
    public var rotation: Double

    public init(rect: CGRect, rotation: Double = 0) {
        self.rect = rect
        self.rotation = rotation
    }
}

/// Finds typed-text and PDF matches on a page. Handwriting is found by
/// Apple's ink search instead (`PencilKitRecognizer.inkBounds`).
public enum PageMatchLocator {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Text boxes and sticky notes holding any of the query's words or phrases.
    public static func typedTextMarks(for query: SearchQuery, in page: Page) -> [PageMatchMark] {
        let terms = query.positiveTerms
        guard !terms.isEmpty else { return [] }
        return page.visibleElements.compactMap { element in
            let text: String
            switch element.content {
            case let .text(value, _, _, _): text = value
            case let .stickyNote(value, _): text = value
            default: return nil
            }
            guard terms.contains(where: { text.range(of: $0, options: options) != nil }) else { return nil }
            let frame = element.frame
            return PageMatchMark(
                rect: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                rotation: frame.rotation
            )
        }
    }

    /// Each occurrence of the query's words or phrases in the page's PDF text,
    /// mapped from the PDF page onto where it is drawn.
    ///
    /// Checks cancellation between elements and terms: a page flip with a search
    /// open abandons the page no longer on screen.
    public static func pdfMarks(for query: SearchQuery, in page: Page, assetsDirectory: URL?) -> [PageMatchMark] {
        let terms = query.positiveTerms
        guard !terms.isEmpty, let assetsDirectory, !Task.isCancelled else { return [] }

        var marks: [PageMatchMark] = []
        for element in page.visibleElements {
            guard !Task.isCancelled else { return marks }
            guard case let .pdfPage(assetName, pageIndex) = element.content,
                  pageIndex >= 0,
                  // Rotated PDF elements are not mapped, as for PDF links.
                  abs(element.frame.rotation) < 0.01,
                  let document = PDFDocument(url: assetsDirectory.appendingPathComponent(assetName)),
                  let pdfPage = document.page(at: pageIndex),
                  let string = pdfPage.string
            else { continue }

            let bounds = pdfPage.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            // Aspect-fit and centred in the element, as the renderer and PDFLinkHandler do.
            let scale = min(element.frame.width / bounds.width, element.frame.height / bounds.height)
            guard scale > 0 else { continue }
            let originX = element.frame.x + (element.frame.width - bounds.width * scale) / 2
            let originY = element.frame.y + (element.frame.height - bounds.height * scale) / 2

            let text = string as NSString
            for term in terms {
                var searchRange = NSRange(location: 0, length: text.length)
                while searchRange.length > 0 {
                    guard !Task.isCancelled else { return marks }
                    let found = text.range(of: term, options: options, range: searchRange)
                    guard found.location != NSNotFound, found.length > 0 else { break }
                    if let selection = pdfPage.selection(for: found) {
                        // One rect per line, so a match that wraps is marked on both lines.
                        for line in selection.selectionsByLine() {
                            let box = line.bounds(for: pdfPage)
                            guard !box.isEmpty else { continue }
                            marks.append(PageMatchMark(rect: CGRect(
                                x: originX + (box.minX - bounds.minX) * scale,
                                y: originY + (bounds.maxY - box.maxY) * scale,
                                width: box.width * scale,
                                height: box.height * scale
                            )))
                        }
                    }
                    let next = found.location + found.length
                    searchRange = NSRange(location: next, length: text.length - next)
                }
            }
        }
        return marks
    }
}
