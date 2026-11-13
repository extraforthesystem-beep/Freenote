import CoreGraphics
import Foundation
import NoteCore
import Observation
import PDFKit
import SwiftUI

enum PDFLinkTarget: Equatable {
    case url(URL)
    case page(Int)
}

/// Finds the link annotation under a tap in page coordinates. The page's PDF
/// element is drawn aspect-fit inside its frame; this reverses that mapping.
@MainActor
enum PDFLinkHandler {
    /// A link's drawn hit area is grown to this many page points before a tap
    /// counts, so a footnote-sized link is still reachable with a fingertip or
    /// an imprecise stylus (the 44 pt enhanced target of WCAG 2.5.5).
    static let minimumTargetSize: CGFloat = 44

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

            if let target = link(at: pdfPoint, in: pdfPage, document: document, scale: scale) {
                return target
            }
        }
        return nil
    }

    /// The link nearest `pdfPoint`, counting a tap up to the minimum target
    /// size away from a small annotation. Distance is in PDF points; `scale`
    /// converts the screen minimum back into them.
    private static func link(
        at pdfPoint: CGPoint,
        in pdfPage: PDFPage,
        document: PDFDocument,
        scale: CGFloat
    ) -> PDFLinkTarget? {
        var best: (target: PDFLinkTarget, distance: CGFloat)?
        for annotation in pdfPage.annotations {
            let distance = distance(from: annotation.bounds, to: pdfPoint, scale: scale)
            guard distance.isFinite else { continue }
            guard let target = target(for: annotation, in: document) else { continue }
            if best == nil || distance < best!.distance {
                best = (target, distance)
            }
        }
        return best?.target
    }

    /// How far `point` is outside the annotation's hit area: 0 inside, positive
    /// outside, and `.infinity` beyond the grown target.
    private static func distance(
        from bounds: CGRect,
        to point: CGPoint,
        scale: CGFloat
    ) -> CGFloat {
        // A link drawn smaller than the minimum target grows symmetrically, so
        // its centre stays the same and its edges move out.
        let paddingX = max(0, (minimumTargetSize - bounds.width * scale) / 2) / scale
        let paddingY = max(0, (minimumTargetSize - bounds.height * scale) / 2) / scale
        let hit = bounds.insetBy(dx: -paddingX, dy: -paddingY)
        guard hit.contains(point) else { return .infinity }
        guard !bounds.contains(point) else { return 0 }
        let dx = max(bounds.minX - point.x, 0, point.x - bounds.maxX)
        let dy = max(bounds.minY - point.y, 0, point.y - bounds.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func target(
        for annotation: PDFAnnotation,
        in document: PDFDocument
    ) -> PDFLinkTarget? {
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

/// The pages a reader moved between by following an in-document PDF link, so a
/// jump can be undone — and redone — without hunting for the page again. Per
/// open notebook, in memory only.
@MainActor
@Observable
final class PDFLinkHistory {
    private struct Jump: Hashable {
        let notebookID: UUID
        let pageIndex: Int
    }

    private var back: [Jump] = []
    private var forward: [Jump] = []

    /// The page a Back returns to, or nil when there is nothing to undo.
    func backPageIndex(notebookID: UUID) -> Int? {
        back.last { $0.notebookID == notebookID }?.pageIndex
    }

    /// The page a Forward returns to, after one or more Backs.
    func forwardPageIndex(notebookID: UUID) -> Int? {
        forward.last { $0.notebookID == notebookID }?.pageIndex
    }

    /// Remembers where a link jump started; a new jump is a new branch of
    /// history, so anything ahead is dropped.
    func recordJump(from pageIndex: Int, notebookID: UUID) {
        let jump = Jump(notebookID: notebookID, pageIndex: pageIndex)
        guard back.last != jump else { return }
        back.append(jump)
        forward.removeAll { $0.notebookID == notebookID }
        if back.count > 20 { back.removeFirst(back.count - 20) }
    }

    /// Moves one jump back: returns the page to show and remembers `pageIndex`
    /// for Forward.
    func goBack(notebookID: UUID, pageIndex: Int) -> Int? {
        guard let index = back.lastIndex(where: { $0.notebookID == notebookID }) else { return nil }
        let jump = back.remove(at: index)
        forward.append(Jump(notebookID: notebookID, pageIndex: pageIndex))
        return jump.pageIndex
    }

    /// The forward half of `goBack`.
    func goForward(notebookID: UUID, pageIndex: Int) -> Int? {
        guard let index = forward.lastIndex(where: { $0.notebookID == notebookID }) else { return nil }
        let jump = forward.remove(at: index)
        back.append(Jump(notebookID: notebookID, pageIndex: pageIndex))
        return jump.pageIndex
    }
}

/// Back and Forward after following a PDF link: small chrome with 44 pt
/// targets, and never in the way of the page.
struct PDFLinkHistoryChip: View {
    let backPageNumber: Int?
    let forwardPageNumber: Int?
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let backPageNumber {
                button(
                    "Back to page \(backPageNumber)",
                    systemImage: "chevron.backward",
                    pageNumber: backPageNumber,
                    action: onBack
                )
            }
            if backPageNumber != nil, forwardPageNumber != nil {
                Divider()
                    .frame(height: 20)
            }
            if let forwardPageNumber {
                button(
                    "Forward to page \(forwardPageNumber)",
                    systemImage: "chevron.forward",
                    pageNumber: forwardPageNumber,
                    action: onForward
                )
            }
        }
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(12)
    }

    private func button(
        _ label: String,
        systemImage: String,
        pageNumber: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text("Page \(pageNumber)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
