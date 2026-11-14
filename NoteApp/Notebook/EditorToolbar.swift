#if os(iOS)
import InkKit
import NoteCore
import SwiftUI

/// The editor's single toolbar row.
///
/// Left (pinned): back, the notebook title, the Pages toggle, and Undo/Redo.
/// Centre: the pen chip and the customisable tool items, the colour well and
/// the overflow menu. Right: recording and the More menu. When the row is too
/// narrow for every tool the extra ones move into an overflow menu. Reading a
/// notebook hides the tools and shows a Read Only pill instead.
struct EditorToolbar<InsertMenu: View, MoreMenu: View, ItemMenu: View>: View {
    @Bindable var editor: EditorToolState
    /// Observed, so Undo/Redo follow the canvas's undo stack instead of staying
    /// greyed until an unrelated redraw.
    @ObservedObject var controller: PencilCanvasController
    @Binding var showsThumbnails: Bool
    /// The notebook's recording state and elapsed time. A view of its own
    /// reads it, so the 2 Hz timer redraws only the recording label. Nil on a
    /// board, which does not record.
    let audio: NotebookAudio?
    let onBack: () -> Void
    let onStopRecording: () -> Void
    /// Opens the notebook's Clear Page confirmation.
    let onClearPage: () -> Void
    /// Bound to the notebook's ruler, for the optional Ruler item.
    @Binding var isRulerActive: Bool
    /// Runs an optional item's existing action. Menu-style items use `itemMenu`.
    let onItemAction: (ToolbarItemID) -> Void
    let onCustomizeToolbar: () -> Void
    /// Page-only controls: thumbnails, Zoom View and PDF link following. A
    /// board shares every other tool but has no pages, zoom panel or links.
    var showsPageControls = true
    /// The element tool; a board has no element editing yet.
    var showsElementTool = true
    /// VoiceOver and tooltip label of the leading back button.
    var backLabel = "Library"
    /// The eraser popover's destructive action: a page in the notebook, the
    /// whole board on a board.
    var clearPageLabel = "Clear Page…"
    /// The notebook's name, shown as a menu right after Back. Nil on a board.
    var notebookTitle: String? = nil
    /// The notebook title menu's content: rename, duplicate, and so on.
    var titleMenu: AnyView? = nil
    @ViewBuilder let insertMenu: () -> InsertMenu
    @ViewBuilder let moreMenu: () -> MoreMenu
    @ViewBuilder let itemMenu: (ToolbarItemID) -> ItemMenu

    @AppStorage(ToolbarLayout.storageKey) private var layoutStorage = ToolbarLayout.defaultStorage
    @AppStorage(AppSettings.Key.pagesPanelOnLeft) private var pagesOnLeft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popover: ToolPopover?
    @State private var showsColorPopover = false
    @State private var showsFavoritePens = false
    @State private var showsZoomOptions = false

    private enum ToolPopover: Hashable {
        case pen, highlighter, eraser, laser
    }

    var body: some View {
        // No dividers between the edge groups and the centre: the centre takes
        // the slack, so a divider there would sit in the middle of an empty gap
        // in landscape. The gap itself separates the groups; the one divider
        // left sits between two tools that always touch (see `editingGroups`).
        HStack(spacing: AppSpacing.s) {
            leading
            centre
                .frame(maxWidth: .infinity)
            trailing
        }
        .padding(.horizontal, AppSpacing.s)
        .frame(height: 52)
        .background(.bar)
        .background {
            // Long-pressing an empty part of the bar opens the toolbar editor.
            Color.clear
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Customise Toolbar…", systemImage: "slider.horizontal.3") {
                        onCustomizeToolbar()
                    }
                }
        }
        .background(alignment: .topLeading) { toolShortcuts }
        .onChange(of: editor.paletteRequestID) {
            popover = nil
            showsColorPopover = true
        }
    }

    /// One key per tool, so the tools work with a hardware keyboard. The
    /// buttons are invisible: the real toolbar buttons keep the visible state,
    /// and a shortcut selects a tool, it never opens a popover. A focused text
    /// field takes the keys first, as it should. The keys work whether or not
    /// the item is shown in the toolbar.
    private var toolShortcuts: some View {
        Group {
            shortcut(.lasso, "v")
            shortcut(.pen, "p")
            shortcut(.highlighter, "h")
            shortcut(.eraser, "e")
            shortcut(.laser, "l")
            Button("Zoom View") {
                editor.isZoomViewShown.toggle()
            }
            .keyboardShortcut("z", modifiers: [])
            Button("Undo") {
                controller.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(editor.isReadOnly)
            Button("Redo") {
                controller.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(editor.isReadOnly)
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
        HStack(spacing: AppSpacing.xxs) {
            ToolbarIconButton(backLabel, systemImage: "chevron.backward", action: onBack)
            titleSlot
            if showsPageControls {
                pagesToggle
            }
            historyControls
        }
    }

    /// The notebook's name, opening its title menu. Nothing on a board, which
    /// has no title slot.
    @ViewBuilder
    private var titleSlot: some View {
        if let notebookTitle {
            if let titleMenu {
                Menu {
                    titleMenu
                } label: {
                    titleLabel(notebookTitle)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Notebook, \(notebookTitle)")
                .help("Notebook: \(notebookTitle)")
            } else {
                titleLabel(notebookTitle)
                    .accessibilityLabel("Notebook, \(notebookTitle)")
            }
        }
    }

    private func titleLabel(_ title: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
        }
        .frame(maxWidth: 240, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Shows or hides the pages panel. A plain toolbar icon, tinted when the
    /// panel is open: only the active drawing tool gets the filled treatment.
    private var pagesToggle: some View {
        Button {
            AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) { showsThumbnails.toggle() }
        } label: {
            Image(systemName: pagesOnLeft ? "sidebar.left" : "sidebar.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(showsThumbnails ? Color.accentColor : Color.primary)
                .frame(width: 40, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsThumbnails ? "Hide Pages" : "Show Pages")
        .accessibilityAddTraits(showsThumbnails ? .isSelected : [])
        .help(showsThumbnails ? "Hide the pages panel" : "Show the pages panel")
    }

    /// Undo and Redo sit at the leading edge, next to Back, when the layout
    /// includes them. A user who removes them in Customise Toolbar hides them.
    @ViewBuilder
    private var historyControls: some View {
        if !editor.isReadOnly, layout.hasHistoryItems {
            HStack(spacing: AppSpacing.xxs) {
                if layout.items.contains(.undo) {
                    historyButton(.undo)
                }
                if layout.items.contains(.redo) {
                    historyButton(.redo)
                }
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: AppSpacing.xxs) {
            RecordingLabelButton(audio: audio, onStop: onStopRecording)
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

    // MARK: - Centre

    @ViewBuilder
    private var centre: some View {
        if editor.isReadOnly {
            readOnlyPill
        } else {
            editingGroups
        }
    }

    /// Reading a notebook: the tools go away and nothing can be drawn or
    /// edited, but pages still scroll, zoom and follow PDF links.
    private var readOnlyPill: some View {
        Button {
            AppMotion.animate(AppMotion.quick, reduceMotion: reduceMotion) { editor.isReadOnly = false }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                Text("Read Only")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(Color.white)
            .background(Color.accentColor, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read Only, on")
        .accessibilityHint("Turns editing back on")
        .accessibilityAddTraits(.isSelected)
        .help("Read Only: tap to edit again")
    }

    private var editingGroups: some View {
        HStack(spacing: 0) {
            customisableTools
                .layoutPriority(1)
            ToolbarDivider()
            colorWell
        }
        .padding(.horizontal, AppSpacing.xxs)
    }

    // MARK: - Customisable tools

    private var layout: ToolbarLayout {
        ToolbarLayout(storage: layoutStorage)
    }

    /// The customisable tool items. Undo and Redo are in the layout too, but
    /// the leading group draws those.
    private var toolItems: [ToolbarItemID] {
        layout.toolItems
    }

    /// All the chosen items when they fit; otherwise the important ones plus a
    /// "More Tools" overflow menu. This group never scrolls.
    private var customisableTools: some View {
        ViewThatFits(in: .horizontal) {
            toolRow(toolItems, overflow: [])
            toolRow(priorityItems, overflow: overflowItems)
            toolRow(compactItems, overflow: compactOverflow)
            toolRow([], overflow: toolItems)
        }
    }

    private func toolRow(_ items: [ToolbarItemID], overflow: [ToolbarItemID]) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            penChip
            ForEach(items) { item in
                toolView(item)
            }
            if !overflow.isEmpty {
                overflowMenu(overflow)
            }
        }
    }

    /// The tool the current mode uses, when it is in the toolbar.
    private var activeToolItem: ToolbarItemID? {
        guard let item = ToolbarItemID(tool: editor.tool), toolItems.contains(item) else { return nil }
        return item
    }

    /// Pen chip, the two ink tools people switch between, and the active tool.
    private var priorityItems: [ToolbarItemID] {
        var priority: Set<ToolbarItemID> = [.highlighter, .eraser]
        if let active = activeToolItem { priority.insert(active) }
        return toolItems.filter { priority.contains($0) }
    }

    private var overflowItems: [ToolbarItemID] {
        toolItems.filter { !priorityItems.contains($0) }
    }

    /// A last resort: the pen chip, the active tool and the overflow menu.
    private var compactItems: [ToolbarItemID] {
        guard let active = activeToolItem, active != .highlighter, active != .eraser else { return [] }
        return [active]
    }

    private var compactOverflow: [ToolbarItemID] {
        toolItems.filter { !compactItems.contains($0) }
    }

    private func overflowMenu(_ items: [ToolbarItemID]) -> some View {
        Menu {
            ForEach(items) { item in
                overflowMenuItem(item)
            }
        } label: {
            ToolbarIcon(systemImage: "chevron.down.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More Tools")
        .help("More tools")
    }

    @ViewBuilder
    private func overflowMenuItem(_ item: ToolbarItemID) -> some View {
        switch item {
        case .insert:
            Menu(item.title, systemImage: item.systemImage) { insertMenu() }
        case .shapes:
            Menu(item.title, systemImage: item.systemImage) { itemMenu(item) }
        case .stickyNote:
            Menu(item.title, systemImage: item.systemImage) { itemMenu(item) }
        case .favoritePens:
            Menu(item.title, systemImage: item.systemImage) { favoritePensMenuItems }
        case .ruler:
            Toggle(item.title, systemImage: item.systemImage, isOn: $isRulerActive)
        case .undo, .redo:
            Button(item.title, systemImage: item.systemImage) {
                activate(item)
            }
            .disabled(editor.isReadOnly || !isHistoryStepAvailable(item))
        default:
            Button(item.title, systemImage: item.systemImage) {
                activate(item)
            }
        }
    }

    /// Recall a saved pen from the overflow menu; the star's popover lives in
    /// the toolbar row itself.
    @ViewBuilder
    private var favoritePensMenuItems: some View {
        ForEach(editor.favoritePens.pens) { pen in
            Button("\(pen.style.displayName), \(editor.colorName(for: pen.color))") {
                editor.recallPen(pen)
            }
        }
        if !editor.favoritePens.pens.isEmpty {
            Divider()
        }
        Button("Add Current Pen", systemImage: "plus") {
            editor.saveCurrentPen()
        }
        .disabled(editor.favoritePens.isFull || editor.isCurrentPenSaved)
    }

    /// One toolbar item, at its full size.
    @ViewBuilder
    private func toolView(_ item: ToolbarItemID) -> some View {
        switch item {
        case .highlighter:
            highlighterButton
        case .eraser:
            eraserButton
        case .lasso:
            lassoButton
        case .elements:
            if showsElementTool {
                elementsButton
            }
        case .insert:
            insertButton
        case .laser:
            laserButton
        case .zoomView:
            if showsPageControls {
                zoomViewButton
            }
        case .followLinks:
            if showsPageControls {
                followLinksButton
            }
        case .ruler:
            rulerButton
        case .shapes:
            shapesButton
        case .textBox, .image, .addPage, .search:
            plainItemButton(item)
        case .stickyNote:
            stickyNoteButton
        case .favoritePens:
            favoritePensButton
        case .undo, .redo:
            historyButton(item)
        }
    }

    /// Undo and Redo are plain buttons, not tool choices: they live at the
    /// leading edge and follow the canvas's undo stack.
    private func historyButton(_ item: ToolbarItemID) -> some View {
        ToolbarIconButton(item.title, systemImage: item.systemImage, help: item.title) {
            if item == .undo {
                controller.undo()
            } else {
                controller.redo()
            }
        }
        .disabled(editor.isReadOnly || !isHistoryStepAvailable(item))
    }

    private func isHistoryStepAvailable(_ item: ToolbarItemID) -> Bool {
        item == .undo ? controller.canUndo : controller.canRedo
    }

    /// Runs the item's existing action; used by the overflow menu too.
    private func activate(_ item: ToolbarItemID) {
        switch item {
        case .highlighter:
            editor.tool = .highlighter
        case .eraser:
            editor.tool = .eraser
        case .lasso:
            editor.tool = .lasso
        case .laser:
            editor.tool = .laser
        case .elements:
            editor.tool = .elements
        case .followLinks:
            editor.tool = .links
        case .zoomView:
            AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) { editor.isZoomViewShown.toggle() }
        case .ruler:
            isRulerActive.toggle()
        case .textBox, .image, .addPage, .search:
            onItemAction(item)
        case .undo:
            controller.undo()
        case .redo:
            controller.redo()
        case .insert, .shapes, .stickyNote, .favoritePens:
            break
        }
    }

    private var lassoButton: some View {
        ToolbarIconButton(
            "Lasso",
            systemImage: "lasso",
            isSelected: editor.tool == .lasso,
            help: "Lasso (V): circle ink, then drag it to move"
        ) {
            editor.tool = .lasso
        }
    }

    private var elementsButton: some View {
        ToolbarIconButton(
            "Select Objects",
            systemImage: "rectangle.and.hand.point.up.left",
            isSelected: editor.tool == .elements,
            help: "Move, resize or delete text, images and shapes"
        ) {
            editor.tool = .elements
        }
    }

    private var insertButton: some View {
        Menu {
            insertMenu()
        } label: {
            ToolbarIcon(systemImage: "plus.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Insert")
        .help("Insert text, image or shape")
    }

    private var followLinksButton: some View {
        ToolbarIconButton(
            "Follow Links",
            systemImage: "hand.point.up.left",
            isSelected: editor.tool == .links,
            help: "Tap links in imported PDFs"
        ) {
            editor.tool = .links
        }
    }

    private var rulerButton: some View {
        ToolbarIconButton(
            "Ruler",
            systemImage: "ruler",
            isSelected: isRulerActive,
            help: "Ruler: draw straight lines along its edge"
        ) {
            isRulerActive.toggle()
        }
    }

    private var shapesButton: some View {
        Menu {
            itemMenu(.shapes)
        } label: {
            ToolbarIcon(systemImage: ToolbarItemID.shapes.systemImage)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(ToolbarItemID.shapes.title)
        .help("Add a shape")
    }

    private var stickyNoteButton: some View {
        Menu {
            itemMenu(.stickyNote)
        } label: {
            ToolbarIcon(systemImage: ToolbarItemID.stickyNote.systemImage)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(ToolbarItemID.stickyNote.title)
        .help("Add a sticky note")
    }

    private func plainItemButton(_ item: ToolbarItemID) -> some View {
        ToolbarIconButton(item.title, systemImage: item.systemImage, help: item.title) {
            onItemAction(item)
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
            HStack(spacing: AppSpacing.s) {
                Image(systemName: editor.penStyle.symbolName)
                    .font(.system(size: 17, weight: .medium))
                Circle()
                    .fill(Color(pen.color))
                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5))
                    .overlay(Circle().strokeBorder(.secondary.opacity(isSelected ? 0 : 0.35), lineWidth: 0.5))
                    .frame(width: dotSize(pen.width, range: pen.widthRange), height: dotSize(pen.width, range: pen.widthRange))
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
        .help("Pen (P): tap again for pen styles, dashes and stabilisation")
        .popover(isPresented: popoverBinding(.pen)) {
            PenSettingsPopover(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Saves the current pen, and recalls, adds or deletes saved pens.
    private var favoritePensButton: some View {
        Button {
            showsFavoritePens = true
        } label: {
            ToolbarIcon(systemImage: editor.isCurrentPenSaved ? "star.fill" : "star")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Favourite Pens")
        .accessibilityHint("Saves this pen, or recalls one with its colour and width")
        .accessibilityAddTraits(editor.isCurrentPenSaved ? .isSelected : [])
        .help("Favourite pens: save this pen or recall a saved one")
        .popover(isPresented: $showsFavoritePens) {
            FavoritePensPopover(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var highlighterButton: some View {
        ToolbarIconButton(
            "Highlighter",
            systemImage: "highlighter",
            isSelected: editor.tool == .highlighter,
            help: "Highlighter (H): tap again for width, straight lines and stabilisation"
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
            EraserSettingsPopover(editor: editor, clearLabel: clearPageLabel) {
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

    /// Shows Zoom View; tapping it while shown opens its options, which can
    /// also close it (as the panel's own close button does).
    private var zoomViewButton: some View {
        ToolbarIconButton(
            "Zoom View",
            systemImage: "plus.magnifyingglass",
            isSelected: editor.isZoomViewShown,
            help: "Zoom View (Z): write in a magnified band. Tap again for options"
        ) {
            if editor.isZoomViewShown {
                showsZoomOptions = true
            } else {
                AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) { editor.isZoomViewShown = true }
            }
        }
        .popover(isPresented: $showsZoomOptions) {
            ZoomViewOptions {
                showsZoomOptions = false
                AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) { editor.isZoomViewShown = false }
            }
            .padding(AppSpacing.l)
            .frame(width: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func popoverBinding(_ kind: ToolPopover) -> Binding<Bool> {
        Binding(
            get: { popover == kind },
            set: { if !$0, popover == kind { popover = nil } }
        )
    }

    // MARK: - Colour

    /// The row's one colour control: a well showing the active ink tool's
    /// colour. Tapping it opens the favourite colours and the full palette.
    private var colorWell: some View {
        Button {
            popover = nil
            showsColorPopover = true
        } label: {
            Circle()
                .fill(Color(editor.inkTool.color))
                .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                .frame(width: 28, height: 28)
                .hitTarget()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour, \(editor.colorName(for: editor.inkTool.color))")
        .accessibilityHint("Opens favourite colours, presets, recent colours and a hex field")
        .help("Colour")
        .popover(isPresented: $showsColorPopover) {
            ToolbarColorPopover(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func dotSize(_ width: Double, range: ClosedRange<Double>) -> CGFloat {
        let fraction = (width - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(7 + min(max(fraction, 0), 1) * 11)
    }
}

private extension ToolbarItemID {
    /// The toolbar item that selects a tool, when there is one.
    init?(tool: EditorTool) {
        switch tool {
        case .pen:
            return nil
        case .highlighter:
            self = .highlighter
        case .eraser:
            self = .eraser
        case .lasso:
            self = .lasso
        case .laser:
            self = .laser
        case .elements:
            self = .elements
        case .links:
            self = .followLinks
        }
    }
}

// MARK: - Popovers

private struct PenSettingsPopover: View {
    @Bindable var editor: EditorToolState

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    /// Top to bottom: the pen types, one width section (presets and slider
    /// together, so the value is only named once), the line style, the two
    /// writing-feel switches, and the saved pens last. That fits a portrait
    /// iPad popover without scrolling in the common case.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
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
                Divider()
                ToolbarWidthPresets(editor: editor, showsSlider: true)
                Divider()
                LineStylePicker(editor: editor)
                Divider()
                SmoothingSlider(title: "Stabilisation", editor: editor)
                ScratchOutToggle()
                Divider()
                FavoritePensContent(editor: editor)
            }
            .padding(AppSpacing.l)
        }
        .frame(width: 320)
        .frame(maxHeight: 620)
    }
}

private struct WidthSettingsPopover: View {
    let title: String
    @Bindable var editor: EditorToolState
    @AppStorage(AppSettings.Key.highlighterStraightLines) private var straightLines = false

    /// One width section, exactly as the pen popover has it: the value once,
    /// the three presets, then the slider beneath them.
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title)
                .font(.headline)
            ToolbarWidthPresets(editor: editor, showsSlider: true)
            Divider()
            SmoothingSlider(title: "Stabilisation", editor: editor)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Straight Lines", isOn: $straightLines)
                    .font(.subheadline)
                    .accessibilityHint("Highlights a straight line from where the Pencil lands to where it lifts")
                Text("Draws from where the Pencil lands to where it lifts, instead of following the hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.l)
        .frame(width: 320)
    }
}

struct WidthSlider: View {
    @Bindable var editor: EditorToolState
    /// When set, the slider edits this width preset slot instead of the ink
    /// tool's current width.
    var presetSlot: Int? = nil
    /// The row's heading; the preset editor names the slot it changes.
    var title = "Width"
    /// False inside the width section, which names the value above the preset
    /// dots already: the slider then draws on its own.
    var showsHeader = true
    /// Shown while dragging; written to the editor (and so to disk, debounced)
    /// only when the drag ends.
    @State private var draft: Double?

    private var shownWidth: Double {
        guard let presetSlot, editor.widthPresets.indices.contains(presetSlot) else {
            return editor.inkTool.width
        }
        return editor.widthPresets[presetSlot]
    }

    private var sliderRange: ClosedRange<Double> {
        PenWidth.millimetreRange(for: editor.inkWidthRange)
    }

    var body: some View {
        let shown = draft ?? shownWidth
        let sliderValue = min(
            max(PenWidth.millimetres(fromPoints: shown), sliderRange.lowerBound),
            sliderRange.upperBound
        )
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if showsHeader {
                HStack {
                    Text(title)
                        .font(.subheadline)
                    Spacer()
                    Text(PenWidth.label(shown))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { draft = PenWidth.snappedPoints(fromMillimetres: $0) }
                ),
                in: sliderRange,
                step: PenWidth.millimetreStep
            ) { isEditing in
                if !isEditing, let draft {
                    if let presetSlot {
                        editor.setWidthPreset(at: presetSlot, to: draft)
                    } else {
                        editor.setWidth(draft)
                    }
                    self.draft = nil
                }
            }
            .accessibilityLabel("\(title) in millimetres")
            .accessibilityValue(PenWidth.label(shown))
        }
    }
}

/// Solid, dashed or dotted pen ink.
private struct LineStylePicker: View {
    @Bindable var editor: EditorToolState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("Line Style")
                .font(.subheadline)
            Picker("Line Style", selection: Binding(
                get: { editor.lineStyle },
                set: { editor.setLineStyle($0) }
            )) {
                ForEach(PenLineStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Line style")
            .accessibilityHint("Dashes are part of the stroke, so they keep their place in the page, the thumbnail and the export")
        }
    }
}

/// How hard the saved stroke is steadied, 0...100.
private struct SmoothingSlider: View {
    let title: String
    @Bindable var editor: EditorToolState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(editor.smoothing)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(editor.smoothing) },
                    set: { editor.setSmoothing(Int($0.rounded())) }
                ),
                in: 0...100,
                step: 5
            )
            .accessibilityLabel(title)
            .accessibilityValue("\(editor.smoothing) of 100")
            .accessibilityHint("Steadies the saved stroke. 0 keeps every wobble")
        }
    }
}

/// The pen-native delete gesture, with the off switch the competitors' users
/// ask for.
private struct ScratchOutToggle: View {
    @AppStorage(AppSettings.Key.scratchOutToErase) private var scratchOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Scratch to Erase", isOn: $scratchOut)
                .font(.subheadline)
                .accessibilityHint("Scribble over ink with the pen to delete it. Off keeps every scribble as ink")
        }
    }
}

private struct EraserSettingsPopover: View {
    @Bindable var editor: EditorToolState
    let clearLabel: String
    let onClearPage: () -> Void
    @AppStorage(EditorToolState.eraserAutoDeselectKey) private var autoDeselect = false
    @AppStorage(AppSettings.Key.eraserFilter) private var filterRaw = AppSettings.eraserFilterUnset

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
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
            VStack(alignment: .leading, spacing: AppSpacing.s) {
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
                Text("Erase")
                    .font(.subheadline)
                Toggle("Pen and Pencil", isOn: filterBinding(.pen))
                Toggle("Highlighter", isOn: filterBinding(.highlighter))
                Toggle("Shapes", isOn: filterBinding(.shape))
                    .accessibilityHint("Strokes snapped by Hold to Shape")
                Text("Only the ink types switched on are erased. Shapes are strokes snapped by Hold to Shape. Works with the whole-stroke eraser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(editor.eraserKind != .stroke)
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
            Button(clearLabel, systemImage: "trash", role: .destructive) {
                onClearPage()
            }
            .font(.subheadline)
        }
        .padding(AppSpacing.l)
        .frame(width: 320)
    }

    /// The filter shown, with the old "Erase Highlighter Only" switch
    /// migrated until the first toggle.
    private var eraserFilter: EraserFilter {
        AppSettings.eraserFilter(rawValue: filterRaw)
    }

    private func filterBinding(_ kind: EraserFilter) -> Binding<Bool> {
        Binding(
            get: { eraserFilter.contains(kind) },
            set: { isOn in
                var updated = eraserFilter
                if isOn {
                    updated.insert(kind)
                } else {
                    updated.remove(kind)
                }
                filterRaw = updated.rawValue
            }
        )
    }
}

/// Dot or Line, and a preview of what the pointer does.
private struct LaserSettingsPopover: View {
    @Bindable var editor: EditorToolState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
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
        .padding(AppSpacing.l)
        .frame(width: 320)
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

/// The toolbar's recording button with its elapsed time.
///
/// A view of its own: the elapsed time ticks twice a second, and reading it in
/// the toolbar's body redrew the whole editor pane at that rate.
private struct RecordingLabelButton: View {
    let audio: NotebookAudio?
    let onStop: () -> Void

    var body: some View {
        if let audio, audio.isRecording {
            let label = Self.label(for: audio.elapsed)
            Button(action: onStop) {
                HStack(spacing: AppSpacing.xs) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(label)
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording, \(label)")
        }
    }

    /// Elapsed time as minutes and seconds.
    static func label(for elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#endif
