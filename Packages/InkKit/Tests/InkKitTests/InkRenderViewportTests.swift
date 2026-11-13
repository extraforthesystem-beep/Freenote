import CoreGraphics
import InkKit
import Testing

struct InkRenderViewportTests {
    private let page = CGSize(width: 595, height: 842)
    private let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)

    @Test
    func wholePageWhileItFitsTheBudget() {
        // 595 × 842 at 1.3 pt/pt on a 2× screen is about 3.4 Mpx.
        let rect = InkRenderViewport.rect(
            pageSize: page, visible: CGRect(x: 0, y: 0, width: 595, height: 600),
            scale: 1.3, displayScale: 2
        )
        #expect(rect == pageRect)
    }

    @Test
    func zoomedInCoversTheVisiblePartWithAMargin() {
        let visible = CGRect(x: 200, y: 300, width: 100, height: 120)
        let rect = InkRenderViewport.rect(pageSize: page, visible: visible, scale: 8, displayScale: 2)
        #expect(rect.contains(visible))
        #expect(rect == CGRect(x: 175, y: 270, width: 150, height: 180))
        // Within the budget: 150 × 180 pt at 16 px/pt.
        #expect(rect.width * rect.height * 256 <= InkRenderViewport.pixelBudget)
    }

    @Test
    func marginShrinksToStayInTheBudget() {
        let visible = CGRect(x: 100, y: 100, width: 200, height: 260)
        let rect = InkRenderViewport.rect(pageSize: page, visible: visible, scale: 6, displayScale: 2)
        #expect(rect.contains(visible))
        // Integral rounding may add at most a point on each side.
        let slack = (rect.width + rect.height) * 2 * 144
        #expect(rect.width * rect.height * 144 <= InkRenderViewport.pixelBudget + slack)
        #expect(rect.width < 200 * 1.5)
    }

    @Test
    func marginIsClampedToThePage() {
        let visible = CGRect(x: -50, y: -40, width: 150, height: 160)
        let rect = InkRenderViewport.rect(pageSize: page, visible: visible, scale: 8, displayScale: 2)
        #expect(rect.minX == 0)
        #expect(rect.minY == 0)
        #expect(pageRect.contains(rect))
    }

    @Test
    func pageOffScreenKeepsTheNearestPiece() {
        let visible = CGRect(x: 100, y: 1000, width: 100, height: 120)
        let rect = InkRenderViewport.rect(pageSize: page, visible: visible, scale: 8, displayScale: 2)
        #expect(pageRect.contains(rect))
        #expect(rect.maxY == page.height)
        #expect(rect.width > 0 && rect.height > 0)
    }

    @Test
    func coversWhenTheVisiblePartIsInside() {
        let rendered = CGRect(x: 100, y: 100, width: 200, height: 200)
        #expect(InkRenderViewport.covers(rendered, visible: CGRect(x: 120, y: 120, width: 100, height: 100), pageSize: page))
        #expect(!InkRenderViewport.covers(rendered, visible: CGRect(x: 250, y: 120, width: 100, height: 100), pageSize: page))
        // Off the page entirely: nothing to cover.
        #expect(InkRenderViewport.covers(rendered, visible: CGRect(x: 0, y: 900, width: 100, height: 100), pageSize: page))
    }
}
