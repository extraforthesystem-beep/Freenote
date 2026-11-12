import AppKit
import Foundation
import PencilKit

/// A tiny seeded PRNG (SplitMix64), written out so runs reproduce exactly.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func uuid() -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { bytes[i] = UInt8(truncatingIfNeeded: next()) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

public enum InkStyles {
    /// Every PencilKit pen style, in a stable order.
    public static var all: [PKInkingTool.InkType] {
        [.pen, .pencil, .marker, .monoline, .fountainPen, .watercolor, .crayon, .reed]
    }

    public static var allNames: [String] { all.map(\.rawValue) }

    public static func name(_ type: PKInkingTool.InkType) -> String { type.rawValue }
}

public enum StrokeFactory {
    public static let canvas = CGRect(x: 0, y: 0, width: 600, height: 400)
    public static let controlPointCounts = [2, 17, 64, 133, 200]

    /// Five synthetic strokes for one pen style, all deterministic for a given seed.
    public static func strokes(for inkType: PKInkingTool.InkType,
                               seed: UInt64 = 0x5EED_1) -> [PKStroke] {
        (0..<5).map { index in
            stroke(inkType: inkType, index: index, seed: seed)
        }
    }

    public static func allStrokes(seed: UInt64 = 0x5EED_1) -> [(ink: PKInkingTool.InkType, stroke: PKStroke)] {
        InkStyles.all.flatMap { ink in
            strokes(for: ink, seed: seed).map { (ink, $0) }
        }
    }

    public static func stroke(inkType: PKInkingTool.InkType,
                              index: Int,
                              seed: UInt64) -> PKStroke {
        var styleSeed = seed &* 0x100_0000_01B3
        for scalar in inkType.rawValue.unicodeScalars { styleSeed = styleSeed &* 31 &+ UInt64(scalar.value) }
        var rng = SplitMix64(seed: styleSeed ^ (UInt64(index) &* 0xD1B5_4A32_D192_ED03))

        let count = controlPointCounts[index]
        let phase = rng.double(in: 0...(.pi * 2))
        // Monoline's default tool width is 0.5 pt and PencilKit draws nothing at
        // point sizes below about 2 pt on macOS 27.2, so clamp to a drawable base.
        let baseWidth = max(Double(inkType.defaultWidth), 3.0)
        let secondaryHeavy = inkType == .watercolor || inkType == .reed

        var points: [PKStrokePoint] = []
        points.reserveCapacity(count)
        var time: Double = 0

        for i in 0..<count {
            let t = count > 1 ? Double(i) / Double(count - 1) : 0
            let x = 40 + t * 420 + rng.double(in: -1.5...1.5)
            let y = 200 + sin(t * .pi * 2 + phase) * 70 + rng.double(in: -2...2)

            time += rng.double(in: 0.004...0.02)

            let widthFactor = 0.35 + 1.65 * rng.unit()
            let width = max(0.1, baseWidth * widthFactor)
            let height = index == 2 ? width * 1.4 : width

            var opacity = rng.double(in: 0.05...1.0)
            if index == 0 { opacity = 1.0 }
            if index == 3 && i == count / 2 { opacity = 1.9 }

            var force = rng.double(in: 0...1)
            if i == 0 { force = 0 }
            if i == count - 1 { force = 1 }

            var azimuth = rng.double(in: 0...(.pi * 2))
            if i == 0 { azimuth = 0 }
            var altitude = rng.double(in: 0...(.pi / 2))
            if i == count - 1 { altitude = .pi / 2 }

            let secondaryScale = secondaryHeavy ? rng.double(in: 0.2...1.0) : rng.double(in: 0...0.4)
            let threshold = inkType == .reed && index == 2 ? rng.double(in: 0.1...0.9) : 0.0
            let lateralJitter = inkType == .pencil ? rng.double(in: 0...1) : 0.0

            points.append(PKStrokePoint(location: CGPoint(x: x, y: y),
                                        timeOffset: time,
                                        size: CGSize(width: width, height: height),
                                        opacity: opacity,
                                        force: force,
                                        azimuth: azimuth,
                                        altitude: altitude,
                                        secondaryScale: secondaryScale,
                                        threshold: threshold,
                                        lateralJitter: lateralJitter))
        }

        let path = PKStrokePath(controlPoints: points,
                                creationDate: Date(timeIntervalSinceReferenceDate: 780_000_000 + Double(index) * 137.5),
                                id: rng.uuid())

        let transform: CGAffineTransform
        switch index {
        case 1:
            transform = CGAffineTransform(translationX: 12.5, y: -7.25)
        case 2:
            transform = CGAffineTransform(rotationAngle: 0.35)
                .concatenating(CGAffineTransform(scaleX: 1.7, y: 0.6))
        case 3:
            transform = CGAffineTransform(a: 1, b: 0.1, c: 0.35, d: 1, tx: -4, ty: 9)
        case 4:
            transform = CGAffineTransform(translationX: 0.125, y: 0.0625)
        default:
            transform = .identity
        }

        let mask = index == 0 ? nil : makeMask(index: index)

        return PKStroke(ink: PKInk(inkType, color: color(index: index)),
                        path: path,
                        transform: transform,
                        mask: mask,
                        randomSeed: UInt32(truncatingIfNeeded: rng.next()),
                        id: rng.uuid(),
                        renderGroupID: index == 3 ? UUID(uuidString: "00000000-0000-4000-8000-0000000000\(String(format: "%02d", 11 + index))") : nil,
                        renderState: nil)
    }

    /// Several colours, including two with alpha below 1 and one Display P3 colour.
    public static func color(index: Int) -> NSColor {
        switch index {
        case 0: return NSColor(srgbRed: 0.10, green: 0.20, blue: 0.30, alpha: 1.0)
        case 1: return NSColor(srgbRed: 0.90, green: 0.10, blue: 0.10, alpha: 0.35)
        case 2: return NSColor(displayP3Red: 0.20, green: 0.80, blue: 0.40, alpha: 1.0)
        case 3: return NSColor(srgbRed: 0.95, green: 0.85, blue: 0.10, alpha: 0.70)
        default: return NSColor(displayP3Red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0)
        }
    }

    /// An eraser-style clip mask (pre-transform), so the stroke is partly masked.
    public static func makeMask(index: Int) -> NSBezierPath {
        let path = NSBezierPath()
        switch index {
        case 1:
            // Rectangle over the left part of the stroke.
            path.move(to: CGPoint(x: 60, y: 60))
            path.line(to: CGPoint(x: 260, y: 60))
            path.line(to: CGPoint(x: 260, y: 340))
            path.line(to: CGPoint(x: 60, y: 340))
            path.close()
        case 2:
            // Circle over the middle, four cubic segments.
            let center = CGPoint(x: 280, y: 200)
            let r: CGFloat = 90
            let k: CGFloat = 0.552_284_749_831
            path.move(to: CGPoint(x: center.x, y: center.y + r))
            path.curve(to: CGPoint(x: center.x + r, y: center.y),
                       controlPoint1: CGPoint(x: center.x + r * k, y: center.y + r),
                       controlPoint2: CGPoint(x: center.x + r, y: center.y + r * k))
            path.curve(to: CGPoint(x: center.x, y: center.y - r),
                       controlPoint1: CGPoint(x: center.x + r, y: center.y - r * k),
                       controlPoint2: CGPoint(x: center.x + r * k, y: center.y - r))
            path.curve(to: CGPoint(x: center.x - r, y: center.y),
                       controlPoint1: CGPoint(x: center.x - r * k, y: center.y - r),
                       controlPoint2: CGPoint(x: center.x - r, y: center.y - r * k))
            path.curve(to: CGPoint(x: center.x, y: center.y + r),
                       controlPoint1: CGPoint(x: center.x - r, y: center.y + r * k),
                       controlPoint2: CGPoint(x: center.x - r * k, y: center.y + r))
            path.close()
        case 3:
            // Two subpaths: a rectangle and a triangle.
            path.move(to: CGPoint(x: 100, y: 80))
            path.line(to: CGPoint(x: 400, y: 80))
            path.line(to: CGPoint(x: 400, y: 200))
            path.line(to: CGPoint(x: 100, y: 200))
            path.close()
            path.move(to: CGPoint(x: 150, y: 240))
            path.line(to: CGPoint(x: 350, y: 240))
            path.line(to: CGPoint(x: 250, y: 360))
            path.close()
        case 4:
            // Quadratic segments.
            path.move(to: CGPoint(x: 80, y: 120))
            path.curve(to: CGPoint(x: 300, y: 120), controlPoint: CGPoint(x: 190, y: 20))
            path.curve(to: CGPoint(x: 520, y: 120), controlPoint: CGPoint(x: 410, y: 220))
            path.line(to: CGPoint(x: 520, y: 320))
            path.line(to: CGPoint(x: 80, y: 320))
            path.close()
        default:
            // No mask.
            path.move(to: CGPoint(x: 0, y: 0))
            path.line(to: CGPoint(x: 1, y: 0))
            path.line(to: CGPoint(x: 1, y: 1))
            path.close()
        }
        path.windingRule = index == 3 ? .evenOdd : .nonZero
        return path
    }
}
