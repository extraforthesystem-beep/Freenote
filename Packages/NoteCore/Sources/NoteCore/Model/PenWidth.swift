import Foundation

/// Pen widths are stored in points, as PencilKit uses them, but shown to the
/// user in millimetres. This is the conversion and rounding the editor's
/// sliders and labels share.
public enum PenWidth {
    /// 1 inch is 72 points and 25.4 millimetres.
    public static let pointsPerMillimetre = 72.0 / 25.4

    /// The width slider moves in tenths of a millimetre.
    public static let millimetreStep = 0.1

    public static func millimetres(fromPoints points: Double) -> Double {
        points / pointsPerMillimetre
    }

    public static func points(fromMillimetres millimetres: Double) -> Double {
        millimetres * pointsPerMillimetre
    }

    /// Rounds to the nearest tenth of a millimetre.
    public static func snappedMillimetres(_ millimetres: Double) -> Double {
        (millimetres / millimetreStep).rounded() * millimetreStep
    }

    /// A slider position in millimetres as a stored width in points.
    public static func snappedPoints(fromMillimetres millimetres: Double) -> Double {
        points(fromMillimetres: snappedMillimetres(millimetres))
    }

    public static func clamp(_ points: Double, to range: ClosedRange<Double>) -> Double {
        min(max(points, range.lowerBound), range.upperBound)
    }

    /// The user-facing width, e.g. "0.5 mm".
    public static func label(_ points: Double) -> String {
        String(format: "%.1f mm", millimetres(fromPoints: points))
    }

    /// A points range as whole tenths of a millimetre, so every slider value
    /// is a step the label can show exactly. Never wider than the input.
    public static func millimetreRange(for points: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = (millimetres(fromPoints: points.lowerBound) / millimetreStep).rounded(.up)
            * millimetreStep
        let upper = (millimetres(fromPoints: points.upperBound) / millimetreStep).rounded(.down)
            * millimetreStep
        return lower...upper
    }
}

/// The default width slots of each ink tool.
public enum WidthPresetDefaults {
    /// Pen: 0.5, 0.7 and 0.9 mm, fine real-pen sizes.
    public static let pen: [Double] = [0.5, 0.7, 0.9].map(PenWidth.points(fromMillimetres:))

    /// Highlighter: the widths the toolbar has always used, in points.
    public static let highlighter: [Double] = [12, 24, 40]
}

/// The three width slots of one ink tool, stored in points. The eraser keeps
/// its own fixed sizes and has no presets of its own.
public struct WidthPresets: Codable, Hashable, Sendable {
    public static let count = 3

    public private(set) var widths: [Double]

    /// Normalises to three slots: extra widths are dropped and missing ones
    /// repeat, so an empty list becomes three one-point widths.
    public init(_ widths: [Double] = []) {
        let values = widths.isEmpty ? [1] : widths
        self.widths = (0..<Self.count).map { values[$0 % values.count] }
    }

    /// Replaces one slot, clamped into `range`. Returns `false` for an
    /// out-of-range slot.
    @discardableResult
    public mutating func setWidth(
        _ width: Double,
        at index: Int,
        range: ClosedRange<Double>
    ) -> Bool {
        guard widths.indices.contains(index) else { return false }
        widths[index] = PenWidth.clamp(width, to: range)
        return true
    }

    /// The three widths clamped into the current ink's range. PencilKit
    /// rejects anything outside it, so this is what the toolbar applies.
    public func clamped(to range: ClosedRange<Double>) -> [Double] {
        widths.map { PenWidth.clamp($0, to: range) }
    }

    /// A rank per slot: equal widths share a rank, so their dots draw the
    /// same size.
    public static func ranks(for widths: [Double]) -> [Int] {
        let sorted = Set(widths).sorted()
        return widths.map { sorted.firstIndex(of: $0) ?? 0 }
    }

    private enum CodingKeys: String, CodingKey {
        case widths
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([Double].self, forKey: .widths)
        guard decoded.count == Self.count,
              decoded.allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .widths,
                in: container,
                debugDescription: "Expected three positive widths"
            )
        }
        widths = decoded
    }
}
