import Foundation
import InkKit
import NoteCore
import PencilKit
import Testing

struct HighlighterTests {
    @Test
    func markerWithTranslucentColourIsStoredAsHighlighter() throws {
        let stroke = SampleStroke.stroke(style: .marker, index: 1)
        let record = StrokeCodec.record(from: stroke, layerID: UUID())

        #expect(record.tool.isHighlighter)
        #expect(record.tool.color.a < 0.99)
        #expect(record.tool.inkType == PKInk.InkType.marker.rawValue)
    }

    @Test
    func opaqueMarkerIsNotAHighlighter() {
        let stroke = SampleStroke.stroke(style: .marker, index: 0)
        let record = StrokeCodec.record(from: stroke, layerID: UUID())
        #expect(!record.tool.isHighlighter)
    }

    @Test
    func highlighterStrokesAreInsertedBeforePenInkOfTheirLayer() {
        let layerID = UUID()
        let pen = StrokeCodec.record(
            from: SampleStroke.stroke(style: .pen, index: 0),
            layerID: layerID
        )
        let highlighter = StrokeCodec.record(
            from: SampleStroke.stroke(style: .marker, index: 1),
            layerID: layerID
        )

        let drawing = StrokeCodec.drawing(from: [pen, highlighter])
        #expect(drawing.strokes.first?.ink.inkType == .marker)
        #expect(drawing.strokes.last?.ink.inkType == .pen)
    }

    @Test
    func strokeToolWithoutHighlighterKeyDecodesAsNormalInk() throws {
        let json = """
        {"engine":"pencilkit","inkType":"com.apple.ink.pen","color":{"r":0,"g":0,"b":0,"a":1},"width":3}
        """.data(using: .utf8)!
        let tool = try JSONDecoder().decode(StrokeTool.self, from: json)
        #expect(!tool.isHighlighter)
    }
}
