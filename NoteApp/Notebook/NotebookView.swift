import AudioKit
import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct NotebookView: View {
    @Bindable var model: AppModel
    /// On, the editor takes the whole screen and the clock and battery hide.
    @AppStorage(AppSettings.Key.hideStatusBar) private var hideStatusBar = false

    var body: some View {
        VStack(spacing: 0) {
            // With one notebook open the tab bar is just chrome; the toolbar's
            // back button already returns to the library.
            if model.tabs.count > 1 {
                tabBar
                Divider()
            }
            if model.isSplitView, let split = model.splitSession, let active = model.session {
                HStack(spacing: 0) {
                    NotebookPane(session: active, model: model)
                    Divider()
                    NotebookPane(session: split, model: model)
                }
            } else if let active = model.session {
                NotebookPane(session: active, model: model)
            }
        }
        .background(AppColor.groupedBackground)
        #if os(iOS)
        .statusBarHidden(hideStatusBar)
        #endif
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.tabs) { tab in
                        tabChip(tab)
                    }
                }
            }

            Spacer(minLength: 4)

            Menu {
                ForEach(model.tabs.filter { $0.notebookID != model.session?.notebookID }) { tab in
                    Button {
                        model.toggleSplit(with: tab.notebookID)
                    } label: {
                        if model.splitNotebookID == tab.notebookID {
                            Label(tab.manifest.title, systemImage: "checkmark")
                        } else {
                            Text(tab.manifest.title)
                        }
                    }
                }
                if model.isSplitView {
                    Divider()
                    Button("Close Split", systemImage: "rectangle") {
                        model.closeSplit()
                    }
                }
            } label: {
                Image(systemName: model.isSplitView ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .accessibilityLabel("Split view")
            .help("Split view")

            Menu {
                Button("New Notebook", systemImage: "book.closed") {
                    Task { await model.createNotebook() }
                }
                Button("Open from Library", systemImage: "books.vertical") {
                    model.showLibrary()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .accessibilityLabel("New tab")
            .help("New notebook or open another")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func tabChip(_ tab: NotebookSession) -> some View {
        let isActive = tab.notebookID == model.activeNotebookID
        return HStack(spacing: 2) {
            Text(tab.manifest.title)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)

            Button {
                model.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close \(tab.manifest.title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(
            isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            model.activateTab(tab.notebookID)
        }
    }
}

struct NotebookPane: View {
    let session: NotebookSession
    @Bindable var model: AppModel

    @AppStorage("noteapp.editor.showsThumbnails") private var showsThumbnails = true
    @AppStorage(AppSettings.Key.pagesPanelOnLeft) private var pagesOnLeft = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsDeletePageConfirmation = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var exportDocument: PDFExportDocument?
    @State private var pngDocument: PNGExportDocument?
    @State private var isExporting = false
    @State private var isExportingPNG = false
    @State private var exportProgress: PDFExportProgress?
    @State private var showsExportOptions = false
    @State private var showExporter = false
    @State private var showPNGExporter = false
    @State private var pngFilename = "Page"
    @State private var exportError: String?
    @State private var showsTemplatePicker = false
    @State private var showsDeleteItems = false
    @State private var showsGoToPage = false
    @State private var showsClearPageConfirmation = false
    @AppStorage(AppSettings.Key.showPageNumber) private var showsPageNumber = true
    @AppStorage(AppSettings.Key.holdToDrawShapes) private var holdToDrawShapes = true
    @AppStorage(AppSettings.Key.darkPaper) private var darkPaperInDarkMode = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppSettings.Key.pageScrollMode) private var defaultScrollMode: PageScrollMode = .vertical
    @State private var showsCoverPicker = false
    @State private var showsTextComposer = false
    @State private var showsElements = false
    @State private var showsImageImporter = false
    @State private var showsPDFImporter = false
    @State private var pdfImport: PDFImportFlow?
    @State private var showsLayers = false
    @State private var showsOutline = false
    @State private var pagesPanelTab: NotebookPanelTab = .pages
    @State private var showsAudio = false
    @State private var showsAI = false
    @State private var showsToolbarEditor = false
    /// The compact-width sheet, which only opens when the reader asks for it.
    @State private var showsCompactPages = false
    @State private var showsHistory = false
    @State private var showsPageOverview = false
    @State private var showsLassoHint = false
    @State private var studyScope: NotebookStudyScope?
    @State private var showsTapeStudy = false
    /// The lasso's selection and the elements the Select Elements tool picked.
    @State private var selection = InkSelection()
    @State private var isRulerActive = false
    @State private var editor = EditorToolState()
    /// Where PDF links were followed from, so a jump can be undone.
    @State private var linkHistory = PDFLinkHistory()
    #if os(iOS)
    @State private var controller = PencilCanvasController()
    @State private var zoomController = PageZoomController()
    @AppStorage(AppSettings.Key.drawWithFinger) private var drawWithFinger = false
    @AppStorage(AppSettings.Key.twoFingerDoubleTapUndo) private var twoFingerDoubleTapUndo = true
    @AppStorage(AppSettings.Key.threeFingerDoubleTapRedo) private var threeFingerDoubleTapRedo = true
    @AppStorage(AppSettings.Key.pencilDoubleTapAction) private var pencilDoubleTapAction: PencilDoubleTapAction = .system
    @AppStorage(AppSettings.Key.eraserFilter) private var eraserFilterRaw = AppSettings.eraserFilterUnset
    @AppStorage(AppSettings.Key.scratchOutToErase) private var scratchOutToErase = false
    @AppStorage(AppSettings.Key.highlighterStraightLines) private var highlighterStraightLines = false
    @State private var zoomView = ZoomViewState()
    @State private var editorHeight: CGFloat = 0
    @AppStorage(AppSettings.Key.zoomAutoAdvance) private var zoomAutoAdvance = true
    @AppStorage(AppSettings.Key.zoomMagnification) private var zoomMagnification = ZoomBand.defaultMagnification
    @AppStorage(AppSettings.Key.zoomPanelFraction) private var zoomPanelFraction = 0.35
    #endif

    /// Dark Paper is an opt-in, and only in dark mode; pages are white paper
    /// otherwise.
    private var usesDarkPaper: Bool {
        darkPaperInDarkMode && colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if !editor.isReadingMode {
                EditorToolbar(
                    editor: editor,
                    controller: controller,
                    showsThumbnails: pagesPanelBinding,
                    audio: session.audio,
                    onBack: { model.showLibrary() },
                    onStopRecording: { Task { await session.audio.stopRecording() } },
                    onClearPage: { showsClearPageConfirmation = true },
                    isRulerActive: $isRulerActive,
                    onItemAction: { item in handleToolbarItem(item) },
                    onCustomizeToolbar: { showsToolbarEditor = true },
                    insertMenu: { insertMenuItems },
                    moreMenu: { moreMenuItems },
                    itemMenu: { item in toolbarItemMenu(for: item) }
                )
            }
            #else
            macHeader
            #endif
            if !editor.isReadingMode {
                Divider()
            }
            HStack(spacing: 0) {
                if showsPagesPanelInline, pagesOnLeft {
                    pagesPanel
                }
                VStack(spacing: 0) {
                    pageArea
                        .overlay(alignment: .top) { banners }
                        #if os(iOS)
                        .overlay(alignment: .topTrailing) {
                            if showsTapeStudy {
                                TapeStudyControls(session: session) {
                                    showsTapeStudy = false
                                }
                                .padding(16)
                            }
                        }
                        #endif
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 8) {
                                #if os(iOS)
                                if showsSelectionActions {
                                    SelectionActionBar(
                                        selection: $selection,
                                        editor: editor,
                                        session: session,
                                        controller: controller
                                    )
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                                #endif
                                #if os(iOS)
                                if session.audio.hasActiveClip {
                                    NowPlayingBar(audio: session.audio)
                                        .padding(.horizontal, 12)
                                }
                                #endif
                                // Reading Mode is one clean page: no page chrome.
                                if !editor.isReadingMode {
                                    PageCounterPill(
                                        session: session,
                                        onSelect: { index in
                                            Task { await session.goToPage(index) }
                                        },
                                        onGoToPage: { showsGoToPage = true },
                                        onShowOverview: { showsPageOverview = true }
                                    )
                                    .padding(.bottom, 12)
                                }
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                PageHistoryControls(session: session)
                                pdfLinkHistoryChip
                            }
                            .padding(.leading, 12)
                            .padding(.bottom, 12)
                        }
                        .overlay(alignment: .topTrailing) { readingModeExit }
                    #if os(iOS)
                    if showsZoomView {
                        // `session.page` changes with every stroke, so the
                        // panel is hosted in its own view: reading the page
                        // here would redraw this body — the toolbar, both
                        // menus and every modifier — once per stroke.
                        ZoomViewSection(session: session) { page in
                            zoomPanel(page)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    #endif
                }
                if showsPagesPanelInline, !pagesOnLeft {
                    pagesPanel
                }
            }
        }
        .background(AppColor.groupedBackground)
        .background(alignment: .topLeading) { pageHistoryShortcuts }
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { editorHeight = $0 }
        #endif
        .animation(.easeInOut(duration: 0.2), value: bannerState)
        .onAppear {
            Task { await session.audio.load() }
            session.audio.replayPageChanged(session.visibleStrokes)
            // Opened from a search: show its results beside the marked pages.
            if session.searchHighlight != nil { openSearch() }
        }
        .onChange(of: session.currentPageID) { _, _ in
            // Replay seeks wait on the ink of the page in view.
            session.audio.replayPageChanged(session.visibleStrokes)
        }
        .onChange(of: session.audio.playingClipID) { _, _ in
            session.audio.replayPageChanged(session.visibleStrokes)
        }
        .onChange(of: session.searchHighlight) { _, highlight in
            if highlight != nil { openSearch() }
        }
        .onDisappear {
            session.audio.stopPlayback()
            editor.saveNow()
            Task {
                await session.flushPendingSave()
                await session.audio.stopRecording()
            }
        }
        .onChange(of: editor.tool) { _, newTool in
            if newTool != .elements { selection.elementIDs = [] }
            if newTool != .lasso {
                selection.strokeIDs = []
                #if os(iOS)
                controller.clearSelection()
                #endif
            }
            showsLassoHint = newTool == .lasso && !editor.isReadOnly
        }
        .onChange(of: editor.isReadOnly) { _, isReadOnly in
            if isReadOnly {
                showsLassoHint = false
                selection.clear()
                #if os(iOS)
                controller.clearSelection()
                #endif
            } else {
                editor.isReadingMode = false
            }
        }
        .onChange(of: session.currentPageID) {
            // A selection belongs to the page it was made on.
            selection.clear()
        }
        .task(id: showsLassoHint) {
            guard showsLassoHint else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { showsLassoHint = false }
        }
        .sheet(isPresented: $showsDeleteItems) {
            DeleteSpecificItemsView(counts: session.itemCounts()) { kinds in
                Task { await session.deleteItems(of: kinds) }
            }
        }
        .sheet(isPresented: $showsGoToPage) {
            GoToPageField(pageCount: session.pageCount, currentIndex: session.pageIndex) { index in
                showsGoToPage = false
                Task { await session.goToPage(index) }
            }
            .padding(20)
            .presentationDetents([.height(120)])
        }
        .alert("Clear this page?", isPresented: $showsClearPageConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Page", role: .destructive) {
                Task { await session.clearCurrentPage() }
            }
        } message: {
            Text("Removes all ink and items from the page. An imported PDF stays. You can restore the page from Version History.")
        }
        .alert("Delete this page?", isPresented: $showsDeletePageConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await session.deleteCurrentPage() }
            }
        }
        .alert("Rename notebook", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task {
                    let manifest = session.manifest
                    await model.rename(manifest, to: renameText)
                    await session.reloadManifest()
                }
            }
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert(
            "Audio error",
            isPresented: Binding(
                get: { session.audio.errorText != nil },
                set: { if !$0 { session.audio.errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.audio.errorText = nil }
        } message: {
            Text(session.audio.errorText ?? "")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsExportOptions) {
            PDFExportOptionsSheet(pageCount: session.pageCount) { options in
                exportPDF(options: options)
            }
        }
        .fileExporter(
            isPresented: $showPNGExporter,
            document: pngDocument,
            contentType: .png,
            defaultFilename: pngFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsTemplatePicker) {
            PageTemplatePicker(
                current: session.page?.template,
                isApplying: session.isApplyingTemplate,
                currentWidth: session.page?.width,
                currentHeight: session.page?.height,
                customTemplates: model.templates,
                assetsDirectory: session.assetsDirectory,
                onApplySize: { size, orientation, applyToAll in
                    let points = size.size(orientation)
                    Task {
                        await session.resizePages(
                            width: points.width,
                            height: points.height,
                            toAllPages: applyToAll
                        )
                    }
                }
            ) { item, applyToAll in
                Task { await session.applyTemplate(item.template, toAllPages: applyToAll) }
            }
        }
        .sheet(isPresented: $showsCoverPicker) {
            NotebookCoverPicker(current: session.manifest.coverName) { name in
                Task {
                    await model.setCover(name, for: session.manifest)
                    await session.reloadManifest()
                }
            }
        }
        .sheet(isPresented: $showsTextComposer) {
            TextElementComposer { text, fontSize, style in
                Task {
                    await session.addTextElement(text, fontSize: fontSize, textStyle: style)
                    editor.tool = .elements
                }
            }
        }
        .sheet(isPresented: $showsElements) {
            PageElementsSheet(session: session)
        }
        .sheet(isPresented: $showsLayers) {
            LayersPanel(session: session)
        }
        .sheet(isPresented: $showsOutline) {
            OutlinePanel(
                session: session,
                outline: model.outline,
                bookmarks: model.bookmarks
            )
        }
        #if os(iOS)
        // Too narrow for a column: the same panel arrives as a sheet.
        .sheet(isPresented: compactPagesSheetBinding) {
            PagesSidePanel(
                session: session,
                isOnLeft: pagesOnLeft,
                search: model.search,
                tab: $pagesPanelTab,
                onHighlight: { session.searchHighlight = $0 },
                onSelect: { index in Task { await session.goToPage(index) } },
                onClose: { pagesPanelBinding.wrappedValue = false }
            )
            .presentationDetents([.medium, .large])
        }
        #endif
        .sheet(isPresented: $showsAudio) {
            AudioRecordingsView(session: session) {
                // Spoken words become searchable as soon as they are recognised,
                // not only when the notebook closes.
                Task { await model.search.index(notebook: session.manifest, store: session.store) }
            }
        }
        .sheet(isPresented: $showsAI) {
            NoteAIPanel(
                session: session,
                search: model.search,
                ai: model.ai,
                study: model.study
            )
        }
        .sheet(item: $studyScope) { scope in
            NotebookStudySheet(study: model.study, session: session, scope: scope)
        }
        .sheet(isPresented: $showsHistory) {
            VersionHistoryView(session: session)
        }
        .sheet(isPresented: $showsPageOverview) {
            PageOverviewGrid(
                session: session,
                outline: model.outline,
                bookmarks: model.bookmarks
            )
        }
        .sheet(isPresented: $showsToolbarEditor) {
            ToolbarEditorView()
        }
        .fileImporter(
            isPresented: $showsPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // One runloop later, so the file picker has finished
                    // dismissing before the import sheet arrives.
                    Task { @MainActor in
                        pdfImport = PDFImportFlow(
                            model: model,
                            url: url,
                            destination: .insert(session)
                        )
                    }
                }
            case .failure(let error):
                session.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $pdfImport) { flow in
            PDFImportSheet(flow: flow)
        }
        .fileImporter(
            isPresented: $showsImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                session.errorMessage = "The image could not be read."
                return
            }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            Task {
                await session.addImageElement(data: data, fileExtension: ext)
                editor.tool = .elements
            }
        }
    }

    // MARK: - Pages panel

    /// Regular width shows the panel beside the page; compact shows a sheet.
    private var pagesPanelIsInline: Bool {
        #if os(iOS)
        horizontalSizeClass != .compact
        #else
        true
        #endif
    }

    private var showsPagesPanelInline: Bool {
        showsThumbnails && pagesPanelIsInline
    }

    /// Regular width toggles the inline panel; compact shows the sheet.
    private var pagesPanelBinding: Binding<Bool> {
        Binding(
            get: { pagesPanelIsInline ? showsThumbnails : showsCompactPages },
            set: { isShown in
                if isShown { pagesPanelTab = .pages }
                if pagesPanelIsInline {
                    showsThumbnails = isShown
                } else {
                    showsCompactPages = isShown
                    // The stored flag remembers the panel closed too.
                    showsThumbnails = isShown
                }
            }
        )
    }

    /// Compact width presents the same grid as a sheet. The sheet waits for a
    /// tap, so a remembered open panel never covers a page at launch.
    private var compactPagesSheetBinding: Binding<Bool> {
        Binding(
            get: { showsCompactPages && !pagesPanelIsInline },
            set: { if !$0 { showsCompactPages = false } }
        )
    }

    private var pagesPanel: some View {
        PagesSidePanel(
            session: session,
            isOnLeft: pagesOnLeft,
            search: model.search,
            tab: $pagesPanelTab,
            onHighlight: { session.searchHighlight = $0 },
            onSelect: { index in
                Task { await session.goToPage(index) }
            },
            onClose: {
                withAnimation(.easeInOut(duration: 0.2)) { pagesPanelBinding.wrappedValue = false }
            }
        )
        .frame(width: 220)
        .transition(.move(edge: pagesOnLeft ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: - Page history

    /// ⌘[ and ⌘] step through the pages this notebook has shown, like a browser.
    /// Hidden: the chevrons over the page are the visible pair.
    private var pageHistoryShortcuts: some View {
        Group {
            Button("Back") {
                Task { await session.goBack() }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!session.canGoBack)
            Button("Forward") {
                Task { await session.goForward() }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!session.canGoForward)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Search

    /// True while the side panel is showing its Search tab.
    private var isSearchVisible: Bool {
        guard pagesPanelTab == .search else { return false }
        return pagesPanelIsInline ? showsThumbnails : showsCompactPages
    }

    /// Opens the side panel on its Search tab; the page keeps its size.
    private func openSearch() {
        pagesPanelTab = .search
        withAnimation(.easeInOut(duration: 0.2)) {
            showsThumbnails = true
            if !pagesPanelIsInline { showsCompactPages = true }
        }
    }

    // MARK: - Banners

    /// Which banners are showing, so their appearance animates.
    private var bannerState: [String] {
        var state: [String] = []
        if session.errorMessage != nil { state.append("error") }
        if session.currentPageWasQuarantined { state.append("quarantine") }
        if hasLayerBlock { state.append("layer") }
        if showsLassoHint { state.append("lasso") }
        if isExporting || isExportingPNG { state.append("export") }
        return state
    }

    private enum LayerBlock {
        case hidden(Page.Layer)
        case locked(Page.Layer)
        case missing
    }

    /// Why the active tool cannot change ink right now, if it cannot.
    private var layerBlock: LayerBlock? {
        guard !editor.isReadOnly,
              session.currentPageID != nil, editor.tool.editsInk, !session.canDrawOnActiveLayer
        else { return nil }
        guard let layer = session.activeLayer else { return .missing }
        return layer.isVisible ? .locked(layer) : .hidden(layer)
    }

    private var hasLayerBlock: Bool {
        if case .none = layerBlock { return false }
        return true
    }

    private var banners: some View {
        VStack(spacing: 8) {
            if let message = session.errorMessage {
                EditorBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    message: message,
                    tint: .red,
                    onDismiss: { session.errorMessage = nil }
                )
            }
            if session.currentPageWasQuarantined {
                EditorBanner(
                    systemImage: "doc.badge.exclamationmark",
                    message: "This page could not be read. The damaged file was kept; restore the last good version.",
                    actionTitle: "Version History",
                    action: { showsHistory = true }
                )
            }
            switch layerBlock {
            case .locked(let layer):
                EditorBanner(
                    systemImage: "lock.fill",
                    message: "“\(layer.name)” is locked",
                    actionTitle: "Unlock",
                    action: { Task { await session.toggleLayerLock(layer.id) } }
                )
            case .hidden(let layer):
                EditorBanner(
                    systemImage: "eye.slash.fill",
                    message: "“\(layer.name)” is hidden",
                    actionTitle: "Show",
                    action: { Task { await session.toggleLayerVisibility(layer.id) } }
                )
            case .missing:
                EditorBanner(
                    systemImage: "square.3.layers.3d",
                    message: "No layer to draw on",
                    actionTitle: "Layers…",
                    action: { showsLayers = true }
                )
            case nil:
                EmptyView()
            }
            if isExporting || isExportingPNG {
                EditorBanner(
                    systemImage: "square.and.arrow.up",
                    message: exportBannerMessage,
                    tint: .accentColor
                )
                .overlay(alignment: .bottom) {
                    if let exportProgress {
                        ProgressView(value: exportProgress.fraction)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                    }
                }
            }
            if showsLassoHint, !hasLayerBlock {
                EditorBanner(
                    systemImage: "lasso",
                    message: "Circle ink with the lasso, then drag to move it or use the bar to recolour, resize or copy it.",
                    tint: .accentColor,
                    onDismiss: { showsLassoHint = false }
                )
            }
        }
        .padding(.top, 10)
    }

    /// What the export banner says: page progress for a PDF export, or which
    /// file is being prepared before the first page reports.
    private var exportBannerMessage: String {
        guard let exportProgress else {
            return isExportingPNG ? "Preparing the PNG…" : "Preparing the PDF…"
        }
        let verb = exportProgress.isAddingAnnotations ? "Adding ink to" : "Exporting"
        let page = min(exportProgress.pagesCompleted + 1, exportProgress.pageCount)
        return "\(verb) page \(page) of \(exportProgress.pageCount)…"
    }

    // MARK: - Menus

    @ViewBuilder
    private var insertMenuItems: some View {
        Button("Text Box…", systemImage: "character.textbox") {
            showsTextComposer = true
        }
        .disabled(session.currentPageID == nil)
        Button("Image…", systemImage: "photo") {
            showsImageImporter = true
        }
        .disabled(session.currentPageID == nil)
        Button("Insert PDF Pages…", systemImage: "doc.badge.plus") {
            showsPDFImporter = true
        }
        Menu("Shape", systemImage: "square.on.circle") {
            Button("Rectangle", systemImage: "rectangle") { addShape("rect") }
            Button("Ellipse", systemImage: "circle") { addShape("ellipse") }
            Button("Line", systemImage: "line.diagonal") { addShape("line") }
        }
        .disabled(session.currentPageID == nil)
        Menu("Sticky Note", systemImage: "note") {
            ForEach(Array(zip(Self.stickyColorNames, NotebookSession.stickyColors)), id: \.0) { name, color in
                Button(name) { addSticky(color) }
            }
        }
        .disabled(session.currentPageID == nil)
        Menu("Tape", systemImage: "bandage") {
            ForEach(Array(zip(Self.tapeColorNames, NotebookSession.tapeColors)), id: \.0) { name, color in
                Button(name) { Task { await session.insertTape(color: color) } }
            }
        }
        .disabled(session.currentPageID == nil)
        Divider()
        Button("Page Elements…", systemImage: "square.on.square.dashed") {
            showsElements = true
        }
        .disabled(session.currentPageID == nil)
    }

    private static let stickyColorNames = [
        "Pink", "Peach", "Yellow", "Green", "Mint", "Blue", "Lavender", "Rose", "Grey", "White",
    ]
    private static let tapeColorNames = ["White", "Red", "Orange"]

    private func addSticky(_ color: RGBAColor) {
        Task {
            await session.insertStickyNote(color: color)
            editor.tool = .elements
        }
    }

    private func addShape(_ kind: String) {
        Task {
            await session.addShapeElement(kind: kind)
            editor.tool = .elements
        }
    }

    /// Runs an optional toolbar item's existing action.
    private func handleToolbarItem(_ item: ToolbarItemID) {
        switch item {
        case .textBox:
            guard session.currentPageID != nil else { return }
            showsTextComposer = true
        case .image:
            guard session.currentPageID != nil else { return }
            showsImageImporter = true
        case .addPage:
            Task { await session.addPage() }
        case .search:
            openSearch()
        default:
            break
        }
    }

    /// The menus behind the Shapes and Sticky Note toolbar items.
    @ViewBuilder
    private func toolbarItemMenu(for item: ToolbarItemID) -> some View {
        switch item {
        case .shapes:
            Button("Rectangle", systemImage: "rectangle") { addShape("rect") }
            Button("Ellipse", systemImage: "circle") { addShape("ellipse") }
            Button("Line", systemImage: "line.diagonal") { addShape("line") }
        case .stickyNote:
            ForEach(Array(zip(Self.stickyColorNames, NotebookSession.stickyColors)), id: \.0) { name, color in
                Button(name) { addSticky(color) }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var moreMenuItems: some View {
        #if os(iOS)
        Section {
            Toggle("Read Only", systemImage: "lock.doc", isOn: Binding(
                get: { editor.isReadOnly },
                set: { editor.isReadOnly = $0 }
            ))
            Button("Reading Mode", systemImage: "book") {
                startReadingMode()
            }
            .disabled(session.currentPageID == nil)
            Button("Customize Toolbar…", systemImage: "slider.horizontal.3") {
                showsToolbarEditor = true
            }
        }
        #endif
        Section(session.manifest.title) {
            Button("Rename…", systemImage: "pencil") {
                renameText = session.manifest.title
                isRenaming = true
            }
            Button("Notebook Cover…", systemImage: "book.closed") {
                showsCoverPicker = true
            }
        }
        Section {
            Button("Layers…", systemImage: "square.3.layers.3d") {
                showsLayers = true
            }
            .disabled(session.currentPageID == nil)
            Button("Outline…", systemImage: "list.bullet.indent") {
                showsOutline = true
            }
            Button("Page Overview…", systemImage: "square.grid.2x2") {
                showsPageOverview = true
            }
            .disabled(session.pageCount == 0)
            Button("Search in Notebook…", systemImage: "magnifyingglass") {
                openSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            bookmarksMenu
            Button("Page Template…", systemImage: "square.grid.3x3") {
                showsTemplatePicker = true
            }
            .disabled(session.currentPageID == nil)
        }
        Section("Study") {
            Button("Review This Notebook…", systemImage: "rectangle.stack") {
                studyScope = .notebook
            }
            Button("Review This Page…", systemImage: "rectangle.on.rectangle") {
                studyScope = .page
            }
            .disabled(session.currentPageID == nil)
            #if os(iOS)
            Button(
                showsTapeStudy ? "Hide Tape Study Bar" : "Tape Study",
                systemImage: "bandage"
            ) {
                showsTapeStudy.toggle()
            }
            .disabled(session.currentPageID == nil)
            #endif
        }
        Section {
            Button(
                session.audio.isRecording ? "Stop Recording" : "Record Audio",
                systemImage: session.audio.isRecording ? "stop.circle" : "record.circle"
            ) {
                Task {
                    if session.audio.isRecording {
                        await session.audio.stopRecording()
                    } else {
                        await session.audio.startRecording()
                    }
                }
            }
            Button("Audio Recordings…", systemImage: "waveform") {
                showsAudio = true
            }
            Button("Page AI…", systemImage: "sparkles") {
                showsAI = true
            }
            Button("Version History…", systemImage: "clock.arrow.circlepath") {
                showsHistory = true
            }
            .disabled(session.currentPageID == nil)
        }
        #if os(iOS)
        Section("Scrolling") {
            scrollModeButton("Scroll Vertically", mode: .vertical)
            scrollModeButton("Scroll Horizontally", mode: .horizontal)
        }
        Section {
            Toggle("Ruler", systemImage: "ruler", isOn: $isRulerActive)
                .disabled(session.currentPageID == nil)
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                zoomController.fit()
            }
            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                zoomController.zoomIn()
            }
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                zoomController.zoomOut()
            }
        }
        #endif
        Section("Page") {
            Button("Add Page After", systemImage: "plus") {
                Task { await session.addPage() }
            }
            Button("Duplicate Page", systemImage: "plus.square.on.square") {
                Task { await session.duplicateCurrentPage() }
            }
            .disabled(session.currentPageID == nil)
            Button("Move Page Left", systemImage: "arrow.left") {
                Task { await session.moveCurrentPage(by: -1) }
            }
            .disabled(session.currentPageID == nil || session.pageIndex == 0)
            Button("Move Page Right", systemImage: "arrow.right") {
                Task { await session.moveCurrentPage(by: 1) }
            }
            .disabled(session.currentPageID == nil || session.pageIndex + 1 >= session.pageCount)
            Menu("Rotate Page", systemImage: "rotate.right") {
                Button("Clockwise 90°", systemImage: "rotate.right") {
                    Task { await session.rotateCurrentPage(quarterTurns: 1) }
                }
                Button("Counter Clockwise 90°", systemImage: "rotate.left") {
                    Task { await session.rotateCurrentPage(quarterTurns: -1) }
                }
                Button("180°", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                    Task { await session.rotateCurrentPage(quarterTurns: 2) }
                }
            }
            .disabled(session.currentPageID == nil)
            Button("Go to Page…", systemImage: "arrow.right.to.line") {
                showsGoToPage = true
            }
            .disabled(session.pageCount < 2)
        }
        Section("Clear or Trash Page") {
            Button("Delete Specific Items…", systemImage: "square.grid.2x2") {
                showsDeleteItems = true
            }
            .disabled(session.currentPageID == nil)
            Button("Clear Page", systemImage: "eraser", role: .destructive) {
                showsClearPageConfirmation = true
            }
            .disabled(session.currentPageID == nil)
            Button("Delete Page", systemImage: "trash", role: .destructive) {
                showsDeletePageConfirmation = true
            }
            .disabled(session.currentPageID == nil)
        }
        Section {
            Button("Export PDF…", systemImage: "square.and.arrow.up") {
                showsExportOptions = true
            }
            .disabled(session.pageCount == 0 || isExporting)
            Button("Export Page as PNG…", systemImage: "photo") {
                exportPNG()
            }
            .disabled(session.currentPageID == nil || isExportingPNG)
        }
    }

    /// This notebook's direction, or the app default when it has none.
    private var scrollMode: PageScrollMode {
        session.pageScrollMode ?? defaultScrollMode
    }

    private func scrollModeButton(_ title: String, mode: PageScrollMode) -> some View {
        Button {
            Task { await session.setPageScrollMode(mode) }
        } label: {
            if scrollMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private var bookmarksMenu: some View {
        Menu("Bookmarks", systemImage: bookmarkedPageIndices.isEmpty ? "bookmark" : "bookmark.fill") {
            if let pageID = session.currentPageID {
                let isBookmarked = model.bookmarks.isBookmarked(notebookID: session.notebookID, pageID: pageID)
                Button(
                    isBookmarked ? "Remove Bookmark" : "Bookmark This Page",
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                ) {
                    model.bookmarks.toggle(notebookID: session.notebookID, pageID: pageID)
                }
                Divider()
            }
            let indices = bookmarkedPageIndices
            if indices.isEmpty {
                Text("No bookmarked pages")
            } else {
                ForEach(indices, id: \.self) { index in
                    Button("Page \(index + 1)") {
                        Task { await session.goToPage(index) }
                    }
                }
            }
        }
    }

    private func exportPDF(options: PDFExportOptions) {
        Task {
            isExporting = true
            exportProgress = nil
            defer {
                isExporting = false
                exportProgress = nil
            }
            do {
                let data = try await NotebookExporter.pdfData(
                    session: session,
                    options: options,
                    outlineTitles: outlineTitles
                ) { progress in
                    exportProgress = progress
                }
                exportDocument = PDFExportDocument(data: data)
                showExporter = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func exportPNG() {
        guard let page = session.page else {
            exportError = "The page could not be rendered."
            return
        }
        let filename = "\(exportFilename) - Page \(session.currentPageNumber)"
        Task {
            isExportingPNG = true
            defer { isExportingPNG = false }
            // Rendered off the main actor: a page-sized PNG takes long enough
            // to draw and encode to freeze the editor.
            guard let data = await NotebookExporter.pngData(
                page: page,
                assetsDirectory: session.assetsDirectory
            ) else {
                exportError = "The page could not be rendered."
                return
            }
            pngDocument = PNGExportDocument(data: data)
            pngFilename = filename
            showPNGExporter = true
        }
    }

    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 12) {
            Button {
                model.showLibrary()
            } label: {
                Label("Library", systemImage: "chevron.backward")
            }
            Text(session.manifest.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button {
                editor.isReadOnly.toggle()
            } label: {
                Label(
                    "Read Only",
                    systemImage: editor.isReadOnly ? "lock.fill" : "lock.doc"
                )
            }
            .help(editor.isReadOnly ? "Read Only: tap to edit again" : "Hide the tools and stop editing")
            .accessibilityAddTraits(editor.isReadOnly ? .isSelected : [])
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { pagesPanelBinding.wrappedValue.toggle() }
            } label: {
                Label("Pages", systemImage: pagesOnLeft ? "sidebar.leading" : "sidebar.trailing")
            }
            Menu {
                insertMenuItems
            } label: {
                Label("Insert", systemImage: "plus.circle")
            }
            .disabled(editor.isReadOnly)
            Menu {
                moreMenuItems
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
    #endif

    #if os(iOS)
    private func openPDFLink(at point: CGPoint) async {
        guard let page = session.page else { return }

        guard let target = PDFLinkHandler.target(
            at: point,
            page: page,
            assetsDirectory: session.assetsDirectory
        ) else {
            // Nothing under the tap: in Reading Mode the page edges turn it.
            guard editor.isReadingMode else { return }
            await turnReadingPage(at: point, pageWidth: page.width)
            return
        }

        switch target {
        case .url(let url):
            await UIApplication.shared.open(url)
        case .page(let pdfPageIndex):
            if let index = session.notebookPageIndex(forPDFPage: pdfPageIndex, from: page) {
                linkHistory.recordJump(from: session.pageIndex, notebookID: session.notebookID)
                await session.goToPage(index)
            }
        }
    }

    /// A tap in the outer strip of the page turns it: left goes back, right goes
    /// on. The strip is a 44 pt target at its narrowest.
    private func turnReadingPage(at point: CGPoint, pageWidth: Double) async {
        let edge = max(44, pageWidth * 0.18)
        if point.x <= edge {
            await session.goToPreviousPage()
        } else if point.x >= pageWidth - edge {
            await session.goToNextPage()
        }
    }
    #endif

    // MARK: - Reading Mode

    /// Read Only with the chrome gone: one page, a tap on either edge turns it,
    /// and PDF links still work. Leaving it brings the tools back.
    private func startReadingMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            pagesPanelBinding.wrappedValue = false
            editor.isReadingMode = true
            editor.isReadOnly = true
        }
    }

    /// The only chrome Reading Mode keeps, so there is always a way back.
    @ViewBuilder
    private var readingModeExit: some View {
        if editor.isReadingMode {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editor.isReadingMode = false
                    editor.isReadOnly = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book")
                        .font(.caption.weight(.semibold))
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave Reading Mode")
            .padding(12)
        }
    }

    /// Back and Forward for the pages a PDF link led to.
    @ViewBuilder
    private var pdfLinkHistoryChip: some View {
        let notebookID = session.notebookID
        let back = linkHistory.backPageIndex(notebookID: notebookID)
        let forward = linkHistory.forwardPageIndex(notebookID: notebookID)
        if back != nil || forward != nil {
            PDFLinkHistoryChip(
                backPageNumber: back.map { $0 + 1 },
                forwardPageNumber: forward.map { $0 + 1 },
                onBack: { goInLinkHistory(backward: true) },
                onForward: { goInLinkHistory(backward: false) }
            )
        }
    }

    private func goInLinkHistory(backward: Bool) {
        let notebookID = session.notebookID
        let current = session.pageIndex
        let target = backward
            ? linkHistory.goBack(notebookID: notebookID, pageIndex: current)
            : linkHistory.goForward(notebookID: notebookID, pageIndex: current)
        guard let target else { return }
        Task { await session.goToPage(target) }
    }

    private var bookmarkedPageIndices: [Int] {
        let ids = model.bookmarks.bookmarkedPageIDs(notebookID: session.notebookID)
        return session.manifest.pageOrder.enumerated().compactMap { index, pageID in
            ids.contains(pageID) ? index : nil
        }
    }

    /// Outline entries for a PDF export: every page with a custom outline
    /// title, and every bookmarked page (titled "Page N" when it has none).
    private var outlineTitles: [UUID: String] {
        let notebookID = session.notebookID
        let bookmarked = model.bookmarks.bookmarkedPageIDs(notebookID: notebookID)
        var titles: [UUID: String] = [:]
        for (index, pageID) in session.manifest.pageOrder.enumerated() {
            if let title = model.outline.title(notebookID: notebookID, pageID: pageID) {
                titles[pageID] = title
            } else if bookmarked.contains(pageID) {
                titles[pageID] = "Page \(index + 1)"
            }
        }
        return titles
    }

    private var exportFilename: String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = session.manifest.title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Notebook" : name
    }

    // MARK: - Page

    private var pageArea: some View {
        GeometryReader { proxy in
            if let page = session.page {
                #if os(iOS)
                PagedNotebookView(
                    mode: scrollMode,
                    pageOrder: session.manifest.pageOrder,
                    activePage: page,
                    source: PageImageSource(
                        notebookID: session.notebookID,
                        store: session.store,
                        assetsDirectory: session.assetsDirectory,
                        token: session.otherPagesToken
                    ),
                    controller: zoomController,
                    fitMargin: 20,
                    panTouches: panTouches,
                    usesDarkPaper: usesDarkPaper,
                    inkCapture: inkCapture,
                    onActivate: { index in await session.goToPage(index) }
                ) {
                    pageContent(page)
                }
                // A new scroll container per notebook and direction.
                .id("\(session.notebookID)-\(scrollMode.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                let aspect = page.width / page.height
                let availableWidth = max(proxy.size.width - 64, 200)
                let availableHeight = max(proxy.size.height - 64, 200)
                let fittedWidth = min(availableWidth, availableHeight * aspect, 820)
                let fittedHeight = fittedWidth / aspect

                macPageImage(page)
                    .frame(width: fittedWidth, height: fittedHeight)
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            } else {
                pagePlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    #if os(iOS)
    /// Read Only takes every tool away: the canvas takes no ink, but page
    /// scroll, zoom and PDF link taps still work.
    private var canvasMode: CanvasMode {
        editor.isReadOnly ? .links : editor.canvasMode
    }

    /// Which ink the stroke eraser may remove, with the old "Erase Highlighter
    /// Only" switch migrated until a filter is chosen.
    private var eraserFilter: EraserFilter {
        AppSettings.eraserFilter(rawValue: eraserFilterRaw)
    }

    /// Fingers needed to scroll or page. With Pencil-only drawing one finger
    /// scrolls; tools that drag with a finger (items, laser) and finger
    /// drawing (the simulator) keep it at two. The Pencil never scrolls.
    private var panTouches: Int {
        #if targetEnvironment(simulator)
        return 2
        #else
        if editor.isReadOnly { return 1 }
        // A finger that draws cannot also scroll.
        if drawWithFinger && editor.tool.editsInk { return 2 }
        switch editor.tool {
        case .elements, .laser: return 2
        default: return 1
        }
        #endif
    }

    /// What a stroke started on a page that is still loading becomes: only
    /// the pen and highlighter ink. A locked layer on the new page refuses it.
    private var inkCapture: InkCapture {
        let inks = !editor.isReadOnly && (editor.tool == .pen || editor.tool == .highlighter)
        return InkCapture(
            tool: inks ? editor.inkTool : nil,
            drawsWithFinger: drawWithFinger,
            canvas: controller,
            onStrokeEnded: { editor.didEndToolGesture() }
        )
    }

    private var canvasIsEditable: Bool {
        if editor.isReadOnly { return true }
        switch editor.tool {
        case .elements, .laser: return false
        // Link taps need touches even on a locked layer; drawing is off anyway.
        case .links: return true
        default: return session.canDrawOnActiveLayer
        }
    }

    /// The lasso or the element tool has something to act on.
    private var showsSelectionActions: Bool {
        !editor.isReadOnly
            && !selection.isEmpty
            && (editor.tool == .lasso || editor.tool == .elements)
    }

    /// The Select Elements layer edits one element at a time; the shared
    /// selection model is what the actions read.
    private var selectedElementID: Binding<UUID?> {
        Binding(
            get: { selection.elementIDs.first },
            set: { selection.elementIDs = $0.map { [$0] } ?? [] }
        )
    }

    // MARK: - Audio replay

    /// The stroke time the audio playhead stands at, when Follow is on and this
    /// page has ink from the recording. Ink written after it is faded.
    ///
    /// Takes the page's visible ink, so a body pass reads it once.
    private func replayCutoff(in strokes: [StrokeRecord]) -> Date? {
        guard session.audio.followsPlayhead, let clip = session.audio.activeClip else {
            return nil
        }
        guard strokes.contains(where: { clip.contains($0.createdAt) }) else { return nil }
        if let active = strokes.first(where: { $0.id == session.audio.activeStrokeID }) {
            return active.createdAt
        }
        // Before the first stroke of the clip, everything from it is still ahead.
        return clip.startedAt
    }

    /// Where the now-playing marker sits: the end of the stroke the recording
    /// has reached.
    private func activeReplayPoint(in strokes: [StrokeRecord]) -> CGPoint? {
        guard let strokeID = session.audio.activeStrokeID,
              let stroke = strokes.first(where: { $0.id == strokeID })
        else { return nil }
        return ZoomBand.endPoint(of: stroke)
    }

    /// A finger tap on ink plays the recording from the moment that ink was
    /// written. Taps on blank paper, and ink from outside a recording, do
    /// nothing. The lasso and element tools keep their own taps.
    ///
    /// The interaction is always installed, so the canvas's tap recogniser
    /// exists before the reader's first tap; the tool check lives in
    /// ``replayInk(at:)``.
    private var replayFingerInteraction: CanvasFingerInteraction {
        #if targetEnvironment(simulator)
        // PencilKit draws with any input on the simulator, so a finger tap would
        // ink a dot as well as seek. There, replay is driven from the transcript
        // and the now-playing bar instead.
        return CanvasFingerInteraction()
        #else
        return CanvasFingerInteraction(onTap: { point in
            replayInk(at: point)
        })
        #endif
    }

    private func replayInk(at point: CGPoint) {
        // With finger drawing on, the tap inks first; it is not a seek.
        guard !editor.isReadOnly, !drawWithFinger else { return }
        switch editor.tool {
        case .pen, .highlighter, .eraser: break
        case .lasso, .laser, .elements, .links: return
        }
        let strokes = session.visibleStrokes
        guard let stroke = ReplayTarget.nearestStroke(to: point, in: strokes) else { return }
        session.audio.replay(from: stroke, strokes: strokes)
    }

    private func pageContent(_ page: Page) -> some View {
        // One read of the visible ink for the whole pass: `visibleStrokes`
        // builds a set of layers and filters every stroke, and this body used
        // to ask for it for each of its consumers.
        let strokes = session.visibleStrokes
        // While a recording plays with Follow on, ink it has not reached yet is
        // faded, and the canvas takes no ink so the two views cannot disagree.
        let cutoff = replayCutoff(in: strokes)
        let shownStrokes = cutoff.map {
            ReplayInk.fading(strokes, after: $0)
        } ?? strokes
        return ZStack(alignment: .topLeading) {
            // Tape is drawn by `TapeOverlay` above the ink so it can hide and
            // reveal it; leaving it in the background would show through.
            PaperBackground(
                page: page.withoutTape,
                assetsDirectory: session.assetsDirectory,
                zoomScale: zoomController.settledZoom,
                usesDarkPaper: usesDarkPaper
            )

            if showsPageNumber {
                Text("\(session.currentPageNumber)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColor.pageAnnotation(usesDarkPaper: usesDarkPaper))
                    .padding([.bottom, .trailing], 14)
                    // Bottom-trailing, clear of the page counter pill at the bottom centre.
                    .frame(width: page.width, height: page.height, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            PencilCanvasView(
                strokes: shownStrokes,
                pageSize: CGSize(width: page.width, height: page.height),
                tool: editor.inkTool,
                mode: cutoff == nil ? canvasMode : .disabled,
                activeLayerID: session.activeLayerID ?? page.layers.first?.id ?? UUID(),
                isEditable: canvasIsEditable && cutoff == nil,
                isRulerActive: isRulerActive,
                controller: controller,
                drawsWithFinger: drawWithFinger,
                undoOnTwoFingerDoubleTap: twoFingerDoubleTapUndo,
                redoOnThreeFingerDoubleTap: threeFingerDoubleTapRedo,
                pencilDoubleTapAction: pencilDoubleTapAction,
                onFingerTap: { point in
                    Task { await openPDFLink(at: point) }
                },
                onToolGestureEnded: {
                    editor.didEndToolGesture()
                    // Writing on the page ends the search marks; they would go stale.
                    if !isSearchVisible { session.searchHighlight = nil }
                },
                holdToDrawShapes: holdToDrawShapes,
                onPencilDoubleTap: { editor.handlePencilDoubleTap($0) },
                smoothing: Double(editor.smoothing),
                lineStyle: editor.lineStyle,
                highlighterStraightLines: highlighterStraightLines,
                scratchOutToErase: scratchOutToErase,
                eraserFilter: eraserFilter,
                usesDarkPaper: usesDarkPaper,
                fingerInteraction: replayFingerInteraction,
                onSelectionChanged: { ids in
                    // Only the lasso selects ink. An empty report can also come
                    // from the canvas rebuilding after an action while those
                    // strokes still exist, so the bar is cleared explicitly on a
                    // tool or page change instead.
                    guard editor.tool == .lasso, !ids.isEmpty else { return }
                    selection.strokeIDs = Set(ids)
                },
                onStrokesChanged: { records in
                    // Follow mode hands the canvas faded copies of the page's
                    // ink. The canvas takes no input then, so any report (an
                    // undo from the toolbar) must not write those copies back.
                    guard cutoff == nil else { return }
                    session.strokesChanged(records, onPage: page.id)
                }
            )
            .id(page.id)

            if let highlight = session.searchHighlight {
                SearchHighlightOverlay(
                    highlight: highlight,
                    page: page,
                    strokes: strokes,
                    assetsDirectory: session.assetsDirectory,
                    search: model.search
                )
                .frame(width: page.width, height: page.height)
            }

            TapeOverlay(
                page: page,
                revealedTapeIDs: session.revealedTapeIDs,
                allowsHitTesting: editor.tool != .elements && editor.tool != .laser,
                onTap: { session.toggleTapeRevealed($0) }
            )

            if let point = activeReplayPoint(in: strokes) {
                NowPlayingMarker(point: point)
            }

            if showsZoomView, let band = zoomBand(page) {
                ZoomFrameOverlay(
                    band: band.rect,
                    showsAdvanceArea: zoomAutoAdvance,
                    onMove: { origin, _ in
                        moveZoomBand(page) { $0.move(to: origin) }
                    },
                    onResize: { width, ended in
                        let magnification = ZoomBand.magnification(forWidth: width, pageWidth: page.width)
                        if ended {
                            zoomMagnification = magnification
                            zoomView.liveMagnification = nil
                        } else {
                            zoomView.liveMagnification = magnification
                        }
                    }
                )
                .frame(width: page.width, height: page.height)
            }

            if editor.tool == .laser, !editor.isReadOnly {
                LaserPointerOverlay(mode: editor.laserMode)
            }

            if editor.tool == .elements, !editor.isReadOnly {
                ElementEditLayer(
                    page: page,
                    selectedID: selectedElementID,
                    onFrame: { elementID, frame in
                        Task { await session.updateElementFrame(elementID, frame: frame) }
                    },
                    onLock: { elementID, isLocked in
                        Task { await session.setElementLocked(elementID, isLocked: isLocked) }
                    },
                    onDelete: { elementID in
                        selection.elementIDs = []
                        Task { await session.removeElement(elementID) }
                    },
                    onMoveZ: { elementID, offset in
                        Task { await session.moveElement(elementID, by: offset) }
                    }
                )
            }
        }
        .frame(width: page.width, height: page.height)
        .clipped()
        // The page slot behind this content draws the paper's shadow.
    }

    // MARK: - Zoom View

    private var showsZoomView: Bool {
        editor.isZoomViewShown && !editor.isReadOnly
    }

    private func zoomBand(_ page: Page) -> ZoomBand? {
        zoomView.band(for: page, magnification: zoomView.liveMagnification ?? zoomMagnification)
    }

    private func moveZoomBand(_ page: Page, _ change: (inout ZoomBand) -> Void) {
        zoomView.update(page: page, magnification: zoomMagnification, change)
    }

    /// Moves the band by a button or auto-advance and keeps it on screen. A
    /// wrap past the bottom margin carries on at the top-left margins of the
    /// next page; the last page stops at its bottom (no page is added).
    private func stepZoomBand(_ page: Page, _ step: (inout ZoomBand) -> ZoomBand.Step) {
        let result = zoomView.update(page: page, magnification: zoomMagnification, step)
        if result == .nextPage {
            if let index = session.manifest.pageOrder.firstIndex(of: page.id),
               index + 1 < session.manifest.pageOrder.count {
                Task {
                    await session.goToPage(index + 1)
                    // A page the band has not been on starts at its margins.
                    if let next = session.page, let band = zoomBand(next) {
                        zoomController.reveal(band.rect, onPage: next.id)
                    }
                }
                return
            }
            moveZoomBand(page) { $0.newLine() }
        }
        if let band = zoomBand(page) {
            zoomController.reveal(band.rect, onPage: page.id)
        }
    }

    /// The panel's height: a share of the editor, at least enough to write in
    /// and never more than most of it.
    private var zoomPanelHeight: CGFloat {
        let total = max(editorHeight, 400)
        let wanted = zoomView.livePanelHeight ?? total * zoomPanelFraction
        return min(max(wanted, 160), total * 0.6)
    }

    private func zoomPanel(_ page: Page) -> some View {
        ZoomWindowPanel(
            page: page.withoutTape,
            band: zoomBand(page),
            tape: TapeOverlay(
                page: page,
                revealedTapeIDs: session.revealedTapeIDs,
                allowsHitTesting: editor.tool != .elements && editor.tool != .laser,
                onTap: { session.toggleTapeRevealed($0) }
            ),
            assetsDirectory: session.assetsDirectory,
            height: zoomPanelHeight,
            showsAdvanceArea: zoomAutoAdvance,
            usesDarkPaper: usesDarkPaper,
            onWritingSizeChange: { zoomView.writingSize = $0 },
            onResize: { height, ended in
                let total = max(editorHeight, 400)
                let clamped = min(max(height, 160), total * 0.6)
                if ended {
                    zoomPanelFraction = Double(clamped / total)
                    zoomView.livePanelHeight = nil
                } else {
                    zoomView.livePanelHeight = clamped
                }
            },
            onBack: { stepZoomBand(page) { $0.back() ? .moved : .stopped } },
            onForward: { stepZoomBand(page) { $0.step() } },
            onNewLine: { stepZoomBand(page) { $0.wrap() } },
            onClose: {
                withAnimation(.easeInOut(duration: 0.2)) { editor.isZoomViewShown = false }
            }
        ) { band in
            PencilCanvasView(
                strokes: session.visibleStrokes,
                pageSize: CGSize(width: page.width, height: page.height),
                tool: editor.inkTool,
                mode: canvasMode,
                activeLayerID: session.activeLayerID ?? page.layers.first?.id ?? UUID(),
                isEditable: canvasIsEditable,
                controller: controller,
                drawsWithFinger: drawWithFinger,
                undoOnTwoFingerDoubleTap: twoFingerDoubleTapUndo,
                redoOnThreeFingerDoubleTap: threeFingerDoubleTapRedo,
                pencilDoubleTapAction: pencilDoubleTapAction,
                onToolGestureEnded: {
                    editor.didEndToolGesture()
                    // Writing on the page ends the search marks; they would go stale.
                    if !isSearchVisible { session.searchHighlight = nil }
                },
                holdToDrawShapes: holdToDrawShapes,
                // The page's canvas answers the Pencil's double-tap; two
                // answers would switch the tool and straight back.
                onPencilDoubleTap: nil,
                smoothing: Double(editor.smoothing),
                lineStyle: editor.lineStyle,
                highlighterStraightLines: highlighterStraightLines,
                scratchOutToErase: scratchOutToErase,
                eraserFilter: eraserFilter,
                viewport: band.rect,
                usesDarkPaper: usesDarkPaper,
                onToolGestureBegan: { zoomView.cancelAdvance() },
                onStrokesChanged: { zoomStrokesChanged($0, on: page) }
            )
            .id(page.id)
        }
    }

    /// Ink from the panel goes to the page like any other; a new stroke that
    /// ends in the advance area moves the band on once the Pencil stays up.
    private func zoomStrokesChanged(_ records: [StrokeRecord], on page: Page) {
        let known = Set(session.visibleStrokes.map(\.id))
        session.strokesChanged(records, onPage: page.id)
        guard zoomAutoAdvance, editor.tool.drawsInk,
              let band = zoomBand(page),
              let newest = records.last(where: { !known.contains($0.id) }),
              let end = ZoomBand.endPoint(of: newest),
              band.isInAdvanceArea(end)
        else { return }
        zoomView.scheduleAdvance {
            stepZoomBand(page) { $0.step() }
        }
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private func macPageImage(_ page: Page) -> some View {
        if let image = PaperAppearance.image(
            page: page,
            assetsDirectory: session.assetsDirectory,
            scale: 2,
            usesDarkPaper: usesDarkPaper
        ) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            PaperBackground(
                page: page,
                assetsDirectory: session.assetsDirectory,
                usesDarkPaper: usesDarkPaper
            )
        }
    }
    #endif

    @ViewBuilder
    private var pagePlaceholder: some View {
        if session.isLoadingPage {
            ProgressView()
        } else if session.pageCount == 0 {
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("This notebook has no pages")
                    .font(.headline)
                Button("Add the First Page") {
                    Task { await session.addPage(after: false) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Page unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(session.loadError ?? "The page file could not be read.")
            }
        }
    }
}

#if os(iOS)
/// Hosts the Zoom View panel below the page.
///
/// The panel is drawn for the active page, and `session.page` changes with
/// every stroke. Reading it in this small view's body keeps the redraw to the
/// panel and leaves the pane's own body — the toolbar, both menus and its
/// modifiers — alone.
private struct ZoomViewSection<Panel: View>: View {
    let session: NotebookSession
    @ViewBuilder let panel: (Page) -> Panel

    var body: some View {
        if let page = session.page {
            panel(page)
        }
    }
}
#endif
