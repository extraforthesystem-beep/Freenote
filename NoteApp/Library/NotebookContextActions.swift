import NoteCore
import SwiftUI

/// The notebook card's context menu, with the rename, tag, delete and cover
/// prompts it opens, so the grid, the Continue rail and the search results all
/// offer the same actions instead of only the grid having them.
struct NotebookContextActions: ViewModifier {
    let model: AppModel
    let notebook: NotebookManifest
    /// The grid card offers Cover; a page tile and a result row leave it out.
    var includesCover = true

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isEditingTags = false
    @State private var tagsText = ""
    @State private var isConfirmingDelete = false
    @State private var coverTarget: CoverTarget?

    func body(content: Content) -> some View {
        content
            .contextMenu { menu }
            .alert("Rename notebook", isPresented: $isRenaming) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let title = renameText
                    Task { await model.rename(notebook, to: title) }
                }
            }
            .alert("Tags", isPresented: $isEditingTags) {
                TextField("Comma-separated tags", text: $tagsText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let tags = tagsText.split(separator: ",").map(String.init)
                    Task { await model.setTags(tags, for: notebook) }
                }
            } message: {
                Text("Tags belong to the library, not to the notebook file.")
            }
            .alert("Move to Recently Deleted?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await model.delete(notebook) }
                }
            } message: {
                Text("The notebook can be restored from Recently Deleted for 30 days.")
            }
            .sheet(item: $coverTarget) { target in
                NotebookCoverPicker(current: target.notebook.coverName) { name in
                    coverTarget = nil
                    Task { await model.setCover(name, for: target.notebook) }
                }
            }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open", systemImage: "book") {
            Task { await model.open(notebook) }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            Task { await model.duplicate(notebook) }
        }
        if includesCover {
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
        }
        Button("Rename", systemImage: "pencil") {
            renameText = notebook.title
            isRenaming = true
        }
        Button("Tags…", systemImage: "tag") {
            tagsText = model.tags(for: notebook.id).joined(separator: ", ")
            isEditingTags = true
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
                        Label(Self.indented(path), systemImage: "checkmark")
                    } else {
                        Text(Self.indented(path))
                    }
                }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
        }
    }

    /// Full path with one indent step per level, so two folders with the same
    /// name can be told apart in a move menu.
    private static func indented(_ path: AppModel.FolderPath) -> String {
        String(repeating: "    ", count: path.depth) + path.path
    }
}

private struct CoverTarget: Identifiable {
    let notebook: NotebookManifest
    var id: UUID { notebook.id }
}

extension View {
    /// Attaches the notebook's context menu and the prompts it opens.
    func notebookContextActions(
        model: AppModel,
        notebook: NotebookManifest,
        includesCover: Bool = true
    ) -> some View {
        modifier(
            NotebookContextActions(
                model: model,
                notebook: notebook,
                includesCover: includesCover
            )
        )
    }
}
