import NoteCore
import SwiftUI

/// A flat, ordered page outline with custom titles and bookmarks. It is the
/// lightweight first step before a hierarchical, heading-driven outline.
struct OutlinePanel: View {
    let session: NotebookSession
    let outline: PageOutline
    let bookmarks: PageBookmarks

    @Environment(\.dismiss) private var dismiss
    @State private var editingPageID: UUID?
    @State private var editText = ""

    private var pageIDs: [UUID] {
        session.manifest.pageOrder
    }

    private var bookmarkedIDs: Set<UUID> {
        bookmarks.bookmarkedPageIDs(notebookID: session.notebookID)
    }

    var body: some View {
        NavigationStack {
            List {
                if pageIDs.isEmpty {
                    ContentUnavailableView(
                        "No Pages",
                        systemImage: "list.bullet.indent",
                        description: Text("Add a page to build an outline.")
                    )
                } else {
                    Section {
                        rows
                    } footer: {
                        Text("Tap a page to open it. Use the bookmark button to pin pages you return to.")
                    }
                }
            }
            .navigationTitle("Outline")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Page title", isPresented: Binding(
                get: { editingPageID != nil },
                set: { if !$0 { editingPageID = nil } }
            )) {
                TextField("Title", text: $editText)
                Button("Cancel", role: .cancel) { editingPageID = nil }
                Button("Save") {
                    if let pageID = editingPageID {
                        outline.setTitle(editText, notebookID: session.notebookID, pageID: pageID)
                    }
                    editingPageID = nil
                }
            }
        }
    }

    /// Every row of the outline, with the bookmark set built once for the
    /// whole pass rather than once per row.
    private var rows: some View {
        let bookmarked = bookmarkedIDs
        return ForEach(Array(pageIDs.enumerated()), id: \.element) { index, pageID in
            row(index: index, pageID: pageID, isBookmarked: bookmarked.contains(pageID))
        }
    }

    @ViewBuilder
    private func row(index: Int, pageID: UUID, isBookmarked: Bool) -> some View {
        let title = outline.title(notebookID: session.notebookID, pageID: pageID) ?? "Page \(index + 1)"
        let isCurrent = index == session.pageIndex

        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                if outline.title(notebookID: session.notebookID, pageID: pageID) != nil {
                    Text("Page \(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                bookmarks.toggle(notebookID: session.notebookID, pageID: pageID)
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark page")

            Button {
                editText = outline.title(notebookID: session.notebookID, pageID: pageID) ?? ""
                editingPageID = pageID
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rename page")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await session.goToPage(index)
                dismiss()
            }
        }
    }
}
