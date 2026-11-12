import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PencilKit
import Testing

struct CapturedStrokeTests {
    private func samples(_ count: Int, pressure: CGFloat? = 0.5) -> [CapturedInkSample] {
        (0..<count).map { index in
            CapturedInkSample(
                location: CGPoint(x: 10 + CGFloat(index) * 5, y: 20),
                time: 100 + Double(index) * 0.01,
                force: 1,
                pressure: pressure,
                altitude: 1,
                azimuth: 0.5
            )
        }
    }

    @Test
    func mediumPressDrawsTheNominalWidth() {
        let tool = InkTool(.pen, width: 4)
        #expect(CapturedStrokeBuilder.width(for: tool, pressure: 0.5) == 4)
        #expect(CapturedStrokeBuilder.width(for: tool, pressure: 0) == 2)
        #expect(CapturedStrokeBuilder.width(for: tool, pressure: 1) == 6)
        #expect(CapturedStrokeBuilder.width(for: tool, pressure: 3) == 6)
    }

    @Test
    func evenInksAndTouchesWithoutPressureKeepTheNominalWidth() {
        #expect(CapturedStrokeBuilder.width(for: InkTool(.pen, width: 4), pressure: nil) == 4)
        #expect(CapturedStrokeBuilder.width(for: InkTool(.monoline, width: 3), pressure: 1) == 3)
        #expect(CapturedStrokeBuilder.width(for: .highlighter, pressure: 1) == 24)
    }

    @Test
    func noSamplesMakeNoStroke() {
        #expect(CapturedStrokeBuilder.stroke(from: [], tool: .pen) == nil)
    }

    @Test
    func strokeStartsAndEndsAtTheTouchAndUsesTheTool() throws {
        let tool = InkTool(.pen, color: RGBAColor(r: 1, g: 0, b: 0, a: 1), width: 4)
        let stroke = try #require(CapturedStrokeBuilder.stroke(from: samples(4), tool: tool))
        let points = Array(stroke.path)

        #expect(stroke.ink.inkType == .pen)
        #expect(RGBAColor(cgColor: stroke.ink.color.cgColor) == RGBAColor(r: 1, g: 0, b: 0, a: 1))
        #expect(points.count == 8)
        #expect(points.first?.location == CGPoint(x: 10, y: 20))
        #expect(points.last?.location == CGPoint(x: 25, y: 20))
        #expect(points.first?.timeOffset == 0)
        #expect(abs((points.last?.timeOffset ?? 0) - 0.03) < 0.0001)
        // PencilKit stores point attributes at reduced precision.
        #expect(points.allSatisfy {
            abs($0.size.width - 4) < 0.01 && abs($0.altitude - 1) < 0.01 && abs($0.azimuth - 0.5) < 0.01
        })
    }

    @Test
    func aDotIsKept() throws {
        let stroke = try #require(CapturedStrokeBuilder.stroke(from: samples(1), tool: .pen))
        #expect(stroke.path.count == 5)
        #expect(stroke.renderBounds.width > 0)
    }

    @Test
    func highlighterStrokeIsStoredAsHighlighter() throws {
        let stroke = try #require(CapturedStrokeBuilder.stroke(from: samples(3), tool: .highlighter))
        let record = StrokeCodec.record(from: stroke, layerID: UUID())
        #expect(record.tool.isHighlighter)
    }
}
