import InkKit
import NoteCore
import SwiftUI

/// A horizontal page switcher. Only the cells near the viewport decode their
/// page, and rendering happens off the main actor.
struct PageThumbnailStrip: View {
    let session: NotebookSession
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(0..<session.pageCount, id: \.self) { index in
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
                    .accessibilityLabel("Add Page")
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

    @AppStorage(AppSettings.Key.darkPaper) private var darkPaperInDarkMode = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: InkImage?
    @State private var failed = false

    private var pageID: UUID? {
        session.manifest.pageOrder.indices.contains(index)
            ? session.manifest.pageOrder[index]
            : nil
    }

    /// Pages follow Dark Paper, so a thumbnail matches the page it opens.
    private var usesDarkPaper: Bool {
        darkPaperInDarkMode && colorScheme == .dark
    }

    var body: some View {
        ZStack {
            // Paper is the page's own colour whatever the appearance.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppColor.paper(usesDarkPaper: usesDarkPaper))

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
        // The current page re-renders after edits; others only when they load.
        return "\(pageID)-\(isCurrent ? session.revision : 0)-\(usesDarkPaper)"
    }

    /// Small enough to be cheap, sharp enough for a 54 pt cell on Retina.
    private static let renderScale: CGFloat = 0.3
    /// Edits keep coming while writing; wait for a pause before re-rendering.
    private static let editDebounce: Duration = .milliseconds(1_500)

    private func load() async {
        guard let pageID else {
            failed = true
            return
        }
        if let cached = ThumbnailCache.image(
            notebookID: session.notebookID,
            pageID: pageID,
            usesDarkPaper: usesDarkPaper
        ) {
            image = cached
            failed = false
            return
        }
        // An edit invalidated the thumbnail: keep showing the old one and wait
        // for the writing to pause. A cancelled sleep means another edit came.
        if image != nil {
            do {
                try await Task.sleep(for: Self.editDebounce)
            } catch {
                return
            }
        }

        // The page on screen may have unsaved ink, so prefer the in-memory copy.
        let page: Page
        if let current = session.page, current.id == pageID {
            page = current
        } else {
            do {
                page = try await session.store.loadPage(pageID, in: session.notebookID)
            } catch {
                if image == nil { failed = true }
                return
            }
        }
        guard !Task.isCancelled else { return }

        let assetsDirectory = session.assetsDirectory
        let scale = Self.renderScale
        let usesDarkPaper = usesDarkPaper
        let rendered = await Task.detached(priority: .utility) {
            PaperAppearance.image(
                page: page,
                assetsDirectory: assetsDirectory,
                scale: scale,
                usesDarkPaper: usesDarkPaper
            )
        }.value
        guard !Task.isCancelled else { return }
        guard let rendered else {
            if image == nil { failed = true }
            return
        }
        ThumbnailCache.store(
            rendered,
            notebookID: session.notebookID,
            pageID: pageID,
            usesDarkPaper: usesDarkPaper
        )
        image = rendered
        failed = false
    }
}

@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func image(notebookID: UUID, pageID: UUID, usesDarkPaper: Bool = false) -> InkImage? {
        cache.object(forKey: key(notebookID, pageID, usesDarkPaper: usesDarkPaper))
    }

    static func store(_ image: InkImage, notebookID: UUID, pageID: UUID, usesDarkPaper: Bool = false) {
        #if os(iOS)
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        #else
        let pixels = image.size.width * image.size.height
        #endif
        cache.setObject(
            image,
            forKey: key(notebookID, pageID, usesDarkPaper: usesDarkPaper),
            cost: Int(pixels * 4)
        )
    }

    static func invalidate(notebookID: UUID, pageID: UUID) {
        cache.removeObject(forKey: key(notebookID, pageID, usesDarkPaper: false))
        cache.removeObject(forKey: key(notebookID, pageID, usesDarkPaper: true))
    }

    private static func key(_ notebookID: UUID, _ pageID: UUID, usesDarkPaper: Bool) -> NSString {
        "\(notebookID.uuidString)/\(pageID.uuidString)\(usesDarkPaper ? "/dark" : "")" as NSString
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
