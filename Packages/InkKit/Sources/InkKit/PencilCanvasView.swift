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

    /// PencilKit registers undo with the canvas's own undo manager, and a
    /// SwiftUI-hosted view has none on its responder chain, so supply one.
    private let canvasUndoManager = UndoManager()
    override public var undoManager: UndoManager? { canvasUndoManager }

    func fitPageIfNeeded() {
        guard pageSize.width > 0, pageSize.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return }
        let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
        // The paper is a SwiftUI image behind the canvas, so it cannot zoom with
        // the ink yet. Lock the zoom until the paper moves into the scroll view.
        guard minimumZoomScale != fit || maximumZoomScale != fit else { return }
        minimumZoomScale = fit
        maximumZoomScale = fit
        zoomScale = fit
        contentOffset = .zero
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
    public var controller: PencilCanvasController?
    /// A tap in page points, finger or Pencil. Only called in `.links` mode;
    /// in every other mode taps belong to drawing and are not reported.
    public var onFingerTap: ((CGPoint) -> Void)?
    /// A pencil or finger lift after using the current tool.
    public var onToolGestureEnded: (() -> Void)?
    /// Draw a stroke, keep the Pencil still for a moment, then lift: the
    /// stroke becomes a clean line or shape when it matches one.
    public var holdToDrawShapes: Bool
    public var onStrokesChanged: ([StrokeRecord]) -> Void

    public init(
        strokes: [StrokeRecord],
        pageSize: CGSize,
        tool: InkTool,
        mode: CanvasMode = .ink,
        activeLayerID: UUID,
        isEditable: Bool = true,
        isRulerActive: Bool = false,
        controller: PencilCanvasController? = nil,
        onFingerTap: ((CGPoint) -> Void)? = nil,
        onToolGestureEnded: (() -> Void)? = nil,
        holdToDrawShapes: Bool = true,
        onStrokesChanged: @escaping ([StrokeRecord]) -> Void
    ) {
        self.strokes = strokes
        self.pageSize = pageSize
        self.tool = tool
        self.mode = mode
        self.activeLayerID = activeLayerID
        self.isEditable = isEditable
        self.isRulerActive = isRulerActive
        self.controller = controller
        self.onFingerTap = onFingerTap
        self.onToolGestureEnded = onToolGestureEnded
        self.holdToDrawShapes = holdToDrawShapes
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
        #if targetEnvironment(simulator)
        // A mouse cannot produce Pencil input, so the simulator demo needs this.
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif
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

        context.coordinator.apply(strokes, to: canvas)
        return canvas
    }

    public func updateUIView(_ canvas: InkCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.canvas = canvas
        controller?.canvas = canvas

        canvas.isUserInteractionEnabled = isEditable
        canvas.tool = canvasTool(for: mode)
        canvas.isRulerActive = isRulerActive
        canvas.drawingGestureRecognizer.isEnabled = mode.allowsDrawing
        coordinator.tapRecognizer?.isEnabled = mode == .links && onFingerTap != nil
        canvas.contentSize = pageSize
        if canvas.pageSize != pageSize {
            canvas.pageSize = pageSize
        }

        coordinator.apply(strokes, to: canvas)
        canvas.fitPageIfNeeded()
    }

    @MainActor
    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvas: InkCanvasView?
        weak var tapRecognizer: UITapGestureRecognizer?

        /// Set while the SwiftUI input is being pushed into the canvas, so the
        /// change is not echoed straight back.
        var isApplyingInput = false
        /// Layer of every stroke seen on this page. New strokes get the active one.
        var layerIDs: [UUID: UUID] = [:]
        /// The last record exchanged with the app for each stroke, as a cheap
        /// signature. It tells an edit from the app apart from an echo.
        private var syncedRecords: [UUID: RecordSignature] = [:]
        private let converter = IncrementalStrokeConverter()

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
            } else {
                drawing = StrokeCodec.drawing(from: strokes)
            }

            isApplyingInput = true
            canvas.drawing = drawing
            isApplyingInput = false
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

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingInput, !isApplyingShape else { return }
            if captureHeldStroke(in: canvasView) { return }
            reportDrawingChange(canvasView)
        }

        func reportDrawingChange(_ canvasView: PKCanvasView) {
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
    }
}
#endif
