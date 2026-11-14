import InkKit
import NoteCore
import SearchKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var purgeTarget: NotebookManifest?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParent: UUID?
    @State private var renameFolderTarget: Folder?
    @State private var renameFolderText = ""
    @State private var deleteFolderTarget: Folder?
    @State private var showPDFImporter = false
    @State private var pdfImport: PDFImportFlow?
    @State private var isSearchPresented = false
    @State private var showsEmptyTrashAlert = false
    @State private var showsSettings = false
    /// The sidebar's Pinned Pages row: page bookmarks across the library.
    @State private var showsPinnedPages = false
    /// The tag shown by the sidebar, lowercased to match stored labels.
    @State private var selectedTag: String?
    /// The search field's text, including `tag:` filters. The model only sees
    /// the words that actually search, so a bare tag filters instead of
    /// searching for the word "tag".
    @State private var queryText = ""
    /// Hits grouped once per search, instead of on every body pass.
    @State private var searchGroups: [NotebookSearchGroup] = []
    /// The grid's list and the sidebar's derived values, recomputed when one of
    /// their inputs changes instead of on every body pass. Nil until the first
    /// pass lands, so the first frame reads them straight from the model.
    @State private var gridNotebooks: [NotebookManifest]?
    @State private var cachedFolderNodes: [FolderNode]?
    @State private var cachedFolderCounts: [UUID: Int]?
    @State private var cachedTagSummaries: [TagSummary]?
    @State private var cachedTagSets: [UUID: Set<String>]?

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
            text: $queryText,
            isPresented: $isSearchPresented,
            placement: .sidebar,
            prompt: "Search notebooks and handwriting"
        )
        .onChange(of: queryText) { _, raw in
            handleQueryChange(raw)
        }
        .onChange(of: model.searchText) { _, text in
            // Another surface (the Pencil pad) writes the model's query directly.
            guard TagQuery(queryText).text != text else { return }
            queryText = text
            handleQueryChange(text)
        }
        .onAppear {
            if queryText.isEmpty, !model.searchText.isEmpty {
                queryText = model.searchText
            }
        }
        .onChange(of: model.selectedLocation) { _, _ in
            // A query belongs to the screen it was typed on.
            model.clearSearch()
            queryText = ""
            selectedTag = nil
            showsPinnedPages = false
        }
        .onChange(of: model.search.hits) { _, hits in
            searchGroups = groupedSearchHits(hits)
        }
        .onChange(of: libraryInputs, initial: true) { _, inputs in
            refreshLibrary(inputs)
        }
        .background(AppColor.groupedBackground)
        .background(alignment: .topLeading) {
            newNotebookShortcut
            if !model.tabs.isEmpty { closeTabShortcut }
        }
        .alert("New folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                // Read the name now: the task runs after the field is cleared.
                let name = newFolderName
                let parent = newFolderParent
                Task { await model.createFolder(named: name, parentID: parent) }
                newFolderName = ""
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .alert("Delete Permanently?", isPresented: purgeAlert) {
            Button("Cancel", role: .cancel) { purgeTarget = nil }
            Button("Delete Permanently", role: .destructive) {
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
            Button("Delete Permanently", role: .destructive) {
                Task { await model.emptyTrash() }
            }
        } message: {
            Text("Every notebook in Recently Deleted is removed for good. This cannot be undone.")
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

    /// ⌘W closes the tab on screen, the library's counterpart of the editor's
    /// Close. It exists only while a tab is open, so with no tabs the window
    /// keeps the system's ⌘W.
    private var closeTabShortcut: some View {
        Button("Close Tab") {
            if let active = model.session { model.closeTab(active) }
        }
        .keyboardShortcut("w", modifiers: .command)
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
                pinnedPagesRow
            }

            Section("Folders") {
                if folderNodes.isEmpty {
                    Text("No folders yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(folderNodes, children: \.children) { node in
                        folderRow(node.folder, depth: node.depth)
                    }
                }
            }

            if !tagSummaries.isEmpty {
                Section {
                    ForEach(tagSummaries) { summary in
                        tagRow(summary)
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Type tag:name in search to filter by tag.")
                        .font(.caption2)
                }
            }

            Section("Documents") {
                Label("Text Documents", systemImage: "doc.text")
                    .tag(AppModel.Location.textDocuments)
                Label("Whiteboards", systemImage: "rectangle.3.group")
                    .tag(AppModel.Location.whiteboards)
                Label("Study Sets", systemImage: "rectangle.stack")
                    .badge(model.study.totalDueCount)
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
                    beginCreatingFolder(parent: newFolderParentForLocation())
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .disabled(!canAddFolderAtSelection)
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
        let depth: Int
        let children: [FolderNode]?
        var id: UUID { folder.id }
    }

    private var folderNodes: [FolderNode] {
        cachedFolderNodes ?? buildFolderNodes(parent: nil, depth: 0, folders: model.folderTree.folders)
    }

    /// The sidebar tree, built once per change of the folder tree rather than
    /// once per body pass. A hand-edited folders.json could contain a cycle;
    /// stop descending instead of recursing forever.
    private func buildFolderNodes(parent: UUID?, depth: Int, folders: [Folder]) -> [FolderNode] {
        guard depth < AppModel.maxFolderDepth else { return [] }
        return folders
            .filter { $0.parentID == parent }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { folder in
                let children = buildFolderNodes(
                    parent: folder.id,
                    depth: depth + 1,
                    folders: folders
                )
                return FolderNode(folder: folder, depth: depth, children: children.isEmpty ? nil : children)
            }
    }

    /// Notebooks per folder, computed in one pass over the assignments.
    private var folderCounts: [UUID: Int] {
        cachedFolderCounts ?? LibraryVisibility.folderCounts(
            folders: model.folderTree.folders,
            notebookFolder: model.folderTree.notebookFolder
        )
    }

    private func folderRow(_ folder: Folder, depth: Int) -> some View {
        Label {
            Text(folder.name)
        } icon: {
            Image(systemName: folder.iconName ?? "folder")
                .foregroundStyle(folderColor(folder))
        }
        .badge(folderCounts[folder.id] ?? 0)
        .tag(AppModel.Location.folder(folder.id))
        .contextMenu { folderMenu(folder, depth: depth) }
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let notebookID = UUID(uuidString: text) else { return false }
            Task { await model.moveNotebook(withID: notebookID, to: folder.id) }
            return true
        }
    }

    /// True when a folder one level down would still be shown by the tree.
    private func canAddSubfolder(at depth: Int) -> Bool {
        depth + 1 < AppModel.maxFolderDepth
    }

    /// The library-wide pinned pages: bookmarks from every notebook, side by
    /// side, instead of a dot buried in one notebook's outline.
    private var pinnedPagesRow: some View {
        Button {
            showsPinnedPages.toggle()
        } label: {
            HStack(spacing: 8) {
                Label(
                    "Pinned Pages",
                    systemImage: showsPinnedPages ? "bookmark.fill" : "bookmark"
                )
                Spacer(minLength: 4)
                Text("\(pinnedCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(showsPinnedPages ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showsPinnedPages ? [.isSelected] : [])
        .accessibilityValue(Text(verbatim: showsPinnedPages ? "Selected" : ""))
    }

    private func tagRow(_ summary: TagSummary) -> some View {
        let isSelected = selectedTag == summary.key
        return Button {
            toggleTag(summary.key)
        } label: {
            HStack(spacing: 8) {
                Label(summary.name, systemImage: isSelected ? "tag.fill" : "tag")
                Spacer(minLength: 4)
                Text("\(summary.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(Text(verbatim: isSelected ? "Selected" : ""))
    }

    private func toggleTag(_ key: String) {
        selectedTag = selectedTag == key ? nil : key
        showsPinnedPages = false
    }

    private var tagSummaries: [TagSummary] {
        cachedTagSummaries ?? TagSummary.summaries(notebooks: model.notebooks, tags: model.tags(for:))
    }

    /// Every notebook's lowercased tags, built once per change of the tree.
    private var notebookTagSets: [UUID: Set<String>] {
        cachedTagSets ?? LibraryVisibility.tagSets(for: model.notebooks, tags: model.tags(for:))
    }

    /// Tags from the sidebar and from `tag:` tokens in the search field. All of
    /// them must be on a notebook for it to show.
    private var activeTagKeys: Set<String> {
        activeTagKeys(query: queryText, selectedTag: selectedTag)
    }

    private func activeTagKeys(query: String, selectedTag: String?) -> Set<String> {
        var keys = TagQuery(query).tagKeys
        if let selectedTag { keys.insert(selectedTag) }
        return keys
    }

    private var activeTagNames: [String] {
        let summaries = tagSummaries
        return activeTagKeys.sorted().map { key in
            summaries.first { $0.key == key }?.name ?? key
        }
    }

    private func matchesActiveTags(_ notebookID: UUID) -> Bool {
        LibraryVisibility.matches(
            notebookID: notebookID,
            requiredTags: activeTagKeys,
            tagSets: notebookTagSets
        )
    }

    /// Everything the grid's derived lists read. Only a change here recomputes
    /// them.
    private var libraryInputs: LibraryInputs {
        LibraryInputs(
            notebooks: model.notebooks,
            trashedNotebooks: model.trashedNotebooks,
            location: model.selectedLocation,
            sortOrder: model.sortOrder,
            searchText: model.searchText,
            query: queryText,
            dateRange: model.search.dateRange,
            selectedTag: selectedTag,
            folderTree: model.folderTree
        )
    }

    /// The grid's list: the sidebar row's browse list, narrowed by the active
    /// tags. Falls back to a direct computation until the first change pass.
    private var shownNotebooks: [NotebookManifest] {
        if let gridNotebooks { return gridNotebooks }
        return LibraryVisibility.filter(
            model.visibleNotebooks,
            requiredTags: activeTagKeys,
            tagSets: notebookTagSets
        )
    }

    /// Recomputes what the grid and the sidebar show, once per input change.
    /// The expensive parts are `visibleNotebooks` (filter and sort), the tag
    /// filter and the folder badges; none of them belong in a body pass.
    private func refreshLibrary(_ inputs: LibraryInputs) {
        let required = activeTagKeys(query: inputs.query, selectedTag: inputs.selectedTag)
        let sets = LibraryVisibility.tagSets(for: inputs.notebooks) {
            inputs.folderTree.tags[$0] ?? []
        }
        cachedTagSets = sets
        cachedTagSummaries = TagSummary.summaries(notebooks: inputs.notebooks) {
            inputs.folderTree.tags[$0] ?? []
        }
        cachedFolderCounts = LibraryVisibility.folderCounts(
            folders: inputs.folderTree.folders,
            notebookFolder: inputs.folderTree.notebookFolder
        )
        cachedFolderNodes = buildFolderNodes(
            parent: nil,
            depth: 0,
            folders: inputs.folderTree.folders
        )
        gridNotebooks = LibraryVisibility.filter(
            model.visibleNotebooks,
            requiredTags: required,
            tagSets: sets
        )
    }

    private var pinnedCount: Int {
        model.bookmarks.allBookmarks.reduce(into: 0) { count, bookmark in
            guard let notebook = model.notebook(withID: bookmark.notebookID),
                  notebook.pageOrder.contains(bookmark.pageID)
            else { return }
            count += 1
        }
    }

    /// Keeps the model's query (which the handwriting index searches) free of
    /// `tag:` tokens, which only the library filters.
    private func handleQueryChange(_ raw: String) {
        let parsed = TagQuery(raw)
        if model.searchText != parsed.text {
            model.searchText = parsed.text
        }
        model.updateHandwritingSearch(parsed.text)
    }

    private func clearTagFilter() {
        selectedTag = nil
        let parsed = TagQuery(queryText)
        guard !parsed.tags.isEmpty else { return }
        queryText = parsed.text
        handleQueryChange(parsed.text)
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder, depth: Int) -> some View {
        if canAddSubfolder(at: depth) {
            Button("New Subfolder", systemImage: "folder.badge.plus") {
                beginCreatingFolder(parent: folder.id)
            }
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

    /// Every folder a folder may move into: not itself, not its descendants, and
    /// not one so deep that the moved folder would leave the visible tree.
    private func folderMoveTargets(for folder: Folder) -> [AppModel.FolderPath] {
        let excluded = model.descendantFolderIDs(of: folder.id)
        return model.folderPaths.filter {
            !excluded.contains($0.id) && canAddSubfolder(at: $0.depth)
        }
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
            if showsPinnedPages {
                PinnedPagesList(model: model)
            } else {
                switch model.selectedLocation {
                case .trash:
                    trashList
                case .textDocuments:
                    TextDocumentsView(model: model.textDocs, showsDoneButton: false)
                case .whiteboards:
                    BoardsView(model: model.boards, showsDoneButton: false)
                case .studySets:
                    StudyLibraryView(study: model.study, showsDoneButton: false) { notebookID, pageID in
                        guard let notebook = model.notebook(withID: notebookID) else { return }
                        Task { await model.open(notebook, pageID: pageID) }
                    }
                case .all, .recents, .favourites, .folder:
                    notebookLibrary
                }
            }
        }
        .background(AppColor.groupedBackground)
        .navigationTitle(detailTitle)
        .toolbar { detailToolbar }
    }

    /// A search runs over everything, and the title says so.
    private var detailTitle: String {
        if showsPinnedPages {
            return "Pinned Pages"
        }
        if model.isSearching, model.showsNotebookLibrary, model.selectedLocation != .trash {
            return "All Notebooks"
        }
        return model.selectedLocationTitle
    }

    @ViewBuilder
    private var notebookLibrary: some View {
        let visibleNotebooks = shownNotebooks
        if let loadError = model.loadError {
            loadErrorView(loadError)
        } else if model.isSearching {
            searchResults(visibleNotebooks)
        } else if visibleNotebooks.isEmpty && !activeTagKeys.isEmpty {
            taggedEmptyState
        } else if visibleNotebooks.isEmpty {
            emptyState
        } else {
            notebookGrid(visibleNotebooks)
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if !model.tabs.isEmpty {
            ToolbarItem(placement: .navigation) {
                openTabsMenu
            }
        }
        if model.showsNotebookLibrary && model.selectedLocation != .trash && !showsPinnedPages {
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
        if showsPinnedPages {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    showsPinnedPages = false
                }
            }
        }
        if model.selectedLocation == .trash && !model.trashedNotebooks.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showsEmptyTrashAlert = true
                } label: {
                    Label("Empty Recently Deleted", systemImage: "trash.slash")
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
            Menu("Close Tab", systemImage: "xmark") {
                ForEach(model.tabs) { tab in
                    Button(tab.manifest.title) {
                        model.closeTab(tab)
                    }
                }
            }
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
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("New Folder", systemImage: "folder.badge.plus") {
                beginCreatingFolder(parent: newFolderParentForLocation())
            }
            .disabled(!canAddFolderAtSelection)
            .keyboardShortcut("n", modifiers: [.command, .shift])
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

    /// The selected folder cannot take a subfolder once it is at the depth limit.
    private var canAddFolderAtSelection: Bool {
        guard case .folder(let folderID) = model.selectedLocation,
              let depth = model.folderPaths.first(where: { $0.id == folderID })?.depth
        else { return true }
        return canAddSubfolder(at: depth)
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
        /// Stored, not recomputed on every read: the header reads it per body pass.
        let pageCount: Int

        var id: UUID { notebook.id }

        func hits(for source: PageTextSource) -> [SearchKit.SearchHit] {
            hits.filter { $0.source == source }
        }
    }

    /// Search hits grouped under the notebook they came from. Sections inside a
    /// notebook follow the order "Written Notes", "Text", "PDFs".
    ///
    /// Runs when the hits change, not on every render: the library's body reads
    /// this list for its sections and chips.
    private func groupedSearchHits(_ hits: [SearchKit.SearchHit]) -> [NotebookSearchGroup] {
        let byNotebook = Dictionary(grouping: hits) { $0.notebookID }
        return byNotebook.compactMap { notebookID, hits -> NotebookSearchGroup? in
            guard let notebook = model.notebook(withID: notebookID) else { return nil }
            // One page index per notebook, so grouping a thousand-page notebook
            // does not scan `pageOrder` once per hit.
            var pageIndex: [UUID: Int] = [:]
            pageIndex.reserveCapacity(notebook.pageOrder.count)
            for (index, pageID) in notebook.pageOrder.enumerated() where pageIndex[pageID] == nil {
                pageIndex[pageID] = index
            }
            // A hit whose page has been deleted is stale. Older records have no
            // page number, so it comes from the manifest while grouping here.
            let live = hits.compactMap { hit -> SearchKit.SearchHit? in
                guard let index = pageIndex[hit.pageID] else { return nil }
                guard hit.pageIndex == 0 else { return hit }
                var resolved = hit
                resolved.pageIndex = index + 1
                return resolved
            }
            guard !live.isEmpty else { return nil }
            let sorted = live.sorted { lhs, rhs in
                if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
                return sourceOrder(lhs.source) < sourceOrder(rhs.source)
            }
            return NotebookSearchGroup(
                notebook: notebook,
                hits: sorted,
                pageCount: Set(sorted.map(\.pageID)).count
            )
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
    private func searchResults(_ visibleNotebooks: [NotebookManifest]) -> some View {
        let groups = visibleSearchGroups
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                tagFilterBar

                if let error = model.search.lastError {
                    searchErrorRow(error)
                }

                if !visibleNotebooks.isEmpty {
                    resultSection("Notebooks") {
                        ForEach(visibleNotebooks, id: \.id) { notebook in
                            Button {
                                Task { await model.open(notebook) }
                            } label: {
                                notebookResultRow(notebook)
                            }
                            .buttonStyle(.plain)
                            .notebookContextActions(model: model, notebook: notebook, includesCover: false)
                            Divider()
                        }
                    }
                }

                ForEach(groups) { group in
                    notebookSearchGroupView(group)
                }

                if visibleNotebooks.isEmpty && groups.isEmpty {
                    if model.search.isIndexing {
                        HStack(spacing: AppSpacing.s) {
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

    /// Search hits are grouped per notebook, so the tag filter applies to the
    /// group's notebook rather than to each hit.
    private var visibleSearchGroups: [NotebookSearchGroup] {
        guard !activeTagKeys.isEmpty else { return searchGroups }
        return searchGroups.filter { matchesActiveTags($0.notebook.id) }
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
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
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
        VStack(alignment: .leading, spacing: AppSpacing.l) {
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
                            LazyHStack(alignment: .top, spacing: AppSpacing.s) {
                                ForEach(sourceHits.prefix(Self.searchChipsPerSource)) { hit in
                                    SearchHitChip(hit: hit, pageLabel: hit.pageLabel) {
                                        open(hit, in: group)
                                    }
                                }
                                if sourceHits.count > Self.searchChipsPerSource,
                                   let first = sourceHits.first {
                                    SearchMoreChip(
                                        count: sourceHits.count - Self.searchChipsPerSource,
                                        pageLabel: first.pageLabel
                                    ) {
                                        open(first, in: group)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.l)
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

    /// How many hit chips a source row draws before it offers the rest. A broad
    /// query can match every page of a long notebook, and each chip is a view
    /// with a snippet, a highlight and a background.
    private static let searchChipsPerSource = 20

    private func open(_ hit: SearchKit.SearchHit, in group: NotebookSearchGroup) {
        Task {
            await model.open(
                group.notebook,
                pageID: hit.pageID,
                highlighting: SearchHighlight(
                    query: model.searchText,
                    sources: model.search.filter.sources,
                    dateRange: model.search.dateRange
                )
            )
        }
    }

    // MARK: - Grid

    private func notebookGrid(_ visibleNotebooks: [NotebookManifest]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                tagFilterBar
                // The Continue rail is library-wide, so it sits under All only.
                if model.selectedLocation == .all, activeTagKeys.isEmpty {
                    ContinueRail(model: model)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 20)],
                    spacing: 24
                ) {
                    ForEach(visibleNotebooks, id: \.id) { notebook in
                        NotebookCard(
                            notebook: notebook,
                            store: model.store,
                            isFavourite: model.isFavourite(notebook.id),
                            isOpen: model.isOpen(notebook.id),
                            tags: model.tags(for: notebook.id)
                        ) {
                            Task { await model.open(notebook) }
                        }
                        .notebookContextActions(model: model, notebook: notebook)
                        .draggable(notebook.id.uuidString)
                        .transition(cardTransition)
                    }
                }
                .appAnimation(gridAnimation, value: visibleNotebooks.map(\.id))
            }
            .padding(20)
        }
    }

    /// Inserts, removals and sort changes in the grid follow the shared standard
    /// curve; Reduce Motion keeps only the fade.
    private var gridAnimation: Animation {
        reduceMotion ? AppMotion.fade : AppMotion.standard
    }

    /// A card the grid gains or loses, without moving the neighbours' content.
    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }

    /// The tags narrowing the grid, with one way to clear them. Empty when no
    /// tag filter is active.
    @ViewBuilder
    private var tagFilterBar: some View {
        let names = activeTagNames
        if !names.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(names, id: \.self) { name in
                    TagChip(tag: name, isActive: true)
                }
                Spacer(minLength: 4)
                Button("Clear") {
                    clearTagFilter()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Empty states

    private var taggedEmptyState: some View {
        ContentUnavailableView {
            Label("No Notebooks Tagged", systemImage: "tag")
        } description: {
            Text("None of the notebooks here carry \(activeTagNames.joined(separator: ", ")).")
        } actions: {
            Button("Clear Tag Filter") {
                clearTagFilter()
            }
            .buttonStyle(.borderedProminent)
        }
    }

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
        let visibleNotebooks = model.visibleNotebooks
        return List {
            ForEach(visibleNotebooks, id: \.id) { notebook in
                HStack(spacing: AppSpacing.l) {
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
                    Button("Delete Permanently", role: .destructive) {
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
            if visibleNotebooks.isEmpty {
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

    private var renameFolderAlert: Binding<Bool> {
        Binding(get: { renameFolderTarget != nil }, set: { if !$0 { renameFolderTarget = nil } })
    }

    private var purgeAlert: Binding<Bool> {
        Binding(get: { purgeTarget != nil }, set: { if !$0 { purgeTarget = nil } })
    }

    private var deleteFolderAlert: Binding<Bool> {
        Binding(get: { deleteFolderTarget != nil }, set: { if !$0 { deleteFolderTarget = nil } })
    }

}

/// Everything the grid's derived lists read. A change here, and only a change
/// here, recomputes them.
private struct LibraryInputs: Equatable {
    let notebooks: [NotebookManifest]
    let trashedNotebooks: [NotebookManifest]
    let location: AppModel.Location
    let sortOrder: AppModel.SortOrder
    let searchText: String
    let query: String
    let dateRange: SearchDateRange
    let selectedTag: String?
    let folderTree: FolderTree
}

/// One tag, in the active-filter bar and on a notebook card. Both drew their
/// own chip before, with different padding and fonts, so the same tag changed
/// size as it moved.
private struct TagChip: View {
    let tag: String
    /// The filter bar tints its chips with the accent to read as active.
    var isActive = false

    var body: some View {
        Text(tag)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xxs)
            .background((isActive ? Color.accentColor : Color.secondary).opacity(0.14), in: Capsule())
    }
}

/// One page of search hits: "p.12" plus the excerpt with the match marked.
private struct SearchHitChip: View {
    let hit: SearchKit.SearchHit
    let pageLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(pageLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HighlightedSnippet(snippet: hit.snippet, matchRange: hit.matchRange, lineLimit: 3)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.m)
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

/// The rest of a source's hits, behind one chip: a broad query can match more
/// pages than a row can draw, and opening the notebook is how the user sees them.
private struct SearchMoreChip: View {
    let count: Int
    let pageLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.s) {
                Text("+\(count)")
                    .font(.headline.monospacedDigit())
                Text("more from \(pageLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(AppSpacing.m)
            .frame(width: 150, height: 92)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(count) more matches, open at \(pageLabel)"))
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
        .task(id: coverTaskID) {
            guard coverStyle == nil else { return }
            if let cached = LibraryCovers.cached(notebook: notebook) {
                cover = cached
                return
            }
            let image = await LibraryCovers.image(for: notebook, store: store)
            guard !Task.isCancelled else { return }
            cover = image
        }
    }

    /// The same key the grid card uses: the notebook's first page and
    /// `updatedAt`, so an edited notebook's cover is drawn again, plus the
    /// cover generation so "Regenerate Thumbnails" reloads it too.
    private var coverTaskID: String {
        "\(notebook.id.uuidString)-\(notebook.pageOrder.first?.uuidString ?? "none")"
            + "-\(Int(notebook.updatedAt.timeIntervalSince1970))"
            + "-\(LibraryCovers.generation)"
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
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                coverArt
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
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
        .accessibilityLabel(Text(accessibilityDescription))
        .task(id: coverTaskID) {
            await loadCover()
        }
    }

    /// The card's explicit label replaces its children, so the grid's own Open
    /// badge, favourite star and tag chips would never be announced. Fold them
    /// into the text instead.
    private var accessibilityDescription: String {
        var parts = [notebook.title, pageCountText, dateText]
        if isOpen { parts.append("open") }
        if isFavourite { parts.append("favourite") }
        if !tags.isEmpty { parts.append("tags: " + tags.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
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
                    .padding(AppSpacing.xl)
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
                VStack(spacing: AppSpacing.s) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: symbolSize))
                    Text("Preview unavailable")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: AppSpacing.s) {
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.l, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isOpen {
                Text("Open")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(AppSpacing.m)
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
            RoundedRectangle(cornerRadius: AppRadius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
    }

    private var tagRow: some View {
        HStack(spacing: AppSpacing.s) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                TagChip(tag: tag)
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
            + "-\(LibraryCovers.generation)"
    }

    private func loadCover() async {
        guard coverStyle == nil, !notebook.pageOrder.isEmpty else { return }
        if let cached = LibraryCovers.cached(notebook: notebook) {
            cover = cached
            coverFailed = false
            return
        }
        let image = await LibraryCovers.image(for: notebook, store: store)
        // The card may have been recycled while the render ran.
        guard !Task.isCancelled else { return }
        cover = image
        coverFailed = image == nil
    }
}
