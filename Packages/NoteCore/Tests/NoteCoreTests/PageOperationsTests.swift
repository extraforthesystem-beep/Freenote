import Foundation
import Testing
@testable import NoteCore

/// Rotating, clearing and resizing a page are pure edits: they move or drop
/// content and keep identity, so the result can be saved like any other page.
@Suite("Page operations")
struct PageOperationsTests {
    // MARK: - Tools

    private static let pen = StrokeTool(engine: "pencilkit", inkType: "pen", color: .black, width: 2)
    private static let pencil = StrokeTool(engine: "pencilkit", inkType: "pencil", color: .black, width: 4)
    private static let highlighter = StrokeTool(
        engine: "pencilkit",
        inkType: "marker",
        color: RGBAColor(r: 1, g: 0.9, b: 0, a: 0.5),
        width: 18,
        isHighlighter: true
    )

    // MARK: - Rotation

    @Test func quarterTurnSwapsPageSizeAndMapsInk() {
        let page = Self.blankPage(width: 100, height: 200)
        let strokeID = UUID()
        let ink = Self.stroke(id: strokeID, layerID: page.layers[0].id, tool: Self.pen, x: 10, y: 20)
        let turned = page.with(strokes: [ink]).rotated(quarterTurns: 1)

        #expect(turned.width == 200)
        #expect(turned.height == 100)
        #expect(turned.strokes.map(\.id) == [strokeID], "rotation keeps every stroke")

        // Clockwise: the page's top-left corner becomes its top-right, so a
        // point 20 from the top and 10 from the left lands 20 from the right.
        let placed = Self.point(of: turned.strokes[0].transform, x: 10, y: 20)
        #expect(Self.matches(placed.x, 180))
        #expect(Self.matches(placed.y, 10))
    }

    @Test func rotationKeepsAnExistingStrokeTransform() {
        let page = Self.blankPage(width: 100, height: 200)
        let shift: [Double] = [1, 0, 0, 1, 5, -7]
        let ink = Self.stroke(
            layerID: page.layers[0].id,
            tool: Self.pen,
            x: 10,
            y: 20,
            transform: shift
        )
        let turned = page.with(strokes: [ink]).rotated(quarterTurns: 1)

        // The stroke's own transform is applied first, then the page turn.
        let placed = Self.point(of: turned.strokes[0].transform, x: 10, y: 20)
        #expect(Self.matches(placed.x, 187))
        #expect(Self.matches(placed.y, 15))
    }

    @Test func fourQuarterTurnsRestoreTheSameGeometry() {
        let page = Self.blankPage(width: 100, height: 200)
        let ink = Self.stroke(layerID: page.layers[0].id, tool: Self.pen, x: 10, y: 20)
        let element = Self.element(
            layerID: page.layers[0].id,
            frame: ElementFrame(x: 10, y: 20, width: 20, height: 40, rotation: 0.25),
            content: .text("Hello", fontName: "System", fontSize: 16, color: .black)
        )
        let original = page.with(strokes: [ink], elements: [element])

        let turned = (0..<4).reduce(original) { page, _ in page.rotated(quarterTurns: 1) }

        #expect(turned.width == original.width)
        #expect(turned.height == original.height)
        for (lhs, rhs) in zip(turned.strokes[0].transform, StrokeRecord.identityTransform) {
            #expect(Self.matches(lhs, rhs))
        }
        let frame = turned.elements[0].frame
        #expect(Self.matches(frame.x, 10))
        #expect(Self.matches(frame.y, 20))
        #expect(Self.matches(frame.width, 20))
        #expect(Self.matches(frame.height, 40))
        #expect(Self.matches(frame.rotation, 0.25))
    }

    @Test func negativeTurnsMatchTheirPositiveEquivalent() {
        let page = Self.blankPage(width: 100, height: 200)
        let ink = Self.stroke(layerID: page.layers[0].id, tool: Self.pen, x: 10, y: 20)
        let original = page.with(strokes: [ink])

        #expect(original.rotated(quarterTurns: -1) == original.rotated(quarterTurns: 3))
        #expect(original.rotated(quarterTurns: -5) == original.rotated(quarterTurns: 3))
        #expect(original.rotated(quarterTurns: 0) == original)
        #expect(original.rotated(quarterTurns: 4) == original)
        #expect(original.rotated(quarterTurns: -4) == original)
    }

    @Test func quarterTurnMovesAnElementCentreAndTurnsIt() {
        let page = Self.blankPage(width: 100, height: 200)
        let element = Self.element(
            layerID: page.layers[0].id,
            frame: ElementFrame(x: 10, y: 20, width: 20, height: 40, rotation: 0.25),
            content: .text("Hello", fontName: "System", fontSize: 16, color: .black)
        )
        let turned = page.with(elements: [element]).rotated(quarterTurns: 1)

        // The centre (20, 40) becomes (160, 20); the box keeps its size.
        let frame = turned.elements[0].frame
        #expect(Self.matches(frame.x, 150))
        #expect(Self.matches(frame.y, 0))
        #expect(Self.matches(frame.width, 20))
        #expect(Self.matches(frame.height, 40))
        #expect(Self.matches(frame.rotation, 0.25 + .pi / 2))
        #expect(turned.elements[0].id == element.id)
    }

    // MARK: - Removing items

    @Test func removingItemsDropsOnlyTheChosenKinds() {
        let page = Self.fullPage()

        let penID = page.strokes[0].id
        let textID = page.elements[0].id
        let keptStrokes = page.strokes.dropFirst().map(\.id)
        let keptElements = page.elements.dropFirst().map(\.id)

        let updated = page.removingItems(of: [.pen, .text])

        #expect(updated.strokes.map(\.id) == Array(keptStrokes))
        #expect(updated.elements.map(\.id) == Array(keptElements))
        #expect(updated.deletedStrokeIDs.contains(penID))
        #expect(updated.deletedElementIDs.contains(textID))
        // Tombstones from earlier edits are kept, not replaced.
        #expect(updated.deletedStrokeIDs.contains(Self.earlierTombstone))
        // Identities that were not chosen stay out of the tombstone lists.
        #expect(!updated.deletedStrokeIDs.contains(page.strokes[1].id))
        #expect(!updated.deletedElementIDs.contains(page.elements[1].id))
        // Nothing else about the page changes.
        #expect(updated.width == page.width)
        #expect(updated.height == page.height)
        #expect(updated.layers == page.layers)
        #expect(updated.template == page.template)
    }

    @Test func removingNoKindsChangesNothing() {
        let page = Self.fullPage()
        #expect(page.removingItems(of: []) == page)
    }

    @Test func clearedKeepsImportedPDFPages() {
        let page = Self.fullPage()
        let pdf = page.elements.first { PageItemKind.of($0) == nil }
        #expect(pdf != nil, "the fixture must carry an imported PDF page")

        let cleared = page.cleared()

        #expect(cleared.strokes.isEmpty)
        #expect(cleared.elements.map(\.id) == [pdf?.id].compactMap { $0 })
        #expect(cleared.deletedStrokeIDs.isSuperset(of: Set(page.strokes.map(\.id))))
        let contentIDs = Set(page.elements.filter { PageItemKind.of($0) != nil }.map(\.id))
        #expect(cleared.deletedElementIDs == contentIDs)
        #expect(pdf.map { !cleared.deletedElementIDs.contains($0.id) } == true)
    }

    // MARK: - Resizing

    @Test func resizedKeepsContentWhereItIs() {
        let page = Self.fullPage()
        let resized = page.resized(width: 1191, height: 842)

        #expect(resized.width == 1191)
        #expect(resized.height == 842)
        #expect(resized.strokes == page.strokes)
        #expect(resized.elements == page.elements)
        #expect(resized.deletedStrokeIDs == page.deletedStrokeIDs)
        #expect(resized.deletedElementIDs == page.deletedElementIDs)
    }

    // MARK: - Fixtures

    private static let earlierTombstone = UUID()

    private static func blankPage(width: Double, height: Double) -> Page {
        Page(
            id: UUID(),
            width: width,
            height: height,
            template: .blank,
            layers: [Page.Layer(id: UUID(), name: "Layer 1")]
        )
    }

    /// A page with one stroke of every ink kind and one element of every kind,
    /// including an imported PDF page.
    private static func fullPage() -> Page {
        let page = blankPage(width: 595, height: 842)
        let layerID = page.layers[0].id
        return page.with(
            strokes: [
                stroke(layerID: layerID, tool: pen),
                stroke(layerID: layerID, tool: pencil),
                stroke(layerID: layerID, tool: highlighter),
            ],
            elements: [
                element(
                    layerID: layerID,
                    frame: ElementFrame(x: 10, y: 20, width: 200, height: 40),
                    content: .text("Hello", fontName: "System", fontSize: 16, color: .black),
                    zIndex: 0
                ),
                element(
                    layerID: layerID,
                    frame: ElementFrame(x: 10, y: 80, width: 120, height: 120),
                    content: .image(assetName: "a.png"),
                    zIndex: 1
                ),
                element(
                    layerID: layerID,
                    frame: ElementFrame(x: 10, y: 220, width: 120, height: 120),
                    content: .shape(kind: "rectangle", stroke: .black, fill: nil, lineWidth: 2),
                    zIndex: 2
                ),
                element(
                    layerID: layerID,
                    frame: ElementFrame(x: 10, y: 360, width: 200, height: 200),
                    content: .stickyNote("Remember", color: RGBAColor(r: 1, g: 0.95, b: 0.62)),
                    zIndex: 3
                ),
                element(
                    layerID: layerID,
                    frame: ElementFrame(x: 0, y: 0, width: 595, height: 842),
                    content: .pdfPage(assetName: "b.pdf", pageIndex: 0),
                    zIndex: -1
                ),
                element(
                    layerID: layerID,
                    frame: ElementFrame(x: 100, y: 600, width: 240, height: 36),
                    content: .tape(color: .white),
                    zIndex: 4
                ),
            ],
            deletedStrokeIDs: [earlierTombstone]
        )
    }

    private static func stroke(
        id: UUID = UUID(),
        layerID: UUID,
        tool: StrokeTool,
        x: Double = 10,
        y: Double = 20,
        transform: [Double] = StrokeRecord.identityTransform
    ) -> StrokeRecord {
        StrokeRecord(
            id: id,
            layerID: layerID,
            tool: tool,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transform: transform,
            randomSeed: 7,
            points: [
                StrokePoint(
                    x: x,
                    y: y,
                    timeOffset: 0,
                    width: tool.width,
                    height: tool.width,
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: 0,
                    secondaryScale: 1
                ),
            ]
        )
    }

    private static func element(
        id: UUID = UUID(),
        layerID: UUID,
        frame: ElementFrame,
        content: ElementContent,
        zIndex: Int = 0
    ) -> PageElement {
        PageElement(
            id: id,
            layerID: layerID,
            frame: frame,
            zIndex: zIndex,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            content: content
        )
    }

    // MARK: - Helpers

    private static func point(
        of transform: [Double],
        x: Double,
        y: Double
    ) -> (x: Double, y: Double) {
        (
            transform[0] * x + transform[2] * y + transform[4],
            transform[1] * x + transform[3] * y + transform[5]
        )
    }

    private static func matches(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 1e-9
    }
}

private extension Page {
    /// The same page with other content, for building fixtures.
    func with(
        strokes: [StrokeRecord]? = nil,
        elements: [PageElement]? = nil,
        deletedStrokeIDs: Set<UUID>? = nil
    ) -> Page {
        var updated = self
        if let strokes { updated.strokes = strokes }
        if let elements { updated.elements = elements }
        if let deletedStrokeIDs { updated.deletedStrokeIDs = deletedStrokeIDs }
        return updated
    }
}
