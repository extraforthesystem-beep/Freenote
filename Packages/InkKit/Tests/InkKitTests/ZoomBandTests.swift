import CoreGraphics
import Foundation
import InkKit
import NoteCore
import Testing

struct ZoomBandTests {
    /// A4 portrait, a panel three times wider than tall.
    private let page = CGSize(width: 600, height: 840)
    private func band(_ magnification: Double = 2.5, aspect: CGFloat = 3, origin: CGPoint? = nil) -> ZoomBand {
        ZoomBand(pageSize: page, magnification: magnification, panelAspect: aspect, origin: origin)
    }

    @Test
    func startsAtTheTopLeftMarginsWithThePanelAspect() {
        let band = band()
        #expect(band.rect == CGRect(x: 30, y: 30, width: 240, height: 80))
        #expect(band.lineStartX == 30)
        #expect(band.lineEndX == 330)
    }

    @Test
    func magnificationIsClampedAndShrinksToFitThePage() {
        #expect(band(10).rect.width == 120)
        #expect(band(1).rect.width == 400)
        // A very tall panel: the band keeps its aspect and fits the page height.
        let tall = ZoomBand.size(pageSize: page, magnification: 1.5, panelAspect: 0.25)
        #expect(tall.height == 840)
        #expect(tall.width == 210)
        #expect(ZoomBand.magnification(forWidth: 240, pageWidth: 600) == 2.5)
        #expect(ZoomBand.magnification(forWidth: 10, pageWidth: 600) == 5)
    }

    @Test
    func advanceStepsRightThenStopsFlushWithTheMarginThenWraps() {
        var band = band()
        do { let moved = band.advance(); #expect(moved) }
        #expect(abs(band.rect.minX - 174) < 0.001)
        do { let moved = band.advance(); #expect(moved) }
        // Still short of the 330 limit, so a full step.
        #expect(abs(band.rect.minX - 318) < 0.001)
        do { let moved = band.advance(); #expect(moved) }
        #expect(band.rect.minX == 330)
        #expect(band.rect.maxX == 570)
        // Already flush with the right margin: next line.
        do { let moved = band.advance(); #expect(moved) }
        #expect(band.rect.origin == CGPoint(x: 30, y: 110))
    }

    @Test
    func newLineStopsAtTheBottomOfThePage() {
        var band = band(origin: CGPoint(x: 200, y: 700))
        do { let moved = band.newLine(); #expect(moved) }
        #expect(band.rect.origin == CGPoint(x: 30, y: 760))
        do { let moved = band.newLine(); #expect(!moved) }
        #expect(band.rect.origin == CGPoint(x: 30, y: 760))
        band.move(to: CGPoint(x: 330, y: 760))
        do { let moved = band.advance(); #expect(!moved) }
        #expect(band.rect.origin == CGPoint(x: 330, y: 760))
    }

    @Test
    func backStepsLeftThenGoesToTheEndOfTheLineAbove() {
        var band = band(origin: CGPoint(x: 100, y: 200))
        do { let moved = band.back(); #expect(moved) }
        #expect(band.rect.minX == 30)
        do { let moved = band.back(); #expect(moved) }
        #expect(band.rect.origin == CGPoint(x: 330, y: 120))
        band.move(to: CGPoint(x: 30, y: 0))
        do { let moved = band.back(); #expect(!moved) }
    }

    @Test
    func moveKeepsTheBandOnThePage() {
        var band = band()
        band.move(to: CGPoint(x: -50, y: 2000))
        #expect(band.rect.origin == CGPoint(x: 0, y: 760))
        band.move(to: CGPoint(x: 1000, y: -1))
        #expect(band.rect.origin == CGPoint(x: 360, y: 0))
    }

    @Test
    func advanceAreaIsTheRightFifthOfTheBand() {
        let band = band()
        #expect(band.isInAdvanceArea(CGPoint(x: 230, y: 60)))
        #expect(band.isInAdvanceArea(CGPoint(x: 269, y: 109)))
        #expect(!band.isInAdvanceArea(CGPoint(x: 220, y: 60)))
        #expect(!band.isInAdvanceArea(CGPoint(x: 230, y: 120)))
    }

    @Test
    func pageAndPanelPointsRoundTrip() {
        let band = band()
        #expect(band.scale(panelWidth: 960) == 4)
        let panel = band.panelPoint(fromPage: CGPoint(x: 130, y: 50), panelWidth: 960)
        #expect(panel == CGPoint(x: 400, y: 80))
        #expect(band.pagePoint(fromPanel: panel, panelWidth: 960) == CGPoint(x: 130, y: 50))
    }

    @Test
    func strokeEndPointFollowsTheTransform() {
        var record = StrokeCodec.record(from: SampleStroke.stroke(style: .pen, index: 0), layerID: UUID())
        record.points = [record.points[0], record.points[0]]
        record.points[1].x = 10
        record.points[1].y = 20
        #expect(ZoomBand.endPoint(of: record) == CGPoint(x: 10, y: 20))
        record.transform = [2, 0, 0, 2, 5, 7]
        #expect(ZoomBand.endPoint(of: record) == CGPoint(x: 25, y: 47))
        record.points = []
        #expect(ZoomBand.endPoint(of: record) == nil)
    }
}
