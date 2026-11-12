import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct NotebookView: View {
    @Bindable var model: AppModel

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
    @State private var showsDeletePageConfirmation = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var exportDocument: PDFExportDocument?
    @State private var pngDocument: PNGExportDocument?
    @State private var isExporting = false
    @State private var exportProgress: PDFExportProgress?
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
    @State private var showsCoverPicker = false
    @State private var showsTextComposer = false
    @State private var showsElements = false
    @State private var showsImageImporter = false
    @State private var showsLayers = false
    @State private var showsOutline = false
    @State private var showsSearch = false
    @State private var showsAudio = false
    @State private var showsAI = false
    @State private var showsHistory = false
    @State private var showsLassoHint = false
    @State private var selectedElementID: UUID?
    @State private var isRulerActive = false
    @State private var editor = EditorToolState()
    #if os(iOS)
    @State private var controller = PencilCanvasController()
    @State private var zoomController = PageZoomController()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            EditorToolbar(
                editor: editor,
                controller: controller,
                showsThumbnails: $showsThumbnails,
                isRecording: session.audio.isRecording,
                recordingLabel: elapsedLabel,
                onBack: { model.showLibrary() },
                onStopRecording: { Task { await session.audio.stopRecording() } },
                insertMenu: { insertMenuItems },
                moreMenu: { moreMenuItems }
            )
            #else
            macHeader
            #endif
            Divider()
            pageArea
                .overlay(alignment: .top) { banners }
                .overlay(alignment: .bottom) {
                    PageCounterPill(session: session) { index in
                        Task { await session.goToPage(index) }
                    }
                    .padding(.bottom, 12)
                }
            if showsThumbnails {
                Divider()
                PageThumbnailStrip(session: session) { index in
                    Task { await session.goToPage(index) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppColor.groupedBackground)
        .animation(.easeInOut(duration: 0.2), value: bannerState)
        .onAppear {
            Task { await session.audio.load() }
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
            if newTool != .elements { selectedElementID = nil }
            showsLassoHint = newTool == .lasso && !editor.isReadOnly
        }
        .onChange(of: editor.isReadOnly) { _, isReadOnly in
            if isReadOnly {
                showsLassoHint = false
                selectedElementID = nil
            }
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
        .inspector(isPresented: $showsSearch) {
            NotebookSearchPanel(notebookID: session.notebookID, search: model.search) { pageID in
                guard let index = session.manifest.pageOrder.firstIndex(of: pageID) else { return }
                Task { await session.goToPage(index) }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .sheet(isPresented: $showsAudio) {
            AudioRecordingsView(session: session)
        }
        .sheet(isPresented: $showsAI) {
            NoteAIPanel(
                session: session,
                search: model.search,
                ai: model.ai,
                study: model.study
            )
        }
        .sheet(isPresented: $showsHistory) {
            VersionHistoryView(session: session)
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

    // MARK: - Banners

    /// Which banners are showing, so their appearance animates.
    private var bannerState: [String] {
        var state: [String] = []
        if session.errorMessage != nil { state.append("error") }
        if hasLayerBlock { state.append("layer") }
        if showsLassoHint { state.append("lasso") }
        if isExporting { state.append("export") }
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
              session.page != nil, editor.tool.editsInk, !session.canDrawOnActiveLayer
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
            if isExporting {
                EditorBanner(
                    systemImage: "square.and.arrow.up",
                    message: exportProgress.map { "Exporting page \(min($0.pagesCompleted + 1, $0.pageCount)) of \($0.pageCount)…" }
                        ?? "Preparing the PDF…",
                    tint: .accentColor
                )
                .overlay(alignment: .bottom) {
                    ProgressView(value: exportProgress?.fraction ?? 0)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
            }
            if showsLassoHint, !hasLayerBlock {
                EditorBanner(
                    systemImage: "lasso",
                    message: "Circle ink with the lasso, then drag the selection to move it.",
                    tint: .accentColor,
                    onDismiss: { showsLassoHint = false }
                )
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Menus

    @ViewBuilder
    private var insertMenuItems: some View {
        Button("Text Box…", systemImage: "character.textbox") {
            showsTextComposer = true
        }
        .disabled(session.page == nil)
        Button("Image…", systemImage: "photo") {
            showsImageImporter = true
        }
        .disabled(session.page == nil)
        Menu("Shape", systemImage: "square.on.circle") {
            Button("Rectangle", systemImage: "rectangle") { addShape("rect") }
            Button("Ellipse", systemImage: "circle") { addShape("ellipse") }
            Button("Line", systemImage: "line.diagonal") { addShape("line") }
        }
        .disabled(session.page == nil)
        Menu("Sticky Note", systemImage: "note") {
            ForEach(Array(zip(Self.stickyColorNames, NotebookSession.stickyColors)), id: \.0) { name, color in
                Button(name) { addSticky(color) }
            }
        }
        .disabled(session.page == nil)
        Menu("Tape", systemImage: "bandage") {
            ForEach(Array(zip(Self.tapeColorNames, NotebookSession.tapeColors)), id: \.0) { name, color in
                Button(name) { Task { await session.insertTape(color: color) } }
            }
        }
        .disabled(session.page == nil)
        Divider()
        Button("Page Elements…", systemImage: "square.on.square.dashed") {
            showsElements = true
        }
        .disabled(session.page == nil)
    }

    private static func removingTape(from page: Page) -> Page {
        var page = page
        page.elements.removeAll { element in
            if case .tape = element.content { return true }
            return false
        }
        return page
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

    @ViewBuilder
    private var moreMenuItems: some View {
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
            .disabled(session.page == nil)
            Button("Outline…", systemImage: "list.bullet.indent") {
                showsOutline = true
            }
            Button("Search in Notebook…", systemImage: "magnifyingglass") {
                showsSearch = true
            }
            .keyboardShortcut("f", modifiers: .command)
            bookmarksMenu
            Button("Page Template…", systemImage: "square.grid.3x3") {
                showsTemplatePicker = true
            }
            .disabled(session.page == nil)
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
            .disabled(session.page == nil)
        }
        #if os(iOS)
        Section {
            Toggle("Ruler", systemImage: "ruler", isOn: $isRulerActive)
                .disabled(session.page == nil)
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
            .disabled(session.page == nil)
            Button("Move Page Left", systemImage: "arrow.left") {
                Task { await session.moveCurrentPage(by: -1) }
            }
            .disabled(session.page == nil || session.pageIndex == 0)
            Button("Move Page Right", systemImage: "arrow.right") {
                Task { await session.moveCurrentPage(by: 1) }
            }
            .disabled(session.page == nil || session.pageIndex + 1 >= session.pageCount)
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
            .disabled(session.page == nil)
            Button("Go to Page…", systemImage: "arrow.right.to.line") {
                showsGoToPage = true
            }
            .disabled(session.pageCount < 2)
        }
        Section("Clear or Trash Page") {
            Button("Delete Specific Items…", systemImage: "square.grid.2x2") {
                showsDeleteItems = true
            }
            .disabled(session.page == nil)
            Button("Clear Page", systemImage: "eraser", role: .destructive) {
                showsClearPageConfirmation = true
            }
            .disabled(session.page == nil)
            Button("Delete Page", systemImage: "trash", role: .destructive) {
                showsDeletePageConfirmation = true
            }
            .disabled(session.page == nil)
        }
        Section {
            Button("Export PDF…", systemImage: "square.and.arrow.up") {
                exportPDF()
            }
            .disabled(session.pageCount == 0 || isExporting)
            Button("Export Page as PNG…", systemImage: "photo") {
                exportPNG()
            }
            .disabled(session.page == nil)
        }
    }

    @ViewBuilder
    private var bookmarksMenu: some View {
        Menu("Bookmarks", systemImage: bookmarkedPageIndices.isEmpty ? "bookmark" : "bookmark.fill") {
            if let page = session.page {
                let isBookmarked = model.bookmarks.isBookmarked(notebookID: session.notebookID, pageID: page.id)
                Button(
                    isBookmarked ? "Remove Bookmark" : "Bookmark This Page",
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                ) {
                    model.bookmarks.toggle(notebookID: session.notebookID, pageID: page.id)
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

    private func exportPDF() {
        Task {
            isExporting = true
            exportProgress = nil
            defer {
                isExporting = false
                exportProgress = nil
            }
            do {
                let data = try await NotebookExporter.pdfData(session: session) { progress in
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
        guard let page = session.page,
              let data = NotebookExporter.pngData(
                  page: page,
                  assetsDirectory: session.assetsDirectory
              )
        else {
            exportError = "The page could not be rendered."
            return
        }
        pngDocument = PNGExportDocument(data: data)
        pngFilename = "\(exportFilename) - Page \(session.currentPageNumber)"
        showPNGExporter = true
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
                withAnimation { showsThumbnails.toggle() }
            } label: {
                Label("Pages", systemImage: "rectangle.bottomthird.inset.filled")
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
        guard let page = session.page,
              let target = PDFLinkHandler.target(
                  at: point,
                  page: page,
                  assetsDirectory: session.assetsDirectory
              )
        else { return }

        switch target {
        case .url(let url):
            await UIApplication.shared.open(url)
        case .page(let pdfPageIndex):
            if let index = session.notebookPageIndex(forPDFPage: pdfPageIndex, from: page) {
                await session.goToPage(index)
            }
        }
    }
    #endif

    private var bookmarkedPageIndices: [Int] {
        let ids = model.bookmarks.bookmarkedPageIDs(notebookID: session.notebookID)
        return session.manifest.pageOrder.enumerated().compactMap { index, pageID in
            ids.contains(pageID) ? index : nil
        }
    }

    private var exportFilename: String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = session.manifest.title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Notebook" : name
    }

    private var elapsedLabel: String {
        let total = max(0, Int(session.audio.elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Page

    private var pageArea: some View {
        GeometryReader { proxy in
            if let page = session.page {
                #if os(iOS)
                ZoomablePageView(
                    pageSize: CGSize(width: page.width, height: page.height),
                    controller: zoomController,
                    fitMargin: 20,
                    minimumPanTouches: 2
                ) {
                    pageContent(page)
                }
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

    private var canvasIsEditable: Bool {
        if editor.isReadOnly { return true }
        switch editor.tool {
        case .elements, .laser: return false
        // Link taps need touches even on a locked layer; drawing is off anyway.
        case .links: return true
        default: return session.canDrawOnActiveLayer
        }
    }

    private func pageContent(_ page: Page) -> some View {
        ZStack(alignment: .topLeading) {
            // Tape is drawn by `TapeOverlay` above the ink so it can hide and
            // reveal it; leaving it in the background would show through.
            PaperBackground(
                page: Self.removingTape(from: page),
                assetsDirectory: session.assetsDirectory,
                zoomScale: zoomController.settledZoom
            )

            if showsPageNumber {
                Text("\(session.currentPageNumber)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding([.bottom, .trailing], 14)
                    // Bottom-trailing, clear of the page counter pill at the bottom centre.
                    .frame(width: page.width, height: page.height, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            PencilCanvasView(
                strokes: session.visibleStrokes,
                pageSize: CGSize(width: page.width, height: page.height),
                tool: editor.inkTool,
                mode: canvasMode,
                activeLayerID: session.activeLayerID ?? page.layers.first?.id ?? UUID(),
                isEditable: canvasIsEditable,
                isRulerActive: isRulerActive,
                controller: controller,
                onFingerTap: { point in
                    Task { await openPDFLink(at: point) }
                },
                onToolGestureEnded: { editor.didEndToolGesture() },
                holdToDrawShapes: holdToDrawShapes,
                onStrokesChanged: { session.strokesChanged($0) }
            )
            .id(page.id)

            TapeOverlay(
                page: page,
                revealedTapeIDs: session.revealedTapeIDs,
                allowsHitTesting: editor.tool != .elements && editor.tool != .laser,
                onTap: { session.toggleTapeRevealed($0) }
            )

            if editor.tool == .laser, !editor.isReadOnly {
                LaserPointerOverlay(mode: editor.laserMode)
            }

            if editor.tool == .elements, !editor.isReadOnly {
                ElementEditLayer(
                    page: page,
                    selectedID: $selectedElementID,
                    onFrame: { elementID, frame in
                        Task { await session.updateElementFrame(elementID, frame: frame) }
                    },
                    onLock: { elementID, isLocked in
                        Task { await session.setElementLocked(elementID, isLocked: isLocked) }
                    },
                    onDelete: { elementID in
                        selectedElementID = nil
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
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private func macPageImage(_ page: Page) -> some View {
        if let image = PageRenderer.image(
            strokes: page.renderStrokes,
            pageSize: CGSize(width: page.width, height: page.height),
            template: page.template,
            elements: page.visibleElements,
            assetsDirectory: session.assetsDirectory
        ) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            PaperBackground(page: page, assetsDirectory: session.assetsDirectory)
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
