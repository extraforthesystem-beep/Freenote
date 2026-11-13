import CoreGraphics
import XCTest
import BoardKit

final class BoardCameraTests: XCTestCase {
    func testWorldAndViewMappingsAreInversesAtSeveralZooms() {
        let viewSize = CGSize(width: 1_024, height: 768)
        let viewPoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 512, y: 384),
            CGPoint(x: 1_024, y: 768),
            CGPoint(x: -40, y: 900),
        ]
        let worldPoints = [
            CGPoint(x: -10_000, y: 5_000),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 999.5, y: -1.25),
        ]

        for zoom in [0.1, 0.25, 1.0, 2.5, 8.0] {
            let camera = BoardCamera(centerX: 123.5, centerY: -456.25, zoom: zoom)

            for viewPoint in viewPoints {
                let world = camera.worldPoint(fromViewPoint: viewPoint, viewSize: viewSize)
                let roundTrip = camera.viewPoint(fromWorldPoint: world, viewSize: viewSize)
                XCTAssertEqual(roundTrip.x, viewPoint.x, accuracy: 0.5)
                XCTAssertEqual(roundTrip.y, viewPoint.y, accuracy: 0.5)
            }

            for worldPoint in worldPoints {
                let view = camera.viewPoint(fromWorldPoint: worldPoint, viewSize: viewSize)
                let roundTrip = camera.worldPoint(fromViewPoint: view, viewSize: viewSize)
                XCTAssertEqual(roundTrip.x, worldPoint.x, accuracy: 0.5)
                XCTAssertEqual(roundTrip.y, worldPoint.y, accuracy: 0.5)
            }
        }
    }

    func testVisibleWorldRect() {
        let camera = BoardCamera(centerX: 100, centerY: 200, zoom: 2)
        let rect = camera.visibleWorldRect(viewSize: CGSize(width: 800, height: 600))

        XCTAssertEqual(rect.minX, -100, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 50, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 400, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 300, accuracy: 1e-9)
    }

    func testZoomIsClampedOnInitAssignmentAndDecode() throws {
        XCTAssertEqual(BoardCamera(zoom: 0.001).zoom, BoardCamera.minimumZoom)
        XCTAssertEqual(BoardCamera(zoom: 100).zoom, BoardCamera.maximumZoom)

        var camera = BoardCamera()
        camera.zoom = 0.001
        XCTAssertEqual(camera.zoom, BoardCamera.minimumZoom)
        camera.zoom = 100
        XCTAssertEqual(camera.zoom, BoardCamera.maximumZoom)

        let json = Data(#"{"centerX":12,"centerY":-34,"zoom":0.001}"#.utf8)
        let decoded = try JSONDecoder().decode(BoardCamera.self, from: json)
        XCTAssertEqual(decoded.zoom, BoardCamera.minimumZoom)
        XCTAssertEqual(decoded.centerX, 12)
        XCTAssertEqual(decoded.centerY, -34)
    }

    func testCodableRoundTrip() throws {
        let camera = BoardCamera(centerX: 12.5, centerY: -34.75, zoom: 3.25)
        let data = try JSONEncoder().encode(camera)
        XCTAssertEqual(try JSONDecoder().decode(BoardCamera.self, from: data), camera)
    }
}
