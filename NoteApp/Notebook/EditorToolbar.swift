#if os(iOS)
import InkKit
import NoteCore
import SwiftUI

/// The editor's single toolbar row.
///
/// Left (pinned): back, thumbnails, undo, redo. Centre: tools. Right: colour
/// swatches and widths. The More menu is pinned at the trailing edge. When the
/// row is too narrow (split view) only the tools and colours scroll.
struct EditorToolbar<InsertMenu: View, MoreMenu: View>: View {
    @Bindable var editor: EditorToolState
    let controller: PencilCanvasController
    @Binding var showsThumbnails: Bool
    let isRecording: Bool
    let recordingLabel: String
    let onBack: () -> Void
    let onStopRecording: () -> Void
    /// Opens the notebook's Clear Page confirmation.
    let onClearPage: () -> Void
    @ViewBuilder let insertMenu: () -> InsertMenu
    @ViewBuilder let moreMenu: () -> MoreMenu

    @State private var popover: ToolPopover?

    private enum ToolPopover: Hashable {
        case pen, highlighter, eraser, laser
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
            ToolbarDivider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    scrollingContent
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    scrollingContent
                }
            }
            .frame(maxWidth: .infinity)
            ToolbarDivider()
            trailing
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
        .background(.bar)
        .background(alignment: .topLeading) { toolShortcuts }
        .onChange(of: editor.paletteRequestID) {
            popover = .pen
        }
    }

    /// One key per tool, so the tools work with a hardware keyboard. The
    /// buttons are invisible: the real toolbar buttons keep the visible state,
    /// and a shortcut selects a tool, it never opens a popover. A focused text
    /// field takes the keys first, as it should.
    private var toolShortcuts: some View {
        Group {
            shortcut(.lasso, "v")
            shortcut(.pen, "p")
            shortcut(.highlighter, "h")
            shortcut(.eraser, "e")
            shortcut(.laser, "l")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .disabled(editor.isReadOnly)
    }

    private func shortcut(_ tool: EditorTool, _ key: KeyEquivalent) -> some View {
        Button(tool.displayName) {
            editor.tool = tool
        }
        .keyboardShortcut(key, modifiers: [])
    }

    // MARK: - Pinned groups

    private var leading: some View {
        HStack(spacing: 2) {
            ToolbarIconButton("Library", systemImage: "chevron.backward", action: onBack)
            ToolbarIconButton(
                showsThumbnails ? "Hide Pages" : "Show Pages",
                systemImage: showsThumbnails ? "rectangle.bottomthird.inset.filled" : "rectangle"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { showsThumbnails.toggle() }
            }
            ToolbarIconButton("Undo", systemImage: "arrow.uturn.backward") {
                controller.undo()
            }
            .disabled(!controller.canUndo || editor.isReadOnly)
            .keyboardShortcut("z", modifiers: .command)
            ToolbarIconButton("Redo", systemImage: "arrow.uturn.forward") {
                controller.redo()
            }
            .disabled(!controller.canRedo || editor.isReadOnly)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    private var trailing: some View {
        HStack(spacing: 2) {
            readOnlyButton
            if isRecording {
                Button(action: onStopRecording) {
                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text(recordingLabel)
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording, \(recordingLabel)")
            }
            Menu {
                moreMenu()
            } label: {
                ToolbarIcon(systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
    }

    /// Reading a notebook: the tools go away and nothing can be drawn or
    /// edited, but pages still scroll, zoom and follow PDF links.
    private var readOnlyButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                editor.isReadOnly.toggle()
            }
        } label: {
            if editor.isReadOnly {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                    Text("Read Only")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .foregroundStyle(Color.white)
                .background(Color.accentColor, in: Capsule())
                .contentShape(Rectangle())
            } else {
                ToolbarIcon(systemImage: "lock.doc")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(editor.isReadOnly ? "Read Only, on" : "Read Only")
        .accessibilityHint(editor.isReadOnly ? "Turns editing back on" : "Hides the tools and stops editing")
        .help(editor.isReadOnly ? "Read Only: tap to edit again" : "Read Only: hide the tools and stop editing")
    }

    // MARK: - Tools and colours

    private var scrollingContent: some View {
        HStack(spacing: 2) {
            tools
            ToolbarDivider()
            swatches
            ToolbarDivider()
            widths
        }
        .padding(.horizontal, 4)
        .disabled(editor.isReadOnly)
    }

    private var tools: some View {
        HStack(spacing: 2) {
            penChip
            highlighterButton
            eraserButton
            ToolbarIconButton(
                "Lasso",
                systemImage: "lasso",
                isSelected: editor.tool == .lasso,
                help: "Lasso (V): circle ink, then drag it to move"
            ) {
                editor.tool = .lasso
            }
            laserButton
            ToolbarIconButton(
                "Select Elements",
                systemImage: "cursorarrow.rays",
                isSelected: editor.tool == .elements
            ) {
                editor.tool = .elements
            }
            .help("Move, resize or delete text, images and shapes")
            Menu {
                insertMenu()
            } label: {
                ToolbarIcon(systemImage: "plus.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Insert")
            .help("Insert text, image or shape")
            ToolbarIconButton(
                "Follow Links",
                systemImage: "hand.point.up.left",
                isSelected: editor.tool == .links
            ) {
                editor.tool = .links
            }
            .help("Tap links in imported PDFs")
        }
    }

    /// Tapping an inactive tool selects it; tapping the active one opens its settings.
    private func select(_ tool: EditorTool, popover kind: ToolPopover) {
        if editor.tool == tool {
            popover = kind
        } else {
            editor.tool = tool
        }
    }

    private var penChip: some View {
        let pen = editor.penTool
        let isSelected = editor.tool == .pen
        return Button {
            select(.pen, popover: .pen)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: editor.penStyle.symbolName)
                    .font(.system(size: 17, weight: .medium))
                Circle()
                    .fill(Color(pen.color))
                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5))
                    .overlay(Circle().strokeBorder(.secondary.opacity(isSelected ? 0 : 0.35), lineWidth: 0.5))
                    .frame(width: dotSize(pen.width, range: 1...40), height: dotSize(pen.width, range: 1...40))
                    .frame(width: 18, height: 18)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 36)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(editor.penStyle.displayName), current pen")
        .accessibilityHint(isSelected ? "Opens pen settings" : "Selects the pen")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("Pen (P): tap again for pen styles")
        .popover(isPresented: popoverBinding(.pen)) {
            PenSettingsPopover(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var highlighterButton: some View {
        ToolbarIconButton(
            "Highlighter",
            systemImage: "highlighter",
            isSelected: editor.tool == .highlighter,
            help: "Highlighter (H): tap again for width"
        ) {
            select(.highlighter, popover: .highlighter)
        }
        .popover(isPresented: popoverBinding(.highlighter)) {
            WidthSettingsPopover(title: "Highlighter", editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var eraserButton: some View {
        ToolbarIconButton(
            editor.eraserKind == .stroke ? "Stroke Eraser" : "Pixel Eraser",
            systemImage: editor.eraserKind == .stroke ? "eraser" : "eraser.line.dashed",
            isSelected: editor.tool == .eraser,
            help: "Eraser (E): tap again for size, filter and Auto-Deselect"
        ) {
            select(.eraser, popover: .eraser)
        }
        .contextMenu {
            Button("Stroke Eraser", systemImage: "eraser") { editor.setEraser(kind: .stroke) }
            Button("Pixel Eraser", systemImage: "eraser.line.dashed") { editor.setEraser(kind: .pixel) }
        }
        .popover(isPresented: popoverBinding(.eraser)) {
            EraserSettingsPopover(editor: editor) {
                popover = nil
                onClearPage()
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var laserButton: some View {
        ToolbarIconButton(
            "Laser Pointer",
            systemImage: "cursorarrow",
            isSelected: editor.tool == .laser,
            help: "Laser Pointer (L): tap again for Dot or Line"
        ) {
            select(.laser, popover: .laser)
        }
        .popover(isPresented: popoverBinding(.laser)) {
            LaserSettingsPopover(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func popoverBinding(_ kind: ToolPopover) -> Binding<Bool> {
        Binding(
            get: { popover == kind },
            set: { if !$0, popover == kind { popover = nil } }
        )
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(Array(editor.swatches.enumerated()), id: \.offset) { _, color in
                let isSelected = editor.tool.drawsInk && editor.isCurrentColor(color)
                Button {
                    editor.setColor(color)
                } label: {
                    Circle()
                        .fill(Color(color))
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
                        .frame(width: 24, height: 24)
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                        }
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            ColorPicker(
                "Custom colour",
                selection: Binding(
                    get: { Color(editor.inkTool.color) },
                    set: { editor.setColor(RGBAColor($0)) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 44, height: 44)
            .accessibilityLabel("Custom colour")
        }
    }

    private var widths: some View {
        let presets = editor.widthPresets
        let current = editor.currentWidth
        let nearest = presets.indices.min { abs(presets[$0] - current) < abs(presets[$1] - current) }
        let isApplicable = editor.tool.drawsInk || editor.tool == .eraser
        return HStack(spacing: 0) {
            ForEach(presets.indices, id: \.self) { index in
                let isSelected = isApplicable && index == nearest
                    && abs(presets[index] - current) < max(0.5, current * 0.05)
                Button {
                    editor.setWidth(presets[index])
                } label: {
                    Circle()
                        .fill(isSelected ? Color.white : Color.primary)
                        .frame(width: CGFloat(5 + index * 4), height: CGFloat(5 + index * 4))
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                        .frame(width: 38, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(["Thin", "Medium", "Thick"][min(index, 2)])
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .opacity(isApplicable ? 1 : 0.4)
    }

    private func dotSize(_ width: Double, range: ClosedRange<Double>) -> CGFloat {
        let fraction = (width - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(7 + min(max(fraction, 0), 1) * 11)
    }
}

// MARK: - Popovers

private struct PenSettingsPopover: View {
    @Bindable var editor: EditorToolState

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pen")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PenStyle.allCases, id: \.self) { style in
                    let isSelected = editor.penStyle == style
                    Button {
                        editor.selectPenStyle(style)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.symbolName)
                                .font(.system(size: 20))
                                .frame(height: 26)
                            Text(style.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            WidthSlider(editor: editor)
        }
        .padding(16)
        .frame(width: 320)
    }
}

private struct WidthSettingsPopover: View {
    let title: String
    @Bindable var editor: EditorToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            WidthSlider(editor: editor)
        }
        .padding(16)
        .frame(width: 280)
    }
}

private struct WidthSlider: View {
    @Bindable var editor: EditorToolState
    /// Shown while dragging; written to the editor (and so to disk, debounced)
    /// only when the drag ends.
    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Width")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f pt", draft ?? editor.inkTool.width))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { draft ?? editor.inkTool.width },
                    set: { draft = $0 }
                ),
                in: editor.inkWidthRange
            ) { isEditing in
                if !isEditing, let draft {
                    editor.setWidth(draft)
                    self.draft = nil
                }
            }
            .accessibilityLabel("Width")
        }
    }
}

private struct EraserSettingsPopover: View {
    @Bindable var editor: EditorToolState
    let onClearPage: () -> Void
    @AppStorage(EditorToolState.eraserAutoDeselectKey) private var autoDeselect = false
    @AppStorage(AppSettings.Key.eraserHighlighterOnly) private var highlighterOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Eraser")
                .font(.headline)
            Picker("Eraser", selection: Binding(
                get: { editor.eraserKind },
                set: { editor.setEraser(kind: $0) }
            )) {
                Text("Whole Stroke").tag(EraserMode.stroke)
                Text("Pixel").tag(EraserMode.pixel)
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 6) {
                Text("Size")
                    .font(.subheadline)
                HStack(spacing: 8) {
                    ForEach(EditorToolState.eraserWidths, id: \.self) { width in
                        let isSelected = abs(editor.eraserWidth - width) < 0.5
                        Button {
                            editor.setEraserWidth(width)
                        } label: {
                            Circle()
                                .strokeBorder(isSelected ? Color.white : Color.primary, lineWidth: 1.5)
                                .frame(width: 6 + width / 2.4, height: 6 + width / 2.4)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Int(width)) point eraser")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Erase Highlighter Only", isOn: $highlighterOnly)
                    .font(.subheadline)
                    .disabled(editor.eraserKind != .stroke)
                    .accessibilityHint("Only highlighter strokes disappear when erasing")
                Text("Leaves pen ink in place. Works with the whole-stroke eraser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Auto-Deselect", isOn: $autoDeselect)
                    .font(.subheadline)
                    .accessibilityHint("Switches back to the previous tool after erasing")
                Text("Goes back to the previous tool after erasing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Clear Page…", systemImage: "trash", role: .destructive) {
                onClearPage()
            }
            .font(.subheadline)
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// Dot or Line, and a preview of what the pointer does.
private struct LaserSettingsPopover: View {
    @Bindable var editor: EditorToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Laser Pointer")
                .font(.headline)
            Picker("Laser pointer", selection: Binding(
                get: { editor.laserMode },
                set: { editor.setLaserMode($0) }
            )) {
                ForEach(LaserMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            LaserPointerPreview(mode: editor.laserMode)
                .frame(height: 54)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("The pointer never marks the page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// A still sample of the laser: a dot, or a stroke that fades at its tail.
private struct LaserPointerPreview: View {
    let mode: LaserMode

    var body: some View {
        Canvas { context, size in
            let red = Color(red: 0.93, green: 0.12, blue: 0.16)
            if mode == .dot {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                func circle(_ radius: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                }
                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.fill(circle(10), with: .color(red.opacity(0.8)))
                context.fill(circle(4.5), with: .color(red))
            } else {
                var path = Path()
                path.move(to: CGPoint(x: 24, y: size.height * 0.7))
                path.addCurve(
                    to: CGPoint(x: size.width - 24, y: size.height * 0.35),
                    control1: CGPoint(x: size.width * 0.35, y: size.height * 0.05),
                    control2: CGPoint(x: size.width * 0.6, y: size.height * 0.95)
                )
                var glow = context
                glow.addFilter(.blur(radius: 7))
                glow.stroke(path, with: .color(red.opacity(0.85)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                context.stroke(path, with: .color(red), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Building blocks

struct ToolbarIcon: View {
    let systemImage: String
    var isSelected = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 40, height: 36)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    /// Tooltip text; defaults to the accessibility title.
    var help: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        systemImage: String,
        isSelected: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ToolbarIcon(systemImage: systemImage, isSelected: isSelected)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(help ?? title)
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: 24)
            .padding(.horizontal, 4)
    }
}
#endif
