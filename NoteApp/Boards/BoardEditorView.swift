import BoardKit
import InkKit
import NoteCore
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// One board on a Freeform-style infinite canvas, with the notebook's tools.
///
/// The board's PencilKit canvas is itself the scroll view: a fixed 50,000-point
/// world, free zoom from 10 % to 400 %, and the same `EditorToolState` the
/// notebook uses. Ink is stored in board coordinates; while the board is open
/// it is shifted into the middle of the world, and shifted back when saved.
struct BoardEditorView: View {
    /// The world the canvas scrolls over. Far larger than any board needs, so
    /// the edge is never reachable in practice.
    static let worldSize = CGSize(width: 50_000, height: 50_000)
    /// Added to stored coordinates while editing, so an old board's origin is
    /// the middle of the world. Removed again by `savedBoard`.
    static let worldOffset = CGPoint(x: 25_000, y: 25_000)
    /// Free zoom range of the board canvas, as in Freeform.
    static let zoomRange: ClosedRange<CGFloat> = 0.1...4.0
    /// Empty page points kept around content by Zoom to Fit.
    private static let fitPadding: CGFloat = 48

    /// Stable layer for every stroke drawn on a board.
    static let inkLayerID = UUID(uuidString: "B0A2D000-0000-4000-8000-000000000001")!
    /// Stable item ID used when a board has no ink item yet.
    static let defaultInkItemID = UUID(uuidString: "B0A2D000-0000-4000-8000-000000000002")!

    let model: BoardModel

    @State private var board: Board
    @State private var isSaving = false
    @State private var hasUnsavedChanges = false
    @State private var saveGeneration = 0
    @State private var saveTask: Task<Void, Never>?
    /// The camera on disk when the board opened, so Done can skip writes that
    /// would only bump the modified date.
    @State private var savedCamera: BoardCamera?
    @State private var didRestoreCamera = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    @State private var editor = EditorToolState()
    @State private var controller = PencilCanvasController()
    @State private var viewport = BoardViewportState()
    @State private var showsClearConfirmation = false
    @AppStorage(AppSettings.Key.holdToDrawShapes) private var holdToDrawShapes = true
    @AppStorage(AppSettings.Key.drawWithFinger) private var drawWithFinger = false
    @AppStorage(AppSettings.Key.twoFingerDoubleTapUndo) private var twoFingerDoubleTapUndo = true
    @AppStorage(AppSettings.Key.threeFingerDoubleTapRedo) private var threeFingerDoubleTapRedo = true
    @AppStorage(AppSettings.Key.pencilDoubleTapAction) private var pencilDoubleTapAction: PencilDoubleTapAction = .system
    @AppStorage(AppSettings.Key.eraserHighlighterOnly) private var eraserHighlighterOnly = false
    @AppStorage(AppSettings.Key.boardDotGrid) private var showsDotGrid = true
    #endif

    init(model: BoardModel, board: Board) {
        self.model = model
        _board = State(initialValue: Self.translated(board, by: Self.worldOffset))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(iOS)
                EditorToolbar(
                    editor: editor,
                    controller: controller,
                    showsThumbnails: .constant(false),
                    isRecording: false,
                    recordingLabel: "",
                    onBack: { Task { await finishEditing() } },
                    onStopRecording: {},
                    onClearPage: { showsClearConfirmation = true },
                    showsPageControls: false,
                    showsElementTool: false,
                    backLabel: "Boards",
                    insertMenu: { insertMenu },
                    moreMenu: { moreMenu }
                )
                Divider()
                #endif
                canvasArea
            }
            .navigationTitle(board.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Clear Board?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("Clear Board", role: .destructive) { clearBoard() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every stroke from this board.")
            }
            #endif
            .toolbar { toolbarContent }
            .alert("Couldn't Save Board", isPresented: errorBinding) {
                Button("Try Again") {
                    Task { _ = await saveNow() }
                }
                Button("Keep Editing", role: .cancel) { model.clearError() }
                Button("Close Without Saving", role: .destructive) {
                    model.clearError()
                    dismiss()
                }
            } message: {
                Text(model.lastError ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { flush() }
            }
            .onDisappear {
                flush()
                #if os(iOS)
                editor.saveNow()
                #endif
            }
            .task {
                savedCamera = model.camera(for: board.id)
                #if os(iOS)
                await restoreCameraIfNeeded()
                #endif
            }
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvasArea: some View {
        #if os(iOS)
        ZStack {
            BoardDotGrid(viewport: viewport, isVisible: showsDotGrid, origin: Self.worldOffset)

            BoardItemLayer(
                items: board.normalizedZOrder().filter { $0.frame != nil },
                viewport: viewport,
                assetsDirectory: assetsDirectory
            )

            PencilCanvasView(
                strokes: inkStrokes,
                pageSize: Self.worldSize,
                tool: editor.inkTool,
                mode: canvasMode,
                activeLayerID: Self.inkLayerID,
                isEditable: canvasIsEditable,
                controller: controller,
                drawsWithFinger: drawWithFinger,
                undoOnTwoFingerDoubleTap: twoFingerDoubleTapUndo,
                redoOnThreeFingerDoubleTap: threeFingerDoubleTapRedo,
                pencilDoubleTapAction: pencilDoubleTapAction,
                onToolGestureEnded: { editor.didEndToolGesture() },
                holdToDrawShapes: holdToDrawShapes,
                onPencilDoubleTap: { editor.handlePencilDoubleTap($0) },
                eraseHighlighterOnly: eraserHighlighterOnly,
                onViewportChange: { rect, zoom in
                    viewport.update(visibleRect: rect, zoom: zoom)
                },
                onStrokesChanged: { strokesChanged($0) }
            )
            .id(board.id)

            if editor.tool == .laser, !editor.isReadOnly {
                LaserPointerOverlay(mode: editor.laserMode)
            }
        }
        .overlay(alignment: .bottomLeading) {
            BoardZoomPill(
                viewport: viewport,
                onFit: { zoomToFit(animated: true) },
                onZoom: { zoom(to: $0, animated: true) }
            )
            .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            BoardGridToggle(isOn: $showsDotGrid)
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        macCanvas
        #endif
    }

    #if os(iOS)
    /// Read Only takes every tool away, as in the notebook.
    private var canvasMode: CanvasMode {
        editor.isReadOnly ? .links : editor.canvasMode
    }

    private var canvasIsEditable: Bool {
        if editor.isReadOnly { return true }
        switch editor.tool {
        case .elements, .laser: return false
        default: return true
        }
    }

    private var assetsDirectory: URL {
        model.rootURL.appendingPathComponent("Assets", isDirectory: true)
    }
    #endif

    #if os(macOS)
    /// The Mac reader stays a static rendering of the board's ink.
    private var macCanvas: some View {
        GeometryReader { proxy in
            Group {
                if let image = macBoardImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(36)
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                } else {
                    ContentUnavailableView {
                        Label("Empty Board", systemImage: "square.dashed")
                    } description: {
                        Text("Draw on this board on an iPad.")
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AppColor.groupedBackground)
    }

    private var macBoardImage: NSImage? {
        guard let content = board.bounds(), content.width > 0, content.height > 0 else { return nil }
        let strokes = Self.translatedStrokes(
            inkStrokes,
            by: CGPoint(x: -content.minX, y: -content.minY)
        )
        let size = CGSize(width: content.width, height: content.height)
        let scale = min(2, max(0.01, 2_048 / max(size.width, size.height)))
        return PageRenderer.image(
            strokes: strokes,
            pageSize: size,
            template: .blank,
            scale: scale
        )
    }
    #endif

    // MARK: - Menus

    #if os(iOS)
    @ViewBuilder
    private var insertMenu: some View {
        Section("Add") {
            Button("Sticky Note", systemImage: "note.text") {}
            Button("Text Box", systemImage: "character.textbox") {}
            Button("Shape", systemImage: "square.on.circle") {}
            Button("Image", systemImage: "photo") {}
        }
        .disabled(true)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
            zoomToFit(animated: true)
        }
        Button(
            showsDotGrid ? "Hide Dot Grid" : "Show Dot Grid",
            systemImage: "circle.grid.3x3"
        ) {
            showsDotGrid.toggle()
        }
    }
    #endif

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                Task { await finishEditing() }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Camera

    #if os(iOS)
    /// Applies the saved viewport once the canvas has a size. A board that was
    /// never positioned fits its content, or opens at 100 % in the middle.
    private func restoreCameraIfNeeded() async {
        guard !didRestoreCamera else { return }
        defer { didRestoreCamera = true }

        for _ in 0..<40 {
            if let canvas = controller.canvas,
               canvas.bounds.width > 1,
               canvas.bounds.height > 1 {
                canvas.layoutIfNeeded()
                if let camera = savedCamera, cameraShowsContent(camera, in: canvas) {
                    apply(camera, to: canvas)
                } else if board.bounds() != nil {
                    zoomToFit(animated: false)
                } else {
                    centerAt100Percent(animated: false)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// A camera saved before the world offset (or after the board was moved
    /// far away) can point at empty space. Fitting the content is more useful.
    private func cameraShowsContent(_ camera: BoardCamera, in canvas: InkCanvasView) -> Bool {
        guard let content = board.bounds() else { return true }
        return content.intersects(camera.visibleWorldRect(viewSize: canvas.bounds.size))
    }

    private func apply(_ camera: BoardCamera, to canvas: InkCanvasView) {
        canvas.setZoomScale(CGFloat(camera.zoom), animated: false)
        canvas.layoutIfNeeded()

        let scale = canvas.zoomScale
        let maxX = max(canvas.contentSize.width - canvas.bounds.width, 0)
        let maxY = max(canvas.contentSize.height - canvas.bounds.height, 0)
        let x = CGFloat(camera.centerX) * scale - canvas.bounds.width / 2
        let y = CGFloat(camera.centerY) * scale - canvas.bounds.height / 2
        canvas.setContentOffset(
            CGPoint(x: min(max(x, 0), maxX), y: min(max(y, 0), maxY)),
            animated: false
        )
    }

    /// Frames all content with a little room around it.
    private func zoomToFit(animated: Bool) {
        guard let canvas = controller.canvas, canvas.bounds.width > 1 else { return }
        guard let content = board.bounds(), content.width > 0, content.height > 0 else {
            centerAt100Percent(animated: animated)
            return
        }
        canvas.zoom(to: content.insetBy(dx: -Self.fitPadding, dy: -Self.fitPadding), animated: animated)
    }

    /// Sets a zoom level around whatever the board is showing now.
    private func zoom(to zoom: CGFloat, animated: Bool) {
        guard let canvas = controller.canvas, canvas.bounds.width > 1, zoom > 0 else { return }
        let center = visibleCenter(of: canvas)
        let size = CGSize(
            width: canvas.bounds.width / zoom,
            height: canvas.bounds.height / zoom
        )
        canvas.zoom(
            to: CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            animated: animated
        )
    }

    private func centerAt100Percent(animated: Bool) {
        guard let canvas = controller.canvas, canvas.bounds.width > 1 else { return }
        let size = canvas.bounds.size
        canvas.zoom(
            to: CGRect(
                x: Self.worldOffset.x - size.width / 2,
                y: Self.worldOffset.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            animated: animated
        )
    }

    private func visibleCenter(of canvas: InkCanvasView) -> CGPoint {
        let scale = max(canvas.zoomScale, 0.0001)
        return CGPoint(
            x: (canvas.contentOffset.x + canvas.bounds.width / 2) / scale,
            y: (canvas.contentOffset.y + canvas.bounds.height / 2) / scale
        )
    }

    private var currentCamera: BoardCamera? {
        guard let canvas = controller.canvas,
              canvas.bounds.width > 1,
              canvas.bounds.height > 1,
              canvas.zoomScale > 0
        else { return nil }

        let scale = canvas.zoomScale
        let visible = CGRect(
            x: canvas.contentOffset.x / scale,
            y: canvas.contentOffset.y / scale,
            width: canvas.bounds.width / scale,
            height: canvas.bounds.height / scale
        )
        return BoardCamera(visibleWorldRect: visible, viewSize: canvas.bounds.size)
    }
    #else
    private var currentCamera: BoardCamera? { nil }
    #endif

    // MARK: - Ink

    private var inkItem: BoardItem? {
        board.items.first { item in
            if case .ink = item.content { return true }
            return false
        }
    }

    /// The board's ink, in the world coordinates the canvas draws in.
    private var inkStrokes: [StrokeRecord] {
        guard let item = inkItem, case let .ink(strokes) = item.content else { return [] }
        return strokes
    }

    private func strokesChanged(_ strokes: [StrokeRecord]) {
        let now = Date()

        if strokes.isEmpty {
            guard let item = inkItem else { return }
            board.remove(item.id, at: now)
        } else if var item = inkItem {
            item.content = .ink(strokes: strokes)
            item.updatedAt = now
            board.add(item, at: now)
        } else {
            let item = BoardItem(
                id: Self.defaultInkItemID,
                zIndex: 0,
                createdAt: now,
                updatedAt: now,
                content: .ink(strokes: strokes)
            )
            board.add(item, at: now)
        }

        scheduleSave()
    }

    #if os(iOS)
    private func clearBoard() {
        strokesChanged([])
    }
    #endif

    // MARK: - Saving

    /// The board as stored: world coordinates shifted back to board
    /// coordinates, so the offset never reaches the file.
    private var savedBoard: Board {
        Self.translated(board, by: CGPoint(x: -Self.worldOffset.x, y: -Self.worldOffset.y))
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveGeneration += 1
        let generation = saveGeneration
        saveTask?.cancel()

        let snapshot = savedBoard
        let camera = currentCamera
        isSaving = true

        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            guard !Task.isCancelled, generation == saveGeneration else { return }

            let saved = await model.save(snapshot, camera: camera)
            guard generation == saveGeneration else { return }
            isSaving = false
            if saved {
                hasUnsavedChanges = false
                savedCamera = camera
            }
        }
    }

    /// Done: wait for the write before dismissing, so a failure keeps the board
    /// open with its alert instead of vanishing behind the sheet.
    private func finishEditing() async {
        saveTask?.cancel()
        saveTask = nil
        defer { isSaving = false }

        let cameraChanged = savedCamera != currentCamera
        guard hasUnsavedChanges || cameraChanged else {
            dismiss()
            return
        }

        if await saveNow() {
            dismiss()
        }
    }

    @discardableResult
    private func saveNow() async -> Bool {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = savedBoard
        let camera = currentCamera
        isSaving = true

        let saved = await model.save(snapshot, camera: camera)
        if generation == saveGeneration {
            isSaving = false
            if saved {
                hasUnsavedChanges = false
                savedCamera = camera
            }
        }
        return saved
    }

    /// Fire-and-forget flush for leaving the screen or backgrounding the app.
    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        let camera = currentCamera
        guard hasUnsavedChanges || (camera != nil && camera != savedCamera) else { return }
        let snapshot = savedBoard
        Task {
            await model.save(snapshot, camera: camera)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.clearError() } }
        )
    }

    // MARK: - Coordinate shift

    /// Moves every item between board coordinates and world coordinates.
    /// Only the live editing state is shifted; the saved snapshot is shifted
    /// back, so board files keep their old coordinates and no stroke is
    /// rewritten during a pan.
    private static func translated(_ board: Board, by offset: CGPoint) -> Board {
        guard offset != .zero else { return board }
        var result = board
        result.items = board.items.map { item in
            var copy = item
            copy.content = translated(item.content, by: offset)
            return copy
        }
        return result
    }

    private static func translated(_ content: BoardItemContent, by offset: CGPoint) -> BoardItemContent {
        switch content {
        case let .ink(strokes):
            return .ink(strokes: translatedStrokes(strokes, by: offset))
        case let .image(assetName, frame):
            return .image(assetName: assetName, frame: frame.offsetBy(dx: offset.x, dy: offset.y))
        case let .text(string, frame, fontSize, color):
            return .text(
                string,
                frame: frame.offsetBy(dx: offset.x, dy: offset.y),
                fontSize: fontSize,
                color: color
            )
        case let .shape(kind, frame, strokeColor, fillColor, lineWidth):
            return .shape(
                kind: kind,
                frame: frame.offsetBy(dx: offset.x, dy: offset.y),
                strokeColor: strokeColor,
                fillColor: fillColor,
                lineWidth: lineWidth
            )
        case .connector:
            return content
        }
    }

    private static func translatedStrokes(
        _ strokes: [StrokeRecord],
        by offset: CGPoint
    ) -> [StrokeRecord] {
        guard offset != .zero else { return strokes }
        return strokes.map { stroke in
            guard stroke.transform.count == StrokeRecord.transformElementCount else { return stroke }
            var copy = stroke
            var transform = copy.transform
            transform[4] += Double(offset.x)
            transform[5] += Double(offset.y)
            copy.transform = transform
            return copy
        }
    }
}
