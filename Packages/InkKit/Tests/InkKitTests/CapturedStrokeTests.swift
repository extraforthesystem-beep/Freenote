import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PencilKit
import Testing

struct CapturedStrokeTests {
    private func samples(_ forces: [CGFloat?]) -> [InkSample] {
        forces.enumerated().map { index, force in
            InkSample(
                location: CGPoint(x: 10 + Double(index) * 4, y: 20),
                timestamp: 100 + Double(index) * 0.01,
                force: force,
                altitude: 1.1,
                azimuth: 0.3
            )
        }
    }

    @Test
    func averageForceAndNoForceGiveTheNominalWidth() {
        #expect(CapturedStroke.pointWidth(nominal: 4, force: 1, inkType: .pen) == 4)
        #expect(CapturedStroke.pointWidth(nominal: 4, force: nil, inkType: .pen) == 4)
    }

    @Test
    func pressureSensitiveWidthGrowsWithForceWithinBounds() {
        let light = CapturedStroke.pointWidth(nominal: 4, force: 0.2, inkType: .pen)
        let firm = CapturedStroke.pointWidth(nominal: 4, force: 2, inkType: .pen)
        #expect(light < 4)
        #expect(firm > 4)
        #expect(CapturedStroke.pointWidth(nominal: 4, force: 0, inkType: .pen) >= 2)
        #expect(CapturedStroke.pointWidth(nominal: 4, force: 10, inkType: .pen) == 6)
    }

    @Test
    func uniformInksIgnoreForce() {
        for inkType in [PKInk.InkType.marker, .monoline, .pencil] {
            #expect(CapturedStroke.pointWidth(nominal: 24, force: 3, inkType: inkType) == 24)
        }
    }

    @Test
    func strokeKeepsSamplesInkAndTiming() throws {
        let input = samples([0.5, 1, 1.5])
        let ink = PKInk(.pen, color: InkPlatformColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        let stroke = try #require(CapturedStroke.stroke(from: input, ink: ink, width: 3))
        let points = Array(stroke.path)

        #expect(stroke.ink.inkType == .pen)
        #expect(points.count == 3)
        #expect(points[0].location == CGPoint(x: 10, y: 20))
        #expect(points[2].location == CGPoint(x: 18, y: 20))
        #expect(abs(points[0].timeOffset) < 0.000_1)
        #expect(abs(points[2].timeOffset - 0.02) < 0.000_1)
        #expect(points[0].size.width < points[2].size.width)
        #expect(abs(points[1].altitude - 1.1) < 0.000_1)
        #expect(abs(points[1].azimuth - 0.3) < 0.000_1)
    }

    @Test
    func timeOffsetsNeverGoBackwards() {
        var input = samples([1, 1, 1])
        input[2].timestamp = input[0].timestamp
        let points = CapturedStroke.strokePoints(from: input, width: 2, inkType: .pen)
        #expect(points[2].timeOffset >= points[1].timeOffset)
    }

    @Test
    func noSamplesMakeNoStroke() {
        #expect(CapturedStroke.stroke(from: [], ink: PKInk(.pen, color: .black), width: 2) == nil)
    }

    @Test
    func capturedHighlighterIsStoredAsHighlighter() throws {
        let tool = InkTool.highlighter
        let stroke = try #require(CapturedStroke.stroke(
            from: samples([nil, nil]),
            ink: tool.inkingTool.ink,
            width: tool.inkingTool.width
        ))
        let record = StrokeCodec.record(from: stroke, layerID: UUID())
        #expect(record.tool.isHighlighter)
    }
}
