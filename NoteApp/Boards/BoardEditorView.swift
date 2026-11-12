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

/// One board on a large fixed page, with the notebook's PencilKit canvas and
/// zoom/pan host reused as-is.
///
/// All ink lives in a single `.ink(strokes:)` item so this pass can add text,
/// shapes and connectors later without changing the on-disk shape. The ink
/// layer ID is stable so every new stroke belongs to the same layer.
struct BoardEditorView: View {
    /// Temporary board page size for v1. Large enough to feel like an infinite
    /// canvas while keeping the saved page and rendering cheap.
    static let boardSize = CGSize(width: 3_000, height: 3_000)
    /// Stable layer for every stroke drawn on a board.
    static let inkLayerID = UUID(uuidString: "B0A2D000-0000-4000-8000-000000000001")!
    /// Stable item ID used when a board has no ink item yet.
    static let defaultInkItemID = UUID(uuidString: "B0A2D000-0000-4000-8000-000000000002")!

    let model: BoardModel

    @State private var board: Board
    @State private var tool = InkTool.pen
    @State private var presets = PenPresets()
    @State private var isSaving = false
    @State private var hasUnsavedChanges = false
    @State private var saveGeneration = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var undoRevision = 0
    /// The camera on disk when the board opened, so Done can skip writes that
    /// would only bump the modified date.
    @State private var savedCamera: BoardCamera?
    @State private var didRestoreCamera = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    @State private var canvasMode: CanvasMode = .ink
    @State private var controller = PencilCanvasController()
    @State private var zoomController = PageZoomController()
    #endif

    init(model: BoardModel, board: Board) {
        self.model = model
        _board = State(initialValue: board)
        let presets = PenPresets.load()
        _presets = State(initialValue: presets)
        _tool = State(initialValue: presets.tool(for: .pen))
    }

    var body: some View {
        NavigationStack {
            canvasArea
                .safeAreaInset(edge: .bottom) {
                    #if os(iOS)
                    toolBar
                    #endif
                }
                .navigationTitle(board.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
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
                .onDisappear { flush() }
                #if os(iOS)
                .onAppear { normalizeWidth() }
                #endif
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
        ZoomablePageView(pageSize: Self.boardSize, controller: zoomController) {
            pageContent
        }
        .background(AppColor.groupedBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        macCanvas
        #endif
    }

    #if os(iOS)
    private var pageContent: some View {
        ZStack(alignment: .topLeading) {
            BoardPaper(size: Self.boardSize)

            PencilCanvasView(
                strokes: inkStrokes,
                pageSize: Self.boardSize,
                tool: tool,
                mode: canvasMode,
                activeLayerID: Self.inkLayerID,
                isEditable: true,
                controller: controller,
                onStrokesChanged: { strokesChanged($0) }
            )
            .id(board.id)
        }
        .frame(width: Self.boardSize.width, height: Self.boardSize.height)
    }
    #endif

    #if os(macOS)
    private var macCanvas: some View {
        GeometryReader { proxy in
            let image = PageRenderer.image(
                strokes: inkStrokes,
                pageSize: Self.boardSize,
                template: .blank,
                scale: 1
            )

            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(36)
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                } else {
                    ContentUnavailableView {
                        Label("Board unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The board image could not be rendered.")
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AppColor.groupedBackground)
    }
    #endif

    // MARK: - Pencil bar

    #if os(iOS)
    /// The drawing controls. Sized for a Pencil-and-finger session: 44 pt
    /// targets, visible colour and width state, and one row that scrolls rather
    /// than clips in a narrow Split View.
    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                group {
                    drawingButton("pencil.tip", label: "Pen", isActive: isPenActive) {
                        selectPen()
                    }
                    drawingButton("highlighter", label: "Highlighter", isActive: isHighlighterActive) {
                        selectHighlighter()
                    }
                    drawingButton("eraser", label: "Eraser", isActive: isErasing) {
                        canvasMode = .eraser(.stroke, width: 12)
                    }
                }

                divider

                group {
                    ForEach(Array(Self.swatchColors.enumerated()), id: \.offset) { _, color in
                        swatchButton(color)
                    }
                    ColorPicker("Ink colour", selection: inkColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Ink colour")
                }

                divider

                group {
                    ForEach(Array(widthChoices.enumerated()), id: \.offset) { index, _ in
                        widthButton(index)
                    }
                }

                divider

                group {
                    drawingButton("arrow.uturn.backward", label: "Undo", isActive: false) {
                        controller.undo()
                        undoRevision += 1
                    }
                    .disabled(!canUndo)
                    .opacity(canUndo ? 1 : 0.35)

                    drawingButton("arrow.uturn.forward", label: "Redo", isActive: false) {
                        controller.redo()
                        undoRevision += 1
                    }
                    .disabled(!canRedo)
                    .opacity(canRedo ? 1 : 0.35)
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(height: 52)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
    }

    private var divider: some View {
        Divider()
            .frame(height: 26)
            .padding(.horizontal, 4)
    }

    private func drawingButton(
        _ symbol: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 44, height: 44)
                .background(
                    isActive ? Color.accentColor.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(label)
    }

    private func swatchButton(_ swatch: RGBAColor) -> some View {
        let isSelected = colorMatches(tool.color, swatch)
        return Button {
            selectColor(Color(swatch))
        } label: {
            ZStack {
                Circle()
                    .fill(Color(swatch))
                    .frame(width: 24, height: 24)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                }
            }
            .frame(width: 44, height: 44)
            .background(
                isSelected ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ink colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func widthButton(_ index: Int) -> some View {
        let sizes = widthChoices
        let width = sizes.indices.contains(index) ? sizes[index] : tool.width
        let isSelected = abs(tool.width - width) < 0.51
        return Button {
            setWidth(width)
        } label: {
            Circle()
                .fill(Color(tool.color))
                .frame(width: min(18, max(5, width * 1.05)), height: min(18, max(5, width * 1.05)))
                .frame(width: 44, height: 44)
                .background(
                    isSelected ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Width \(Int(width))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var widthChoices: [Double] {
        tool.isHighlighter ? [12, 24, 36] : [3, 8, 16]
    }

    private func colorMatches(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Bool {
        abs(lhs.r - rhs.r) < 0.02 && abs(lhs.g - rhs.g) < 0.02 && abs(lhs.b - rhs.b) < 0.02
    }

    private static let swatchColors: [RGBAColor] = [
        RGBAColor(r: 0.08, g: 0.08, b: 0.09),
        RGBAColor(r: 0.10, g: 0.36, b: 0.86),
        RGBAColor(r: 0.85, g: 0.16, b: 0.16),
        RGBAColor(r: 0.13, g: 0.60, b: 0.36),
        RGBAColor(r: 0.95, g: 0.56, b: 0.12),
    ]

    private var inkColorBinding: Binding<Color> {
        Binding(
            get: { Color(tool.color) },
            set: { selectColor($0) }
        )
    }

    private func selectColor(_ color: Color) {
        var updated = tool
        var rgba = RGBAColor(color)
        if tool.isHighlighter {
            // A highlighter stays translucent whatever the picker returns.
            rgba.a = min(rgba.a, 0.4)
        } else {
            rgba.a = 1
        }
        updated.color = rgba
        canvasMode = .ink
        apply(updated)
    }

    private func setWidth(_ width: Double) {
        var updated = tool
        updated.width = width
        canvasMode = .ink
        apply(updated)
    }

    private func selectPen() {
        canvasMode = .ink
        tool = presets.tool(for: .pen)
    }

    private func selectHighlighter() {
        canvasMode = .ink
        tool = presets.highlighter
    }

    private func apply(_ updated: InkTool) {
        tool = updated
        presets.update(updated)
        presets.save()
    }

    /// Keeps one width button selected when a stored preset uses an older
    /// default width, so the control never looks unset.
    private func normalizeWidth() {
        guard !widthChoices.contains(where: { abs($0 - tool.width) < 0.51 }) else { return }
        var updated = tool
        updated.width = widthChoices[1]
        apply(updated)
    }

    private var isPenActive: Bool {
        canvasMode == .ink && !tool.isHighlighter
    }

    private var isHighlighterActive: Bool {
        canvasMode == .ink && tool.isHighlighter
    }

    private var isErasing: Bool {
        if case .eraser = canvasMode { return true }
        return false
    }

    private var canUndo: Bool {
        _ = undoRevision
        return controller.canUndo
    }

    private var canRedo: Bool {
        _ = undoRevision
        return controller.canRedo
    }

    /// Uses the live scroll bounds rather than the controller's cached fit so
    /// the button keeps working after an iPad rotation.
    private func fittedScale(for scroll: UIScrollView) -> CGFloat {
        guard scroll.bounds.width > 1, scroll.bounds.height > 1 else {
            return zoomController.fitScale
        }
        return min(
            scroll.bounds.width / Self.boardSize.width,
            scroll.bounds.height / Self.boardSize.height
        )
    }

    private func fitBoard() {
        guard let scroll = zoomController.scrollView else { return }
        scroll.setZoomScale(fittedScale(for: scroll), animated: true)
    }

    /// Resets the scroll view to the fitted scale and puts the page centre in
    /// the middle of the viewport. A negative offset is correct when the page is
    /// smaller than the viewport, because the scroll view's insets centre it.
    private func centerCamera() {
        guard let scroll = zoomController.scrollView else { return }
        let scale = max(fittedScale(for: scroll), 0.0001)
        scroll.setZoomScale(scale, animated: false)
        scroll.layoutIfNeeded()
        scroll.setContentOffset(
            CGPoint(
                x: (scroll.contentSize.width - scroll.bounds.width) / 2,
                y: (scroll.contentSize.height - scroll.bounds.height) / 2
            ),
            animated: false
        )
    }

    // MARK: Camera

    /// Applies the saved viewport once the page host has a size. The page fits
    /// itself on its first layout, so the camera is applied just after that.
    private func restoreCameraIfNeeded() async {
        guard !didRestoreCamera else { return }
        defer { didRestoreCamera = true }

        guard let camera = savedCamera else { return }
        for _ in 0..<40 {
            if let scroll = zoomController.scrollView,
               scroll.bounds.width > 1,
               scroll.bounds.height > 1 {
                scroll.layoutIfNeeded()
                apply(camera, to: scroll)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func apply(_ camera: BoardCamera, to scroll: UIScrollView) {
        let scale = CGFloat(camera.zoom)
        scroll.setZoomScale(scale, animated: false)
        scroll.layoutIfNeeded()

        let maxX = max(scroll.contentSize.width - scroll.bounds.width, 0)
        let maxY = max(scroll.contentSize.height - scroll.bounds.height, 0)
        let x = CGFloat(camera.centerX) * scale - scroll.bounds.width / 2
        let y = CGFloat(camera.centerY) * scale - scroll.bounds.height / 2
        scroll.setContentOffset(
            CGPoint(x: min(max(x, 0), maxX), y: min(max(y, 0), maxY)),
            animated: false
        )
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

        ToolbarItemGroup(placement: .primaryAction) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            #if os(iOS)
            Button {
                fitBoard()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Fit board")
            .help("Fit board")

            Button {
                centerCamera()
            } label: {
                Image(systemName: "scope")
            }
            .accessibilityLabel("Center board")
            .help("Center board")
            #endif
        }
    }

    // MARK: - Ink

    private var inkItem: BoardItem? {
        board.items.first { item in
            if case .ink = item.content { return true }
            return false
        }
    }

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

        undoRevision += 1
        scheduleSave()
    }

    // MARK: - Saving

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveGeneration += 1
        let generation = saveGeneration
        saveTask?.cancel()

        let snapshot = board
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
        let snapshot = board
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
        guard hasUnsavedChanges else { return }
        let snapshot = board
        let camera = currentCamera
        Task {
            await model.save(snapshot, camera: camera)
        }
    }

    private var currentCamera: BoardCamera? {
        #if os(iOS)
        guard let scroll = zoomController.scrollView,
              scroll.bounds.width > 1,
              scroll.bounds.height > 1,
              scroll.zoomScale > 0
        else { return nil }

        let scale = scroll.zoomScale
        return BoardCamera(
            centerX: Double((scroll.contentOffset.x + scroll.bounds.width / 2) / scale),
            centerY: Double((scroll.contentOffset.y + scroll.bounds.height / 2) / scale),
            zoom: Double(scale)
        )
        #else
        return nil
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.clearError() } }
        )
    }
}

// MARK: - Paper

#if os(iOS)
/// White paper with a faint dot grid, drawn from one tiled image instead of
/// thousands of per-zoom `Canvas` dots.
private struct BoardPaper: View {
    let size: CGSize

    var body: some View {
        DotGridBackground()
            .frame(width: size.width, height: size.height)
            .overlay {
                Rectangle()
                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 2)
            }
    }
}

/// A static, tiled dot pattern. The tile is rendered once at 3× so the dots
/// stay crisp through the page's zoom range without redrawing.
private struct DotGridBackground: UIViewRepresentable {
    private static let spacing: CGFloat = 48
    private static let tileScale: CGFloat = 3

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(patternImage: Self.tile)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static let tile: UIImage = {
        let spacing = Self.spacing
        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.tileScale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: spacing, height: spacing),
            format: format
        )
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: spacing, height: spacing))

            let radius: CGFloat = 1.4
            UIColor(white: 0, alpha: 0.16).setFill()
            context.cgContext.fillEllipse(
                in: CGRect(
                    x: spacing - radius,
                    y: spacing - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }()
}
#endif
