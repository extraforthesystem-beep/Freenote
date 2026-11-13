import BoardKit
import Foundation
import SwiftUI

/// The whiteboard library, shaped to be presented as a sheet from the
/// notebook library:
///
/// ```swift
/// .sheet(isPresented: $showsBoards) {
///     BoardsView(model: boardModel)
/// }
/// ```
struct BoardsView: View {
    @Bindable var model: BoardModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBoard: Board?
    @State private var prompt: NamePrompt?
    /// The board being renamed while `prompt` is open; nil means "create".
    @State private var renamedBoard: Board?
    /// A freshly created board, opened once the naming sheet is gone.
    @State private var pendingBoard: Board?

    /// False when the view is embedded in the library's detail column instead of a sheet.
    private let showsDoneButton: Bool

    init(model: BoardModel, showsDoneButton: Bool = true) {
        self.model = model
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        NavigationStack {
            content
                .sheet(item: $prompt, onDismiss: openPendingBoard) { prompt in
                    NamePromptSheet(prompt: prompt) { name in
                        submit(name)
                    }
                }
                .navigationTitle("Boards")
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
                            Label("New Board", systemImage: "plus")
                        }
                    }
                }
                // One alert node, so the error alert cannot shadow another alert.
                .alert("Board error", isPresented: errorAlert) {
                    Button("OK", role: .cancel) { model.clearError() }
                } message: {
                    Text(model.lastError ?? "")
                }
                // A board is its own workspace: a sheet leaves it as a small
                // form window on iPad, so it takes the whole screen instead.
                #if os(iOS)
                .fullScreenCover(item: $selectedBoard) { board in
                    BoardEditorView(model: model, board: board)
                }
                #else
                .sheet(item: $selectedBoard) { board in
                    BoardEditorView(model: model, board: board)
                }
                #endif
                .task { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.boards.isEmpty {
            ProgressView("Loading boards…")
        } else if model.boards.isEmpty {
            emptyState
        } else {
            boardList
        }
    }

    private var boardList: some View {
        List {
            ForEach(model.boards) { board in
                Button {
                    selectedBoard = board
                } label: {
                    boardRow(board)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { beginRenaming(board) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.delete(board) }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.delete(board) }
                    }
                    Button("Rename", systemImage: "pencil") { beginRenaming(board) }
                        .tint(.indigo)
                }
            }
            .onDelete(perform: deleteBoards)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .refreshable { await model.load() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Boards", systemImage: "rectangle.3.group")
        } description: {
            Text("Sketch ideas, collect references and connect thoughts on a large canvas.")
        } actions: {
            Button("New Board") { beginCreating() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func boardRow(_ board: Board) -> some View {
        HStack(spacing: 14) {
            BoardThumbnail(board: board)

            VStack(alignment: .leading, spacing: 3) {
                Text(board.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(
                    "\(itemCountLabel(board.visibleItems.count)) · Updated "
                        + board.updatedAt.formatted(date: .abbreviated, time: .shortened)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func itemCountLabel(_ count: Int) -> String {
        "\(count) item\(count == 1 ? "" : "s")"
    }

    // MARK: - Actions

    private func beginCreating() {
        renamedBoard = nil
        prompt = NamePrompt(
            title: "New Board",
            message: "Name the board, then start drawing.",
            value: "",
            actionTitle: "Create"
        )
    }

    private func beginRenaming(_ board: Board) {
        renamedBoard = board
        prompt = NamePrompt(
            title: "Rename Board",
            message: nil,
            value: board.title,
            actionTitle: "Save"
        )
    }

    private func submit(_ name: String) {
        if let board = renamedBoard {
            renamedBoard = nil
            Task { await model.rename(board, to: name) }
        } else {
            Task {
                if let board = await model.createBoard(title: name) {
                    pendingBoard = board
                    prompt = nil
                }
            }
        }
    }

    /// Opens a just-created board after the naming sheet has fully dismissed,
    /// so the two sheets never try to present at once.
    private func openPendingBoard() {
        guard let board = pendingBoard else { return }
        pendingBoard = nil
        selectedBoard = board
    }

    /// Snapshots the targets before deleting: each delete shrinks the list, so
    /// reading indices inside the loop would address the wrong rows.
    private func deleteBoards(_ offsets: IndexSet) {
        let targets = offsets.compactMap { index in
            model.boards.indices.contains(index) ? model.boards[index] : nil
        }
        guard !targets.isEmpty else { return }
        Task {
            for board in targets {
                await model.delete(board)
            }
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { isPresented in
                if !isPresented { model.clearError() }
            }
        )
    }
}
