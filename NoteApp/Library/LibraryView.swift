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
    @State private var tagTarget: NotebookManifest?
    @State private var tagsText = ""

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
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search notebooks and handwriting")
        .onChange(of: model.searchText) { _, query in
            Task { await model.updateHandwritingSearch(query) }
        }
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
            Text("The notebook can be restored from Recently Deleted.")
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
            Text("Only the folder is removed. Its notebooks stay in the library at the root.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: locationSelection) {
            Section {
                Label("All Notebooks", systemImage: "books.vertical")
                    .tag(AppModel.Location.all)
                Label("Favourites", systemImage: "star")
                    .tag(AppModel.Location.favourites)
            }

            Section("Folders") {
                ForEach(flattenedFolders()) { row in
                    FolderSidebarRow(folder: row.folder, depth: row.depth)
                        .tag(AppModel.Location.folder(row.folder.id))
                        .contextMenu {
                            Button("New Subfolder", systemImage: "folder.badge.plus") {
                                newFolderParent = row.folder.id
                                newFolderName = ""
                                isCreatingFolder = true
                            }
                            Button("Rename", systemImage: "pencil") {
                                renameFolderTarget = row.folder
                                renameFolderText = row.folder.name
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleteFolderTarget = row.folder
                            }
                        }
                }
            }

            Section {
                Label("Recently Deleted", systemImage: "trash")
                    .tag(AppModel.Location.trash)
            }
        }
        .navigationTitle("NoteApp")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFolderParent = nil
                    newFolderName = ""
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private struct FolderRow: Identifiable {
        var folder: Folder
        var depth: Int
        var id: UUID { folder.id }
    }

    private func flattenedFolders(parent: UUID? = nil, depth: Int = 0) -> [FolderRow] {
        model.folderTree.folders
            .filter { $0.parentID == parent }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .flatMap { folder in
                [FolderRow(folder: folder, depth: depth)]
                    + flattenedFolders(parent: folder.id, depth: depth + 1)
            }
    }

    // MARK: - Detail

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A deleted page can leave a stale hit until the index is pruned.
    private var handwritingHits: [SearchKit.SearchHit] {
        model.search.hits.filter {
            model.pageNumber(notebookID: $0.notebookID, pageID: $0.pageID) != nil
        }
    }

    private var detail: some View {
        Group {
            if model.selectedLocation == .trash {
                trashList
            } else if isSearching {
                searchResults
            } else if model.visibleNotebooks.isEmpty {
                emptyState
            } else {
                notebookGrid
            }
        }
        .navigationTitle(model.selectedLocationTitle)
        .toolbar {
            if model.selectedLocation != .trash {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPDFImporter = true
                    } label: {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.createNotebook() }
                    } label: {
                        Label("New Notebook", systemImage: "plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await model.importPDF(from: url) }
                }
            case .failure(let error):
                model.notice = AppModel.Notice(
                    title: "Could not open the PDF",
                    message: error.localizedDescription
                )
            }
        }
    }

    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !model.visibleNotebooks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notebooks")
                            .font(.headline)
                        ForEach(model.visibleNotebooks, id: \.id) { notebook in
                            Button {
                                Task { await model.open(notebook) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "book.closed")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(notebook.title)
                                            .font(.body.weight(.medium))
                                        Text("\(notebook.pageOrder.count) page\(notebook.pageOrder.count == 1 ? "" : "s")")
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
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }

                if !handwritingHits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("In handwriting")
                            .font(.headline)
                        ForEach(handwritingHits) { hit in
                            handwritingHitRow(hit)
                            Divider()
                        }
                    }
                }

                if model.visibleNotebooks.isEmpty && handwritingHits.isEmpty {
                    if model.search.isIndexing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading handwriting… \(model.search.indexedPages) of \(model.search.totalPages)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    } else {
                        ContentUnavailableView.search(text: model.searchText)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColor.groupedBackground)
    }

    @ViewBuilder
    private func handwritingHitRow(_ hit: SearchKit.SearchHit) -> some View {
        let notebook = model.notebook(withID: hit.notebookID)
        let page = model.pageNumber(notebookID: hit.notebookID, pageID: hit.pageID)
        Button {
            if let notebook {
                Task { await model.open(notebook, pageID: hit.pageID) }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notebook?.title ?? "Notebook")
                        .font(.body.weight(.medium))
                    Text(hit.snippet)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(page.map { "Page \($0)" } ?? "Page")
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
        .buttonStyle(.plain)
    }

    private var notebookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 24)],
                spacing: 28
            ) {
                ForEach(model.visibleNotebooks, id: \.id) { notebook in
                    NotebookCard(
                        notebook: notebook,
                        store: model.store,
                        isFavourite: model.isFavourite(notebook.id),
                        folderName: model.folderName(for: notebook.id)
                    )
                    .onTapGesture {
                        Task { await model.open(notebook) }
                    }
                    .contextMenu {
                        Button("Open", systemImage: "book") {
                            Task { await model.open(notebook) }
                        }
                        Button(
                            model.isFavourite(notebook.id) ? "Remove from Favourites" : "Add to Favourites",
                            systemImage: model.isFavourite(notebook.id) ? "star.slash" : "star"
                        ) {
                            Task { await model.toggleFavourite(notebook) }
                        }
                        Button("Rename", systemImage: "pencil") {
                            renameText = notebook.title
                            renameTarget = notebook
                        }
                        Button("Tags…", systemImage: "tag") {
                            tagsText = model.tags(for: notebook.id).joined(separator: ", ")
                            tagTarget = notebook
                        }
                        Menu("Move to Folder", systemImage: "folder") {
                            Button("Root") {
                                Task { await model.move(notebook, to: nil) }
                            }
                            ForEach(model.folderTree.folders.sorted(by: { $0.name < $1.name })) { folder in
                                Button(folder.name) {
                                    Task { await model.move(notebook, to: folder.id) }
                                }
                            }
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteTarget = notebook
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(AppColor.groupedBackground)
    }

    private var trashList: some View {
        List {
            ForEach(model.visibleNotebooks, id: \.id) { notebook in
                HStack(spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notebook.title)
                        Text(notebook.updatedAt, format: .dateTime.day().month().year())
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
                    description: Text("Notebooks you delete appear here for a while.")
                )
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.searchText.isEmpty ? "No Notebooks" : "No Matches", systemImage: "book.closed")
        } description: {
            Text(model.searchText.isEmpty
                 ? "Create a notebook and start writing."
                 : "Try a different search.")
        } actions: {
            if model.searchText.isEmpty {
                Button("New Notebook") {
                    Task { await model.createNotebook() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
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

private struct FolderSidebarRow: View {
    let folder: Folder
    let depth: Int

    var body: some View {
        Label(folder.name, systemImage: "folder")
            .padding(.leading, CGFloat(depth) * 14)
    }
}

private struct NotebookCard: View {
    let notebook: NotebookManifest
    let store: LibraryStore
    let isFavourite: Bool
    let folderName: String?

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

    private var titleColor: Color {
        coverStyle?.prefersLightText == false ? .black.opacity(0.72) : .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: coverColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let coverStyle {
                        Image(systemName: coverStyle.symbol)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(titleColor.opacity(0.35))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(22)
                    } else if let cover {
                        Image(inkImage: cover)
                            .resizable()
                            .scaledToFill()
                    }

                    if coverStyle == nil {
                        LinearGradient(
                            colors: [.clear, .black.opacity(cover == nil ? 0.15 : 0.62)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: coverStyle?.symbol ?? "book.closed")
                            .font(.title2)
                            .opacity(0.9)
                        Text(notebook.title)
                            .font(.headline)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(titleColor)
                    .shadow(
                        color: coverStyle?.prefersLightText == false ? .clear : .black.opacity(0.35),
                        radius: 4,
                        y: 1
                    )
                    .padding(18)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .task(id: notebook.id) {
                    await loadCover()
                }

                if isFavourite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(10)
                        .background(.black.opacity(0.18), in: Circle())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private func loadCover() async {
        guard coverStyle == nil, let pageID = notebook.pageOrder.first else { return }
        if let cached = ThumbnailCache.image(notebookID: notebook.id, pageID: pageID) {
            cover = cached
            return
        }
        guard let page = try? await store.loadPage(pageID, in: notebook.id),
              let rendered = PageRenderer.image(
                  strokes: page.strokes,
                  pageSize: CGSize(width: page.width, height: page.height),
                  template: page.template,
                  elements: page.elements,
                  assetsDirectory: store.assetsDirectoryURL(for: notebook.id),
                  scale: 1
              )
        else { return }
        ThumbnailCache.store(rendered, notebookID: notebook.id, pageID: pageID)
        cover = rendered
    }

    private var subtitle: String {
        let pages = notebook.pageOrder.count
        let date = notebook.updatedAt.formatted(.relative(presentation: .named))
        if let folderName {
            return "\(folderName) · \(pages) page\(pages == 1 ? "" : "s") · \(date)"
        }
        return "\(pages) page\(pages == 1 ? "" : "s") · \(date)"
    }
}
