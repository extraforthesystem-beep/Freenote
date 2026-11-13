import CoreGraphics
import Testing
import BoardKit

/// The board stores its camera as the world rectangle the view showed, which
/// is independent of the zoom scale a particular scroll view happened to use.
struct BoardCameraFreeformTests {
    @Test func cameraFromVisibleRectShowsTheSameRect() {
        let viewSize = CGSize(width: 1_194, height: 834)
        let rect = CGRect(x: 24_120, y: 24_510, width: 1_194, height: 834)

        let camera = BoardCamera(visibleWorldRect: rect, viewSize: viewSize)

        #expect(camera.centerX == Double(rect.midX))
        #expect(camera.centerY == Double(rect.midY))
        #expect(camera.zoom == 1)
        #expect(camera.visibleWorldRect(viewSize: viewSize) == rect)
    }

    @Test func cameraFromZoomedVisibleRectRoundTrips() {
        let viewSize = CGSize(width: 1_000, height: 700)
        let rect = CGRect(x: 25_500, y: 24_800, width: 2_000, height: 1_400)

        let camera = BoardCamera(visibleWorldRect: rect, viewSize: viewSize)
        let shown = camera.visibleWorldRect(viewSize: viewSize)

        #expect(abs(camera.zoom - 0.5) < 1e-12)
        #expect(abs(shown.minX - rect.minX) < 1e-9)
        #expect(abs(shown.minY - rect.minY) < 1e-9)
        #expect(abs(shown.width - rect.width) < 1e-9)
        #expect(abs(shown.height - rect.height) < 1e-9)
    }

    @Test func restoringOnAnotherViewSizeKeepsCentreAndMagnification() {
        let savedRect = CGRect(x: 25_000, y: 25_000, width: 800, height: 600)
        let camera = BoardCamera(visibleWorldRect: savedRect, viewSize: CGSize(width: 800, height: 600))
        let widerView = CGSize(width: 1_200, height: 600)
        let restored = camera.visibleWorldRect(viewSize: widerView)

        #expect(restored.midX == savedRect.midX)
        #expect(restored.midY == savedRect.midY)
        #expect(abs(restored.width - 1_200) < 1e-9)
        #expect(abs(restored.height - 600) < 1e-9)
    }

    @Test func emptyVisibleRectFallsBackToDefaultCamera() {
        let camera = BoardCamera(
            visibleWorldRect: CGRect(x: 10, y: 20, width: 0, height: 0),
            viewSize: CGSize(width: 1_000, height: 800)
        )

        #expect(camera.zoom == 1)
        #expect(camera.centerX == 10)
        #expect(camera.centerY == 20)
    }

    @Test func extremeVisibleRectIsClampedToSupportedZoom() {
        let camera = BoardCamera(
            visibleWorldRect: CGRect(x: 0, y: 0, width: 100_000, height: 100_000),
            viewSize: CGSize(width: 1_000, height: 1_000)
        )

        #expect(camera.zoom == BoardCamera.minimumZoom)
    }
}
