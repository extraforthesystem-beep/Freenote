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
    private var didFit = false

    /// PencilKit registers undo with the canvas's own undo manager, and a
    /// SwiftUI-hosted view has none on its responder chain, so supply one.
    private let canvasUndoManager = UndoManager()
    override public var undoManager: UndoManager? { canvasUndoManager }

    func fitPageIfNeeded() {
        guard !didFit,
              pageSize.width > 0, pageSize.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return }
        didFit = true
        let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
        minimumZoomScale = fit * 0.5
        maximumZoomScale = max(fit * 4, 1)
        zoomScale = fit
        contentOffset = .zero
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        fitPageIfNeeded()
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
    public var activeLayerID: UUID
    public var isEditable: Bool
    public var controller: PencilCanvasController?
    public var onStrokesChanged: ([StrokeRecord]) -> Void

    public init(
        strokes: [StrokeRecord],
        pageSize: CGSize,
        tool: InkTool,
        activeLayerID: UUID,
        isEditable: Bool = true,
        controller: PencilCanvasController? = nil,
        onStrokesChanged: @escaping ([StrokeRecord]) -> Void
    ) {
        self.strokes = strokes
        self.pageSize = pageSize
        self.tool = tool
        self.activeLayerID = activeLayerID
        self.isEditable = isEditable
        self.controller = controller
        self.onStrokesChanged = onStrokesChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> InkCanvasView {
        let canvas = InkCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
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
        canvas.tool = tool.inkingTool
        context.coordinator.canvas = canvas
        controller?.canvas = canvas
        return canvas
    }

    public func updateUIView(_ canvas: InkCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.canvas = canvas
        controller?.canvas = canvas

        canvas.isUserInteractionEnabled = isEditable
        canvas.tool = tool.inkingTool
        canvas.contentSize = pageSize
        if canvas.pageSize != pageSize {
            canvas.pageSize = pageSize
        }

        // Only replace the drawing when the set of strokes changed. Re-applying
        // identical strokes would interrupt the stroke being drawn and would
        // fight the user's scroll and zoom.
        let incoming = strokes.map(\.id)
        if incoming != canvas.drawing.strokes.map(\.id) {
            coordinator.absorbLayers(from: strokes)
            coordinator.isApplyingInput = true
            canvas.drawing = StrokeCodec.drawing(from: strokes)
            coordinator.isApplyingInput = false
            coordinator.appliedRecords = coordinator.records(
                from: canvas,
                activeLayerID: activeLayerID
            )
        } else {
            coordinator.absorbLayers(from: strokes)
        }

        canvas.fitPageIfNeeded()
    }

    @MainActor
    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvas: InkCanvasView?

        /// Set while the SwiftUI input is being pushed into the canvas, so the
        /// change is not echoed straight back.
        var isApplyingInput = false
        /// What the canvas held right after the last input was applied.
        var appliedRecords: [StrokeRecord]?
        /// Layer of every stroke seen on this page. New strokes get the active one.
        var layerIDs: [UUID: UUID] = [:]

        init(parent: PencilCanvasView) {
            self.parent = parent
        }

        func absorbLayers(from records: [StrokeRecord]) {
            for record in records {
                layerIDs[record.id] = record.layerID
            }
        }

        func records(from canvas: PKCanvasView, activeLayerID: UUID) -> [StrokeRecord] {
            let strokes = canvas.drawing.strokes
            let liveIDs = Set(strokes.map(\.id))
            layerIDs = layerIDs.filter { liveIDs.contains($0.key) }

            var records: [StrokeRecord] = []
            records.reserveCapacity(strokes.count)
            for stroke in strokes {
                let layerID = layerIDs[stroke.id] ?? activeLayerID
                layerIDs[stroke.id] = layerID
                records.append(StrokeCodec.record(from: stroke, layerID: layerID))
            }
            return records
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingInput else { return }
            let records = records(from: canvasView, activeLayerID: parent.activeLayerID)
            // PencilKit can notify a moment *after* a programmatic change, so a
            // pending guard flag alone is not enough.
            if let appliedRecords, appliedRecords == records { return }
            appliedRecords = records
            parent.onStrokesChanged(records)
        }
    }
}
#endif
