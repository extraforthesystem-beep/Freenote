import InkKit
import NoteCore
import SwiftUI

/// A horizontal page switcher. Only the cells near the viewport decode their page.
struct PageThumbnailStrip: View {
    let session: NotebookSession
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(0..<max(session.pageCount, 1), id: \.self) { index in
                        PageThumbnailCell(
                            session: session,
                            index: index,
                            isCurrent: index == session.pageIndex
                        )
                        .id(index)
                        .onTapGesture { onSelect(index) }
                    }

                    Button {
                        Task { await session.addPage() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.title3)
                            Text("Page")
                                .font(.caption2)
                        }
                        .frame(width: 54, height: 76)
                        .foregroundStyle(.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .onChange(of: session.pageIndex) { _, index in
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(session.pageIndex, anchor: .center)
            }
        }
        .frame(height: 94)
        .background(.bar)
    }
}

private struct PageThumbnailCell: View {
    let session: NotebookSession
    let index: Int
    let isCurrent: Bool

    @State private var image: InkImage?
    @State private var failed = false

    private var pageID: UUID? {
        session.manifest.pageOrder.indices.contains(index)
            ? session.manifest.pageOrder[index]
            : nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)

            if let image {
                Image(inkImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }

            VStack {
                Spacer()
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .frame(width: 54, height: 76)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isCurrent ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isCurrent ? 2 : 1
                )
        }
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        guard let pageID else { return "missing-\(index)" }
        // The current page is re-rendered after every edit; others only when they load.
        return "\(pageID)-\(isCurrent ? session.revision : 0)"
    }

    private func load() async {
        guard let pageID else {
            failed = true
            return
        }
        if let cached = ThumbnailCache.image(notebookID: session.notebookID, pageID: pageID) {
            image = cached
            failed = false
            return
        }
        do {
            let page = try await session.store.loadPage(pageID, in: session.notebookID)
            guard let rendered = PageRenderer.image(
                strokes: page.strokes,
                pageSize: CGSize(width: page.width, height: page.height),
                template: page.template,
                elements: page.elements,
                assetsDirectory: session.assetsDirectory,
                scale: 1
            ) else {
                failed = true
                return
            }
            ThumbnailCache.store(rendered, notebookID: session.notebookID, pageID: pageID)
            image = rendered
            failed = false
        } catch {
            failed = true
        }
    }
}

@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func image(notebookID: UUID, pageID: UUID) -> InkImage? {
        cache.object(forKey: key(notebookID, pageID))
    }

    static func store(_ image: InkImage, notebookID: UUID, pageID: UUID) {
        #if os(iOS)
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        #else
        let pixels = image.size.width * image.size.height
        #endif
        cache.setObject(
            image,
            forKey: key(notebookID, pageID),
            cost: Int(pixels * 4)
        )
    }

    static func invalidate(notebookID: UUID, pageID: UUID) {
        cache.removeObject(forKey: key(notebookID, pageID))
    }

    private static func key(_ notebookID: UUID, _ pageID: UUID) -> NSString {
        "\(notebookID.uuidString)/\(pageID.uuidString)" as NSString
    }
}

extension Image {
    init(inkImage: InkImage) {
        #if os(iOS)
        self.init(uiImage: inkImage)
        #else
        self.init(nsImage: inkImage)
        #endif
    }
}
