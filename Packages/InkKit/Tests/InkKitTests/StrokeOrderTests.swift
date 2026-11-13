import Foundation
import InkKit
import NoteCore
import PencilKit
import Testing

struct StrokeOrderTests {
    private func record(_ style: PenStyle, index: Int, layer: UUID) -> StrokeRecord {
        StrokeCodec.record(from: SampleStroke.stroke(style: style, index: index), layerID: layer)
    }

    private func pen(_ layer: UUID) -> StrokeRecord { record(.pen, index: 0, layer: layer) }
    private func highlighter(_ layer: UUID) -> StrokeRecord { record(.marker, index: 1, layer: layer) }

    @Test
    func strokesPaintInLayerOrderWithHighlightersFirstWithinALayer() {
        let bottom = UUID(), top = UUID()
        let topPen = pen(top)
        let bottomPen = pen(bottom)
        let topHighlighter = highlighter(top)
        let bottomHighlighter = highlighter(bottom)

        let ordered = StrokeOrder.renderOrder(
            [topPen, bottomPen, topHighlighter, bottomHighlighter],
            layerOrder: [bottom, top]
        )
        #expect(ordered.map(\.id) == [bottomHighlighter.id, bottomPen.id, topHighlighter.id, topPen.id])
    }

    @Test
    func renderOrderIsStableAndIdempotent() {
        let layer = UUID()
        let strokes = [pen(layer), pen(layer), highlighter(layer), pen(layer), highlighter(layer)]
        let once = StrokeOrder.renderOrder(strokes, layerOrder: [layer])
        #expect(once.map(\.id) == [strokes[2], strokes[4], strokes[0], strokes[1], strokes[3]].map(\.id))
        #expect(StrokeOrder.renderOrder(once, layerOrder: [layer]).map(\.id) == once.map(\.id))
    }

    @Test
    func aNewHighlighterAfterOrderedInkStillMovesUnderIt() {
        // An ordered page plus one new stroke at the end: the shape of every
        // merge. The in-order shortcut must not keep a highlighter on top.
        let layer = UUID()
        let ordered = StrokeOrder.renderOrder([pen(layer), highlighter(layer), pen(layer)], layerOrder: [layer])
        let newHighlighter = highlighter(layer)
        let merged = StrokeOrder.merge(
            existing: ordered,
            canvas: ordered + [newHighlighter],
            hiddenLayerIDs: [],
            layerOrder: [layer]
        )
        #expect(merged.strokes.map(\.id) == [ordered[0].id, newHighlighter.id, ordered[1].id, ordered[2].id])
        #expect(merged.addedIDs == [newHighlighter.id])
    }

    @Test
    func movingALayerChangesTheDrawingOrder() {
        let a = UUID(), b = UUID()
        let inkA = pen(a), inkB = pen(b)
        let page = Page(
            id: UUID(), width: 100, height: 100, template: .blank,
            layers: [Page.Layer(id: b, name: "B"), Page.Layer(id: a, name: "A")],
            strokes: [inkA, inkB]
        )
        #expect(page.renderStrokes.map(\.id) == [inkB.id, inkA.id])
        #expect(StrokeCodec.drawing(from: page.renderStrokes).strokes.map(\.id) == [inkB.id, inkA.id])
    }

    @Test
    func renderStrokesSkipHiddenLayers() {
        let shown = UUID(), hidden = UUID()
        let visible = pen(shown)
        let page = Page(
            id: UUID(), width: 100, height: 100, template: .blank,
            layers: [Page.Layer(id: shown, name: "1"), Page.Layer(id: hidden, name: "2", isVisible: false)],
            strokes: [visible, pen(hidden)]
        )
        #expect(page.renderStrokes.map(\.id) == [visible.id])
    }

    @Test
    func mergeKeepsHiddenStrokesInPlaceAndReportsErasedStrokes() {
        let shown = UUID(), hidden = UUID()
        let first = pen(shown), secret = pen(hidden), erased = pen(shown), last = pen(shown)
        let existing = [first, secret, erased, last]
        var moved = last
        moved.transform = [1, 0, 0, 1, 5, 5]
        let drawn = pen(shown)

        let merge = StrokeOrder.merge(
            existing: existing,
            canvas: [first, moved, drawn],
            hiddenLayerIDs: [hidden],
            layerOrder: [shown, hidden]
        )
        #expect(merge.strokes.map(\.id) == [first.id, last.id, drawn.id, secret.id])
        #expect(merge.strokes[1].transform == moved.transform)
        #expect(merge.removedIDs == [erased.id])
        #expect(merge.addedIDs == [drawn.id])
    }

    @Test
    func showingALayerAgainDoesNotReshuffleStacking() {
        let a = UUID(), b = UUID()
        let strokes = StrokeOrder.renderOrder([pen(a), pen(b), pen(a), pen(b)], layerOrder: [a, b])
        // Layer b hidden: the canvas only reports layer a.
        let whileHidden = StrokeOrder.merge(
            existing: strokes,
            canvas: strokes.filter { $0.layerID == a },
            hiddenLayerIDs: [b],
            layerOrder: [a, b]
        )
        #expect(whileHidden.strokes.map(\.id) == strokes.map(\.id))
        // Shown again: the canvas reports both.
        let shownAgain = StrokeOrder.merge(
            existing: whileHidden.strokes,
            canvas: whileHidden.strokes,
            hiddenLayerIDs: [],
            layerOrder: [a, b]
        )
        #expect(shownAgain.strokes.map(\.id) == strokes.map(\.id))
        #expect(shownAgain.removedIDs.isEmpty)
    }
}

struct IncrementalStrokeConverterTests {
    @Test
    func onlyNewOrChangedStrokesAreConverted() {
        let layer = UUID()
        let converter = IncrementalStrokeConverter()
        var strokes = (0..<4).map { SampleStroke.stroke(style: .pen, index: $0) }

        let first = converter.changedRecords(from: strokes, layerID: { _ in layer })
        #expect(first?.count == 4)
        #expect(converter.conversionCount == 4)

        #expect(converter.changedRecords(from: strokes, layerID: { _ in layer }) == nil)
        #expect(converter.conversionCount == 4)

        strokes.append(SampleStroke.stroke(style: .marker, index: 1))
        let second = converter.changedRecords(from: strokes, layerID: { _ in layer })
        #expect(second?.count == 5)
        #expect(converter.conversionCount == 5)

        strokes[0].transform = CGAffineTransform(translationX: 10, y: 0)
        let third = converter.changedRecords(from: strokes, layerID: { _ in layer })
        #expect(converter.conversionCount == 6)
        #expect(third?.first?.transform[4] == 10)
    }

    @Test
    func seededRecordsAreReturnedVerbatim() {
        let layer = UUID()
        let records = (0..<3).map {
            StrokeCodec.record(from: SampleStroke.stroke(style: .pen, index: $0), layerID: layer)
        }
        let drawing = StrokeCodec.drawing(from: records)
        let converter = IncrementalStrokeConverter()
        converter.seed(strokes: drawing.strokes, records: records)

        #expect(converter.changedRecords(from: drawing.strokes, layerID: { _ in layer }) == nil)
        let all = converter.records(from: drawing.strokes, layerID: { _ in layer })
        #expect(all == records)
        #expect(converter.conversionCount == 0)
    }

    @Test
    func erasedStrokeDisappearsFromTheRecords() {
        let layer = UUID()
        let converter = IncrementalStrokeConverter()
        let strokes = (0..<3).map { SampleStroke.stroke(style: .pen, index: $0) }
        _ = converter.changedRecords(from: strokes, layerID: { _ in layer })
        let after = converter.changedRecords(from: Array(strokes.dropFirst()), layerID: { _ in layer })
        #expect(after?.map(\.id) == strokes.dropFirst().map(\.id))
        #expect(converter.conversionCount == 3)
    }
}
