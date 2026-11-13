import CoreGraphics
import Foundation
import PencilKit

/// Recognises a pen scribble drawn over ink, the gesture that deletes what it
/// covers.
///
/// Pure geometry, so it is testable anywhere: a scribble is a stroke that
/// travels much farther than its own bounding box and changes direction
/// several times, unlike writing, an underline or a shape.
public enum ScratchOut {
    /// The area a scratch-out covers, or nil when `points` are not a scribble.
    public static func scribbledArea(_ points: [CGPoint]) -> CGRect? {
        let cleaned = ShapeRecognizer.deduplicated(points)
        guard cleaned.count >= 8 else { return nil }
        let box = ShapeRecognizer.bounds(of: cleaned)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= 16 else { return nil }
        let length = ShapeRecognizer.pathLength(cleaned)
        guard length >= 3 * diagonal else { return nil }
        guard directionReversals(cleaned) >= 4 else { return nil }
        return box
    }

    /// How many times the stroke changes horizontal or vertical direction on
    /// its way, counting only runs longer than a wobble.
    static func directionReversals(_ points: [CGPoint]) -> Int {
        let simplified = ShapeRecognizer.simplify(points, epsilon: 1.5)
        guard simplified.count > 2 else { return 0 }
        var reversals = 0
        var lastX = 0, lastY = 0
        for index in 1..<simplified.count {
            let dx = simplified[index].x - simplified[index - 1].x
            let dy = simplified[index].y - simplified[index - 1].y
            if abs(dx) >= 2 {
                let sign = dx > 0 ? 1 : -1
                if lastX != 0, sign != lastX { reversals += 1 }
                lastX = sign
            }
            if abs(dy) >= 2 {
                let sign = dy > 0 ? 1 : -1
                if lastY != 0, sign != lastY { reversals += 1 }
                lastY = sign
            }
        }
        return reversals
    }
}

#if os(iOS)
import UIKit

extension PencilCanvasView.Coordinator {
    /// Deletes the ink a pen scribble covers, together with the scribble, and
    /// registers one undo step that puts the covered ink back.
    ///
    /// Returns true when it took the change: the caller then reports the new
    /// drawing instead of the scribble. Off unless `scratchOutToErase` is on,
    /// and never in the eraser, lasso or links modes.
    func applyScratchOut(in canvas: PKCanvasView) -> Bool {
        guard parent.scratchOutToErase, case .ink = parent.mode,
              !parent.tool.isHighlighter, !parent.isRulerActive
        else { return false }

        let current = canvas.drawing.strokes
        let known = Set(baselineStrokes.map(\.id))
        let added = current.filter { !known.contains($0.id) }
        guard added.count == 1, let scribble = added.first else { return false }

        let scribblePoints = drawnPoints(of: scribble)
        guard let area = ScratchOut.scribbledArea(scribblePoints) else { return false }
        let coveredArea = area.insetBy(dx: -4, dy: -4)
        let covered = baselineStrokes.filter { stroke in
            drawnPoints(of: stroke).contains { coveredArea.contains($0) }
        }
        guard !covered.isEmpty else { return false }

        let coveredIDs = Set(covered.map(\.id))
        let remaining = current.filter { $0.id != scribble.id && !coveredIDs.contains($0.id) }
        // Undo restores the page as it was before the scribble: the covered
        // ink is back and the scribble itself is not.
        setDrawing(
            PKDrawing(strokes: baselineStrokes),
            undoTo: PKDrawing(strokes: remaining),
            in: canvas
        )
        return true
    }

    /// A stroke's control points in the page's coordinates.
    private func drawnPoints(of stroke: PKStroke) -> [CGPoint] {
        let transform = stroke.transform
        return (0..<stroke.path.count).map { stroke.path[$0].location.applying(transform) }
    }

    /// Writes `drawing` without an undo step of its own, then registers the
    /// reverse as one undo. Inside PencilKit's per-event group this joins it,
    /// so the whole gesture undoes at once; on its own it is still one step.
    private func setDrawing(_ drawing: PKDrawing, undoTo previous: PKDrawing, in canvas: PKCanvasView) {
        canvas.undoManager?.disableUndoRegistration()
        isApplyingInput = true
        canvas.drawing = drawing
        isApplyingInput = false
        canvas.undoManager?.enableUndoRegistration()
        canvas.undoManager?.registerUndo(withTarget: self) { [weak canvas] coordinator in
            MainActor.assumeIsolated {
                guard let canvas else { return }
                coordinator.setDrawing(previous, undoTo: drawing, in: canvas)
            }
        }
    }
}
#endif
