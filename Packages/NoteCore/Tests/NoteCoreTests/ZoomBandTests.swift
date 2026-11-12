import CoreGraphics
import Foundation
import Testing
@testable import NoteCore

@Suite("Zoom View band")
struct ZoomBandTests {
    let page = CGSize(width: 600, height: 800)

    @Test func startsAtTheTopLeftMarginWithThePanelsAspect() {
        let band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        #expect(band.rect == CGRect(x: 30, y: 30, width: 240, height: 120))
        #expect(abs(band.magnification - 2.5) < 0.0001)
    }

    @Test func magnificationIsClamped() {
        #expect(abs(ZoomBand(pageSize: page, magnification: 10, aspect: 0.5).magnification - 5) < 0.0001)
        #expect(abs(ZoomBand(pageSize: page, magnification: 1, aspect: 0.5).magnification - 1.5) < 0.0001)
        #expect(ZoomBand.clampedMagnification(.nan) == ZoomBand.defaultMagnification)
    }

    @Test func advanceMovesRightThenStopsAtTheRightMargin() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        band.advance()
        #expect(abs(band.rect.minX - 174) < 0.001)
        band.advance()
        // 318 + 240 = 558 is inside the right margin (570): a full step.
        #expect(abs(band.rect.minX - 318) < 0.001)
        band.advance()
        // The next step would pass the margin, so it stops exactly at it.
        #expect(abs(band.rect.maxX - 570) < 0.001)
        #expect(band.rect.minY == 30)
    }

    @Test func advanceAtTheRightMarginWrapsToTheNextLine() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        band.move(to: CGPoint(x: 330, y: 30))
        band.advance()
        #expect(band.rect.minX == 30)
        #expect(band.rect.minY == 150)
    }

    @Test func newLineStopsAtTheBottomOfThePage() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        for _ in 0..<20 { band.newLine() }
        #expect(band.rect.maxY == 800)
        #expect(band.rect.minX == 30)
    }

    @Test func moveBackStopsAtThePageEdge() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        band.moveBack()
        #expect(band.rect.minX == 0)
    }

    @Test func movingIsKeptOnThePage() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        band.move(to: CGPoint(x: -50, y: 10_000))
        #expect(band.rect.origin == CGPoint(x: 0, y: 680))
    }

    @Test func resizingChangesMagnificationAndKeepsAspect() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        band.resize(toWidth: 300)
        #expect(abs(band.magnification - 2) < 0.0001)
        #expect(band.rect.height == 150)
        band.resize(toWidth: 1)
        #expect(abs(band.magnification - 5) < 0.0001)
    }

    @Test func panelResizeFollowsItsAspect() {
        var band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        band.setAspect(0.25)
        #expect(band.rect.size == CGSize(width: 240, height: 60))
    }

    @Test func advanceAreaIsTheRightFifth() {
        let band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        #expect(band.isInAdvanceArea(CGPoint(x: 260, y: 100)))
        #expect(!band.isInAdvanceArea(CGPoint(x: 200, y: 100)))
        #expect(!band.isInAdvanceArea(CGPoint(x: 260, y: 400)))
    }

    @Test func panelAndPageMappingRoundTrips() {
        let band = ZoomBand(pageSize: page, magnification: 2.5, aspect: 0.5)
        #expect(band.panelScale(panelWidth: 720) == 3)
        let panel = band.panelPoint(fromPage: CGPoint(x: 130, y: 80), panelWidth: 720)
        #expect(panel == CGPoint(x: 300, y: 150))
        #expect(band.pagePoint(fromPanel: panel, panelWidth: 720) == CGPoint(x: 130, y: 80))
    }

    @Test func strokeEndPointFollowsTheTransform() {
        let point = StrokePoint(x: 10, y: 20, timeOffset: 0, width: 2, height: 2, opacity: 1, force: 1, azimuth: 0, altitude: 0, secondaryScale: 1)
        let stroke = StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(engine: "pencilkit", inkType: "pen", color: RGBAColor(r: 0, g: 0, b: 0), width: 2),
            createdAt: Date(),
            transform: [2, 0, 0, 2, 5, 7],
            randomSeed: 0,
            points: [point]
        )
        #expect(ZoomBand.endPoint(of: stroke) == CGPoint(x: 25, y: 47))
    }
}
