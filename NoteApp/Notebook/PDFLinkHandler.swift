import CoreGraphics
import Foundation
import NoteCore
import PDFKit

enum PDFLinkTarget: Equatable {
    case url(URL)
    case page(Int)
}

/// Finds the link annotation under a tap in page coordinates. The page's PDF
/// element is drawn aspect-fit inside its frame; this reverses that mapping.
@MainActor
enum PDFLinkHandler {
    /// The last document opened here, with the URL it came from. A tap on a
    /// PDF page would otherwise parse the whole file again (0.2 ms for a
    /// synthetic page, over a millisecond for a 1,000-page book) for one
    /// annotation lookup, on the main actor.
    private static var lastDocument: (url: URL, document: PDFDocument)?

    static func target(
        at point: CGPoint,
        page: Page,
        assetsDirectory: URL?
    ) -> PDFLinkTarget? {
        guard let assetsDirectory else { return nil }

        for element in page.elements {
            guard case let .pdfPage(assetName, pageIndex) = element.content else { continue }
            guard abs(element.frame.rotation) < 0.01 else { continue }
            let frameRect = CGRect(
                x: element.frame.x,
                y: element.frame.y,
                width: element.frame.width,
                height: element.frame.height
            )
            guard frameRect.contains(point) else { continue }

            let url = assetsDirectory.appendingPathComponent(assetName)
            guard let document = document(at: url),
                  let pdfPage = document.page(at: pageIndex)
            else { continue }

            let bounds = pdfPage.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            let scale = min(element.frame.width / bounds.width, element.frame.height / bounds.height)
            guard scale > 0 else { continue }
            let drawnWidth = bounds.width * scale
            let drawnHeight = bounds.height * scale
            let originX = element.frame.x + (element.frame.width - drawnWidth) / 2
            let originY = element.frame.y + (element.frame.height - drawnHeight) / 2

            let localX = (point.x - originX) / scale
            let localY = (point.y - originY) / scale
            guard localX >= 0, localX <= bounds.width, localY >= 0, localY <= bounds.height else {
                continue
            }

            let pdfPoint = CGPoint(
                x: bounds.minX + localX,
                y: bounds.maxY - localY
            )

            for annotation in pdfPage.annotations {
                guard annotation.bounds.contains(pdfPoint) else { continue }

                if let url = annotation.url {
                    return .url(url)
                }
                if let destinationPage = annotation.destination?.page {
                    let index = document.index(for: destinationPage)
                    if index != NSNotFound {
                        return .page(index)
                    }
                }
                if let action = annotation.action {
                    if let urlAction = action as? PDFActionURL, let url = urlAction.url {
                        return .url(url)
                    }
                    if let goTo = action as? PDFActionGoTo,
                       let destinationPage = goTo.destination.page {
                        let index = document.index(for: destinationPage)
                        if index != NSNotFound {
                            return .page(index)
                        }
                    }
                }
            }
        }
        return nil
    }

    /// The document at `url`, reused when it is the one last opened here.
    private static func document(at url: URL) -> PDFDocument? {
        if let lastDocument, lastDocument.url == url {
            return lastDocument.document
        }
        guard let document = PDFDocument(url: url) else { return nil }
        lastDocument = (url, document)
        return document
    }
}
