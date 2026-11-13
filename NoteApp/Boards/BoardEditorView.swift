import BoardKit
import InkKit
import NoteCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import PhotosUI
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
    /// The selected object, if any.
    @State private var selection: UUID?
    /// The sticky note or text box being typed into, if any.
    @State private var editingItemID: UUID?
    @State private var editingText = ""
    /// The finger drag on the selection, while one is in progress.
    @State private var drag: BoardItemDrag?
    /// Whether the current drag has moved the selection. A tap on the
    /// selection starts a drag that never moves, and saves nothing.
    @State private var dragMoved = false
    /// Alignment guides for the current drag.
    @State private var snapGuides: [BoardSnapGuide] = []
    @State private var showsPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    clearPageLabel: "Clear Board…",
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
            .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                Task {
                    await insertImage(from: item)
                    photoSelection = nil
                }
            }
            .confirmationDialog("Clear Board?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("Clear Board", role: .destructive) { clearBoard() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every stroke and object from this board.")
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
                assetsDirectory: assetsDirectory,
                reduceMotion: reduceMotion,
                editingItemID: editingItemID
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
                freeZoom: Self.zoomRange,
                onViewportChange: { rect, zoom in
                    viewport.update(visibleRect: rect, zoom: zoom)
                },
                fingerInteraction: fingerInteraction,
                onStrokesChanged: { strokesChanged($0) }
            )
            .id(board.id)

            if editor.tool == .laser, !editor.isReadOnly {
                LaserPointerOverlay(mode: editor.laserMode)
            }

            if let selectedItem {
                BoardSelectionOverlay(
                    item: selectedItem,
                    viewport: viewport,
                    guides: snapGuides,
                    isEditing: editingItemID != nil,
                    reduceMotion: reduceMotion,
                    onDuplicate: duplicateSelected,
                    onDelete: deleteSelected,
                    onBringToFront: bringSelectionToFront,
                    onSendToBack: sendSelectionToBack,
                    onColor: setColor,
                    onFillColor: setFillColor,
                    onEditText: beginEditingSelected
                )
            }

            if let editingItem, let editingItemID, editingItemID == editingItem.id {
                BoardTextEditor(
                    frame: editingItem.frame ?? .zero,
                    viewport: viewport,
                    isSticky: isSticky(editingItem),
                    textFontSize: textFontSize(of: editingItem),
                    textColor: textColor(of: editingItem),
                    text: $editingText,
                    onSubmit: commitEditing
                )
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

    private var assetsDirectory: URL {
        model.rootURL.appendingPathComponent("Assets", isDirectory: true)
    }

    #if os(iOS)
    /// The selected, frame-backed object, if it still exists.
    private var selectedItem: BoardItem? {
        guard let selection,
              let item = board.item(selection),
              item.frame != nil,
              !board.deletedItemIDs.contains(selection)
        else { return nil }
        return item
    }

    private var editingItem: BoardItem? {
        guard let editingItemID else { return nil }
        return board.item(editingItemID)
    }

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

    private var fingerInteraction: CanvasFingerInteraction {
        CanvasFingerInteraction(
            onTap: { point in canvasTapped(at: point) },
            onDragPossible: { point in dragTarget(at: point) != nil },
            onDragBegan: { point in beginDrag(at: point) },
            onDragChanged: { translation in dragChanged(translation) },
            onDragEnded: { endDrag() }
        )
    }
    #endif

    #if os(macOS)
    /// The Mac reader stays a static rendering: objects, then the ink over
    /// them, as the iPad shows them.
    private var macCanvas: some View {
        GeometryReader { proxy in
            if let content = board.bounds(), content.width > 0, content.height > 0 {
                let scale = min(
                    1.5,
                    min(
                        max(proxy.size.width - 72, 1) / content.width,
                        max(proxy.size.height - 72, 1) / content.height
                    )
                )
                let width = content.width * scale
                let height = content.height * scale

                ZStack(alignment: .topLeading) {
                    Color.white

                    BoardStaticItemLayer(
                        items: board.normalizedZOrder(),
                        content: content,
                        scale: scale,
                        assetsDirectory: assetsDirectory
                    )

                    if let ink = macInkImage(in: content) {
                        Image(nsImage: ink)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: width, height: height)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            } else {
                ContentUnavailableView {
                    Label("Empty Board", systemImage: "square.dashed")
                } description: {
                    Text("Draw on this board on an iPad.")
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .background(AppColor.groupedBackground)
    }

    private func macInkImage(in content: CGRect) -> NSImage? {
        guard !inkStrokes.isEmpty else { return nil }
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
            Button("Sticky Note", systemImage: "note.text") { insertSticky() }
            Button("Text Box", systemImage: "character.textbox") { insertText() }
            Menu("Shape", systemImage: "square.on.circle") {
                ForEach(BoardShapeKind.allCases, id: \.self) { kind in
                    Button(kind.displayName, systemImage: kind.symbolName) {
                        insertShape(kind)
                    }
                }
            }
            Button("Image", systemImage: "photo") { showsPhotoPicker = true }
        }
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
        selection = nil
        editingItemID = nil
        editingText = ""
        snapGuides = []
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
        #if os(iOS)
        commitEditing()
        #endif
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
        case let .sticky(string, frame, color):
            return .sticky(
                string,
                frame: frame.offsetBy(dx: offset.x, dy: offset.y),
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

#if os(iOS)
/// A finger drag on the selected object: a move, or a resize from one corner.
private struct BoardItemDrag {
    let itemID: UUID
    let frame: CGRect
    let corner: BoardResizeCorner?
    let keepsSquare: Bool
}

extension BoardEditorView {
    // MARK: - Selection

    /// A finger tap on the canvas: select the topmost object under it, or
    /// clear the selection. A tap on the already selected sticky note or text
    /// box starts typing, which is also how a double tap feels.
    private func canvasTapped(at point: CGPoint) {
        guard !editor.isReadOnly else { return }
        if editingItemID != nil {
            commitEditing()
        }
        guard let hit = topmostItem(at: point) else {
            select(nil)
            return
        }
        if hit.id == selection, isTextLike(hit) {
            beginEditing(hit)
        } else {
            select(hit.id)
        }
    }

    /// The object drawn last under a world point.
    private func topmostItem(at point: CGPoint) -> BoardItem? {
        board.normalizedZOrder().reversed().first { item in
            item.frame?.contains(point) == true
        }
    }

    private func select(_ id: UUID?) {
        guard selection != id else { return }
        if editingItemID != nil {
            commitEditing()
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            selection = id
        }
        if id == nil {
            snapGuides = []
        }
    }

    private func isTextLike(_ item: BoardItem) -> Bool {
        switch item.content {
        case .text, .sticky: true
        default: false
        }
    }

    private func isSticky(_ item: BoardItem) -> Bool {
        if case .sticky = item.content { return true }
        return false
    }

    private func textColor(of item: BoardItem) -> Color {
        switch item.content {
        case .text(_, _, _, let color): Color(color)
        case .sticky: Color.black.opacity(0.85)
        default: .primary
        }
    }

    private func textFontSize(of item: BoardItem) -> CGFloat {
        if case let .text(_, _, fontSize, _) = item.content {
            return CGFloat(fontSize)
        }
        return 18
    }

    // MARK: - Text editing

    private func beginEditingSelected() {
        guard let selectedItem, isTextLike(selectedItem) else { return }
        beginEditing(selectedItem)
    }

    private func beginEditing(_ item: BoardItem) {
        if editingItemID != nil {
            commitEditing()
        }
        switch item.content {
        case let .text(text, _, _, _):
            editingText = text
        case let .sticky(text, _, _):
            editingText = text
        default:
            return
        }
        selection = item.id
        editingItemID = item.id
    }

    /// Writes the typed text back to the object, then closes the editor.
    private func commitEditing() {
        guard let id = editingItemID else { return }
        let text = editingText
        editingItemID = nil
        editingText = ""
        guard var item = board.item(id) else { return }

        switch item.content {
        case let .text(old, frame, fontSize, color):
            guard old != text else { return }
            item.content = .text(text, frame: frame, fontSize: fontSize, color: color)
        case let .sticky(old, frame, color):
            guard old != text else { return }
            item.content = .sticky(text, frame: frame, color: color)
        default:
            return
        }

        item.updatedAt = Date()
        board.add(item)
        scheduleSave()
    }

    // MARK: - Dragging

    /// The drag a finger at `point` would start, if it lands on the selection.
    /// Asked at touch-down, so a finger that also draws can wait for it and
    /// ink anywhere else.
    private func dragTarget(at point: CGPoint) -> BoardItemDrag? {
        guard !editor.isReadOnly,
              editingItemID == nil,
              let item = selectedItem,
              let frame = item.frame,
              !item.isLocked
        else { return nil }

        let zoom = max(viewport.zoom, 0.001)
        if let corner = BoardResizeCorner.corner(at: point, in: frame, tolerance: 22 / zoom) {
            return BoardItemDrag(
                itemID: item.id,
                frame: frame,
                corner: corner,
                keepsSquare: isSticky(item)
            )
        }

        guard frame.insetBy(dx: -2 / zoom, dy: -2 / zoom).contains(point) else {
            return nil
        }
        return BoardItemDrag(itemID: item.id, frame: frame, corner: nil, keepsSquare: false)
    }

    private func beginDrag(at point: CGPoint) -> Bool {
        guard let target = dragTarget(at: point) else { return false }
        drag = target
        dragMoved = false
        return true
    }

    private func dragChanged(_ translation: CGPoint) {
        guard let drag else { return }
        dragMoved = true
        let now = Date()

        if let corner = drag.corner {
            let frame = Self.resized(
                drag.frame,
                corner: corner,
                by: translation,
                keepsSquare: drag.keepsSquare
            )
            board.setFrame(drag.itemID, to: frame, at: now)
            snapGuides = []
        } else {
            var frame = drag.frame
            frame.origin.x += translation.x
            frame.origin.y += translation.y
            let snapped = Self.snapped(
                frame,
                items: board.visibleItems,
                ignoring: drag.itemID,
                tolerance: 6 / max(viewport.zoom, 0.001)
            )
            board.setFrame(drag.itemID, to: snapped.frame, at: now)
            snapGuides = snapped.guides
        }

        scheduleSave()
    }

    private func endDrag() {
        let moved = dragMoved && drag != nil
        drag = nil
        dragMoved = false
        snapGuides = []
        if moved {
            scheduleSave()
        }
    }

    private static func resized(
        _ frame: CGRect,
        corner: BoardResizeCorner,
        by translation: CGPoint,
        keepsSquare: Bool
    ) -> CGRect {
        let minimum: CGFloat = 40
        var width = max(
            minimum,
            corner.isLeft ? frame.width - translation.x : frame.width + translation.x
        )
        var height = max(
            minimum,
            corner.isTop ? frame.height - translation.y : frame.height + translation.y
        )
        if keepsSquare {
            let side = max(width, height)
            width = side
            height = side
        }
        let anchorX = corner.isLeft ? frame.maxX : frame.minX
        let anchorY = corner.isTop ? frame.maxY : frame.minY
        return CGRect(
            x: corner.isLeft ? anchorX - width : anchorX,
            y: corner.isTop ? anchorY - height : anchorY,
            width: width,
            height: height
        )
    }

    private struct SnapOutcome {
        var frame: CGRect
        var guides: [BoardSnapGuide]
    }

    /// Pulls a dragged frame onto another item's edges or centres when it is
    /// within `tolerance` world points, and reports the guide lines to draw.
    private static func snapped(
        _ frame: CGRect,
        items: [BoardItem],
        ignoring itemID: UUID,
        tolerance: CGFloat
    ) -> SnapOutcome {
        let frames = items.compactMap { item -> CGRect? in
            guard item.id != itemID else { return nil }
            return item.frame
        }
        guard !frames.isEmpty else {
            return SnapOutcome(frame: frame, guides: [])
        }

        let xTargets = frames.flatMap { [$0.minX, $0.midX, $0.maxX] }
        let yTargets = frames.flatMap { [$0.minY, $0.midY, $0.maxY] }
        var result = frame
        var guides: [BoardSnapGuide] = []

        if let snap = nearestSnap(
            edges: [frame.minX, frame.midX, frame.maxX],
            targets: xTargets,
            tolerance: tolerance
        ) {
            result.origin.x += snap.delta
            guides.append(BoardSnapGuide(axis: .vertical, position: snap.line))
        }
        if let snap = nearestSnap(
            edges: [frame.minY, frame.midY, frame.maxY],
            targets: yTargets,
            tolerance: tolerance
        ) {
            result.origin.y += snap.delta
            guides.append(BoardSnapGuide(axis: .horizontal, position: snap.line))
        }
        return SnapOutcome(frame: result, guides: guides)
    }

    private static func nearestSnap(
        edges: [CGFloat],
        targets: [CGFloat],
        tolerance: CGFloat
    ) -> (delta: CGFloat, line: CGFloat)? {
        var best: (delta: CGFloat, line: CGFloat)?
        for edge in edges {
            for target in targets {
                let delta = target - edge
                guard abs(delta) <= tolerance else { continue }
                if abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, target)
                }
            }
        }
        return best
    }

    // MARK: - Insert

    /// The middle of what the board is showing, in world points.
    private var insertionCenter: CGPoint? {
        guard viewport.isReady else { return nil }
        return CGPoint(x: viewport.visibleRect.midX, y: viewport.visibleRect.midY)
    }

    private var nextZIndex: Int {
        (board.visibleItems.map(\.zIndex).max() ?? 0) + 1
    }

    private func centeredFrame(size: CGSize) -> CGRect? {
        guard let center = insertionCenter else { return nil }
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Adds an object in the middle of the view, selects it, and springs it in.
    private func addNewItem(_ item: BoardItem) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            board.add(item)
            selection = item.id
        }
        scheduleSave()
    }

    private func insertSticky() {
        guard let frame = centeredFrame(size: boardStickySize) else { return }
        let item = BoardItem(
            zIndex: nextZIndex,
            content: .sticky("", frame: frame, color: BoardStickyPalette.defaultColor)
        )
        addNewItem(item)
        beginEditing(item)
    }

    private func insertText() {
        guard let frame = centeredFrame(size: CGSize(width: 320, height: 88)) else { return }
        let item = BoardItem(
            zIndex: nextZIndex,
            content: .text("", frame: frame, fontSize: 18, color: .black)
        )
        addNewItem(item)
        beginEditing(item)
    }

    private func insertShape(_ kind: BoardShapeKind) {
        let size = kind == .line || kind == .arrow
            ? CGSize(width: 220, height: 60)
            : CGSize(width: 200, height: 200)
        guard let frame = centeredFrame(size: size) else { return }
        let item = BoardItem(
            zIndex: nextZIndex,
            content: .shape(
                kind: kind,
                frame: frame,
                strokeColor: RGBAColor(r: 0.13, g: 0.16, b: 0.22),
                fillColor: nil,
                lineWidth: 3
            )
        )
        addNewItem(item)
    }

    private func insertImage(from pickerItem: PhotosPickerItem) async {
        guard let data = try? await pickerItem.loadTransferable(type: Data.self) else {
            return
        }
        let fileExtension = pickerItem.supportedContentTypes.first?.preferredFilenameExtension
            ?? "png"
        let pixels = ImageSizeReader.size(of: data) ?? CGSize(width: 1_000, height: 1_000)
        let ratio = min(
            480 / max(pixels.width, 1),
            480 / max(pixels.height, 1),
            1
        )
        let size = CGSize(
            width: max(pixels.width * ratio, 40),
            height: max(pixels.height * ratio, 40)
        )
        guard let frame = centeredFrame(size: size) else { return }

        do {
            let assetName = try await model.addAsset(data, fileExtension: fileExtension)
            addNewItem(
                BoardItem(
                    zIndex: nextZIndex,
                    content: .image(assetName: assetName, frame: frame)
                )
            )
        } catch {
            model.lastError = error.localizedDescription
        }
    }

    // MARK: - Object commands

    private func duplicateSelected() {
        guard let item = selectedItem, item.frame != nil else { return }
        var copy = item
        let now = Date()
        copy.id = UUID()
        copy.createdAt = now
        copy.updatedAt = now
        copy.zIndex = nextZIndex
        copy.isLocked = false
        copy.content = Self.translated(item.content, by: CGPoint(x: 24, y: 24))

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            board.add(copy)
            selection = copy.id
        }
        scheduleSave()
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        if editingItemID == id {
            editingItemID = nil
            editingText = ""
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            board.remove(id)
            selection = nil
        }
        snapGuides = []
        scheduleSave()
    }

    private func bringSelectionToFront() {
        guard var item = selectedItem else { return }
        item.zIndex = nextZIndex
        item.updatedAt = Date()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            board.add(item)
        }
        scheduleSave()
    }

    private func sendSelectionToBack() {
        guard var item = selectedItem else { return }
        item.zIndex = (board.visibleItems.map(\.zIndex).min() ?? 0) - 1
        item.updatedAt = Date()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            board.add(item)
        }
        scheduleSave()
    }

    private func setColor(_ color: RGBAColor) {
        guard var item = selectedItem else { return }
        switch item.content {
        case let .sticky(text, frame, _):
            item.content = .sticky(text, frame: frame, color: color)
        case let .shape(kind, frame, _, fillColor, lineWidth):
            item.content = .shape(
                kind: kind,
                frame: frame,
                strokeColor: color,
                fillColor: fillColor,
                lineWidth: lineWidth
            )
        default:
            return
        }
        item.updatedAt = Date()
        board.add(item)
        scheduleSave()
    }

    /// Sets or clears a shape's fill, leaving its line colour alone.
    private func setFillColor(_ color: RGBAColor?) {
        guard var item = selectedItem,
              case let .shape(kind, frame, strokeColor, _, lineWidth) = item.content
        else { return }
        item.content = .shape(
            kind: kind,
            frame: frame,
            strokeColor: strokeColor,
            fillColor: color,
            lineWidth: lineWidth
        )
        item.updatedAt = Date()
        board.add(item)
        scheduleSave()
    }
}
#endif
