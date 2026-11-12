import InkKit
import NoteCore
import SearchKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: AppModel

    @State private var renameTarget: NotebookManifest?
    @State private var renameText = ""
    @State private var deleteTarget: NotebookManifest?
    @State private var purgeTarget: NotebookManifest?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParent: UUID?
    @State private var renameFolderTarget: Folder?
    @State private var renameFolderText = ""
    @State private var deleteFolderTarget: Folder?
    @State private var showPDFImporter = false
    @State private var pdfImport: PDFImportFlow?
    @State private var tagTarget: NotebookManifest?
    @State private var tagsText = ""
    @State private var coverTarget: CoverTarget?
    @State private var isSearchPresented = false
    @State private var showsEmptyTrashAlert = false
    @State private var showsSettings = false

    /// The library search's source filter; a change searches again.
    private var searchSources: Binding<Set<PageTextSource>> {
        Binding(
            get: { model.search.filter.sources },
            set: {
                model.search.filter.sources = $0
                model.refreshHandwritingSearch()
            }
        )
    }

    /// The library search's edit-date choice; a change searches again.
    private var searchDateRange: Binding<SearchDateRange> {
        Binding(
            get: { model.search.dateRange },
            set: {
                model.search.dateRange = $0
                model.refreshHandwritingSearch()
            }
        )
    }

    private var locationSelection: Binding<AppModel.Location?> {
        Binding(
            get: { model.selectedLocation },
            set: { if let value = $0 { model.selectedLocation = value } }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(
            text: $model.searchText,
            isPresented: $isSearchPresented,
            placement: .sidebar,
            prompt: "Search notebooks and handwriting"
        )
        .onChange(of: model.searchText) { _, query in
            model.updateHandwritingSearch(query)
        }
        .onChange(of: model.selectedLocation) { _, _ in
            // A query belongs to the screen it was typed on.
            model.clearSearch()
        }
        .background(AppColor.groupedBackground)
        .background(alignment: .topLeading) { newNotebookShortcut }
        .alert("Rename notebook", isPresented: renameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let target = renameTarget {
                    Task { await model.rename(target, to: renameText) }
                }
                renameTarget = nil
            }
        }
        .alert("New folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                Task { await model.createFolder(named: newFolderName, parentID: newFolderParent) }
                newFolderName = ""
            }
        }
        .alert("Rename folder", isPresented: renameFolderAlert) {
            TextField("Folder name", text: $renameFolderText)
            Button("Cancel", role: .cancel) { renameFolderTarget = nil }
            Button("Rename") {
                if let target = renameFolderTarget {
                    Task { await model.renameFolder(target, to: renameFolderText) }
                }
                renameFolderTarget = nil
            }
        }
        .alert("Move to Recently Deleted?", isPresented: deleteAlert) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    Task { await model.delete(target) }
                }
                deleteTarget = nil
            }
        } message: {
            Text("The notebook can be restored from Recently Deleted for 30 days.")
        }
        .alert("Delete permanently?", isPresented: purgeAlert) {
            Button("Cancel", role: .cancel) { purgeTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = purgeTarget {
                    Task { await model.purge(target) }
                }
                purgeTarget = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Empty Recently Deleted?", isPresented: $showsEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                Task { await model.emptyTrash() }
            }
        } message: {
            Text("Every notebook in Recently Deleted is removed for good. This cannot be undone.")
        }
        .alert("Tags", isPresented: tagAlert) {
            TextField("Comma-separated tags", text: $tagsText)
            Button("Cancel", role: .cancel) { tagTarget = nil }
            Button("Save") {
                if let target = tagTarget {
                    let tags = tagsText.split(separator: ",").map(String.init)
                    Task { await model.setTags(tags, for: target) }
                }
                tagTarget = nil
            }
        } message: {
            Text("Tags belong to the library, not to the notebook file.")
        }
        .alert("Delete this folder?", isPresented: deleteFolderAlert) {
            Button("Cancel", role: .cancel) { deleteFolderTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = deleteFolderTarget {
                    Task { await model.deleteFolder(target) }
                }
                deleteFolderTarget = nil
            }
        } message: {
            Text("Only the folder is removed. Its notebooks and subfolders move to the folder above it.")
        }
        .sheet(item: $coverTarget) { target in
            NotebookCoverPicker(current: target.notebook.coverName) { name in
                coverTarget = nil
                Task { await model.setCover(name, for: target.notebook) }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: model)
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // One runloop later, so the file picker has finished
                    // dismissing before the import sheet arrives.
                    Task { @MainActor in
                        pdfImport = PDFImportFlow(model: model, url: url, destination: .newNotebook)
                    }
                }
            case .failure(let error):
                model.notice = AppModel.Notice(
                    title: "Could not open the PDF",
                    message: error.localizedDescription
                )
            }
        }
        .sheet(item: $pdfImport) { flow in
            PDFImportSheet(flow: flow)
        }
    }

    /// ⌘N works from anywhere in the library, including the sheet-free detail column.
    private var newNotebookShortcut: some View {
        Button("New Notebook") {
            Task { await model.createNotebook() }
        }
        .keyboardShortcut("n", modifiers: .command)
        .opacity(0)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: locationSelection) {
            Section("Library") {
                Label("All Notebooks", systemImage: "books.vertical")
                    .badge(model.notebooks.count)
                    .tag(AppModel.Location.all)
                Label("Recent", systemImage: "clock")
                    .tag(AppModel.Location.recents)
                Label("Favourites", systemImage: "star")
                    .tag(AppModel.Location.favourites)
            }

            Section("Folders") {
                if folderNodes.isEmpty {
                    Text("No folders yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(folderNodes, children: \.children) { node in
                        folderRow(node.folder)
                    }
                }
            }

            Section("Documents") {
                Label("Text Documents", systemImage: "doc.text")
                    .tag(AppModel.Location.textDocuments)
                Label("Whiteboards", systemImage: "rectangle.3.group")
                    .tag(AppModel.Location.whiteboards)
                Label("Study Sets", systemImage: "rectangle.stack")
                    .tag(AppModel.Location.studySets)
            }

            Section {
                Label("Recently Deleted", systemImage: "trash")
                    .badge(model.trashedNotebooks.count)
                    .tag(AppModel.Location.trash)
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    beginCreatingFolder(parent: nil)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    /// The gear in the library's toolbar, and ⌘, on iOS where there is no
    /// Settings scene to own that shortcut.
    private var settingsButton: some View {
        let button = Button {
            showsSettings = true
        } label: {
            Label("Settings", systemImage: "gear")
        }
        #if os(iOS)
        return button.keyboardShortcut(",", modifiers: .command)
        #else
        return button
        #endif
    }

    private struct FolderNode: Identifiable {
        let folder: Folder
        let children: [FolderNode]?
        var id: UUID { folder.id }
    }

    private var folderNodes: [FolderNode] {
        folderNodes(parent: nil, depth: 0)
    }

    private func folderNodes(parent: UUID?, depth: Int) -> [FolderNode] {
        // A hand-edited folders.json could contain a cycle; stop descending instead
        // of recursing forever.
        guard depth < 12 else { return [] }
        return model.folderTree.folders
            .filter { $0.parentID == parent }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { folder in
                let children = folderNodes(parent: folder.id, depth: depth + 1)
                return FolderNode(folder: folder, children: children.isEmpty ? nil : children)
            }
    }

    private func folderRow(_ folder: Folder) -> some View {
        Label {
            Text(folder.name)
        } icon: {
            Image(systemName: folder.iconName ?? "folder")
                .foregroundStyle(folderColor(folder))
        }
        .badge(model.notebookCount(inFolder: folder.id))
        .tag(AppModel.Location.folder(folder.id))
        .contextMenu { folderMenu(folder) }
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let notebookID = UUID(uuidString: text) else { return false }
            Task { await model.moveNotebook(withID: notebookID, to: folder.id) }
            return true
        }
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button("New Subfolder", systemImage: "folder.badge.plus") {
            beginCreatingFolder(parent: folder.id)
        }
        Button("Rename", systemImage: "pencil") {
            renameFolderTarget = folder
            renameFolderText = folder.name
        }
        Menu("Move to Folder", systemImage: "arrow.turn.up.right") {
            Button("Root") {
                Task { await model.moveFolder(folder, to: nil) }
            }
            ForEach(folderMoveTargets(for: folder)) { path in
                Button {
                    Task { await model.moveFolder(folder, to: path.id) }
                } label: {
                    Text(indented(path))
                }
            }
        }
        Menu("Colour") {
            Button("Default") {
                setAppearance(folder, color: nil, icon: folder.iconName)
            }
            ForEach(folderColors) { option in
                Button {
                    setAppearance(folder, color: option.name, icon: folder.iconName)
                } label: {
                    Label(option.name.capitalized, systemImage: "circle.fill")
                        .foregroundStyle(option.color)
                }
            }
        }
        Menu("Icon") {
            Button("Folder") {
                setAppearance(folder, color: folder.colorName, icon: nil)
            }
            ForEach(folderIcons, id: \.self) { symbol in
                Button {
                    setAppearance(folder, color: folder.colorName, icon: symbol)
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            deleteFolderTarget = folder
        }
    }

    /// Every folder a folder may move into: not itself, not its descendants.
    private func folderMoveTargets(for folder: Folder) -> [AppModel.FolderPath] {
        let excluded = model.descendantFolderIDs(of: folder.id)
        return model.folderPaths.filter { !excluded.contains($0.id) }
    }

    private var folderColors: [FolderColorOption] {
        [
            .init(name: "blue", color: .blue),
            .init(name: "teal", color: .teal),
            .init(name: "green", color: .green),
            .init(name: "orange", color: .orange),
            .init(name: "pink", color: .pink),
            .init(name: "purple", color: .purple),
            .init(name: "red", color: .red),
            .init(name: "gray", color: .gray),
        ]
    }

    private var folderIcons: [String] {
        ["folder", "folder.fill", "books.vertical", "graduationcap", "briefcase", "heart", "star", "tray"]
    }

    private func folderColor(_ folder: Folder) -> Color {
        switch folder.colorName?.lowercased() {
        case "blue": .blue
        case "teal": .teal
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "gray": .gray
        default: .accentColor
        }
    }

    private struct FolderColorOption: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    private func beginCreatingFolder(parent: UUID?) {
        newFolderParent = parent
        newFolderName = ""
        isCreatingFolder = true
    }

    private func setAppearance(_ folder: Folder, color: String?, icon: String?) {
        Task {
            await model.setFolderAppearance(folder, colorName: color, iconName: icon)
        }
    }

    /// Full path with one indent step per level, so two folders with the same name
    /// can be told apart in a move menu.
    private func indented(_ path: AppModel.FolderPath) -> String {
        String(repeating: "    ", count: path.depth) + path.path
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Group {
            switch model.selectedLocation {
            case .trash:
                trashList
            case .textDocuments:
                TextDocumentsView(model: model.textDocs, showsDoneButton: false)
            case .whiteboards:
                BoardsView(model: model.boards, showsDoneButton: false)
            case .studySets:
                StudyLibraryView(study: model.study, showsDoneButton: false)
            case .all, .recents, .favourites, .folder:
                notebookLibrary
            }
        }
        .background(AppColor.groupedBackground)
        .navigationTitle(detailTitle)
        .toolbar { detailToolbar }
    }

    /// A search runs over everything, and the title says so.
    private var detailTitle: String {
        if model.isSearching, model.showsNotebookLibrary, model.selectedLocation != .trash {
            return "All Notebooks"
        }
        return model.selectedLocationTitle
    }

    @ViewBuilder
    private var notebookLibrary: some View {
        if let loadError = model.loadError {
            loadErrorView(loadError)
        } else if model.isSearching {
            searchResults
        } else if model.visibleNotebooks.isEmpty {
            emptyState
        } else {
            notebookGrid
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if !model.tabs.isEmpty {
            ToolbarItem(placement: .navigation) {
                openTabsMenu
            }
        }
        if model.showsNotebookLibrary && model.selectedLocation != .trash {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isSearchPresented = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                PencilSearchButton(search: model.search) { query in
                    model.searchText = query
                    if !query.isEmpty { isSearchPresented = true }
                }
            }
            #endif
            if model.isSearching {
                ToolbarItem(placement: .primaryAction) {
                    SearchFilterMenu(sources: searchSources, dateRange: searchDateRange)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
            ToolbarItem(placement: .primaryAction) {
                newMenu
            }
        }
        if model.selectedLocation == .trash && !model.trashedNotebooks.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showsEmptyTrashAlert = true
                } label: {
                    Label("Empty Trash", systemImage: "trash.slash")
                }
            }
        }
    }

    private var openTabsMenu: some View {
        Menu {
            ForEach(model.tabs) { tab in
                Button {
                    model.activateTab(tab.notebookID)
                } label: {
                    if tab.notebookID == model.activeNotebookID {
                        Label(tab.manifest.title, systemImage: "checkmark")
                    } else {
                        Text(tab.manifest.title)
                    }
                }
            }
            Divider()
            Button("Close All Tabs", systemImage: "xmark.circle", role: .destructive) {
                Task { await model.closeAllTabs() }
            }
        } label: {
            Label("Open Tabs (\(model.tabs.count))", systemImage: "rectangle.on.rectangle")
        }
    }

    private var newMenu: some View {
        Menu {
            Button("New Notebook", systemImage: "book.closed") {
                Task { await model.createNotebook() }
            }
            Button("Import PDF…", systemImage: "square.and.arrow.down") {
                showPDFImporter = true
            }
            Divider()
            Button("New Folder", systemImage: "folder.badge.plus") {
                beginCreatingFolder(parent: newFolderParentForLocation())
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .accessibilityLabel("New notebook, PDF or folder")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sortOrder) {
                ForEach(AppModel.SortOrder.allCases) { order in
                    Label(order.title, systemImage: order.symbol).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort notebooks, \(model.sortOrder.title)")
    }

    private func newFolderParentForLocation() -> UUID? {
        if case .folder(let folderID) = model.selectedLocation { return folderID }
        return nil
    }

    private func loadErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("The Library Could Not Be Opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await model.retryLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Search results

    private struct NotebookSearchGroup: Identifiable {
        let notebook: NotebookManifest
        let hits: [SearchKit.SearchHit]

        var id: UUID { notebook.id }

        var pageCount: Int {
            Set(hits.map(\.pageID)).count
        }

        func hits(for source: PageTextSource) -> [SearchKit.SearchHit] {
            hits.filter { $0.source == source }
        }
    }

    /// Search hits grouped under the notebook they came from. Sections inside a
    /// notebook follow the order "Written Notes", "Text", "PDFs".
    private var searchGroups: [NotebookSearchGroup] {
        let byNotebook = Dictionary(grouping: model.search.hits) { $0.notebookID }
        return byNotebook.compactMap { notebookID, hits in
            guard let notebook = model.notebook(withID: notebookID) else { return nil }
            // A hit whose page has been deleted is stale.
            let live = hits.filter { model.pageNumber(notebookID: notebookID, pageID: $0.pageID) != nil }
            guard !live.isEmpty else { return nil }
            let sorted = live.sorted { lhs, rhs in
                if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
                return sourceOrder(lhs.source) < sourceOrder(rhs.source)
            }
            return NotebookSearchGroup(notebook: notebook, hits: sorted)
        }
        .sorted { lhs, rhs in
            if lhs.hits.count != rhs.hits.count { return lhs.hits.count > rhs.hits.count }
            return lhs.notebook.title.localizedCaseInsensitiveCompare(rhs.notebook.title) == .orderedAscending
        }
    }

    private func sourceOrder(_ source: PageTextSource) -> Int {
        PageTextSource.allCases.firstIndex(of: source) ?? PageTextSource.allCases.count
    }

    /// A search runs over the whole library, so every notebook with a matching title
    /// is listed here regardless of the selected sidebar row.
    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.search.lastError {
                    searchErrorRow(error)
                }

                if !model.visibleNotebooks.isEmpty {
                    resultSection("Notebooks") {
                        ForEach(model.visibleNotebooks, id: \.id) { notebook in
                            Button {
                                Task { await model.open(notebook) }
                            } label: {
                                notebookResultRow(notebook)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }

                ForEach(searchGroups) { group in
                    notebookSearchGroupView(group)
                }

                if model.visibleNotebooks.isEmpty && searchGroups.isEmpty {
                    if model.search.isIndexing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading handwriting… \(model.search.indexedPages) of \(model.search.totalPages)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView.search(text: model.searchText)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resultSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func searchErrorRow(_ error: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func notebookResultRow(_ notebook: NotebookManifest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.title)
                    .font(.body.weight(.medium))
                Text(pageCountText(notebook))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func notebookSearchGroupView(_ group: NotebookSearchGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SearchNotebookCover(notebook: group.notebook, store: model.store)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.notebook.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(hitCountText(group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(PageTextSource.allCases, id: \.self) { source in
                let sourceHits = group.hits(for: source)
                if !sourceHits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.sectionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(sourceHits) { hit in
                                    SearchHitChip(hit: hit, pageLabel: pageLabel(for: hit)) {
                                        Task {
                                            await model.open(
                                                group.notebook,
                                                pageID: hit.pageID,
                                                highlighting: SearchHighlight(
                                                    query: model.searchText,
                                                    sources: model.search.filter.sources
                                                )
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func hitCountText(_ group: NotebookSearchGroup) -> String {
        let matches = group.hits.count
        let pages = group.pageCount
        return "\(matches) match\(matches == 1 ? "" : "es") in \(pages) page\(pages == 1 ? "" : "s")"
    }

    /// The index knows the number; the library is the fallback for older records.
    private func pageLabel(for hit: SearchKit.SearchHit) -> String {
        if hit.pageIndex > 0 { return "p.\(hit.pageIndex)" }
        if let number = model.pageNumber(notebookID: hit.notebookID, pageID: hit.pageID) {
            return "p.\(number)"
        }
        return "Page"
    }

    // MARK: - Grid

    private var notebookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 20)],
                spacing: 24
            ) {
                ForEach(model.visibleNotebooks, id: \.id) { notebook in
                    NotebookCard(
                        notebook: notebook,
                        store: model.store,
                        isFavourite: model.isFavourite(notebook.id),
                        isOpen: model.isOpen(notebook.id),
                        tags: model.tags(for: notebook.id)
                    ) {
                        Task { await model.open(notebook) }
                    }
                    .contextMenu { cardMenu(notebook) }
                    .draggable(notebook.id.uuidString)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func cardMenu(_ notebook: NotebookManifest) -> some View {
        Button("Open", systemImage: "book") {
            Task { await model.open(notebook) }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            Task { await model.duplicate(notebook) }
        }
        Menu("Cover", systemImage: "book.closed") {
            Button("First Page") {
                Task { await model.setCover(nil, for: notebook) }
            }
            ForEach(NotebookCoverStyle.allCases) { style in
                Button {
                    Task { await model.setCover(style.rawValue, for: notebook) }
                } label: {
                    if notebook.coverName == style.rawValue {
                        Label(style.name, systemImage: "checkmark")
                    } else {
                        Text(style.name)
                    }
                }
            }
            Divider()
            Button("Choose Cover…", systemImage: "square.grid.2x2") {
                coverTarget = CoverTarget(notebook: notebook)
            }
        }
        Button("Rename", systemImage: "pencil") {
            renameText = notebook.title
            renameTarget = notebook
        }
        Button("Tags…", systemImage: "tag") {
            tagsText = model.tags(for: notebook.id).joined(separator: ", ")
            tagTarget = notebook
        }
        Button(
            model.isFavourite(notebook.id) ? "Remove from Favourites" : "Add to Favourites",
            systemImage: model.isFavourite(notebook.id) ? "star.slash" : "star"
        ) {
            Task { await model.toggleFavourite(notebook) }
        }
        Menu("Move to Folder", systemImage: "folder") {
            Button("Root") {
                Task { await model.move(notebook, to: nil) }
            }
            ForEach(model.folderPaths) { path in
                Button {
                    Task { await model.move(notebook, to: path.id) }
                } label: {
                    if model.folderID(of: notebook) == path.id {
                        Label(indented(path), systemImage: "checkmark")
                    } else {
                        Text(indented(path))
                    }
                }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            deleteTarget = notebook
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        switch model.selectedLocation {
        case .favourites:
            ContentUnavailableView(
                "No Favourites",
                systemImage: "star",
                description: Text("Star a notebook to see it here.")
            )
        case .recents:
            ContentUnavailableView(
                "No Recent Notebooks",
                systemImage: "clock",
                description: Text("Notebooks you edit appear here.")
            )
        case .folder(let folderID):
            let name = model.folderTree.folder(withID: folderID)?.name ?? "this folder"
            ContentUnavailableView {
                Label("No Notebooks in \(name)", systemImage: "folder")
            } description: {
                Text("Put a notebook here, or move one in from another folder.")
            } actions: {
                Button("New Notebook Here") {
                    Task { await model.createNotebook() }
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            ContentUnavailableView {
                Label("No Notebooks", systemImage: "book.closed")
            } description: {
                Text("Create a notebook and start writing.")
            } actions: {
                Button("New Notebook") {
                    Task { await model.createNotebook() }
                }
                .buttonStyle(.borderedProminent)
                Button("Import PDF…") {
                    showPDFImporter = true
                }
            }
        }
    }

    // MARK: - Trash

    private var trashList: some View {
        List {
            ForEach(model.visibleNotebooks, id: \.id) { notebook in
                HStack(spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notebook.title)
                        Text(deletedDescription(notebook))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") {
                        Task { await model.restore(notebook) }
                    }
                    .buttonStyle(.bordered)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        purgeTarget = notebook
                    }
                }
                .contextMenu {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        Task { await model.restore(notebook) }
                    }
                    Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                        purgeTarget = notebook
                    }
                }
            }
        }
        .overlay {
            if model.visibleNotebooks.isEmpty {
                ContentUnavailableView(
                    "No Deleted Notebooks",
                    systemImage: "trash",
                    description: Text("Notebooks you delete stay here for 30 days.")
                )
            }
        }
    }

    private func deletedDescription(_ notebook: NotebookManifest) -> String {
        guard let deletedAt = notebook.deletedAt else {
            return "Deleted recently · purged after 30 days"
        }
        let days = Int(Date().timeIntervalSince(deletedAt) / (24 * 60 * 60))
        let when = deletedAt.formatted(.dateTime.day().month().year())
        if days >= 1 {
            return "Deleted \(when) · \(30 - min(30, days)) days left"
        }
        return "Deleted \(when)"
    }

    private func pageCountText(_ notebook: NotebookManifest) -> String {
        let pages = notebook.pageOrder.count
        return "\(pages) page\(pages == 1 ? "" : "s")"
    }

    // MARK: - Alert bindings

    private var renameAlert: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var renameFolderAlert: Binding<Bool> {
        Binding(get: { renameFolderTarget != nil }, set: { if !$0 { renameFolderTarget = nil } })
    }

    private var deleteAlert: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var purgeAlert: Binding<Bool> {
        Binding(get: { purgeTarget != nil }, set: { if !$0 { purgeTarget = nil } })
    }

    private var deleteFolderAlert: Binding<Bool> {
        Binding(get: { deleteFolderTarget != nil }, set: { if !$0 { deleteFolderTarget = nil } })
    }

    private var tagAlert: Binding<Bool> {
        Binding(get: { tagTarget != nil }, set: { if !$0 { tagTarget = nil } })
    }
}

private struct CoverTarget: Identifiable {
    let notebook: NotebookManifest
    var id: UUID { notebook.id }
}

/// One page of search hits: "p.12" plus the excerpt with the match marked.
private struct SearchHitChip: View {
    let hit: SearchKit.SearchHit
    let pageLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(pageLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HighlightedSnippet(snippet: hit.snippet, matchRange: hit.matchRange, lineLimit: 3)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(width: 150, height: 92, alignment: .topLeading)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(pageLabel), \(hit.source.sectionTitle)"))
    }
}

/// A compact notebook cover for a search result header, the size of a thumbnail
/// rather than a library card.
private struct SearchNotebookCover: View {
    let notebook: NotebookManifest
    let store: LibraryStore

    @State private var cover: InkImage?

    private var coverStyle: NotebookCoverStyle? {
        notebook.coverName.flatMap(NotebookCoverStyle.init(rawValue:))
    }

    private var coverColors: [Color] {
        if let coverStyle { return coverStyle.colors }
        let seed = notebook.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let palettes: [[Color]] = [
            [.indigo, .blue],
            [.orange, .pink],
            [.teal, .green],
            [.purple, .indigo],
            [.brown, .orange],
        ]
        return palettes[seed % palettes.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let coverStyle {
                Image(systemName: coverStyle.symbol)
                    .font(.caption)
                    .foregroundStyle(coverStyle.prefersLightText == false
                        ? Color.black.opacity(0.5)
                        : Color.white.opacity(0.75))
            } else if let cover {
                Image(inkImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 34, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
        .task(id: notebook.id) {
            guard coverStyle == nil else { return }
            if let cached = LibraryCovers.cached(notebook: notebook) {
                cover = cached
                return
            }
            cover = await LibraryCovers.image(for: notebook, store: store)
        }
    }
}

private struct NotebookCard: View {
    let notebook: NotebookManifest
    let store: LibraryStore
    let isFavourite: Bool
    let isOpen: Bool
    let tags: [String]
    let open: () -> Void

    @State private var cover: InkImage?
    @State private var coverFailed = false
    @ScaledMetric(relativeTo: .title2) private var symbolSize: CGFloat = 22

    private var coverStyle: NotebookCoverStyle? {
        notebook.coverName.flatMap(NotebookCoverStyle.init(rawValue:))
    }

    private var coverColors: [Color] {
        if let coverStyle { return coverStyle.colors }
        let seed = notebook.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let palettes: [[Color]] = [
            [.indigo, .blue],
            [.orange, .pink],
            [.teal, .green],
            [.purple, .indigo],
            [.brown, .orange],
        ]
        return palettes[seed % palettes.count]
    }

    private var coverTint: Color {
        coverStyle?.prefersLightText == false ? .black.opacity(0.65) : .white
    }

    private var pages: Int { notebook.pageOrder.count }

    private var dateText: String {
        notebook.updatedAt.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                coverArt
                VStack(alignment: .leading, spacing: 3) {
                    Text(notebook.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(pageCountText) · \(dateText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !tags.isEmpty { tagRow }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(notebook.title), \(pageCountText), \(dateText)"))
        .task(id: coverTaskID) {
            await loadCover()
        }
    }

    private var coverArt: some View {
        ZStack {
            // The gradient is always there, so the card reads as a cover before the
            // first page render arrives and while it is missing.
            LinearGradient(colors: coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let coverStyle {
                Image(systemName: coverStyle.symbol)
                    .font(.system(size: symbolSize * 1.8, weight: .light))
                    .foregroundStyle(coverTint.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(18)
            } else if let cover {
                Image(inkImage: cover)
                    .resizable()
                    .scaledToFill()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.22)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            } else if coverFailed {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: symbolSize))
                    Text("Preview unavailable")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: symbolSize))
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.7))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isOpen {
                Text("Open")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isFavourite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .padding(12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pageCountText: String {
        "\(pages) page\(pages == 1 ? "" : "s")"
    }

    /// Re-render when the notebook's first page changes, which bumps `updatedAt`.
    private var coverTaskID: String {
        "\(notebook.id.uuidString)-\(notebook.pageOrder.first?.uuidString ?? "none")"
            + "-\(Int(notebook.updatedAt.timeIntervalSince1970))"
    }

    private func loadCover() async {
        guard coverStyle == nil, !notebook.pageOrder.isEmpty else { return }
        if let cached = LibraryCovers.cached(notebook: notebook) {
            cover = cached
            coverFailed = false
            return
        }
        let image = await LibraryCovers.image(for: notebook, store: store)
        cover = image
        coverFailed = image == nil
    }
}
