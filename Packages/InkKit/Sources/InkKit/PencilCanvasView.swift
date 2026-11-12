#if os(iOS)
import NoteCore
import PencilKit
import SwiftUI
import UIKit

/// Lets the app drive PencilKit's own undo stack from a toolbar or a menu.
///
/// The canvas owns the stack; this object only forwards to it. `canUndo`
/// and `canRedo` are read live, so re-read them when the canvas changes.
@MainActor
public final class PencilCanvasController: ObservableObject {
    public init() {}

    weak var canvas: InkCanvasView?

    public var canUndo: Bool { canvas?.undoManager?.canUndo ?? false }
    public var canRedo: Bool { canvas?.undoManager?.canRedo ?? false }

    public func undo() { canvas?.undoManager?.undo() }
    public func redo() { canvas?.undoManager?.redo() }
}

/// A `PKCanvasView` that can be hosted by SwiftUI without losing undo.
public final class InkCanvasView: PKCanvasView {
    var pageSize: CGSize = .zero
    /// When set, the canvas shows only this rectangle of the page (page
    /// points), scaled to fill its width, instead of fitting the whole page.
    var viewport: CGRect?

    /// PencilKit registers undo with the canvas's own undo manager, and a
    /// SwiftUI-hosted view has none on its responder chain, so supply one.
    private let canvasUndoManager = UndoManager()
    override public var undoManager: UndoManager? { canvasUndoManager }

    func fitPageIfNeeded() {
        guard pageSize.width > 0, pageSize.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return }
        if let viewport, viewport.width > 0 {
            showViewport(viewport)
            return
        }
        let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
        // The paper is a SwiftUI image behind the canvas, so it cannot zoom with
        // the ink yet. Lock the zoom until the paper moves into the scroll view.
        guard minimumZoomScale != fit || maximumZoomScale != fit else { return }
        minimumZoomScale = fit
        maximumZoomScale = fit
        zoomScale = fit
        contentOffset = .zero
    }

    /// Zoom View: the page zoomed so `viewport` fills the width, scrolled to
    /// its top-left corner. Scrolling is off, so only code moves it.
    private func showViewport(_ viewport: CGRect) {
        let scale = bounds.width / viewport.width
        if minimumZoomScale != scale || maximumZoomScale != scale || zoomScale != scale {
            minimumZoomScale = min(minimumZoomScale, scale)
            maximumZoomScale = max(maximumZoomScale, scale)
            zoomScale = scale
            minimumZoomScale = scale
            maximumZoomScale = scale
        }
        let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        if contentSize != size { contentSize = size }
        let offset = CGPoint(x: viewport.minX * scale, y: viewport.minY * scale)
        if contentOffset != offset { contentOffset = offset }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        fitPageIfNeeded()
    }
}

/// What the Pencil does on the canvas.
public enum EraserKind: String, Codable, Hashable, Sendable {
    /// Removes whole strokes (PencilKit's vector eraser).
    case stroke
    /// Removes pixels, splitting a stroke with a mask (PencilKit's bitmap eraser).
    case pixel
}

public enum CanvasMode: Hashable, Sendable {
    case ink
    case eraser(EraserKind, width: Double)
    case lasso
    /// Taps (finger or Pencil) go to link handling; drawing is off.
    case links
    /// Something above the canvas owns the pointer (the laser pointer):
    /// the canvas takes no drawing input at all.
    case disabled

    /// Whether the Pencil draws in this mode.
    var allowsDrawing: Bool {
        switch self {
        case .ink, .eraser, .lasso: true
        case .links, .disabled: false
        }
    }

    var pkTool: PKTool {
        switch self {
        case .ink:
            // Replaced by the caller's current ink tool.
            return PKInkingTool(.pen)
        case let .eraser(kind, width):
            return PKEraserTool(
                kind == .stroke ? .vector : .bitmap,
                width: CGFloat(max(1, width))
            )
        case .lasso:
            return PKLassoTool()
        case .links, .disabled:
            return PKInkingTool(.pen)
        }
    }
}

/// A drawing canvas for one page.
///
/// Strokes flow in as records and come back out as records; the view never
/// mutates the page itself. The paper is drawn by the app behind this view,
/// so the canvas is transparent.
@MainActor
public struct PencilCanvasView: UIViewRepresentable {
    public var strokes: [StrokeRecord]
    public var pageSize: CGSize
    public var tool: InkTool
    public var mode: CanvasMode
    public var activeLayerID: UUID
    public var isEditable: Bool
    /// PencilKit's on-canvas ruler. The page shows it while this is true.
    public var isRulerActive: Bool
    /// Zoom View: show only this rectangle of the page, in page points,
    /// magnified to the canvas width. nil fits the whole page.
    public var viewport: CGRect?
    public var controller: PencilCanvasController?
    /// When on, a finger draws as well as the Pencil; when off, one finger
    /// scrolls and only the Pencil inks. The simulator always draws with any
    /// input, because a mouse cannot produce Pencil touches.
    public var drawsWithFinger: Bool
    /// Two-finger double-tap undoes, three-finger double-tap redoes.
    public var undoOnTwoFingerDoubleTap: Bool
    public var redoOnThreeFingerDoubleTap: Bool
    /// What the Apple Pencil's double-tap does; `.system` follows the user's
    /// Apple Pencil preference. The canvas resolves it and reports the result.
    public var pencilDoubleTapAction: PencilDoubleTapAction
    /// A tap in page points, finger or Pencil. Only called in `.links` mode;
    /// in every other mode taps belong to drawing and are not reported.
    public var onFingerTap: ((CGPoint) -> Void)?
    /// A pencil or finger lift after using the current tool.
    public var onToolGestureEnded: (() -> Void)?
    /// Draw a stroke, keep the Pencil still for a moment, then lift: the
    /// stroke becomes a clean line or shape when it matches one.
    public var holdToDrawShapes: Bool
    /// A resolved Pencil double-tap action: never `.system`.
    public var onPencilDoubleTap: ((PencilDoubleTapAction) -> Void)?
    /// Only stroke erasing uses this: highlighter strokes disappear, pen ink
    /// stays where it is.
    public var eraseHighlighterOnly: Bool
    public var onStrokesChanged: ([StrokeRecord]) -> Void

    public init(
        strokes: [StrokeRecord],
        pageSize: CGSize,
        tool: InkTool,
        mode: CanvasMode = .ink,
        activeLayerID: UUID,
        isEditable: Bool = true,
        isRulerActive: Bool = false,
        viewport: CGRect? = nil,
        controller: PencilCanvasController? = nil,
        drawsWithFinger: Bool = false,
        undoOnTwoFingerDoubleTap: Bool = true,
        redoOnThreeFingerDoubleTap: Bool = true,
        pencilDoubleTapAction: PencilDoubleTapAction = .system,
        onFingerTap: ((CGPoint) -> Void)? = nil,
        onToolGestureEnded: (() -> Void)? = nil,
        holdToDrawShapes: Bool = true,
        onPencilDoubleTap: ((PencilDoubleTapAction) -> Void)? = nil,
        eraseHighlighterOnly: Bool = false,
        onStrokesChanged: @escaping ([StrokeRecord]) -> Void
    ) {
        self.strokes = strokes
        self.pageSize = pageSize
        self.tool = tool
        self.mode = mode
        self.activeLayerID = activeLayerID
        self.isEditable = isEditable
        self.isRulerActive = isRulerActive
        self.viewport = viewport
        self.controller = controller
        self.drawsWithFinger = drawsWithFinger
        self.undoOnTwoFingerDoubleTap = undoOnTwoFingerDoubleTap
        self.redoOnThreeFingerDoubleTap = redoOnThreeFingerDoubleTap
        self.pencilDoubleTapAction = pencilDoubleTapAction
        self.onFingerTap = onFingerTap
        self.onToolGestureEnded = onToolGestureEnded
        self.holdToDrawShapes = holdToDrawShapes
        self.onPencilDoubleTap = onPencilDoubleTap
        self.eraseHighlighterOnly = eraseHighlighterOnly
        self.onStrokesChanged = onStrokesChanged
    }

    private func canvasTool(for mode: CanvasMode) -> PKTool {
        if case .ink = mode { return tool.inkingTool }
        return mode.pkTool
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> InkCanvasView {
        let canvas = InkCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The page host owns scrolling and zooming; the canvas must not fight
        // it for finger pans. Pencil drawing still works with scrolling off.
        canvas.isScrollEnabled = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.contentSize = pageSize
        canvas.pageSize = pageSize
        canvas.viewport = viewport
        applyDrawingPolicy(to: canvas)
        canvas.tool = canvasTool(for: mode)
        canvas.isRulerActive = isRulerActive
        canvas.drawingGestureRecognizer.isEnabled = mode.allowsDrawing
        context.coordinator.canvas = canvas
        controller?.canvas = canvas

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
        tap.cancelsTouchesInView = false
        tap.isEnabled = mode == .links && onFingerTap != nil
        canvas.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap
        context.coordinator.installHoldObserver(on: canvas)

        let undo = doubleTap(
            touches: 2,
            action: #selector(Coordinator.handleUndoDoubleTap(_:)),
            coordinator: context.coordinator
        )
        undo.isEnabled = undoOnTwoFingerDoubleTap
        canvas.addGestureRecognizer(undo)
        context.coordinator.undoDoubleTap = undo

        let redo = doubleTap(
            touches: 3,
            action: #selector(Coordinator.handleRedoDoubleTap(_:)),
            coordinator: context.coordinator
        )
        redo.isEnabled = redoOnThreeFingerDoubleTap
        canvas.addGestureRecognizer(redo)
        context.coordinator.redoDoubleTap = redo

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)

        context.coordinator.apply(strokes, to: canvas)
        return canvas
    }

    /// A finger-only double-tap. It runs alongside the page host's pinch and
    /// pan gestures, so a two-finger double-tap does not stop a two-finger pan.
    private func doubleTap(
        touches: Int,
        action: Selector,
        coordinator: Coordinator
    ) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer(target: coordinator, action: action)
        tap.numberOfTapsRequired = 2
        tap.numberOfTouchesRequired = touches
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        tap.delegate = coordinator
        return tap
    }

    private func applyDrawingPolicy(to canvas: InkCanvasView) {
        #if targetEnvironment(simulator)
        // A mouse cannot produce Pencil input, so the simulator demo needs this.
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
        #endif
    }

    public func updateUIView(_ canvas: InkCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.canvas = canvas
        controller?.canvas = canvas

        canvas.isUserInteractionEnabled = isEditable
        applyDrawingPolicy(to: canvas)
        canvas.tool = canvasTool(for: mode)
        canvas.isRulerActive = isRulerActive
        canvas.drawingGestureRecognizer.isEnabled = mode.allowsDrawing
        coordinator.tapRecognizer?.isEnabled = mode == .links && onFingerTap != nil
        coordinator.undoDoubleTap?.isEnabled = undoOnTwoFingerDoubleTap
        coordinator.redoDoubleTap?.isEnabled = redoOnThreeFingerDoubleTap
        if viewport == nil {
            canvas.contentSize = pageSize
        }
        if canvas.pageSize != pageSize {
            canvas.pageSize = pageSize
        }
        canvas.viewport = viewport

        coordinator.apply(strokes, to: canvas)
        canvas.fitPageIfNeeded()
    }

    @MainActor
    public final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var parent: PencilCanvasView
        weak var canvas: InkCanvasView?
        weak var tapRecognizer: UITapGestureRecognizer?
        weak var undoDoubleTap: UITapGestureRecognizer?
        weak var redoDoubleTap: UITapGestureRecognizer?

        /// Set while the SwiftUI input is being pushed into the canvas, so the
        /// change is not echoed straight back.
        var isApplyingInput = false
        /// Layer of every stroke seen on this page. New strokes get the active one.
        var layerIDs: [UUID: UUID] = [:]
        /// The last record exchanged with the app for each stroke, as a cheap
        /// signature. It tells an edit from the app apart from an echo.
        private var syncedRecords: [UUID: RecordSignature] = [:]
        private let converter = IncrementalStrokeConverter()
        /// The canvas strokes as last set or seen. The highlighter-only eraser
        /// puts the strokes it keeps back at their old index from here.
        private var baselineStrokes: [PKStroke] = []

        // Hold to straighten (see HoldToShape.swift).
        weak var holdObserver: UIGestureRecognizer?
        var canvasFeedback: UICanvasFeedbackGenerator?
        /// The current touch paused before lifting.
        var holdDetected = false
        /// Strokes on the canvas when the current touch began.
        var strokeIDsAtTouchBegan: Set<UUID> = []
        /// A held stroke waiting to be swapped for its shape.
        var pendingShape: PendingShapeReplacement?
        /// Set while a shape swap writes the drawing, so it is not handled twice.
        var isApplyingShape = false

        init(parent: PencilCanvasView) {
            self.parent = parent
        }

        /// Brings the canvas in line with `strokes`, doing as little as possible.
        ///
        /// - Same strokes in the same order: nothing, so a stroke in progress,
        ///   scroll and zoom are never interrupted.
        /// - Same strokes, other order (a new highlighter that belongs under
        ///   ink, a moved layer): the canvas's own strokes are reordered without
        ///   re-encoding. A highlighter drawn this session therefore drops under
        ///   pen ink as soon as the app has stored it.
        /// - Anything else: the drawing is rebuilt from the records.
        func apply(_ strokes: [StrokeRecord], to canvas: InkCanvasView) {
            // A held stroke is on the canvas but not yet reported; rebuilding
            // now would drop it. The swap reports it in a moment.
            guard pendingShape == nil else { return }
            for record in strokes {
                layerIDs[record.id] = record.layerID
            }
            let current = canvas.drawing.strokes
            let incomingIDs = strokes.map(\.id)
            let currentIDs = current.map(\.id)
            let contentMatches = strokes.allSatisfy { syncedRecords[$0.id] == RecordSignature($0) }

            if contentMatches, incomingIDs == currentIDs { return }

            let drawing: PKDrawing
            if contentMatches, Set(incomingIDs) == Set(currentIDs), incomingIDs.count == currentIDs.count {
                var byID: [UUID: PKStroke] = [:]
                for stroke in current { byID[stroke.id] = stroke }
                drawing = PKDrawing(strokes: incomingIDs.compactMap { byID[$0] })
            } else if incomingIDs.count > currentIDs.count,
                      Array(incomingIDs.prefix(currentIDs.count)) == currentIDs,
                      strokes.prefix(currentIDs.count).allSatisfy({ syncedRecords[$0.id] == RecordSignature($0) }) {
                // Strokes added after the ones already here (written in the
                // Zoom View panel, or by another canvas on the same page):
                // decode only the new ones.
                // The app's strokes are already in render order (the merge
                // puts them there), so the new ones go on top as given.
                let added = strokes.dropFirst(currentIDs.count).compactMap { try? StrokeCodec.stroke(from: $0) }
                drawing = PKDrawing(strokes: current + added)
            } else {
                drawing = StrokeCodec.drawing(from: strokes)
            }

            isApplyingInput = true
            canvas.drawing = drawing
            isApplyingInput = false
            baselineStrokes = drawing.strokes
            converter.seed(strokes: drawing.strokes, records: strokes)
            syncedRecords = Dictionary(
                strokes.map { ($0.id, RecordSignature($0)) },
                uniquingKeysWith: { _, last in last }
            )
            let liveIDs = Set(drawing.strokes.map(\.id))
            layerIDs = layerIDs.filter { liveIDs.contains($0.key) }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard case .links = parent.mode,
                  let canvas, let onTap = parent.onFingerTap
            else { return }
            let point = gesture.location(in: canvas)
            let pagePoint = CGPoint(
                x: (point.x + canvas.contentOffset.x) / canvas.zoomScale,
                y: (point.y + canvas.contentOffset.y) / canvas.zoomScale
            )
            onTap(pagePoint)
        }

        public func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.onToolGestureEnded?()
        }

        // MARK: - Finger double-taps

        @objc func handleUndoDoubleTap(_ gesture: UITapGestureRecognizer) {
            canvas?.undoManager?.undo()
        }

        @objc func handleRedoDoubleTap(_ gesture: UITapGestureRecognizer) {
            canvas?.undoManager?.redo()
        }

        /// The page host's pinch and pan keep working alongside these taps.
        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: - Apple Pencil

        public func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveTap tap: UIPencilInteraction.Tap
        ) {
            guard let action = resolvedPencilAction(), action != .off else { return }
            parent.onPencilDoubleTap?(action)
        }

        /// The configured action, or the system preference for `.system`.
        /// Actions the app has no meaning for (ink attributes, a shortcut)
        /// come back as `nil`, so nothing happens.
        private func resolvedPencilAction() -> PencilDoubleTapAction? {
            guard parent.pencilDoubleTapAction == .system else {
                return parent.pencilDoubleTapAction
            }
            switch UIPencilInteraction.preferredTapAction {
            case .switchEraser: return .eraser
            case .switchPrevious: return .previousTool
            case .showColorPalette: return .colorPalette
            default: return nil
            }
        }

        // MARK: - Drawing changes

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingInput, !isApplyingShape else { return }
            if parent.eraseHighlighterOnly {
                keepNonHighlighterStrokes(in: canvasView)
            }
            if captureHeldStroke(in: canvasView) {
                baselineStrokes = canvasView.drawing.strokes
                return
            }
            reportDrawingChange(canvasView)
        }

        func reportDrawingChange(_ canvasView: PKCanvasView) {
            defer { baselineStrokes = canvasView.drawing.strokes }
            let activeLayerID = parent.activeLayerID
            // PencilKit can notify a moment *after* a programmatic change, so a
            // pending guard flag alone is not enough: the converter also
            // reports nil when the strokes match what was last applied.
            guard let records = converter.changedRecords(
                from: canvasView.drawing.strokes,
                layerID: { [self] id in
                    if let layer = layerIDs[id] { return layer }
                    layerIDs[id] = activeLayerID
                    return activeLayerID
                }
            ) else { return }
            let liveIDs = Set(records.map(\.id))
            layerIDs = layerIDs.filter { liveIDs.contains($0.key) }
            syncedRecords = Dictionary(
                records.map { ($0.id, RecordSignature($0)) },
                uniquingKeysWith: { _, last in last }
            )
            parent.onStrokesChanged(records)
        }

        /// With "Erase Highlighter Only" on, a stroke eraser pass may only
        /// remove highlighters: every other stroke it took goes back at its
        /// old index. The restore is not registered with the canvas's undo
        /// manager, so one undo still restores the whole erase.
        private func keepNonHighlighterStrokes(in canvas: PKCanvasView) {
            guard case let .eraser(kind, _) = parent.mode, kind == .stroke else { return }
            let current = canvas.drawing.strokes
            let currentIDs = Set(current.map(\.id))
            let removed = baselineStrokes.filter { !currentIDs.contains($0.id) }
            guard removed.contains(where: { !Self.isHighlighter($0) }) else { return }

            var live: [UUID: PKStroke] = [:]
            for stroke in current { live[stroke.id] = stroke }
            var restored: [PKStroke] = []
            var keptIDs = Set<UUID>()
            restored.reserveCapacity(baselineStrokes.count)
            for stroke in baselineStrokes {
                if let stroke = live[stroke.id] {
                    restored.append(stroke)
                    keptIDs.insert(stroke.id)
                } else if !Self.isHighlighter(stroke) {
                    restored.append(stroke)
                    keptIDs.insert(stroke.id)
                }
            }
            // A stroke the baseline never saw keeps its place at the end.
            for stroke in current where !keptIDs.contains(stroke.id) {
                restored.append(stroke)
            }

            canvas.undoManager?.disableUndoRegistration()
            isApplyingInput = true
            canvas.drawing = PKDrawing(strokes: restored)
            isApplyingInput = false
            canvas.undoManager?.enableUndoRegistration()
        }

        /// A highlighter is a translucent marker, the same rule the stroke
        /// codec uses when it stores `StrokeTool.isHighlighter`.
        private static func isHighlighter(_ stroke: PKStroke) -> Bool {
            stroke.ink.inkType == .marker && stroke.ink.color.cgColor.alpha < 0.99
        }
    }
}
#endif
