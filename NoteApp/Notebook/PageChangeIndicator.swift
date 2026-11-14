import SwiftUI

/// The page number, shown for a moment as the page changes and then gone.
///
/// The notebook keeps no permanent page chrome; this is the only sign of which
/// page is in view while turning pages.
struct PageChangeIndicator: View {
    let session: NotebookSession

    @AppStorage(AppSettings.Key.showPageNumber) private var showsPageNumber = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped on every page change, so a change while the number is showing
    /// restarts the wait instead of letting the first change hide it early.
    @State private var showToken = 0
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                Text("\(session.currentPageNumber) / \(session.pageCount)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: session.pageIndex) { _, _ in
            guard showsPageNumber else { return }
            showToken += 1
        }
        .task(id: showToken) {
            // The first appear has no page change behind it.
            guard showToken > 0 else { return }
            AppMotion.animate(AppMotion.quick, reduceMotion: reduceMotion) {
                isVisible = true
            }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            AppMotion.animate(AppMotion.quick, reduceMotion: reduceMotion) {
                isVisible = false
            }
        }
    }
}
