import CoreGraphics
import Foundation
import PencilKit

/// Which ink the whole-stroke eraser may remove.
///
/// This is an allow-list: a stroke of a kind the filter leaves out is put back
/// where it was after an eraser pass, and one undo still restores whatever the
/// pass did remove. `all` is the old behaviour; `.highlighter` alone is the old
/// "Erase Highlighter Only".
public struct EraserFilter: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Pen, pencil and every other opaque ink.
    public static let pen = EraserFilter(rawValue: 1 << 0)
    public static let highlighter = EraserFilter(rawValue: 1 << 1)
    /// A stroke snapped by Hold to Shape (line, arrow, triangle, rectangle,
    /// rhombus, pentagon, hexagon or ellipse).
    public static let shape = EraserFilter(rawValue: 1 << 2)
    public static let all: EraserFilter = [.pen, .highlighter, .shape]
    public static let none: EraserFilter = []

    public func allows(_ kind: StrokeKind) -> Bool {
        contains(kind.filter)
    }
}

/// What a stroke is, for the eraser filter.
public enum StrokeKind: String, CaseIterable, Sendable {
    case pen
    case highlighter
    case shape

    var filter: EraserFilter {
        switch self {
        case .pen: .pen
        case .highlighter: .highlighter
        case .shape: .shape
        }
    }
}

/// Sorts a stroke into the eraser filter's kinds.
public enum StrokeClassifier {
    /// A highlighter is a translucent marker, the same rule the stroke codec
    /// uses when it stores `StrokeTool.isHighlighter`.
    public static func isHighlighter(_ stroke: PKStroke) -> Bool {
        stroke.ink.inkType == .marker && stroke.ink.color.cgColor.alpha < 0.99
    }

    public static func kind(of stroke: PKStroke) -> StrokeKind {
        if isHighlighter(stroke) { return .highlighter }
        if isSnappedShape(stroke) { return .shape }
        return .pen
    }

    /// Whether the stroke already lies on the clean shape Hold to Shape would
    /// have replaced it with. Handwriting and freehand lines miss by more than
    /// the tolerance; a snapped line, arrow, polygon or ellipse lies on it
    /// almost exactly.
    public static func isSnappedShape(_ stroke: PKStroke) -> Bool {
        guard !isHighlighter(stroke) else { return false }
        let path = stroke.path
        guard path.count >= 3 else { return false }
        let transform = stroke.transform
        let drawn = (0..<path.count).map { path[$0].location.applying(transform) }
        guard let shape = ShapeRecognizer().recognize(drawn) else { return false }
        let ideal = ShapeRecognizer.points(for: shape, spacing: 2)
        guard ideal.count >= 2 else { return false }

        let tolerance: CGFloat = 0.4
        for point in ideal {
            var nearest = CGFloat.infinity
            for index in 1..<drawn.count {
                nearest = min(nearest, ShapeRecognizer.distance(point, toSegment: drawn[index - 1], drawn[index]))
            }
            if nearest > tolerance { return false }
        }
        return true
    }
}
