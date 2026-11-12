import AppKit
import CoreGraphics
import Foundation
import PencilKit

public enum SpikeConversionError: Error, CustomStringConvertible {
    case unknownInkType(String)
    case unrepresentableColor(String)
    case unknownColorSpace(String)
    case malformedRenderState(String)
    case malformedMask(String)

    public var description: String {
        switch self {
        case .unknownInkType(let v): return "unknown ink type '\(v)'"
        case .unrepresentableColor(let v): return "cannot rebuild colour: \(v)"
        case .unknownColorSpace(let v): return "cannot rebuild colour space '\(v)'"
        case .malformedRenderState(let v): return "cannot rebuild render state: \(v)"
        case .malformedMask(let v): return "cannot rebuild mask: \(v)"
        }
    }
}

// MARK: - NSColor space table

private enum ColorSpaces {
    static let candidates: [NSColorSpace] = [
        .sRGB,
        .extendedSRGB,
        .displayP3,
        .genericRGB,
        .deviceRGB,
        .adobeRGB1998,
        .genericGamma22Gray,
        .extendedGenericGamma22Gray,
        .deviceGray,
        .genericCMYK,
        .deviceCMYK
    ]

    static let byName: [String: NSColorSpace] = {
        var map: [String: NSColorSpace] = [:]
        for space in candidates {
            if let cg = space.cgColorSpace, let name = cg.name as String? {
                map[name] = space
            }
        }
        return map
    }()

    static func name(of space: NSColorSpace) -> String? {
        guard let cg = space.cgColorSpace, let name = cg.name as String? else { return nil }
        return name
    }
}

private func colorTypeName(_ type: NSColor.ColorType) -> String {
    switch type {
    case .componentBased: return "componentBased"
    case .catalog: return "catalog"
    case .pattern: return "pattern"
    @unknown default: return "unknown(\(type.rawValue))"
    }
}

private func resolvedSRGB(_ color: NSColor) -> [Double]? {
    guard let c = color.usingColorSpace(.sRGB) else { return nil }
    return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
}

/// Read an `NSColor` into Foundation values only.
public func spikeColor(_ color: NSColor) -> SpikeColor {
    switch color.type {
    case .componentBased:
        let space = color.colorSpace
        let componentCount = space.numberOfColorComponents + 1
        var components = [CGFloat](repeating: 0, count: componentCount)
        components.withUnsafeMutableBufferPointer { buffer in
            color.getComponents(buffer.baseAddress!)
        }
        let name = ColorSpaces.name(of: space) ?? "custom"
        let icc = ColorSpaces.name(of: space) == nil ? space.cgColorSpace?.copyICCData() as Data? : nil
        return SpikeColor(spaceName: name,
                          components: components.map(Double.init),
                          iccProfile: icc,
                          sourceType: "componentBased",
                          resolvedSRGB: resolvedSRGB(color))
    case .catalog:
        return SpikeColor(spaceName: "catalog",
                          components: [],
                          sourceType: "catalog",
                          catalogName: color.catalogNameComponent,
                          colorName: color.colorNameComponent,
                          resolvedSRGB: resolvedSRGB(color))
    case .pattern:
        return SpikeColor(spaceName: "pattern",
                          components: [],
                          sourceType: "pattern",
                          resolvedSRGB: resolvedSRGB(color))
    @unknown default:
        return SpikeColor(spaceName: "unknown",
                          components: [],
                          sourceType: colorTypeName(color.type),
                          resolvedSRGB: resolvedSRGB(color))
    }
}

/// Rebuild an `NSColor` from the record.
public func nsColor(_ record: SpikeColor) throws -> NSColor {
    switch record.sourceType {
    case "componentBased":
        let space: NSColorSpace
        if record.spaceName == "custom" {
            guard let icc = record.iccProfile, let cg = CGColorSpace(iccData: icc as CFData) else {
                throw SpikeConversionError.unrepresentableColor("custom colour space without ICC data")
            }
            guard let ns = NSColorSpace(cgColorSpace: cg) else {
                throw SpikeConversionError.unrepresentableColor("CGColorSpace not supported by NSColorSpace")
            }
            space = ns
        } else {
            guard let known = ColorSpaces.byName[record.spaceName] else {
                throw SpikeConversionError.unknownColorSpace(record.spaceName)
            }
            space = known
        }
        let values = record.components.map { CGFloat($0) }
        guard values.count == space.numberOfColorComponents + 1 else {
            throw SpikeConversionError.unrepresentableColor(
                "component count \(values.count) does not match space \(record.spaceName) (\(space.numberOfColorComponents)+alpha)")
        }
        return values.withUnsafeBufferPointer { buffer in
            NSColor(colorSpace: space, components: buffer.baseAddress!, count: buffer.count)
        }
    case "catalog":
        if let catalog = record.catalogName, let name = record.colorName,
           let color = NSColor(catalogName: catalog, colorName: name) {
            return color
        }
        guard let srgb = record.resolvedSRGB, srgb.count == 4 else {
            throw SpikeConversionError.unrepresentableColor("catalog colour \(record.catalogName ?? "?")/\(record.colorName ?? "?") is not available and has no fallback")
        }
        return NSColor(srgbRed: srgb[0], green: srgb[1], blue: srgb[2], alpha: srgb[3])
    case "pattern":
        throw SpikeConversionError.unrepresentableColor("pattern colours are not representable as components")
    default:
        throw SpikeConversionError.unrepresentableColor("unknown colour type '\(record.sourceType)'")
    }
}

// MARK: - PKStrokePoint

public func spikePoint(_ point: PKStrokePoint) -> SpikePoint {
    SpikePoint(location: SpikePoint2D(x: Double(point.location.x), y: Double(point.location.y)),
               timeOffset: point.timeOffset,
               size: SpikeSize(width: Double(point.size.width), height: Double(point.size.height)),
               opacity: Double(point.opacity),
               force: Double(point.force),
               azimuth: Double(point.azimuth),
               altitude: Double(point.altitude),
               secondaryScale: Double(point.secondaryScale),
               threshold: Double(point.threshold),
               lateralJitter: Double(point.lateralJitter))
}

public func pkStrokePoint(_ record: SpikePoint) -> PKStrokePoint {
    PKStrokePoint(location: CGPoint(x: record.location.x, y: record.location.y),
                  timeOffset: record.timeOffset,
                  size: CGSize(width: record.size.width, height: record.size.height),
                  opacity: record.opacity,
                  force: record.force,
                  azimuth: record.azimuth,
                  altitude: record.altitude,
                  secondaryScale: record.secondaryScale,
                  threshold: record.threshold,
                  lateralJitter: record.lateralJitter)
}

// MARK: - Mask

public func spikeMask(_ mask: NSBezierPath) -> SpikeMask {
    var elements: [SpikePathElement] = []
    elements.reserveCapacity(mask.elementCount)
    var buffer = [NSPoint](repeating: .zero, count: 3)
    for index in 0..<mask.elementCount {
        let element = buffer.withUnsafeMutableBufferPointer { pointer -> NSBezierPath.ElementType in
            mask.element(at: index, associatedPoints: pointer.baseAddress)
        }
        let toRecord: (String, Int)
        switch element {
        case .moveTo: toRecord = ("move", 1)
        case .lineTo: toRecord = ("line", 1)
        case .cubicCurveTo: toRecord = ("cubic", 3)
        case .quadraticCurveTo: toRecord = ("quadratic", 2)
        case .closePath: toRecord = ("close", 0)
        @unknown default: toRecord = ("unknown(\(element.rawValue))", 0)
        }
        let points = (0..<toRecord.1).map { SpikePoint2D(x: Double(buffer[$0].x), y: Double(buffer[$0].y)) }
        elements.append(SpikePathElement(kind: toRecord.0, points: points))
    }
    return SpikeMask(elements: elements, windingRule: Int(mask.windingRule.rawValue))
}

public func nsBezierPath(_ record: SpikeMask) throws -> NSBezierPath {
    let path = NSBezierPath()
    path.windingRule = NSBezierPath.WindingRule(rawValue: UInt(record.windingRule)) ?? .nonZero
    for element in record.elements {
        let p = element.points
        switch element.kind {
        case "move":
            guard p.count == 1 else { throw SpikeConversionError.malformedMask("move needs 1 point") }
            path.move(to: CGPoint(x: p[0].x, y: p[0].y))
        case "line":
            guard p.count == 1 else { throw SpikeConversionError.malformedMask("line needs 1 point") }
            path.line(to: CGPoint(x: p[0].x, y: p[0].y))
        case "cubic":
            guard p.count == 3 else { throw SpikeConversionError.malformedMask("cubic needs 3 points") }
            path.curve(to: CGPoint(x: p[2].x, y: p[2].y),
                       controlPoint1: CGPoint(x: p[0].x, y: p[0].y),
                       controlPoint2: CGPoint(x: p[1].x, y: p[1].y))
        case "quadratic":
            guard p.count == 2 else { throw SpikeConversionError.malformedMask("quadratic needs 2 points") }
            path.curve(to: CGPoint(x: p[1].x, y: p[1].y),
                       controlPoint: CGPoint(x: p[0].x, y: p[0].y))
        case "close":
            path.close()
        default:
            throw SpikeConversionError.malformedMask("unknown element '\(element.kind)'")
        }
    }
    return path
}

// MARK: - PKStroke

/// Read a `PKStroke` into the plain record. Never throws: anything PencilKit
/// cannot express is either carried (ICC bytes, catalog names) or converted
/// (exotic colours) and reported by the comparison helper.
public func toRecord(_ stroke: PKStroke) -> SpikeStroke {
    let path = stroke.path
    let points = (0..<path.count).map { spikePoint(path[$0]) }
    let renderState: SpikeRenderState? = stroke.renderState.map { state in
        let json = try? JSONEncoder().encode(state)
        let grain = state.grainOffset.map { SpikePoint2D(x: Double($0.x), y: Double($0.y)) }
        return SpikeRenderState(grainOffset: grain, codableJSON: json)
    }
    return SpikeStroke(
        strokeID: stroke.id,
        ink: SpikeInk(inkType: stroke.ink.inkType.rawValue,
                      color: spikeColor(stroke.ink.color),
                      requiredContentVersion: stroke.ink.requiredContentVersion.rawValue),
        transform: SpikeAffineTransform(a: stroke.transform.a,
                                        b: stroke.transform.b,
                                        c: stroke.transform.c,
                                        d: stroke.transform.d,
                                        tx: stroke.transform.tx,
                                        ty: stroke.transform.ty),
        path: SpikePath(id: path.id,
                        creationDate: path.creationDate.timeIntervalSinceReferenceDate,
                        controlPoints: points),
        mask: stroke.mask.map(spikeMask),
        randomSeed: stroke.randomSeed,
        renderGroupID: stroke.renderGroupID,
        renderState: renderState,
        requiredContentVersion: stroke.requiredContentVersion.rawValue
    )
}

/// Rebuild a `PKStroke` from the plain record.
public func toStroke(_ record: SpikeStroke) throws -> PKStroke {
    guard let inkType = PKInkingTool.InkType(rawValue: record.ink.inkType) else {
        throw SpikeConversionError.unknownInkType(record.ink.inkType)
    }
    let color = try nsColor(record.ink.color)
    let ink = PKInk(inkType, color: color)

    let points = record.path.controlPoints.map(pkStrokePoint)
    let path = PKStrokePath(controlPoints: points,
                            creationDate: Date(timeIntervalSinceReferenceDate: record.path.creationDate),
                            id: record.path.id)

    let mask = try record.mask.map(nsBezierPath)

    let transform = CGAffineTransform(a: record.transform.a,
                                      b: record.transform.b,
                                      c: record.transform.c,
                                      d: record.transform.d,
                                      tx: record.transform.tx,
                                      ty: record.transform.ty)

    let renderState: PKStroke.RenderState?
    if let recorded = record.renderState {
        if let json = recorded.codableJSON, let decoded = try? JSONDecoder().decode(PKStroke.RenderState.self, from: json) {
            renderState = decoded
        } else if let grain = recorded.grainOffset {
            renderState = PKStroke.RenderState(grainOffset: CGPoint(x: grain.x, y: grain.y))
        } else {
            throw SpikeConversionError.malformedRenderState("no decodable state")
        }
    } else {
        renderState = nil
    }

    return PKStroke(ink: ink,
                    path: path,
                    transform: transform,
                    mask: mask,
                    randomSeed: record.randomSeed,
                    id: record.strokeID,
                    renderGroupID: record.renderGroupID,
                    renderState: renderState)
}
