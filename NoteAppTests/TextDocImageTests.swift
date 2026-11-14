import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NoteApp

/// Image blocks draw the file they name: the loader caps the decode so a
/// full-resolution photo cannot be decoded at the size it was taken.
final class TextDocImageTests: XCTestCase {
    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func temporaryFile(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TextDocImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .notDirectory)
    }

    func testDecodeCapsTheLongEdgeAtThePixelLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TextDocImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "wide.png", directoryHint: .notDirectory)
        try writePNG(width: 3_000, height: 1_500, to: file)

        let decoded = try XCTUnwrap(TextDocImageDecoder.decode(fileAt: file))

        XCTAssertEqual(max(decoded.width, decoded.height), TextDocImageDecoder.maximumPixelSize)
        XCTAssertEqual(Double(decoded.width) / Double(decoded.height), 2, accuracy: 0.05)
    }

    func testDecodeReturnsNilForAMissingFile() {
        let file = temporaryFile(named: "missing.png")

        XCTAssertNil(TextDocImageDecoder.decode(fileAt: file))
    }

    func testAssetLocationResolvesRelativeAndAbsolutePaths() {
        let directory = URL(fileURLWithPath: "/tmp/TextDocs", isDirectory: true)

        XCTAssertEqual(
            TextDocAssetLocation.url(named: "photo.png", in: directory)?.path,
            "/tmp/TextDocs/photo.png"
        )
        XCTAssertEqual(
            TextDocAssetLocation.url(named: "/tmp/elsewhere.png", in: directory)?.path,
            "/tmp/elsewhere.png"
        )
        XCTAssertNil(TextDocAssetLocation.url(named: "   ", in: directory))
    }
}
