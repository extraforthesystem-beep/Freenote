import SwiftUI

/// Every page of the notebook in one space-filling grid, with its number, its
/// outline title and its bookmark. A whole-document overview beats scrolling for
/// finding a page (04 #4), especially on a long notebook.
struct PageOverviewGrid: View {
    let session: NotebookSession
    let outline: PageOutline
    let bookmarks: PageBookmarks

    @Environment(\.dismiss) private var dismiss
    @State private var namingPageID: UUID?
    @State private var nameText = ""

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 210), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(Array(session.manifest.pageOrder.enumerated()), id: \.element) { index, pageID in
                        cell(index: index, pageID: pageID)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Pages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Bookmark name", isPresented: namingAlert) {
                TextField("Name (optional)", text: $nameText)
                Button("Cancel", role: .cancel) { namingPageID = nil }
                Button("Save") {
                    if let pageID = namingPageID {
                        bookmarks.setTitle(nameText, notebookID: session.notebookID, pageID: pageID)
                    }
                    namingPageID = nil
                }
            } message: {
                Text("A name shows in the Pinned Pages list.")
            }
        }
    }

    @ViewBuilder
    private func cell(index: Int, pageID: UUID) -> some View {
        let title = outline.title(notebookID: session.notebookID, pageID: pageID)
        let bookmark = bookmarks.bookmark(notebookID: session.notebookID, pageID: pageID)
        let isCurrent = index == session.pageIndex

        Button {
            Task {
                await session.goToPage(index)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PagePreviewThumbnail(
                    notebookID: session.notebookID,
                    pageID: pageID,
                    store: session.store
                )
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if bookmark != nil {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .padding(8)
                    }
                }
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }

                Text(title ?? "Page \(index + 1)")
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                if let name = bookmark?.title {
                    Label(name, systemImage: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if bookmark == nil {
                Button("Bookmark This Page", systemImage: "bookmark") {
                    bookmarks.toggle(notebookID: session.notebookID, pageID: pageID)
                    beginNaming(pageID)
                }
            } else {
                Button("Name Bookmark…", systemImage: "pencil") {
                    beginNaming(pageID)
                }
                Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                    bookmarks.toggle(notebookID: session.notebookID, pageID: pageID)
                }
            }
        }
        .accessibilityLabel(Text("Page \(index + 1), \(title ?? "untitled")"))
    }

    private func beginNaming(_ pageID: UUID) {
        nameText = bookmarks.bookmark(notebookID: session.notebookID, pageID: pageID)?.title ?? ""
        namingPageID = pageID
    }

    private var namingAlert: Binding<Bool> {
        Binding(
            get: { namingPageID != nil },
            set: { if !$0 { namingPageID = nil } }
        )
    }
}
