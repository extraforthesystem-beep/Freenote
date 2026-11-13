// A custom page template is a picture in the notebook's assets. The page must
// draw it aspect-fit over its paper, and a missing file must cost the picture,
// not the page.

import CoreGraphics
import Foundation
import ImageIO
import NoteCore
import Testing
@testable import InkKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@Suite("Custom page templates")
struct CustomTemplateTests {
    static let red = RGBAColor(r: 0.9, g: 0.05, b: 0.05)

    @Test("A custom template draws its picture aspect-fit")
    func drawsPicture() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try writePNG(try solidImage(width: 100, height: 100), to: assets.appendingPathComponent("template.png"))

        let template = PageTemplate.custom(assetName: "template.png")
        let image = try #require(
            PageRenderer.image(
                strokes: [],
                pageSize: CGSize(width: 100, height: 200),
                template: template,
                assetsDirectory: assets,
                scale: 1
            )
        )
        let bitmap = try #require(TestBitmap(image: image))
        // A square picture on a tall page covers a band in the middle.
        #expect(bitmap.pixel(50, 100).isRed)
        #expect(bitmap.pixel(50, 5).isPaper)
    }

    @Test("A missing picture leaves the paper plain")
    func missingPicture() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for assetsDirectory in [nil, directory] {
            let image = try #require(
                TemplateRenderer.image(
                    PageTemplate.custom(assetName: "absent.png"),
                    pageSize: CGSize(width: 60, height: 60),
                    scale: 1,
                    assetsDirectory: assetsDirectory
                )
            )
            let bitmap = try #require(TestBitmap(image: image))
            #expect(bitmap.pixel(30, 30).isPaper)
        }
    }

    @Test("A built-in kind is not a custom template")
    func builtInHasNoAsset() {
        #expect(PageTemplate.blank.customAssetName == nil)
        #expect(PageTemplate.custom(assetName: "x.png").customAssetName == "x.png")
        #expect(PageTemplate(kind: "custom:", spacing: 0, lineColor: .white, paperColor: .white).customAssetName == nil)
    }

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-template-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func solidImage(width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            Issue.record("could not create a bitmap")
            throw CancellationError()
        }
        let colour = Self.red
        context.setFillColor(
            CGColor(srgbRed: colour.r, green: colour.g, blue: colour.b, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            Issue.record("could not make an image")
            throw CancellationError()
        }
        return image
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            Issue.record("could not create \(url.lastPathComponent)")
            throw CancellationError()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            Issue.record("could not write \(url.lastPathComponent)")
            throw CancellationError()
        }
    }
}

/// A rendered page flattened to sRGB, rows numbered from the top of the page.
private struct TestBitmap {
    let width: Int
    let height: Int
    let data: [UInt8]

    init?(image: InkImage) {
        guard let cgImage = Self.cgImage(of: image) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        self.width = width
        self.height = height
        self.data = data
    }

    func pixel(_ x: Int, _ y: Int) -> Pixel {
        let x = min(max(x, 0), width - 1)
        let y = min(max(y, 0), height - 1)
        let index = (y * width + x) * 4
        return Pixel(r: Int(data[index]), g: Int(data[index + 1]), b: Int(data[index + 2]))
    }

    private static func cgImage(of image: InkImage) -> CGImage? {
        #if os(iOS)
        image.cgImage
        #else
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

private struct Pixel {
    let r: Int
    let g: Int
    let b: Int

    var isPaper: Bool { r > 245 && g > 245 && b > 245 }
    var isRed: Bool { r > 200 && g < 80 && b < 80 }
}
