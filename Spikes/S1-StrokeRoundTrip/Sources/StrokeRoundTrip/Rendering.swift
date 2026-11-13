import AppKit
import Foundation
import PencilKit

public struct RGBABitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Raw RGBA8 bytes, row major, as produced by `NSBitmapImageRep`.
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public var nonTransparentPixels: Int {
        stride(from: 0, to: bytes.count, by: 4).reduce(0) { count, offset in
            bytes[offset + 3] > 0 ? count + 1 : count
        }
    }
}

public struct BitmapDiff: Sendable {
    public let dimensionsMatch: Bool
    public let differingPixels: Int
    public let maxChannelDelta: Int
    public let differingAlphaPixels: Int
    public let differingRGBPixels: Int
    public let originalNonTransparentPixels: Int
    public let rebuiltNonTransparentPixels: Int

    public var identical: Bool { dimensionsMatch && differingPixels == 0 }

    public var summary: String {
        "identical=\(identical) size=\(originalNonTransparentPixels)/\(rebuiltNonTransparentPixels)px "
            + "differingPixels=\(differingPixels) maxChannelDelta=\(maxChannelDelta) "
            + "alphaOnlyDiff=\(differingAlphaPixels) rgbDiffAtSameAlpha=\(differingRGBPixels)"
    }
}

public enum SpikeRenderError: Error, CustomStringConvertible {
    case emptyRect
    case bitmapAllocationFailed(Int, Int)
    case missingGraphicsContext
    case blankImage(Int)

    public var description: String {
        switch self {
        case .emptyRect: return "render rect is empty"
        case .bitmapAllocationFailed(let w, let h): return "NSBitmapImageRep allocation failed for \(w)x\(h)"
        case .missingGraphicsContext: return "could not make an NSGraphicsContext for the bitmap"
        case .blankImage(let pixels): return "rendered image is blank (\(pixels) non-transparent pixels)"
        }
    }
}

/// Renders a drawing with PencilKit's own `image(from:scale:)` into raw RGBA bytes.
public func renderRGBA(_ drawing: PKDrawing, rect: CGRect, scale: CGFloat) throws -> RGBABitmap {
    guard rect.width > 0, rect.height > 0 else { throw SpikeRenderError.emptyRect }

    let image = drawing.image(from: rect, scale: scale)
    let pixelWidth = Int((rect.width * scale).rounded())
    let pixelHeight = Int((rect.height * scale).rounded())
    guard pixelWidth > 0, pixelHeight > 0 else { throw SpikeRenderError.emptyRect }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelWidth,
                                     pixelsHigh: pixelHeight,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: pixelWidth * 4,
                                     bitsPerPixel: 32) else {
        throw SpikeRenderError.bitmapAllocationFailed(pixelWidth, pixelHeight)
    }
    rep.size = NSSize(width: rect.width, height: rect.height)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw SpikeRenderError.missingGraphicsContext
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .none
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: rect.width, height: rect.height).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let byteCount = pixelWidth * pixelHeight * 4
    guard let data = rep.bitmapData else { throw SpikeRenderError.bitmapAllocationFailed(pixelWidth, pixelHeight) }
    let bytes = [UInt8](UnsafeBufferPointer(start: data, count: byteCount))
    return RGBABitmap(width: pixelWidth, height: pixelHeight, bytes: bytes)
}

public func compareBitmaps(_ original: RGBABitmap, _ rebuilt: RGBABitmap) -> BitmapDiff {
    let dimensionsMatch = original.width == rebuilt.width && original.height == rebuilt.height
    guard dimensionsMatch else {
        return BitmapDiff(dimensionsMatch: false, differingPixels: -1, maxChannelDelta: -1,
                          differingAlphaPixels: -1, differingRGBPixels: -1,
                          originalNonTransparentPixels: original.nonTransparentPixels,
                          rebuiltNonTransparentPixels: rebuilt.nonTransparentPixels)
    }

    var differingPixels = 0
    var maxChannelDelta = 0
    var differingAlphaPixels = 0
    var differingRGBPixels = 0

    var offset = 0
    while offset < original.bytes.count {
        let r0 = Int(original.bytes[offset]), g0 = Int(original.bytes[offset + 1])
        let b0 = Int(original.bytes[offset + 2]), a0 = Int(original.bytes[offset + 3])
        let r1 = Int(rebuilt.bytes[offset]), g1 = Int(rebuilt.bytes[offset + 1])
        let b1 = Int(rebuilt.bytes[offset + 2]), a1 = Int(rebuilt.bytes[offset + 3])
        let deltas = [abs(r0 - r1), abs(g0 - g1), abs(b0 - b1), abs(a0 - a1)]
        let pixelMax = deltas.max() ?? 0
        if pixelMax > 0 {
            differingPixels += 1
            maxChannelDelta = max(maxChannelDelta, pixelMax)
            if a0 != a1 { differingAlphaPixels += 1 }
            if r0 != r1 || g0 != g1 || b0 != b1 { differingRGBPixels += 1 }
        }
        offset += 4
    }

    return BitmapDiff(dimensionsMatch: true,
                      differingPixels: differingPixels,
                      maxChannelDelta: maxChannelDelta,
                      differingAlphaPixels: differingAlphaPixels,
                      differingRGBPixels: differingRGBPixels,
                      originalNonTransparentPixels: original.nonTransparentPixels,
                      rebuiltNonTransparentPixels: rebuilt.nonTransparentPixels)
}
