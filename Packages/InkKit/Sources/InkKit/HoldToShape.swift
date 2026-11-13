import CoreGraphics
import Foundation
import PencilKit

/// Builds the clean replacement for a hand-drawn stroke.
public enum ShapeStrokeBuilder {
    /// Point spacing of the replacement path, in drawing points.
    static let spacing: CGFloat = 2

    /// A stroke with the same id, ink and transform as `stroke` whose path is
    /// the recognised shape, or nil when the stroke is not a shape.
    ///
    /// The shape follows the original stroke's width, opacity, pressure and
    /// tilt at each point, so it keeps the pen's taper at the start and end.
    public static func shapeStroke(replacing stroke: PKStroke, recognizer: ShapeRecognizer = ShapeRecognizer()) -> PKStroke? {
        guard let shape = recognizedShape(of: stroke, recognizer: recognizer) else { return nil }
        let inverse = stroke.transform.inverted()
        let locations = ShapeRecognizer.points(for: shape, spacing: spacing).map { $0.applying(inverse) }
        return replacement(of: stroke, along: locations)
    }

    /// A stroke with the same id, ink and transform as `stroke` whose path is
    /// the straight line from where the stroke started to where it ended. Used
    /// by the highlighter's straight-line mode; nil for a stroke too short to
    /// be a line.
    public static func straightened(_ stroke: PKStroke) -> PKStroke? {
        let path = stroke.path
        guard path.count >= 2,
              let start = path.first?.location,
              let end = path.last?.location,
              ShapeRecognizer.distance(start, end) >= 12
        else { return nil }
        return replacement(of: stroke, along: ShapeRecognizer.resample(polyline: [start, end], spacing: spacing))
    }

    /// The shape `stroke` was drawn as, recognised where the user sees it.
    static func recognizedShape(of stroke: PKStroke, recognizer: ShapeRecognizer) -> RecognizedShape? {
        let path = stroke.path
        guard path.count >= 2 else { return nil }
        let drawn = (0..<path.count).map { path[$0].location.applying(stroke.transform) }
        return recognizer.recognize(drawn)
    }

    /// The replacement stroke for `locations` (in the stroke's own space).
    ///
    /// Every point samples the original stroke at the same fraction of its
    /// length, so the pen's width, force, opacity and angle carry over instead
    /// of one flat model point.
    private static func replacement(of stroke: PKStroke, along locations: [CGPoint]) -> PKStroke? {
        guard locations.count >= 2 else { return nil }
        let path = stroke.path
        guard path.count >= 2 else { return nil }
        let profile = TaperProfile(path: path)
        let step = 1.0 / 120
        var points = locations.enumerated().map { index, location in
            let fraction = Double(index) / Double(locations.count - 1)
            let model = profile.point(at: fraction)
            return PKStrokePoint(
                location: location,
                timeOffset: Double(index) * step,
                size: model.size,
                opacity: model.opacity,
                force: model.force,
                azimuth: model.azimuth,
                altitude: model.altitude,
                secondaryScale: model.secondaryScale,
                threshold: model.threshold,
                lateralJitter: model.lateralJitter
            )
        }
        // Change tracking compares point counts and creation dates, so make
        // sure the replacement can never look identical to the original.
        if points.count == path.count, let last = points.last {
            points.append(PKStrokePoint(
                location: last.location, timeOffset: last.timeOffset + step, size: last.size,
                opacity: last.opacity, force: last.force, azimuth: last.azimuth, altitude: last.altitude,
                secondaryScale: last.secondaryScale, threshold: last.threshold, lateralJitter: last.lateralJitter
            ))
        }

        let newPath = PKStrokePath(controlPoints: points, creationDate: path.creationDate, id: UUID())
        return PKStroke(
            ink: stroke.ink,
            path: newPath,
            transform: stroke.transform,
            mask: nil,
            randomSeed: stroke.randomSeed,
            id: stroke.id,
            renderGroupID: stroke.renderGroupID,
            renderState: stroke.renderState
        )
    }
}

/// The original stroke's point attributes at a fraction of its arc length, so
/// a snapped shape keeps the pen's taper where the user actually drew it.
private struct TaperProfile {
    private let points: [PKStrokePoint]
    /// Each point's position along the stroke as a fraction of its length.
    private let positions: [Double]

    init(path: PKStrokePath) {
        let points = (0..<path.count).map { path[$0] }
        self.points = points
        var walked: [Double] = [0]
        walked.reserveCapacity(points.count)
        for index in 1..<max(points.count, 1) {
            walked.append(
                walked[index - 1]
                    + ShapeRecognizer.distance(points[index].location, points[index - 1].location)
            )
        }
        let total = walked.last ?? 0
        positions = total > 0 ? walked.map { $0 / total } : walked
    }

    func point(at fraction: Double) -> PKStrokePoint {
        guard !points.isEmpty else {
            return PKStrokePoint(
                location: .zero, timeOffset: 0, size: .zero, opacity: 1, force: 0,
                azimuth: 0, altitude: 0, secondaryScale: 1, threshold: 0, lateralJitter: 0
            )
        }
        let clamped = min(max(fraction, 0), 1)
        guard let index = positions.firstIndex(where: { $0 >= clamped }) else {
            return points[points.count - 1]
        }
        return points[index]
    }
}

#if os(iOS)
import UIKit


/// Watches touches on the canvas for a pause: the touch staying within a few
/// points for half a second while still down.
///
/// It never recognises and never blocks another recognizer, so PencilKit's
/// drawing, the canvas's taps and scrolling behave exactly as without it.
final class StrokeHoldObserver: UIGestureRecognizer {
    /// How far the touch may drift and still count as holding still, in points.
    var radius: CGFloat = 4
    var holdDuration: Duration = .milliseconds(500)

    /// A new single touch started.
    var onTouchBegan: (() -> Void)?
    /// The touch has paused (true), or moved on after a pause (false).
    var onHoldChanged: ((Bool, CGPoint) -> Void)?

    private var anchor: CGPoint = .zero
    private var isHolding = false
    private var timer: Task<Void, Never>?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, (event.allTouches?.count ?? touches.count) == 1 else {
            stop()
            state = .failed
            return
        }
        anchor = touch.location(in: view)
        isHolding = false
        onTouchBegan?()
        restartTimer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: view)
        guard hypot(location.x - anchor.x, location.y - anchor.y) > radius else { return }
        anchor = location
        if isHolding {
            isHolding = false
            onHoldChanged?(false, location)
        }
        restartTimer()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        stop()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if isHolding { onHoldChanged?(false, anchor) }
        stop()
        state = .failed
    }

    override func reset() {
        super.reset()
        stop()
        isHolding = false
    }

    private func stop() {
        timer?.cancel()
        timer = nil
    }

    private func restartTimer() {
        timer?.cancel()
        let duration = holdDuration
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, !self.isHolding else { return }
            self.isHolding = true
            self.onHoldChanged?(true, self.anchor)
        }
    }
}

/// One held stroke waiting to be swapped for its shape.
struct PendingShapeReplacement {
    let freehand: PKStroke
    let shape: PKStroke
    var attempts = 0
}

extension PencilCanvasView.Coordinator {
    func installHoldObserver(on canvas: InkCanvasView) {
        let observer = StrokeHoldObserver(target: nil, action: nil)
        observer.onTouchBegan = { [weak self] in
            guard let self else { return }
            holdDetected = false
            // The strokes as last seen, not `canvas.drawing.strokes`: that
            // would bridge every stroke out of PencilKit at each touch-down.
            // Copying the array is O(1); it is only searched after a hold.
            strokesAtTouchBegan = baselineStrokes
        }
        observer.onHoldChanged = { [weak self, weak canvas] holding, location in
            guard let self else { return }
            holdDetected = holding && shapeSnappingApplies
            if holdDetected, let canvas {
                feedback(for: canvas).alignmentOccurred(at: location)
            }
        }
        canvas.addGestureRecognizer(observer)
        holdObserver = observer
    }

    private func feedback(for canvas: InkCanvasView) -> UICanvasFeedbackGenerator {
        if let canvasFeedback { return canvasFeedback }
        let generator = UICanvasFeedbackGenerator(view: canvas)
        canvasFeedback = generator
        return generator
    }

    /// Hold to straighten works for the pen and highlighter only, and not
    /// with the ruler, which already draws straight lines.
    var shapeSnappingApplies: Bool {
        guard parent.holdToDrawShapes, !parent.isRulerActive, case .ink = parent.mode else { return false }
        return true
    }

    /// Called from `canvasViewDrawingDidChange` before the change is reported.
    /// Returns true when the change is a held stroke that will be replaced:
    /// the caller then skips reporting, so the app only ever sees the shape.
    func captureHeldStroke(in canvas: PKCanvasView) -> Bool {
        guard holdDetected else { return false }
        holdDetected = false
        guard pendingShape == nil, shapeSnappingApplies,
              let canvas = canvas as? InkCanvasView,
              case let strokes = canvas.drawing.strokes,
              let stroke = strokes.last,
              strokes.count == strokesAtTouchBegan.count + 1,
              !strokesAtTouchBegan.contains(where: { $0.id == stroke.id }),
              let shape = ShapeStrokeBuilder.shapeStroke(replacing: stroke).map({ shape in
                  // A dashed pen draws a dashed shape, so the snapped outline
                  // keeps the pen's style.
                  parent.lineStyle == .solid
                      ? shape
                      : StrokeDash.masked(shape, style: parent.lineStyle) ?? shape
              })
        else { return false }
        pendingShape = PendingShapeReplacement(freehand: stroke, shape: shape)
        schedulePendingShape(on: canvas)
        return true
    }

    /// Swaps the stroke on a later turn of the run loop.
    ///
    /// PencilKit registers its "add stroke" undo in the undo manager's
    /// automatic per-event group. Registering the swap in that same group
    /// would make one undo remove the stroke entirely, so wait until the
    /// group has closed (`groupingLevel == 0`) and register the swap as its
    /// own undo step on top: the first undo restores the freehand stroke, the
    /// second removes it.
    private func schedulePendingShape(on canvas: InkCanvasView) {
        DispatchQueue.main.async { [weak self, weak canvas] in
            MainActor.assumeIsolated {
                guard let self, let canvas, var pending = self.pendingShape else { return }
                if let undo = canvas.undoManager, undo.groupingLevel > 0, pending.attempts < 20 {
                    pending.attempts += 1
                    self.pendingShape = pending
                    self.schedulePendingShape(on: canvas)
                    return
                }
                self.pendingShape = nil
                self.swapStroke(pending.freehand.id, to: pending.shape, undoTo: pending.freehand, in: canvas)
            }
        }
    }

    /// Replaces the stroke with `id` by `replacement`, reports the change, and
    /// registers the opposite swap for undo (or redo, while undoing).
    func swapStroke(_ id: UUID, to replacement: PKStroke, undoTo previous: PKStroke, in canvas: InkCanvasView) {
        var strokes = canvas.drawing.strokes
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes[index] = replacement
            isApplyingShape = true
            canvas.drawing = PKDrawing(strokes: strokes)
            isApplyingShape = false
            canvas.undoManager?.registerUndo(withTarget: self) { [weak canvas] coordinator in
                MainActor.assumeIsolated {
                    guard let canvas else { return }
                    coordinator.swapStroke(id, to: previous, undoTo: replacement, in: canvas)
                }
            }
        }
        // Report even when the stroke vanished meanwhile, so the freehand
        // stroke held back in `captureHeldStroke` still reaches the app.
        reportDrawingChange(canvas)
    }
}
#endif
