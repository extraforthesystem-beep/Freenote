import SwiftUI

/// The pages the page pill's menu lists: `current` and up to `radius` pages
/// either side, clamped at the ends of the notebook.
///
/// A window, never the whole notebook: a 1,000-page imported PDF would
/// otherwise have to build every page's button when the pill is tapped.
func pageMenuWindow(current: Int, count: Int, radius: Int = 3) -> [Int] {
    guard radius >= 0, count > 0, (0..<count).contains(current) else { return [] }
    return Array(max(0, current - radius)...min(count - 1, current + radius))
}

/// The floating "3 / 12" pill over the bottom of the page.
struct PageCounterPill: View {
    let session: NotebookSession
    let onSelect: (Int) -> Void
    /// Opens the pane's existing go-to-page sheet.
    var onGoToPage: () -> Void = {}
    /// Opens the pane's page overview grid, when it has one.
    var onShowOverview: (() -> Void)?

    /// The saving spinner waits for a write that is not instant; an ordinary
    /// save lands before it could read.
    @State private var showsSaving = false

    var body: some View {
        HStack(spacing: 0) {
            if session.pageCount == 0 {
                Text("No pages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            } else {
                pillButton("Previous Page", systemImage: "chevron.backward") {
                    Task { await session.goToPreviousPage() }
                }
                .disabled(session.pageIndex == 0)

                pageMenu

                pillButton("Next Page", systemImage: "chevron.forward") {
                    Task { await session.goToNextPage() }
                }
                .disabled(session.pageIndex + 1 >= session.pageCount)

                Divider()
                    .frame(height: 20)

                pillButton("Add Page", systemImage: "plus") {
                    Task { await session.addPage() }
                }
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .task(id: session.isSaving) { await updateSavingIndicator() }
    }

    private var pageMenu: some View {
        Menu {
            pageWindowItems
            Divider()
            Button("Go to Page…", systemImage: "arrow.right.to.line") {
                onGoToPage()
            }
            .disabled(session.pageCount < 2)
            if let onShowOverview {
                Button("Page Overview…", systemImage: "square.grid.2x2") {
                    onShowOverview()
                }
            }
        } label: {
            HStack(spacing: AppSpacing.s) {
                Text("\(session.currentPageNumber) / \(session.pageCount)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                if showsSaving {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Saving")
                }
            }
            .padding(.horizontal, AppSpacing.s)
            .frame(minWidth: 60, minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(session.currentPageNumber) of \(session.pageCount)")
    }

    /// The nearby pages, plus the ends when the window does not reach them.
    @ViewBuilder
    private var pageWindowItems: some View {
        let window = pageMenuWindow(current: session.pageIndex, count: session.pageCount)
        ForEach(window, id: \.self) { index in
            Button {
                onSelect(index)
            } label: {
                if index == session.pageIndex {
                    Label("Page \(index + 1)", systemImage: "checkmark")
                } else {
                    Text("Page \(index + 1)")
                }
            }
        }
        if let first = window.first, first > 0 {
            Button("First Page") { onSelect(0) }
        }
        if let last = window.last, last < session.pageCount - 1 {
            Button("Last Page") { onSelect(session.pageCount - 1) }
        }
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    /// Shows the spinner only once the save has outlasted the 300 ms an
    /// instant write takes.
    private func updateSavingIndicator() async {
        guard session.isSaving else {
            showsSaving = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        showsSaving = true
    }
}

/// A small non-blocking message over the top of the page.
struct EditorBanner: View {
    let systemImage: String
    let message: String
    var tint: Color = .orange
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, onDismiss == nil ? 14 : 4)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
