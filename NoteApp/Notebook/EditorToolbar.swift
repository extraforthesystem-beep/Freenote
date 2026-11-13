#if os(iOS)
import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers

/// The editor's single toolbar row.
///
/// Left (pinned): back, pages, undo, redo. Centre: the pen chip and the
/// customisable tool items, the colour favourites and the width presets.
/// Right: recording and the More menu. Only the colour favourites scroll; when
/// the row is too narrow for every tool the extra ones move into an overflow
/// menu. Reading a notebook hides the tools and shows a Read Only pill instead.
struct EditorToolbar<InsertMenu: View, MoreMenu: View, ItemMenu: View>: View {
    @Bindable var editor: EditorToolState
    let controller: PencilCanvasController
    @Binding var showsThumbnails: Bool
    /// Which edge the Pages panel sits on.
    let pagesOnLeft: Bool
    let isRecording: Bool
    let recordingLabel: String
    let onBack: () -> Void
    let onStopRecording: () -> Void
    /// Opens the notebook's Clear Page confirmation.
    let onClearPage: () -> Void
    /// Bound to the notebook's ruler, for the optional Ruler item.
    @Binding var isRulerActive: Bool
    /// Runs an optional item's existing action. Menu-style items use `itemMenu`.
    let onItemAction: (ToolbarItemID) -> Void
    let onCustomizeToolbar: () -> Void
    @ViewBuilder let insertMenu: () -> InsertMenu
    @ViewBuilder let moreMenu: () -> MoreMenu
    @ViewBuilder let itemMenu: (ToolbarItemID) -> ItemMenu

    @AppStorage(ToolbarLayout.storageKey) private var layoutStorage = ToolbarLayout.defaultStorage
    @State private var popover: ToolPopover?
    @State private var showsPalette = false
    @State private var showsFavoritePens = false
    @State private var showsZoomOptions = false
    /// The favourite slot the palette is replacing, when one is being edited.
    @State private var editingFavorite: Int?
    /// The favourite a dragged colour is hovering over, for the drop ring.
    @State private var dropTarget: Int?
    /// Which edges of the colour strip have more colours off screen.
    @State private var swatchEdges = SwatchEdges()

    private enum ToolPopover: Hashable {
        case pen, highlighter, eraser, laser
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
            ToolbarDivider()
            centre
                .frame(maxWidth: .infinity)
            if !editor.isReadOnly {
                ToolbarDivider()
            }
            trailing
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
        .background(.bar)
        .background {
            // Long-pressing an empty part of the bar opens the toolbar editor.
            Color.clear
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Customize Toolbar…", systemImage: "slider.horizontal.3") {
                        onCustomizeToolbar()
                    }
                }
        }
        .background(alignment: .topLeading) { toolShortcuts }
        .onChange(of: editor.paletteRequestID) {
            popover = nil
            showsPalette = true
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
                systemImage: pagesOnLeft ? "sidebar.leading" : "sidebar.trailing",
                isSelected: showsThumbnails
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
            withAnimation(.easeInOut(duration: 0.15)) { editor.isReadOnly = false }
        } label: {
            HStack(spacing: 5) {
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
            colorGroup
            ToolbarDivider()
            widths
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Customisable tools

    private var layout: ToolbarLayout {
        ToolbarLayout(storage: layoutStorage)
    }

    /// All the chosen items when they fit; otherwise the important ones plus a
    /// "More Tools" overflow menu. This group never scrolls.
    private var customisableTools: some View {
        ViewThatFits(in: .horizontal) {
            toolRow(layout.items, overflow: [])
            toolRow(priorityItems, overflow: overflowItems)
            toolRow(compactItems, overflow: compactOverflow)
            toolRow([], overflow: layout.items)
        }
    }

    private func toolRow(_ items: [ToolbarItemID], overflow: [ToolbarItemID]) -> some View {
        HStack(spacing: 2) {
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
        guard let item = ToolbarItemID(tool: editor.tool), layout.items.contains(item) else { return nil }
        return item
    }

    /// Pen chip, the two ink tools people switch between, and the active tool.
    private var priorityItems: [ToolbarItemID] {
        var priority: Set<ToolbarItemID> = [.highlighter, .eraser]
        if let active = activeToolItem { priority.insert(active) }
        return layout.items.filter { priority.contains($0) }
    }

    private var overflowItems: [ToolbarItemID] {
        layout.items.filter { !priorityItems.contains($0) }
    }

    /// A last resort: the pen chip, the active tool and the overflow menu.
    private var compactItems: [ToolbarItemID] {
        guard let active = activeToolItem, active != .highlighter, active != .eraser else { return [] }
        return [active]
    }

    private var compactOverflow: [ToolbarItemID] {
        layout.items.filter { !compactItems.contains($0) }
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
            elementsButton
        case .insert:
            insertButton
        case .laser:
            laserButton
        case .zoomView:
            zoomViewButton
        case .followLinks:
            followLinksButton
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
        }
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
            withAnimation(.easeInOut(duration: 0.2)) { editor.isZoomViewShown.toggle() }
        case .ruler:
            isRulerActive.toggle()
        case .textBox, .image, .addPage, .search:
            onItemAction(item)
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
            "Select Elements",
            systemImage: "cursorarrow.rays",
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
                withAnimation(.easeInOut(duration: 0.2)) { editor.isZoomViewShown = true }
            }
        }
        .popover(isPresented: $showsZoomOptions) {
            ZoomViewOptions {
                showsZoomOptions = false
                withAnimation(.easeInOut(duration: 0.2)) { editor.isZoomViewShown = false }
            }
            .padding(16)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func popoverBinding(_ kind: ToolPopover) -> Binding<Bool> {
        Binding(
            get: { popover == kind },
            set: { if !$0, popover == kind { popover = nil } }
        )
    }

    // MARK: - Colours

    /// The active ink tool's favourites in their own scroll view, with the
    /// palette button fixed beside it. This is the only part of the bar that
    /// scrolls.
    private var colorGroup: some View {
        let favorites = editor.favoriteColors
        return HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(favorites.colors.enumerated()), id: \.element) { index, color in
                            favoriteSwatch(color, index: index)
                                .id(index)
                        }
                        if !favorites.isFull {
                            addFavoriteSlot
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(-1)
                .mask(swatchMask)
                .onScrollGeometryChange(for: SwatchEdges.self) { geometry in
                    SwatchEdges(
                        leading: geometry.contentOffset.x > 1,
                        trailing: geometry.contentOffset.x + geometry.containerSize.width
                            < geometry.contentSize.width - 1
                    )
                } action: { _, edges in
                    swatchEdges = edges
                }
                .onAppear { revealSelectedColor(proxy) }
                .onChange(of: editor.activeInkTool) { revealSelectedColor(proxy) }
                .onChange(of: editor.inkTool.color) { revealSelectedColor(proxy) }
                .onChange(of: favorites.colors.count) { revealSelectedColor(proxy) }
            }
            paletteButton
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: editingFavoriteBinding) {
            ColorPalettePopover(editor: editor, replacingFavorite: editingFavorite)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Fades an edge of the colour strip only when more colours sit past it.
    private var swatchMask: some View {
        LinearGradient(
            stops: [
                .init(color: swatchEdges.leading ? .clear : .black, location: 0),
                .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.96),
                .init(color: swatchEdges.trailing ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Keeps the colour in use visible, on appear and when the colour changes.
    private func revealSelectedColor(_ proxy: ScrollViewProxy) {
        guard let index = editor.favoriteColors.colors.firstIndex(where: { editor.isCurrentColor($0) })
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    private var editingFavoriteBinding: Binding<Bool> {
        Binding(
            get: { editingFavorite != nil },
            set: { if !$0 { editingFavorite = nil } }
        )
    }

    private func favoriteSwatch(_ color: RGBAColor, index: Int) -> some View {
        let isSelected = editor.tool.drawsInk && editor.isCurrentColor(color)
        let isDropTarget = dropTarget == index
        return Button {
            editor.setColor(color)
        } label: {
            Circle()
                .fill(Color(color))
                .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                .frame(width: 24, height: 24)
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                }
                .overlay {
                    if isDropTarget {
                        Circle()
                            .strokeBorder(
                                Color.accentColor.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, dash: [3, 2])
                            )
                    }
                }
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit…", systemImage: "slider.horizontal.3") {
                showsPalette = false
                editingFavorite = index
            }
            Button("Replace with Current Colour", systemImage: "arrow.triangle.2.circlepath") {
                editor.replaceFavoriteColor(at: index, with: editor.inkTool.color)
            }
            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                editor.removeFavoriteColor(at: index)
            }
        }
        .draggable(FavoriteColorSlot(index: index)) {
            Circle()
                .fill(Color(color))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 34, height: 34)
                .padding(5)
        }
        .dropDestination(for: FavoriteColorSlot.self) { slots, _ in
            guard let source = slots.first?.index, source != index else { return false }
            dropTarget = nil
            withAnimation(.easeInOut(duration: 0.15)) {
                editor.moveFavoriteColor(from: source, to: index)
            }
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTarget = index
            } else if dropTarget == index {
                dropTarget = nil
            }
        }
        .accessibilityLabel("\(editor.colorName(for: color)), favourite \(index + 1)")
        .accessibilityHint(
            "Double-tap to use this colour. Touch and hold to edit, replace or remove it, "
                + "or drag it onto another favourite to move it."
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Move Left") {
            editor.moveFavoriteColor(from: index, to: index - 1)
        }
        .accessibilityAction(named: "Move Right") {
            editor.moveFavoriteColor(from: index, to: index + 1)
        }
    }

    /// Shown once a favourite is removed: adds the current colour back.
    private var addFavoriteSlot: some View {
        Button {
            editor.addFavoriteColor(editor.inkTool.color)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background {
                    Circle().strokeBorder(
                        Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                }
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(editor.colorName(for: editor.inkTool.color)) to favourites")
        .help("Add the current colour to the favourites")
    }

    private var paletteButton: some View {
        Button {
            showsPalette = true
        } label: {
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .teal, .blue, .purple, .red],
                        center: .center
                    ))
                Circle()
                    .fill(Color(editor.inkTool.color))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 24, height: 24)
            .padding(3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour palette, \(editor.colorName(for: editor.inkTool.color))")
        .accessibilityHint("Opens presets, recent colours and a hex field")
        .help("Colour palette")
        .popover(isPresented: $showsPalette) {
            ColorPalettePopover(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Widths

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
                .accessibilityHint(isApplicable ? "Sets the current width" : "No width for this tool")
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

/// Which edges of the colour strip have more colours off screen.
private struct SwatchEdges: Equatable {
    var leading = false
    var trailing = false
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FavoritePensContent(editor: editor)
                Divider()
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
        }
        .frame(width: 320)
        .frame(maxHeight: 620)
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

/// A favourite colour's slot in the toolbar, carried while its swatch is
/// dragged. In-app only, so the type is never handed to another app.
nonisolated private struct FavoriteColorSlot: Codable, Transferable {
    var index: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .noteAppFavoriteColorSlot)
    }
}

nonisolated private extension UTType {
    static var noteAppFavoriteColorSlot: UTType {
        UTType(exportedAs: "com.noteapp.favorite-color-slot")
    }
}
#endif
