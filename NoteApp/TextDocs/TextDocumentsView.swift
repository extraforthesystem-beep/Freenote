import SwiftUI
import TextDocKit

/// The text-document library, presented as a sheet from the main library.
///
/// Entry point: `TextDocumentsView(model:)`. The caller owns the model and
/// supplies the root folder, so this view never touches a fixed location.
struct TextDocumentsView: View {
    let model: TextDocModel

    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []
    @State private var prompt: NamePrompt?
    /// The document being renamed while `prompt` is open; nil means "create".
    @State private var renamedDocument: TextDocument?

    /// Documents waiting for the delete confirmation. Empty when it is closed.
    @State private var deletionTargets: [TextDocument] = []
    @State private var isConfirmingDelete = false

    /// False when the view is embedded in the library's detail column instead of a sheet.
    private let showsDoneButton: Bool

    init(model: TextDocModel, showsDoneButton: Bool = true) {
        self.model = model
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                // One alert node, so it cannot fight a second alert modifier.
                .alert("Text Document Error", isPresented: errorBinding) {
                    Button("OK", role: .cancel) { model.clearError() }
                } message: {
                    Text(model.lastError ?? "")
                }
                .confirmationDialog(
                    deletionTitle,
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Document", role: .destructive) { confirmDeletion() }
                    Button("Cancel", role: .cancel) { deletionTargets = [] }
                } message: {
                    Text(deletionMessage)
                }
                .onChange(of: isConfirmingDelete) { _, isPresented in
                    if !isPresented { deletionTargets = [] }
                }
                .navigationTitle("Text Documents")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if showsDoneButton {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            beginCreating()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New document")
                        .disabled(model.isLoading)
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let document = model.document(withID: id) {
                        TextDocumentEditorView(model: model, document: document)
                    } else {
                        ContentUnavailableView(
                            "Document Not Found",
                            systemImage: "doc.questionmark",
                            description: Text("The document may have been deleted.")
                        )
                    }
                }
                .sheet(item: $prompt) { prompt in
                    NamePromptSheet(prompt: prompt) { name in
                        submit(name)
                    }
                }
                .task { await model.load() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.documents.isEmpty {
            ProgressView("Loading documents…")
        } else if model.documents.isEmpty {
            emptyState
        } else {
            documentList
        }
    }

    private var documentList: some View {
        List {
            ForEach(model.documents) { document in
                NavigationLink(value: document.id) {
                    row(document)
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { beginRenaming(document) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        requestDeletion([document])
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        requestDeletion([document])
                    }
                    Button("Rename", systemImage: "pencil") { beginRenaming(document) }
                        .tint(.indigo)
                }
            }
            .onDelete(perform: deleteDocuments)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Text Documents", systemImage: "doc.text")
        } description: {
            Text("Write long-form notes with headings, lists, quotes, code and checklists.")
        } actions: {
            Button("New Document") { beginCreating() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func row(_ document: TextDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle(document))
                .font(.body.weight(.medium))
                .lineLimit(1)

            Text(
                "\(blockCountText(document.blocks.count)) · "
                    + document.updatedAt.formatted(date: .abbreviated, time: .shortened)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func beginCreating() {
        renamedDocument = nil
        prompt = NamePrompt(
            title: "New Document",
            message: "Name the document, then start writing.",
            value: "",
            actionTitle: "Create"
        )
    }

    private func beginRenaming(_ document: TextDocument) {
        renamedDocument = document
        prompt = NamePrompt(
            title: "Rename Document",
            message: nil,
            value: document.title,
            actionTitle: "Save"
        )
    }

    private func submit(_ name: String) {
        if let document = renamedDocument {
            renamedDocument = nil
            Task { await model.rename(document, to: name) }
        } else {
            Task {
                if let document = await model.createDocument(title: name) {
                    path.append(document.id)
                }
            }
        }
    }

    /// Asks before deleting: a swipe or a context-menu tap used to remove the
    /// file for good, unlike the notebook library, which keeps a Recently
    /// Deleted copy.
    private func requestDeletion(_ documents: [TextDocument]) {
        guard !documents.isEmpty else { return }
        deletionTargets = documents
        isConfirmingDelete = true
    }

    private func confirmDeletion() {
        let targets = deletionTargets
        deletionTargets = []
        guard !targets.isEmpty else { return }
        Task {
            for document in targets {
                await model.delete(document)
            }
        }
    }

    private var deletionTitle: String {
        if deletionTargets.count == 1, let document = deletionTargets.first {
            return "Delete \u{201C}\(displayTitle(document))\u{201D}?"
        }
        return "Delete \(deletionTargets.count) Documents?"
    }

    private var deletionMessage: String {
        deletionTargets.count == 1
            ? "The document will be deleted permanently."
            : "These documents will be deleted permanently."
    }

    /// Snapshots the targets before deleting: each delete shrinks the list, so
    /// reading indices inside the loop would address the wrong rows.
    private func deleteDocuments(_ offsets: IndexSet) {
        let targets = offsets.compactMap { index in
            model.documents.indices.contains(index) ? model.documents[index] : nil
        }
        requestDeletion(targets)
    }

    private func displayTitle(_ document: TextDocument) -> String {
        document.title.isEmpty ? "Untitled" : document.title
    }

    private func blockCountText(_ count: Int) -> String {
        "\(count) block\(count == 1 ? "" : "s")"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.clearError() } }
        )
    }
}

#Preview("Text Documents") {
    TextDocumentsView(
        model: TextDocModel(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("TextDocsPreview-\(UUID().uuidString)", isDirectory: true)
        )
    )
}
