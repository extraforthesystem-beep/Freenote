// Synthetic strokes for the codec tests, in the shape S1's generator produced:
// several point counts, transforms, masks, colours and ink styles.

import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PencilKit

#if os(macOS)
import AppKit
typealias SamplePath = NSBezierPath
#else
import UIKit
typealias SamplePath = UIBezierPath

// The AppKit spellings the samples are written in, so the suite also builds
// for the iOS Simulator, where the iOS-only canvas tests run.
extension UIBezierPath {
    func line(to point: CGPoint) { addLine(to: point) }

    func curve(to point: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
        addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }
}

extension UIColor {
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

enum SampleStroke {
    static let pointCounts = [2, 17, 64, 133]

    static func color(_ index: Int) -> InkPlatformColor {
        switch index {
        case 0: InkPlatformColor(srgbRed: 0.10, green: 0.20, blue: 0.30, alpha: 1.0)
        case 1: InkPlatformColor(srgbRed: 0.90, green: 0.10, blue: 0.10, alpha: 0.35)
        case 2: InkPlatformColor(displayP3Red: 0.20, green: 0.80, blue: 0.40, alpha: 1.0)
        default: InkPlatformColor(displayP3Red: 1.0, green: 0.0, blue: 0.5, alpha: 0.70)
        }
    }

    static func stroke(style: PenStyle, index: Int, pointCount: Int? = nil) -> PKStroke {
        let count = pointCount ?? pointCounts[index % pointCounts.count]
        let base = max(style.defaultWidth, 1)
        var points: [PKStrokePoint] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let t = count > 1 ? Double(i) / Double(count - 1) : 0
            let width = base * (0.5 + 0.5 * Double((i * 3) % 5) / 4)
            let height = width * (0.8 + 0.2 * Double((i * 7) % 3) / 2)
            points.append(
                PKStrokePoint(
                    location: CGPoint(
                        x: 30 + t * 320 + Double(i % 7) * 0.37,
                        y: 140 + sin(t * 2 * .pi) * 55 + Double((i % 11) - 5) * 0.5
                    ),
                    timeOffset: t * 0.75 + Double(i) * 0.001,
                    size: CGSize(width: width, height: height),
                    opacity: 0.35 + 0.65 * Double((i * 7) % 11) / 10,
                    force: Double((i * 13) % 17) / 16,
                    azimuth: (t * 5.5).truncatingRemainder(dividingBy: 6.28),
                    altitude: 0.2 + t * 1.2,
                    secondaryScale: Double((i * 5) % 9) / 10,
                    threshold: index == 2 ? Double((i * 3) % 4) / 3 : 0,
                    lateralJitter: index == 1 ? Double((i * 5) % 3) / 2 : 0
                )
            )
        }

        let path = PKStrokePath(
            controlPoints: points,
            creationDate: Date(timeIntervalSinceReferenceDate: 780_000_000 + Double(index) * 137.5),
            id: UUID()
        )

        let transform: CGAffineTransform
        switch index {
        case 1:
            transform = CGAffineTransform(translationX: 12.5, y: -7.25)
        case 2:
            transform = CGAffineTransform(rotationAngle: 0.35)
                .concatenating(CGAffineTransform(scaleX: 1.7, y: 0.6))
        case 3:
            transform = CGAffineTransform(a: 1, b: 0.1, c: 0.35, d: 1, tx: -4, ty: 9)
        default:
            transform = .identity
        }

        return PKStroke(
            ink: PKInk(style.inkType, color: color(index)),
            path: path,
            transform: transform,
            mask: index == 0 ? nil : mask(index),
            randomSeed: UInt32(truncatingIfNeeded: 0x5EED_1 &+ index * 7919),
            id: UUID(),
            renderGroupID: index == 2 ? UUID() : nil,
            renderState: index == 1
                ? PKStroke.RenderState(grainOffset: CGPoint(x: 1.25, y: -0.5))
                : nil
        )
    }

    /// A rectangle, a four-cubic circle and a two-subpath mask.
    static func mask(_ index: Int) -> SamplePath {
        let path = SamplePath()
        switch index {
        case 1:
            path.move(to: CGPoint(x: 60, y: 60))
            path.line(to: CGPoint(x: 260, y: 60))
            path.line(to: CGPoint(x: 260, y: 340))
            path.line(to: CGPoint(x: 60, y: 340))
            path.close()
        case 2:
            let center = CGPoint(x: 280, y: 200)
            let radius: CGFloat = 90
            let k: CGFloat = 0.552_284_749_831
            path.move(to: CGPoint(x: center.x, y: center.y + radius))
            path.curve(
                to: CGPoint(x: center.x + radius, y: center.y),
                controlPoint1: CGPoint(x: center.x + radius * k, y: center.y + radius),
                controlPoint2: CGPoint(x: center.x + radius, y: center.y + radius * k)
            )
            path.curve(
                to: CGPoint(x: center.x, y: center.y - radius),
                controlPoint1: CGPoint(x: center.x + radius, y: center.y - radius * k),
                controlPoint2: CGPoint(x: center.x + radius * k, y: center.y - radius)
            )
            path.curve(
                to: CGPoint(x: center.x - radius, y: center.y),
                controlPoint1: CGPoint(x: center.x - radius * k, y: center.y - radius),
                controlPoint2: CGPoint(x: center.x - radius, y: center.y - radius * k)
            )
            path.curve(
                to: CGPoint(x: center.x, y: center.y + radius),
                controlPoint1: CGPoint(x: center.x - radius, y: center.y + radius * k),
                controlPoint2: CGPoint(x: center.x - radius * k, y: center.y + radius)
            )
            path.close()
        default:
            path.move(to: CGPoint(x: 100, y: 80))
            path.line(to: CGPoint(x: 400, y: 80))
            path.line(to: CGPoint(x: 400, y: 200))
            path.line(to: CGPoint(x: 100, y: 200))
            path.close()
            path.move(to: CGPoint(x: 150, y: 240))
            path.line(to: CGPoint(x: 350, y: 240))
            path.line(to: CGPoint(x: 250, y: 360))
            path.close()
        }
        return path
    }

    static func vertices(_ mask: [PathElement]?) -> [CGPoint] {
        guard let mask else { return [] }
        return mask.flatMap { element -> [CGPoint] in
            switch element {
            case let .move(x, y), let .line(x, y):
                [CGPoint(x: x, y: y)]
            case let .quad(cx, cy, x, y):
                [CGPoint(x: cx, y: cy), CGPoint(x: x, y: y)]
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                [
                    CGPoint(x: c1x, y: c1y),
                    CGPoint(x: c2x, y: c2y),
                    CGPoint(x: x, y: y),
                ]
            case .close:
                []
            }
        }
    }
}
