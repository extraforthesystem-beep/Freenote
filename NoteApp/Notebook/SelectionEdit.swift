import CoreGraphics
import Foundation
import NoteCore

/// A selection copied out of a page. It is self-contained: the ink records and
/// only the elements that need no notebook assets (text, shapes, sticky notes
/// and tape). That is what lets a paste land in another notebook.
nonisolated struct SelectionPayload: Codable, Equatable {
    var strokes: [StrokeRecord] = []
    var elements: [CopiedElement] = []

    var isEmpty: Bool { strokes.isEmpty && elements.isEmpty }
}

/// An element as it travels on the pasteboard. Images and PDF pages are left
/// behind because their asset names only mean something in their own notebook.
nonisolated struct CopiedElement: Codable, Equatable {
    var frame: ElementFrame
    var content: ElementContent
}

/// Pure edits on a page for the lasso's actions. Keeping them here, away from
/// the session and the pasteboard, makes each action testable and lets one
/// action be one page change.
nonisolated enum SelectionEdit {
    /// The same transparency the highlighter tool uses, so a recoloured
    /// highlighter still reads as one to the stroke codec.
    static let highlighterAlpha = 0.35
    /// How far a duplicate or a paste lands from the original.
    static let copyOffset = 16.0
    /// PencilKit rejects non-positive widths.
    private static let minimumWidth = 0.1
    private static let maximumWidth = 100.0

    // MARK: - Colour and width

    /// Recolours the selected ink and the selected shapes and text boxes. Sticky
    /// notes and tape keep their own colours.
    static func recolour(_ selection: InkSelection, in page: Page, to color: RGBAColor) -> Page {
        let strokes = Set(selection.editableStrokes(in: page).map(\.id))
        let elements = Set(selection.editableElements(in: page).map(\.id))
        guard !strokes.isEmpty || !elements.isEmpty else { return page }

        var updated = page
        updated.strokes = page.strokes.map { record in
            guard strokes.contains(record.id) else { return record }
            var record = record
            record.tool.color = record.tool.isHighlighter ? color.withAlpha(highlighterAlpha) : color.withAlpha(1)
            return record
        }
        updated.elements = page.elements.map { element in
            guard elements.contains(element.id) else { return element }
            var element = element
            switch element.content {
            case let .text(text, fontName, fontSize, _):
                element.content = .text(text, fontName: fontName, fontSize: fontSize, color: color.withAlpha(1))
            case let .shape(kind, _, fill, lineWidth):
                element.content = .shape(kind: kind, stroke: color.withAlpha(1), fill: fill, lineWidth: lineWidth)
            case .image, .pdfPage, .stickyNote, .tape:
                return element
            }
            element.updatedAt = Date()
            return element
        }
        return updated
    }

    /// Scales the selected ink and shape outlines. Each stroke keeps its own
    /// pressure profile: every point is scaled by the same factor.
    static func scaleWidth(_ selection: InkSelection, in page: Page, by factor: Double) -> Page {
        guard factor > 0, factor != 1 else { return page }
        let strokes = Set(selection.editableStrokes(in: page).map(\.id))
        let elements = Set(selection.editableElements(in: page).map(\.id))
        guard !strokes.isEmpty || !elements.isEmpty else { return page }

        var updated = page
        updated.strokes = page.strokes.map { record in
            guard strokes.contains(record.id) else { return record }
            return scaling(record, by: factor)
        }
        updated.elements = page.elements.map { element in
            guard elements.contains(element.id),
                  case let .shape(kind, stroke, fill, lineWidth) = element.content
            else { return element }
            var element = element
            element.content = .shape(
                kind: kind,
                stroke: stroke,
                fill: fill,
                lineWidth: clampWidth(lineWidth * factor)
            )
            element.updatedAt = Date()
            return element
        }
        return updated
    }

    /// Makes every selected stroke's widest point the target width, keeping its
    /// pressure variation. Shape outlines take the same width.
    static func setWidth(_ selection: InkSelection, in page: Page, to width: Double) -> Page {
        let target = clampWidth(width)
        let strokes = Set(selection.editableStrokes(in: page).map(\.id))
        let elements = Set(selection.editableElements(in: page).map(\.id))
        guard !strokes.isEmpty || !elements.isEmpty else { return page }

        var updated = page
        updated.strokes = page.strokes.map { record in
            guard strokes.contains(record.id) else { return record }
            let current = max(record.points.map(\.width).max() ?? record.tool.width, minimumWidth)
            return scaling(record, by: target / current)
        }
        updated.elements = page.elements.map { element in
            guard elements.contains(element.id),
                  case let .shape(kind, stroke, fill, _) = element.content
            else { return element }
            var element = element
            element.content = .shape(kind: kind, stroke: stroke, fill: fill, lineWidth: target)
            element.updatedAt = Date()
            return element
        }
        return updated
    }

    private static func scaling(_ record: StrokeRecord, by factor: Double) -> StrokeRecord {
        var record = record
        record.points = record.points.map { point in
            var point = point
            point.width = clampWidth(point.width * factor)
            point.height = clampWidth(point.height * factor)
            return point
        }
        record.tool.width = clampWidth(record.tool.width * factor)
        return record
    }

    private static func clampWidth(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }

    // MARK: - Duplicate and delete

    /// Copies the selection in place, offset a little so the copy shows. New
    /// ids mean the copy is independent ink.
    static func duplicate(_ selection: InkSelection, in page: Page) -> Page {
        let strokes = selection.editableStrokes(in: page)
        let elements = selection.editableElements(in: page)
        guard !strokes.isEmpty || !elements.isEmpty else { return page }

        var updated = page
        updated.strokes.append(contentsOf: strokes.map { copying($0, layerID: $0.layerID) })
        var zIndex = page.elements.map(\.zIndex).max() ?? 0
        for element in elements {
            zIndex += 1
            updated.elements.append(
                PageElement(
                    id: UUID(),
                    layerID: element.layerID,
                    frame: offset(element.frame, in: page),
                    zIndex: zIndex,
                    updatedAt: Date(),
                    content: element.content
                )
            )
        }
        return updated
    }

    /// Removes the selected ink and items. `NotebookSession` keeps their ids as
    /// tombstones when the page is saved.
    static func delete(_ selection: InkSelection, from page: Page) -> Page {
        let strokes = Set(selection.editableStrokes(in: page).map(\.id))
        let elements = Set(selection.editableElements(in: page).map(\.id))
        guard !strokes.isEmpty || !elements.isEmpty else { return page }

        var updated = page
        updated.strokes.removeAll { strokes.contains($0.id) }
        updated.elements.removeAll { elements.contains($0.id) }
        return updated
    }

    // MARK: - Copy and paste

    /// The part of the selection that can leave the page: all ink and the
    /// elements that carry no notebook asset.
    static func copied(_ selection: InkSelection, from page: Page) -> SelectionPayload {
        let elements = selection.elements(in: page).compactMap { element -> CopiedElement? in
            switch element.content {
            case .image, .pdfPage:
                return nil
            case .text, .shape, .stickyNote, .tape:
                return CopiedElement(frame: element.frame, content: element.content)
            }
        }
        return SelectionPayload(
            strokes: selection.strokes(in: page),
            elements: elements
        )
    }

    /// Adds a copied selection on `layerID`, offset from the original.
    static func paste(_ payload: SelectionPayload, into page: Page, layerID: UUID) -> Page {
        guard !payload.isEmpty else { return page }

        var updated = page
        updated.strokes.append(contentsOf: payload.strokes.map { copying($0, layerID: layerID) })
        var zIndex = page.elements.map(\.zIndex).max() ?? 0
        for copied in payload.elements {
            zIndex += 1
            updated.elements.append(
                PageElement(
                    id: UUID(),
                    layerID: layerID,
                    frame: offset(copied.frame, in: page),
                    zIndex: zIndex,
                    updatedAt: Date(),
                    content: copied.content
                )
            )
        }
        return updated
    }

    /// A copy with a fresh id, its own path identity and the offset applied.
    private static func copying(_ record: StrokeRecord, layerID: UUID) -> StrokeRecord {
        var copy = record
        copy.id = UUID()
        copy.layerID = layerID
        copy.createdAt = Date()
        copy.pathID = nil
        if copy.transform.count == StrokeRecord.transformElementCount {
            copy.transform[4] += copyOffset
            copy.transform[5] += copyOffset
        }
        return copy
    }

    /// Moves a frame by the copy offset, keeping it on the page.
    private static func offset(_ frame: ElementFrame, in page: Page) -> ElementFrame {
        var frame = frame
        frame.x = min(max(0, frame.x + copyOffset), max(page.width - frame.width, 0))
        frame.y = min(max(0, frame.y + copyOffset), max(page.height - frame.height, 0))
        return frame
    }

    // MARK: - Text

    /// The page box the selected ink covers.
    static func inkBounds(_ selection: InkSelection, in page: Page) -> CGRect? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for record in selection.strokes(in: page) {
            let transform = affineTransform(record.transform)
            for point in record.points {
                let location = CGPoint(x: point.x, y: point.y).applying(transform)
                minX = min(minX, location.x)
                minY = min(minY, location.y)
                maxX = max(maxX, location.x)
                maxY = max(maxY, location.y)
            }
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Adds the recognised text as a text box under the selected ink, so the
    /// original stays readable above it.
    static func textBox(
        for text: String,
        selection: InkSelection,
        in page: Page,
        layerID: UUID,
        fontSize: Double = 16
    ) -> Page? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let inkBox = inkBounds(selection, in: page)
        let boundsWidth = Double(inkBox?.width ?? 0)
        let boundsMinX = Double(inkBox?.minX ?? 16)
        let boundsMinY = inkBox.map { Double($0.minY) } ?? page.height
        let boundsMaxY = Double(inkBox?.maxY ?? 16)
        let lines = trimmed.components(separatedBy: .newlines).count
        let height = max(fontSize * 1.5 * Double(lines) + 16, fontSize * 2)
        let width = min(max(boundsWidth, fontSize * 6), max(page.width - 16, 1))
        let x = min(max(0, boundsMinX - 2), max(page.width - width, 0))
        var y = boundsMaxY + 8
        if y + height > page.height {
            y = max(0, boundsMinY - height - 8)
        }

        var updated = page
        updated.elements.append(
            PageElement(
                id: UUID(),
                layerID: layerID,
                frame: ElementFrame(x: x, y: y, width: width, height: height),
                zIndex: (page.elements.map(\.zIndex).max() ?? 0) + 1,
                updatedAt: Date(),
                content: .text(trimmed, fontName: "System", fontSize: fontSize, color: .black)
            )
        )
        return updated
    }

    private static func affineTransform(_ transform: [Double]) -> CGAffineTransform {
        guard transform.count == StrokeRecord.transformElementCount else { return .identity }
        return CGAffineTransform(
            a: transform[0],
            b: transform[1],
            c: transform[2],
            d: transform[3],
            tx: transform[4],
            ty: transform[5]
        )
    }
}

nonisolated extension RGBAColor {
    /// The same colour with another alpha, so recolouring can keep a
    /// highlighter translucent and pen ink opaque.
    func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: alpha)
    }
}
