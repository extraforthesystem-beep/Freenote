import NoteCore
import SwiftUI

/// Every bookmarked page in the library, with its notebook and page around it.
/// A dot in one notebook's outline cannot answer "where did I pin that?" (04 #9),
/// so the pins get their own browsable list.
struct PinnedPagesList: View {
    let model: AppModel

    @State private var namingPin: Pin?
    @State private var nameText = ""

    private struct Pin: Identifiable {
        let notebook: NotebookManifest
        let pageID: UUID
        let pageNumber: Int
        let pageTitle: String?
        let bookmark: PageBookmarks.Bookmark

        var id: String { bookmark.id }
    }

    private var pins: [Pin] {
        model.bookmarks.allBookmarks.compactMap { bookmark in
            guard let notebook = model.notebook(withID: bookmark.notebookID),
                  let index = notebook.pageOrder.firstIndex(of: bookmark.pageID)
            else { return nil }
            return Pin(
                notebook: notebook,
                pageID: bookmark.pageID,
                pageNumber: index + 1,
                pageTitle: model.outline.title(notebookID: notebook.id, pageID: bookmark.pageID),
                bookmark: bookmark
            )
        }
    }

    var body: some View {
        let pins = pins
        List {
            ForEach(pins) { pin in
                Button {
                    Task { await model.open(pin.notebook, pageID: pin.pageID) }
                } label: {
                    row(pin)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remove Pin", role: .destructive) {
                        model.bookmarks.toggle(notebookID: pin.notebook.id, pageID: pin.pageID)
                    }
                }
                .contextMenu {
                    Button("Open", systemImage: "book") {
                        Task { await model.open(pin.notebook, pageID: pin.pageID) }
                    }
                    Button("Name Bookmark…", systemImage: "pencil") {
                        beginNaming(pin)
                    }
                    Button("Remove Pin", systemImage: "bookmark.slash", role: .destructive) {
                        model.bookmarks.toggle(notebookID: pin.notebook.id, pageID: pin.pageID)
                    }
                }
            }
        }
        .overlay {
            if pins.isEmpty {
                ContentUnavailableView {
                    Label("No Pinned Pages", systemImage: "bookmark")
                } description: {
                    Text("Bookmark a page in a notebook, then it is listed here.")
                }
            }
        }
        .alert("Bookmark name", isPresented: namingAlert) {
            TextField("Name (optional)", text: $nameText)
            Button("Cancel", role: .cancel) { namingPin = nil }
            Button("Save") {
                if let pin = namingPin {
                    model.bookmarks.setTitle(
                        nameText,
                        notebookID: pin.notebook.id,
                        pageID: pin.pageID
                    )
                }
                namingPin = nil
            }
        }
    }

    private func row(_ pin: Pin) -> some View {
        HStack(spacing: 12) {
            PagePreviewThumbnail(
                notebookID: pin.notebook.id,
                pageID: pin.pageID,
                store: model.store
            )
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(pin.bookmark.title ?? pin.pageTitle ?? "Page \(pin.pageNumber)")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(pin.notebook.title) · Page \(pin.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func beginNaming(_ pin: Pin) {
        nameText = pin.bookmark.title ?? ""
        namingPin = pin
    }

    private var namingAlert: Binding<Bool> {
        Binding(
            get: { namingPin != nil },
            set: { if !$0 { namingPin = nil } }
        )
    }
}
