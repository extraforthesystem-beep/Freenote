import InkKit
import NoteCore
import SwiftUI

/// A vertical page switcher that sits beside the page. Only the cells the
/// viewport reaches decode their page, and rendering happens off the main actor.
///
/// The caller sets the panel's width: a fixed column on a regular-width iPad,
/// or the whole sheet when width is compact.
struct PagesSidePanel: View {
    let session: NotebookSession
    /// Which edge the panel sits on; its divider faces the page.
    let isOnLeft: Bool
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)]

    /// Pages can be different sizes, so the grid follows the page on screen.
    private var aspectRatio: CGFloat {
        guard let page = session.page, page.height > 0 else { return 0.707 }
        return page.width / page.height
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isOnLeft { edge }
            VStack(spacing: 0) {
                header
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(0..<session.pageCount, id: \.self) { index in
                                pageCell(index)
                            }
                            addPageTile
                        }
                        .padding(10)
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
            }
            if isOnLeft { edge }
        }
        .background(.bar)
    }

    private var edge: some View {
        Divider()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Pages")
                .font(.subheadline.weight(.semibold))
            Text("\(session.pageCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: isOnLeft ? "sidebar.leading" : "sidebar.trailing")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide Pages")
            .help("Hide Pages")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    private func pageCell(_ index: Int) -> some View {
        let isCurrent = index == session.pageIndex
        return Button {
            onSelect(index)
        } label: {
            VStack(spacing: 3) {
                PageThumbnailCell(
                    session: session,
                    index: index,
                    isCurrent: isCurrent,
                    aspectRatio: aspectRatio
                )
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var addPageTile: some View {
        Button {
            Task { await session.addPage() }
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title3)
                        Text("Page")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Page")
        .help("Add Page")
    }
}

private struct PageThumbnailCell: View {
    let session: NotebookSession
    let index: Int
    let isCurrent: Bool
    /// The page's width over its height, so the cell matches the paper.
    let aspectRatio: CGFloat

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
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
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

    /// Small enough to be cheap, sharp enough for a panel-sized cell on Retina.
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
        // A detached task does not inherit this task's cancellation, so pass
        // it on: a render still waiting for a thread when the cell scrolls
        // away is skipped. A fling across a scanned PDF otherwise queues a
        // full-page image decode for every cell it passes.
        let render = Task.detached(priority: .utility) { () -> InkImage? in
            guard !Task.isCancelled else { return nil }
            return PaperAppearance.image(
                page: page,
                assetsDirectory: assetsDirectory,
                scale: scale,
                usesDarkPaper: usesDarkPaper
            )
        }
        let rendered = await withTaskCancellationHandler {
            await render.value
        } onCancel: {
            render.cancel()
        }
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

    static func removeAll() {
        cache.removeAllObjects()
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
