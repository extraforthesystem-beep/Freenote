import CoreGraphics
import Foundation
import NoteCore
import PencilKit

#if os(iOS)
import UIKit
private typealias PlatformBezierPath = UIBezierPath
#else
import AppKit
private typealias PlatformBezierPath = NSBezierPath
#endif

public enum StrokeCodecError: Error, Equatable, Sendable {
    case unsupportedInkType(String)
    case invalidTransform
    case emptyPoints
}

/// Converts between PencilKit strokes and `StrokeRecord`.
///
/// The record can hold everything PencilKit exposes except `renderState`'s
/// opaque part, of which only `grainOffset` is public. The conversion is *not*
/// bit-exact: S1 measured that PencilKit re-stores point azimuth, altitude,
/// size.height and mask vertices in a compressed form, so those drift by a few
/// storage steps on the way back in.
public enum StrokeCodec {
    /// `StrokeTool.engine` for strokes that came from PencilKit.
    public static let engine = "pencilkit"

    // MARK: Record from stroke

    public static func record(from stroke: PKStroke, layerID: UUID) -> StrokeRecord {
        let path = stroke.path
        var points: [StrokePoint] = []
        points.reserveCapacity(path.count)
        for index in 0..<path.count {
            let point = path[index]
            points.append(
                StrokePoint(
                    x: Double(point.location.x),
                    y: Double(point.location.y),
                    timeOffset: point.timeOffset,
                    width: Double(point.size.width),
                    height: Double(point.size.height),
                    opacity: Double(point.opacity),
                    force: Double(point.force),
                    azimuth: Double(point.azimuth),
                    altitude: Double(point.altitude),
                    secondaryScale: Double(point.secondaryScale),
                    threshold: Double(point.threshold),
                    lateralJitter: Double(point.lateralJitter)
                )
            )
        }

        let grainOffset: StrokeRecord.GrainOffset? = stroke.renderState?.grainOffset.map {
            StrokeRecord.GrainOffset(x: Double($0.x), y: Double($0.y))
        }

        // `PKInk` has no width; the ink's size lives in the control points, so
        // the widest point is the best available nominal width.
        let width = points.map(\.width).max() ?? Double(stroke.ink.inkType.defaultWidth)
        // PencilKit normalises ink colours to sRGB; store what it reports.
        // A pattern colour has no RGB components and falls back to black.
        let color = RGBAColor(srgb: stroke.ink.color) ?? .black

        return StrokeRecord(
            id: stroke.id,
            layerID: layerID,
            tool: StrokeTool(
                engine: engine,
                inkType: stroke.ink.inkType.rawValue,
                color: color,
                width: width,
                // A highlighter is a marker with a translucent colour. PencilKit
                // has no other way to express one.
                isHighlighter: stroke.ink.inkType == .marker && color.a < 0.99
            ),
            createdAt: path.creationDate,
            transform: [
                Double(stroke.transform.a),
                Double(stroke.transform.b),
                Double(stroke.transform.c),
                Double(stroke.transform.d),
                Double(stroke.transform.tx),
                Double(stroke.transform.ty),
            ],
            randomSeed: stroke.randomSeed,
            mask: maskElements(stroke.mask),
            renderGroupID: stroke.renderGroupID,
            pathID: path.id,
            grainOffset: grainOffset,
            points: points
        )
    }

    // MARK: Stroke from record

    public static func stroke(from record: StrokeRecord) throws -> PKStroke {
        guard let inkType = PKInkingTool.InkType(rawValue: record.tool.inkType) else {
            throw StrokeCodecError.unsupportedInkType(record.tool.inkType)
        }
        guard record.transform.count == StrokeRecord.transformElementCount else {
            throw StrokeCodecError.invalidTransform
        }
        guard !record.points.isEmpty else {
            throw StrokeCodecError.emptyPoints
        }

        let points = record.points.map { point in
            PKStrokePoint(
                location: CGPoint(x: point.x, y: point.y),
                timeOffset: point.timeOffset,
                size: CGSize(width: point.width, height: point.height),
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold,
                lateralJitter: point.lateralJitter
            )
        }

        let path = PKStrokePath(
            controlPoints: points,
            creationDate: record.createdAt,
            id: record.pathID ?? UUID()
        )

        let t = record.transform
        let transform = CGAffineTransform(a: t[0], b: t[1], c: t[2], d: t[3], tx: t[4], ty: t[5])
        let renderState = record.grainOffset.map {
            PKStroke.RenderState(grainOffset: CGPoint(x: $0.x, y: $0.y))
        }

        return PKStroke(
            ink: PKInk(inkType, color: record.tool.color.inkColor),
            path: path,
            transform: transform,
            mask: platformMask(record.mask),
            randomSeed: record.randomSeed,
            id: record.id,
            renderGroupID: record.renderGroupID,
            renderState: renderState
        )
    }

    /// Rebuilds a whole page. A record PencilKit cannot express is skipped
    /// instead of losing the page.
    ///
    /// Strokes are painted in `StrokeOrder` render order: layers grouped by
    /// first appearance (pass `Page.renderStrokes` to follow `Page.layers`),
    /// and within a layer highlighters before pen ink, the way a paper
    /// highlighter behaves.
    public static func drawing(from records: [StrokeRecord]) -> PKDrawing {
        PKDrawing(strokes: StrokeOrder.renderOrder(records).compactMap { try? stroke(from: $0) })
    }

    // MARK: Mask

    private static func maskElements(_ mask: PlatformBezierPath?) -> [PathElement]? {
        guard let mask else { return nil }
        let elements = pathElements(from: mask.cgPath)
        return isSupportedMask(elements) ? elements : nil
    }

    private static func pathElements(from path: CGPath) -> [PathElement] {
        var elements: [PathElement] = []
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                elements.append(.move(x: Double(element.points[0].x), y: Double(element.points[0].y)))
            case .addLineToPoint:
                elements.append(.line(x: Double(element.points[0].x), y: Double(element.points[0].y)))
            case .addQuadCurveToPoint:
                elements.append(
                    .quad(
                        cx: Double(element.points[0].x),
                        cy: Double(element.points[0].y),
                        x: Double(element.points[1].x),
                        y: Double(element.points[1].y)
                    )
                )
            case .addCurveToPoint:
                elements.append(
                    .cubic(
                        c1x: Double(element.points[0].x),
                        c1y: Double(element.points[0].y),
                        c2x: Double(element.points[1].x),
                        c2y: Double(element.points[1].y),
                        x: Double(element.points[2].x),
                        y: Double(element.points[2].y)
                    )
                )
            case .closeSubpath:
                elements.append(.close)
            @unknown default:
                break
            }
        }
        return elements
    }

    /// S1 found that on this SDK an *empty* mask path and a mask made only of
    /// quadratic curves trap inside PencilKit when read back. Both are dropped
    /// rather than handed to `PKStroke`, so a bad mask costs the mask, not the app.
    private static func isSupportedMask(_ elements: [PathElement]) -> Bool {
        for element in elements {
            switch element {
            case .line, .cubic: return true
            default: continue
            }
        }
        return false
    }

    private static func platformMask(_ elements: [PathElement]?) -> PlatformBezierPath? {
        guard let elements, isSupportedMask(elements) else { return nil }
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case let .move(x, y):
                path.move(to: CGPoint(x: x, y: y))
            case let .line(x, y):
                path.addLine(to: CGPoint(x: x, y: y))
            case let .quad(cx, cy, x, y):
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case let .cubic(c1x, c1y, c2x, c2y, x, y):
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: c1x, y: c1y),
                    control2: CGPoint(x: c2x, y: c2y)
                )
            case .close:
                path.closeSubpath()
            }
        }
        guard !path.isEmpty else { return nil }
        return PlatformBezierPath(cgPath: path)
    }
}
