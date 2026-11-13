import XCTest
@testable import NoteApp
import NoteCore

final class SelectionEditTests: XCTestCase {
    private let layerID = UUID()
    private let lockedLayerID = UUID()

    private func makePage(lockedLayer: Bool = false) -> Page {
        Page(
            id: UUID(),
            width: 600,
            height: 800,
            template: .blank,
            layers: [
                Page.Layer(id: layerID, name: "Layer 1"),
                Page.Layer(id: lockedLayerID, name: "Layer 2", isLocked: lockedLayer),
            ]
        )
    }

    private func makeStroke(
        id: UUID = UUID(),
        layerID: UUID? = nil,
        color: RGBAColor = .black,
        width: Double = 2,
        highlighter: Bool = false,
        offset: Double = 0
    ) -> StrokeRecord {
        StrokeRecord(
            id: id,
            layerID: layerID ?? self.layerID,
            tool: StrokeTool(
                engine: "pencilkit",
                inkType: highlighter ? "com.apple.ink.marker" : "com.apple.ink.pen",
                color: color,
                width: width,
                isHighlighter: highlighter
            ),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            transform: [1, 0, 0, 1, offset, offset],
            randomSeed: 1,
            points: [
                StrokePoint(
                    x: 10, y: 20, timeOffset: 0, width: width, height: width,
                    opacity: 1, force: 1, azimuth: 0, altitude: 1, secondaryScale: 1
                ),
                StrokePoint(
                    x: 30, y: 40, timeOffset: 0.01, width: width * 2, height: width * 2,
                    opacity: 1, force: 1, azimuth: 0, altitude: 1, secondaryScale: 1
                ),
            ]
        )
    }

    private func makeTextElement(at y: Double, text: String = "hello") -> PageElement {
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 20, y: y, width: 200, height: 60),
            zIndex: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0),
            content: .text(text, fontName: "System", fontSize: 16, color: .black)
        )
    }

    func testRecolourChangesOnlyTheSelectedStrokes() {
        let kept = makeStroke(color: .black)
        let changed = makeStroke(color: .black)
        let page = makePage()
        var pageWithInk = page
        pageWithInk.strokes = [kept, changed]

        let selection = InkSelection(strokeIDs: [changed.id])
        let updated = SelectionEdit.recolour(selection, in: pageWithInk, to: RGBAColor(r: 1, g: 0, b: 0))

        XCTAssertEqual(updated.strokes[0].tool.color, .black)
        XCTAssertEqual(updated.strokes[1].tool.color, RGBAColor(r: 1, g: 0, b: 0, a: 1))
    }

    func testRecolourKeepsHighlighterTranslucent() {
        let highlighter = makeStroke(color: RGBAColor(r: 1, g: 1, b: 0, a: 0.35), highlighter: true)
        var page = makePage()
        page.strokes = [highlighter]

        let updated = SelectionEdit.recolour(
            InkSelection(strokeIDs: [highlighter.id]),
            in: page,
            to: RGBAColor(r: 1, g: 0, b: 0)
        )

        XCTAssertEqual(updated.strokes[0].tool.color.a, SelectionEdit.highlighterAlpha, accuracy: 0.0001)
        XCTAssertTrue(updated.strokes[0].tool.isHighlighter)
    }

    func testRecolourLeavesInkOnALockedLayerAlone() {
        let locked = makeStroke(layerID: lockedLayerID)
        var page = makePage(lockedLayer: true)
        page.strokes = [locked]

        let updated = SelectionEdit.recolour(
            InkSelection(strokeIDs: [locked.id]),
            in: page,
            to: RGBAColor(r: 1, g: 0, b: 0)
        )

        XCTAssertEqual(updated, page)
    }

    func testSetWidthMakesTheWidestPointTheTargetAndKeepsPressure() {
        let stroke = makeStroke(width: 2)
        var page = makePage()
        page.strokes = [stroke]

        let updated = SelectionEdit.setWidth(
            InkSelection(strokeIDs: [stroke.id]),
            in: page,
            to: 10
        )
        let changed = updated.strokes[0]

        XCTAssertEqual(changed.points[0].width, 5, accuracy: 0.0001)
        XCTAssertEqual(changed.points[1].width, 10, accuracy: 0.0001)
        XCTAssertEqual(changed.tool.width, 5, accuracy: 0.0001)
    }

    func testScaleWidthChangesShapeOutlineAndLeavesOtherItems() {
        let shapeID = UUID()
        var page = makePage()
        page.elements = [
            PageElement(
                id: shapeID,
                layerID: layerID,
                frame: ElementFrame(x: 0, y: 0, width: 100, height: 100),
                zIndex: 0,
                updatedAt: Date(timeIntervalSinceReferenceDate: 0),
                content: .shape(kind: "rect", stroke: .black, fill: nil, lineWidth: 2)
            ),
            makeTextElement(at: 300),
        ]

        let updated = SelectionEdit.scaleWidth(
            InkSelection(elementIDs: [shapeID]),
            in: page,
            by: 1.5
        )

        guard case let .shape(_, _, _, lineWidth) = updated.elements[0].content else {
            return XCTFail("The shape changed kind")
        }
        XCTAssertEqual(lineWidth, 3, accuracy: 0.0001)
        XCTAssertEqual(updated.elements[1], page.elements[1])
    }

    func testDuplicateAddsOffsetCopiesWithNewIds() {
        let stroke = makeStroke()
        var page = makePage()
        page.strokes = [stroke]

        let updated = SelectionEdit.duplicate(InkSelection(strokeIDs: [stroke.id]), in: page)

        XCTAssertEqual(updated.strokes.count, 2)
        XCTAssertEqual(updated.strokes[0], stroke)
        XCTAssertNotEqual(updated.strokes[1].id, stroke.id)
        XCTAssertEqual(updated.strokes[1].transform[4], stroke.transform[4] + SelectionEdit.copyOffset)
        XCTAssertEqual(updated.strokes[1].transform[5], stroke.transform[5] + SelectionEdit.copyOffset)
    }

    func testDeleteRemovesOnlyTheSelection() {
        let kept = makeStroke()
        let removed = makeStroke()
        var page = makePage()
        page.strokes = [kept, removed]
        page.elements = [makeTextElement(at: 100)]

        let updated = SelectionEdit.delete(InkSelection(strokeIDs: [removed.id]), from: page)

        XCTAssertEqual(updated.strokes.map(\.id), [kept.id])
        XCTAssertEqual(updated.elements.count, 1)
    }

    func testCopiedPayloadLeavesAssetElementsBehind() {
        let stroke = makeStroke()
        var page = makePage()
        page.strokes = [stroke]
        page.elements = [
            makeTextElement(at: 100),
            PageElement(
                id: UUID(),
                layerID: layerID,
                frame: ElementFrame(x: 0, y: 0, width: 100, height: 100),
                zIndex: 2,
                updatedAt: Date(timeIntervalSinceReferenceDate: 0),
                content: .image(assetName: "photo.png")
            ),
        ]

        let payload = SelectionEdit.copied(
            InkSelection(strokeIDs: [stroke.id], elementIDs: Set(page.elements.map(\.id))),
            from: page
        )

        XCTAssertEqual(payload.strokes.map(\.id), [stroke.id])
        XCTAssertEqual(payload.elements.count, 1)
    }

    func testPasteMovesCopiedItemsToTheTargetLayerAndPage() {
        let source = makeStroke(offset: 100)
        var page = makePage()
        page.strokes = [source]
        page.elements = [makeTextElement(at: 780)]
        let payload = SelectionEdit.copied(
            InkSelection(strokeIDs: [source.id], elementIDs: Set(page.elements.map(\.id))),
            from: page
        )

        let targetLayer = UUID()
        var target = makePage()
        target.layers.append(Page.Layer(id: targetLayer, name: "Pasted"))
        let pasted = SelectionEdit.paste(payload, into: target, layerID: targetLayer)

        XCTAssertEqual(pasted.strokes.count, 1)
        XCTAssertNotEqual(pasted.strokes[0].id, source.id)
        XCTAssertEqual(pasted.strokes[0].layerID, targetLayer)
        XCTAssertEqual(pasted.elements.count, 1)
        XCTAssertEqual(pasted.elements[0].layerID, targetLayer)
        // The source box was at the page's bottom edge: the paste stays on the page.
        XCTAssertLessThanOrEqual(pasted.elements[0].frame.y + pasted.elements[0].frame.height, target.height)
    }

    func testInkBoundsFollowsTheStrokeTransform() {
        let stroke = makeStroke(offset: 100)
        var page = makePage()
        page.strokes = [stroke]

        let bounds = SelectionEdit.inkBounds(InkSelection(strokeIDs: [stroke.id]), in: page)

        XCTAssertEqual(bounds?.minX, 110)
        XCTAssertEqual(bounds?.minY, 120)
        XCTAssertEqual(bounds?.maxX, 130)
        XCTAssertEqual(bounds?.maxY, 140)
    }

    func testTextBoxSitsUnderTheSelection() throws {
        let stroke = makeStroke()
        var page = makePage()
        page.strokes = [stroke]

        let updated = try XCTUnwrap(
            SelectionEdit.textBox(
                for: "hello world",
                selection: InkSelection(strokeIDs: [stroke.id]),
                in: page,
                layerID: layerID
            )
        )

        let box = try XCTUnwrap(updated.elements.last)
        guard case let .text(text, _, _, _) = box.content else {
            return XCTFail("The box is not a text element")
        }
        XCTAssertEqual(text, "hello world")
        XCTAssertGreaterThanOrEqual(box.frame.y, 40)
        XCTAssertEqual(box.layerID, layerID)
    }

    func testTextBoxRefusesEmptyText() {
        let page = makePage()
        XCTAssertNil(
            SelectionEdit.textBox(
                for: "   ",
                selection: InkSelection(),
                in: page,
                layerID: layerID
            )
        )
    }
}
