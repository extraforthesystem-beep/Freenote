import InkKit
import NoteCore
import SwiftUI

/// A page thumbnail rendered from the store, for library lists, the Continue
/// rail and the page overview.
///
/// Renders off the main actor and shares `ThumbnailCache` with the editor's page
/// panel, so opening one view warms the others.
struct PagePreviewThumbnail: View {
    let notebookID: UUID
    let pageID: UUID
    let store: LibraryStore

    @State private var image: InkImage?
    @State private var failed = false
    @State private var aspect: CGFloat = 0.707

    /// Small enough to be cheap, sharp enough for a cell on Retina.
    private static let renderScale: CGFloat = 0.28

    private var taskID: String {
        "\(notebookID.uuidString)/\(pageID.uuidString)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColor.paper(usesDarkPaper: false))

            if let image {
                Image(inkImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .task(id: taskID) {
            await load()
        }
    }

    private func load() async {
        if let cached = ThumbnailCache.image(notebookID: notebookID, pageID: pageID) {
            image = cached
            failed = false
            aspect = Self.aspect(of: cached) ?? aspect
            return
        }
        guard let page = try? await store.loadPage(pageID, in: notebookID) else {
            failed = true
            return
        }
        if page.height > 0 {
            aspect = page.width / page.height
        }
        let assets = store.assetsDirectoryURL(for: notebookID)
        let scale = Self.renderScale
        let rendered = await Task.detached(priority: .utility) {
            PaperAppearance.image(
                page: page,
                assetsDirectory: assets,
                scale: scale,
                usesDarkPaper: false
            )
        }.value
        guard !Task.isCancelled else { return }
        guard let rendered else {
            failed = true
            return
        }
        ThumbnailCache.store(rendered, notebookID: notebookID, pageID: pageID)
        image = rendered
        failed = false
    }

    private static func aspect(of image: InkImage) -> CGFloat? {
        guard image.size.height > 0 else { return nil }
        return image.size.width / image.size.height
    }
}
