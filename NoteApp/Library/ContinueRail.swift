import NoteCore
import SwiftUI

/// The last few pages written on, across every notebook, at the top of the
/// library. Research on jumping back (04 #2/#3) puts this first: re-finding is
/// mostly returning to where the writing was, not searching for its words.
struct ContinueRail: View {
    let model: AppModel

    private static let limit = 8

    private struct Item: Identifiable {
        let notebook: NotebookManifest
        let pageID: UUID
        let pageNumber: Int
        let title: String

        var id: String { "\(notebook.id.uuidString)/\(pageID.uuidString)" }
    }

    private var items: [Item] {
        var result: [Item] = []
        for entry in model.pageRecents.entries {
            guard result.count < Self.limit else { break }
            guard let notebook = model.notebook(withID: entry.notebookID),
                  let index = notebook.pageOrder.firstIndex(of: entry.pageID)
            else { continue }
            result.append(
                Item(
                    notebook: notebook,
                    pageID: entry.pageID,
                    pageNumber: index + 1,
                    title: model.outline.title(notebookID: notebook.id, pageID: entry.pageID)
                        ?? "Page \(index + 1)"
                )
            )
        }
        return result
    }

    var body: some View {
        let items = items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Continue")
                        .font(.headline)
                    Text("Pages you wrote on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            Button {
                                Task { await model.open(item.notebook, pageID: item.pageID) }
                            } label: {
                                tile(item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                Text("Continue \(item.notebook.title), \(item.title)")
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func tile(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            PagePreviewThumbnail(
                notebookID: item.notebook.id,
                pageID: item.pageID,
                store: model.store
            )
            .frame(width: 94)
            Text(item.notebook.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(item.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 94, alignment: .leading)
        .contentShape(Rectangle())
    }
}
