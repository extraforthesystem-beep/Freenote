import AppKit
import Foundation
import PencilKit

// MARK: - Flat field extraction

public struct FlatStroke {
    public var numbers: [(label: String, value: Double)] = []
    public var strings: [(label: String, value: String)] = []
}

private func append(_ flat: inout FlatStroke, _ label: String, _ value: Double) {
    flat.numbers.append((label, value))
}

private func append(_ flat: inout FlatStroke, _ label: String, _ value: String) {
    flat.strings.append((label, value))
}

/// Flattens every publicly readable property of a stroke into labelled scalars.
/// Labels beginning with `derived.` are PencilKit-computed values, not stored state.
public func flatten(_ stroke: PKStroke) -> FlatStroke {
    var flat = FlatStroke()

    append(&flat, "stroke.id", stroke.id.uuidString)
    append(&flat, "stroke.ink.type", stroke.ink.inkType.rawValue)
    append(&flat, "stroke.ink.requiredContentVersion", Double(stroke.ink.requiredContentVersion.rawValue))
    append(&flat, "stroke.requiredContentVersion", Double(stroke.requiredContentVersion.rawValue))

    let color = stroke.ink.color
    append(&flat, "ink.color.type", color.typeName)
    let record = spikeColor(color)
    append(&flat, "ink.color.spaceName", record.spaceName)
    append(&flat, "ink.color.iccProfile", record.iccProfile.map { "\($0.count) bytes" } ?? "nil")
    append(&flat, "ink.color.catalogName", record.catalogName ?? "nil")
    append(&flat, "ink.color.colorName", record.colorName ?? "nil")
    for (index, component) in record.components.enumerated() {
        append(&flat, "ink.color.component[\(index)]", component)
    }
    if let srgb = record.resolvedSRGB {
        for (index, component) in srgb.enumerated() {
            append(&flat, "ink.color.resolvedSRGB[\(index)]", component)
        }
    }

    let t = stroke.transform
    append(&flat, "transform.a", Double(t.a))
    append(&flat, "transform.b", Double(t.b))
    append(&flat, "transform.c", Double(t.c))
    append(&flat, "transform.d", Double(t.d))
    append(&flat, "transform.tx", Double(t.tx))
    append(&flat, "transform.ty", Double(t.ty))

    let path = stroke.path
    append(&flat, "path.id", path.id.uuidString)
    append(&flat, "path.creationDate", path.creationDate.timeIntervalSinceReferenceDate)
    append(&flat, "path.count", Double(path.count))
    for index in 0..<path.count {
        let p = path[index]
        let prefix = "point[\(index)]"
        append(&flat, "\(prefix).location.x", Double(p.location.x))
        append(&flat, "\(prefix).location.y", Double(p.location.y))
        append(&flat, "\(prefix).timeOffset", p.timeOffset)
        append(&flat, "\(prefix).size.width", Double(p.size.width))
        append(&flat, "\(prefix).size.height", Double(p.size.height))
        append(&flat, "\(prefix).opacity", Double(p.opacity))
        append(&flat, "\(prefix).force", Double(p.force))
        append(&flat, "\(prefix).azimuth", Double(p.azimuth))
        append(&flat, "\(prefix).altitude", Double(p.altitude))
        append(&flat, "\(prefix).secondaryScale", Double(p.secondaryScale))
        append(&flat, "\(prefix).threshold", Double(p.threshold))
        append(&flat, "\(prefix).lateralJitter", Double(p.lateralJitter))
    }

    append(&flat, "randomSeed", Double(stroke.randomSeed))
    append(&flat, "renderGroupID", stroke.renderGroupID?.uuidString ?? "nil")
    if let state = stroke.renderState {
        append(&flat, "renderState.present", 1)
        append(&flat, "renderState.grainOffset.x", Double(state.grainOffset?.x ?? -1))
        append(&flat, "renderState.grainOffset.y", Double(state.grainOffset?.y ?? -1))
        let encoded = (try? JSONEncoder().encode(state))?.base64EncodedString() ?? "encode-failed"
        append(&flat, "renderState.codableJSON", encoded)
    } else {
        append(&flat, "renderState.present", 0)
        append(&flat, "renderState.grainOffset.x", 0)
        append(&flat, "renderState.grainOffset.y", 0)
        append(&flat, "renderState.codableJSON", "nil")
    }

    if let mask = stroke.mask {
        append(&flat, "mask.present", 1)
        append(&flat, "mask.elementCount", Double(mask.elementCount))
        append(&flat, "mask.windingRule", Double(mask.windingRule.rawValue))
        var buffer = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<mask.elementCount {
            let element = buffer.withUnsafeMutableBufferPointer { pointer in
                mask.element(at: index, associatedPoints: pointer.baseAddress)
            }
            let pointCount: Int
            switch element {
            case .moveTo, .lineTo: pointCount = 1
            case .cubicCurveTo: pointCount = 3
            case .quadraticCurveTo: pointCount = 2
            case .closePath: pointCount = 0
            @unknown default: pointCount = 0
            }
            append(&flat, "mask[\(index)].kind", "\(element.rawValue)")
            for p in 0..<pointCount {
                append(&flat, "mask[\(index)].point[\(p)].x", Double(buffer[p].x))
                append(&flat, "mask[\(index)].point[\(p)].y", Double(buffer[p].y))
            }
        }
    } else {
        append(&flat, "mask.present", 0)
    }

    // Derived values: evidence about how PencilKit interprets the state, not stored state.
    let bounds = stroke.renderBounds
    append(&flat, "derived.renderBounds.minX", Double(bounds.minX))
    append(&flat, "derived.renderBounds.minY", Double(bounds.minY))
    append(&flat, "derived.renderBounds.width", Double(bounds.width))
    append(&flat, "derived.renderBounds.height", Double(bounds.height))
    append(&flat, "derived.maskedPathRanges.count", Double(stroke.maskedPathRanges.count))
    for (index, range) in stroke.maskedPathRanges.enumerated() {
        append(&flat, "derived.maskedPathRanges[\(index)].lower", range.lowerBound)
        append(&flat, "derived.maskedPathRanges[\(index)].upper", range.upperBound)
    }

    return flat
}

private extension NSColor {
    var typeName: String {
        switch type {
        case .componentBased: return "componentBased"
        case .catalog: return "catalog"
        case .pattern: return "pattern"
        @unknown default: return "unknown(\(type.rawValue))"
        }
    }
}

// MARK: - Comparison

public struct FieldMismatch: Sendable, CustomStringConvertible {
    public let field: String
    public let original: String
    public let rebuilt: String
    public let delta: Double?
    public let derived: Bool

    public var description: String {
        let d = delta.map { String(format: " delta=%.9g", $0) } ?? ""
        return "\(field): \(original) -> \(rebuilt)\(d)"
    }
}

public struct ComparisonReport: Sendable {
    public var mismatches: [FieldMismatch] = []
    public var numericFields: Int = 0
    public var stringFields: Int = 0
    public var derivedFields: Int = 0
    public var maxDelta: Double = 0
    public var maxDeltaField: String = "-"
    public var beyondTolerance: [FieldMismatch] = []

    public var exact: Bool { mismatches.isEmpty }
    public var toleranceMet: Bool { beyondTolerance.isEmpty }

    public var summary: String {
        let worst = maxDelta == 0 ? "0" : String(format: "%.9g", maxDelta)
        return "fields=\(numericFields + stringFields) exactMismatches=\(mismatches.count) "
            + "maxDelta=\(worst)@\(maxDeltaField) beyond1e-6=\(beyondTolerance.count)"
    }

    public var mismatchDetail: String {
        guard !mismatches.isEmpty else { return "none" }
        return mismatches.prefix(12).map(\.description).joined(separator: "; ")
    }
}

/// Compares every readable field of two strokes. Exact first; the same pass also
/// records the largest numeric difference and which fields exceed `tolerance`.
public func compareStrokes(_ original: PKStroke, _ rebuilt: PKStroke, tolerance: Double = 1e-6) -> ComparisonReport {
    let a = flatten(original)
    let b = flatten(rebuilt)
    var report = ComparisonReport()

    func record(field: String, originalText: String, rebuiltText: String, delta: Double?, derived: Bool) {
        if derived { report.derivedFields += 1 }
        let equal: Bool
        if let delta {
            equal = (delta == 0)
            if abs(delta) > report.maxDelta {
                report.maxDelta = abs(delta)
                report.maxDeltaField = field
            }
        } else {
            equal = (originalText == rebuiltText)
        }
        guard !equal else { return }
        let mismatch = FieldMismatch(field: field, original: originalText, rebuilt: rebuiltText, delta: delta, derived: derived)
        report.mismatches.append(mismatch)
        if !derived {
            let beyond = delta.map { abs($0) > tolerance } ?? true
            if beyond { report.beyondTolerance.append(mismatch) }
        }
    }

    let aNumbers = Dictionary(uniqueKeysWithValues: a.numbers.map { ($0.label, $0.value) })
    let bNumbers = Dictionary(uniqueKeysWithValues: b.numbers.map { ($0.label, $0.value) })
    for (label, value) in a.numbers {
        report.numericFields += 1
        let derived = label.hasPrefix("derived.")
        guard let other = bNumbers[label] else {
            let mismatch = FieldMismatch(field: label, original: "\(value)", rebuilt: "<missing>", delta: nil, derived: derived)
            report.mismatches.append(mismatch)
            if !derived { report.beyondTolerance.append(mismatch) }
            continue
        }
        record(field: label,
               originalText: "\(value)",
               rebuiltText: "\(other)",
               delta: other - value,
               derived: derived)
    }
    let aStrings = Dictionary(uniqueKeysWithValues: a.strings.map { ($0.label, $0.value) })
    let bStrings = Dictionary(uniqueKeysWithValues: b.strings.map { ($0.label, $0.value) })
    for (label, value) in a.strings {
        report.stringFields += 1
        let derived = label.hasPrefix("derived.")
        let other = bStrings[label] ?? "<missing>"
        record(field: label, originalText: value, rebuiltText: other, delta: nil, derived: derived)
    }
    return report
}
