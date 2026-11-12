import SearchKit
import SwiftUI

/// In-notebook search: a query field, one result per page with the matched text
/// marked, and a footer that steps through the matches.
///
/// The editor owns where the panel is shown; this view only reports the page the
/// user picked, so the same panel can sit in a sidebar, a sheet or a split view.
struct NotebookSearchPanel: View {
    private let notebookID: UUID
    private let search: HandwritingSearch
    private let onSelectPage: (UUID) -> Void
    private let onHighlight: (SearchHighlight?) -> Void

    @State private var query = ""
    @State private var sources = Set(PageTextSource.allCases)
    @State private var dateRange = SearchDateRange.anyTime
    @State private var hits: [SearchKit.SearchHit] = []
    @State private var selectedPageID: UUID?
    @State private var searchTask: Task<Void, Never>?

    /// - Parameters:
    ///   - notebookID: the notebook to search; the index is scoped to it.
    ///   - search: the app's shared `HandwritingSearch`, which owns the index.
    ///   - onHighlight: called with the query the page should mark, or nil to clear the marks.
    ///   - onSelectPage: called with the page ID of the chosen result.
    init(
        notebookID: UUID,
        search: HandwritingSearch,
        onHighlight: @escaping (SearchHighlight?) -> Void = { _ in },
        onSelectPage: @escaping (UUID) -> Void
    ) {
        self.notebookID = notebookID
        self.search = search
        self.onHighlight = onHighlight
        self.onSelectPage = onSelectPage
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
            Divider()
            footer
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
        .background(.background)
        .onChange(of: query) { _, value in
            scheduleSearch(value)
        }
        .onChange(of: sources) { _, _ in
            scheduleSearch(query)
        }
        .onChange(of: dateRange) { _, _ in
            scheduleSearch(query)
        }
        .onDisappear {
            searchTask?.cancel()
            onHighlight(nil)
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search this notebook", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            #if os(iOS)
            PencilSearchButton(search: search) { query = $0 }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            #endif
            SearchFilterMenu(sources: $sources, dateRange: $dateRange)
                .labelStyle(.iconOnly)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(12)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if pageResults.isEmpty {
            ContentUnavailableView {
                Label(query.isEmpty ? "Search This Notebook" : "No Matches", systemImage: "text.magnifyingglass")
            } description: {
                Text(query.isEmpty
                    ? "Handwriting, typed text and PDF text are all searched."
                    : "Nothing in this notebook matches “\(query)”.")
                    + Text(query.isEmpty ? "\nWrite with Apple Pencil, or use \"exact phrase\", OR and -word." : "")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(pageResults) { result in
                        pageRow(result)
                        Divider()
                    }
                }
            }
        }
    }

    private func pageRow(_ result: PageResult) -> some View {
        let isSelected = result.pageID == selectedPageID
        return Button {
            select(result)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(pageTitle(result))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if result.hits.count > 1 {
                        Text("\(result.hits.count) matches")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                if let first = result.hits.first {
                    HighlightedSnippet(snippet: first.snippet, matchRange: first.matchRange, lineLimit: 3)
                        .font(.callout)
                }
                ForEach(Array(result.hits.dropFirst().enumerated()), id: \.offset) { _, hit in
                    HighlightedSnippet(snippet: hit.snippet, matchRange: hit.matchRange, lineLimit: 2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(matchCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(pageResults.isEmpty || selectedIndex <= 0)
            .accessibilityLabel("Previous match")
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(pageResults.isEmpty || selectedIndex >= pageResults.count - 1)
            .accessibilityLabel("Next match")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var matchCountText: String {
        let count = hits.count
        return "\(count) match\(count == 1 ? "" : "es")"
    }

    // MARK: State

    private struct PageResult: Identifiable {
        let pageID: UUID
        let pageIndex: Int
        let hits: [SearchKit.SearchHit]
        var id: UUID { pageID }
    }

    /// One row per page, in page order, with every source's hit on that page.
    private var pageResults: [PageResult] {
        var order: [UUID] = []
        var grouped: [UUID: [SearchKit.SearchHit]] = [:]
        for hit in hits {
            if grouped[hit.pageID] == nil { order.append(hit.pageID) }
            grouped[hit.pageID, default: []].append(hit)
        }
        return order.compactMap { pageID in
            guard let pageHits = grouped[pageID] else { return nil }
            return PageResult(
                pageID: pageID,
                pageIndex: pageHits.first?.pageIndex ?? 0,
                hits: pageHits
            )
        }
        .sorted { $0.pageIndex < $1.pageIndex }
    }

    private var selectedIndex: Int {
        guard let selectedPageID else { return -1 }
        return pageResults.firstIndex { $0.pageID == selectedPageID } ?? -1
    }

    private func pageTitle(_ result: PageResult) -> String {
        result.pageIndex > 0 ? "Page \(result.pageIndex)" : "Page"
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            selectedPageID = nil
            onHighlight(nil)
            return
        }
        let sources = sources
        let dateRange = dateRange
        searchTask = Task {
            // Debounce: one scoped search per pause, not per keystroke.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = await search.search(trimmed, in: notebookID, sources: sources, dateRange: dateRange)
            guard !Task.isCancelled else { return }
            hits = found
            onHighlight(SearchHighlight(query: trimmed, sources: sources))
            selectedPageID = pageResults.first?.pageID
        }
    }

    private func select(_ result: PageResult) {
        selectedPageID = result.pageID
        onSelectPage(result.pageID)
    }

    /// Moves the selection by `offset` and reports the page it lands on.
    private func step(_ offset: Int) {
        let results = pageResults
        guard !results.isEmpty else { return }
        let current = selectedIndex
        let next = min(max(current + offset, 0), results.count - 1)
        guard next != current else { return }
        select(results[next])
    }
}

#Preview("Notebook Search") {
    NotebookSearchPanel(
        notebookID: UUID(),
        search: HandwritingSearch(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("NotebookSearchPanelPreview", isDirectory: true)),
        onSelectPage: { _ in }
    )
    .frame(width: 320, height: 520)
}
