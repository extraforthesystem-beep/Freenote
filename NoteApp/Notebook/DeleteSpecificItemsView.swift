import NoteCore
import SwiftUI

/// Clears one kind of content from the open page, for example every pen
/// stroke while keeping highlights and text. Fits a popover or a sheet.
struct DeleteSpecificItemsView: View {
    let counts: [PageItemKind: Int]
    let onDelete: (Set<PageItemKind>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<PageItemKind> = []
    @State private var isConfirming = false

    init(counts: [PageItemKind: Int], onDelete: @escaping (Set<PageItemKind>) -> Void) {
        self.counts = counts
        self.onDelete = onDelete
    }

    private var available: [PageItemKind] {
        PageItemKind.allCases.filter { (counts[$0] ?? 0) > 0 }
    }

    private var selectedCount: Int {
        selection.reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    private var allSelected: Bool {
        !available.isEmpty && available.allSatisfy { selection.contains($0) }
    }

    private var itemCountText: String {
        "\(selectedCount) item\(selectedCount == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PageItemKind.allCases) { kind in
                        row(kind)
                    }
                } footer: {
                    Text("Only the selected content is removed. Everything else on the page is kept.")
                }
            }
            .navigationTitle("Delete Specific Items")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allSelected ? "Clear" : "Select All") {
                        selection = allSelected ? [] : Set(available)
                    }
                    .disabled(available.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    isConfirming = true
                } label: {
                    Label("Delete Page Items", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selection.isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .confirmationDialog(
                selectedCount == 0
                    ? "Delete items from this page?"
                    : "Delete \(itemCountText) from this page?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Delete Items", role: .destructive) {
                    deleteSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can restore the page from Version History.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 330, minHeight: 420)
        #endif
    }

    @ViewBuilder
    private func row(_ kind: PageItemKind) -> some View {
        let count = counts[kind] ?? 0
        Toggle(isOn: binding(for: kind)) {
            HStack(spacing: 12) {
                Image(systemName: symbol(for: kind))
                    .font(.body)
                    .foregroundStyle(count > 0 ? Color.secondary : Color.secondary.opacity(0.5))
                    .frame(width: 26)

                Text(kind.displayName)

                Spacer()

                Text("\(count)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(count == 0)
    }

    private func binding(for kind: PageItemKind) -> Binding<Bool> {
        Binding(
            get: { selection.contains(kind) },
            set: { isSelected in
                if isSelected {
                    selection.insert(kind)
                } else {
                    selection.remove(kind)
                }
            }
        )
    }

    private func symbol(for kind: PageItemKind) -> String {
        switch kind {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .shapes: "square.on.circle"
        case .images: "photo"
        case .stickyNotes: "note.text"
        case .tape: "rectangle.dashed"
        }
    }

    private func deleteSelected() {
        let kinds = selection
        guard !kinds.isEmpty else { return }
        onDelete(kinds)
        dismiss()
    }
}

#Preview("Delete Specific Items") {
    DeleteSpecificItemsView(
        counts: [.pen: 12, .pencil: 3, .highlighter: 0, .text: 4, .shapes: 1, .images: 2, .stickyNotes: 1, .tape: 0],
        onDelete: { _ in }
    )
    .frame(width: 360, height: 460)
}
