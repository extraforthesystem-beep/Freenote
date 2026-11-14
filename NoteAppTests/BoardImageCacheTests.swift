import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NoteApp

/// The board's photo cache and decoder: the piece that keeps a photo off the
/// main actor and out of a per-frame disk read.
@MainActor
final class BoardImageCacheTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardImageCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        BoardImageCache.removeAll()
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Writes a solid-colour PNG of the given pixel size.
    private func writePNG(width: Int, height: Int) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let url = root.appendingPathComponent("photo-\(width)x\(height).png")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    // MARK: - Decoder

    func testDecodeCapsTheLongestEdgeAtThePixelBudget() throws {
        let url = try writePNG(width: 3_000, height: 1_500)

        let decoded = try XCTUnwrap(BoardImageDecoder.decode(fileAt: url))

        XCTAssertEqual(decoded.width, BoardImageDecoder.maximumPixelSize)
        XCTAssertEqual(decoded.height, BoardImageDecoder.maximumPixelSize / 2)
    }

    func testDecodeDoesNotUpscaleASmallPhoto() throws {
        let url = try writePNG(width: 120, height: 60)

        let decoded = try XCTUnwrap(BoardImageDecoder.decode(fileAt: url))

        XCTAssertEqual(decoded.width, 120)
        XCTAssertEqual(decoded.height, 60)
    }

    func testDecodeReturnsNilForAMissingFile() {
        let url = root.appendingPathComponent("not-there.png")

        XCTAssertNil(BoardImageDecoder.decode(fileAt: url))
    }

    // MARK: - Cache

    func testCacheReturnsWhatItStoredAndForgetsItOnPurge() throws {
        let url = try writePNG(width: 200, height: 100)
        let decoded = try XCTUnwrap(BoardImageDecoder.decode(fileAt: url))

        XCTAssertNil(BoardImageCache.shared.image(for: url))

        BoardImageCache.shared.store(decoded, for: url)
        let cached = try XCTUnwrap(BoardImageCache.shared.image(for: url))
        XCTAssertEqual(cached.width, decoded.width)
        XCTAssertEqual(cached.height, decoded.height)

        BoardImageCache.removeAll()
        XCTAssertNil(BoardImageCache.shared.image(for: url))
    }

    func testCacheKeysByPath() throws {
        let first = try writePNG(width: 40, height: 40)
        let second = try writePNG(width: 80, height: 80)

        BoardImageCache.shared.store(try XCTUnwrap(BoardImageDecoder.decode(fileAt: first)), for: first)

        XCTAssertNotNil(BoardImageCache.shared.image(for: first))
        XCTAssertNil(BoardImageCache.shared.image(for: second))
    }
}
