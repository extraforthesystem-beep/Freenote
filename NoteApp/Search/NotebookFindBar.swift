import SearchKit
import SwiftUI

/// In-notebook search as a find bar: one query row over the page and the
/// results dropping beneath it in the same material.
///
/// The editor owns where the bar is shown and what a jump means; this view only
/// reports the page the reader picked, so the bar can float over the page.
struct NotebookFindBar: View {
    private let notebookID: UUID
    private let search: HandwritingSearch
    private let pageCount: Int
    /// The search the pages already mark, e.g. from the library search.
    private let activeHighlight: SearchHighlight?
    private let onHighlight: (SearchHighlight?) -> Void
    private let onSelectPage: (UUID) -> Void
    private let onGoToPage: (Int) -> Void
    private let onClose: () -> Void

    @State private var query = ""
    @State private var sources = Set(PageTextSource.allCases)
    @State private var dateRange = SearchDateRange.anyTime
    @State private var hits: [SearchKit.SearchHit] = []
    @State private var selectedPageID: UUID?
    /// Consumed by the first search, so later searches start at the first result.
    @State private var pendingInitialPageID: UUID?
    /// The query whose hits are in `hits`, so an empty list is not shown mid-search.
    @State private var settledQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showsResults = true
    @FocusState private var isFieldFocused: Bool

    /// - Parameters:
    ///   - notebookID: the notebook to search; the index is scoped to it.
    ///   - search: the app's shared `HandwritingSearch`, which owns the index.
    ///   - pageCount: the notebook's pages, so page numbers can be range-checked.
    ///   - activeHighlight: the search the pages already mark; the bar adopts it.
    ///   - initialPageID: the page the first search should land on, when it has a match.
    ///   - onHighlight: called with the query the page should mark, or nil to clear the marks.
    ///   - onSelectPage: called with the page ID of the chosen text hit.
    ///   - onGoToPage: called with the 0-based page of a page-number query.
    ///   - onClose: called when the bar asks to close.
    init(
        notebookID: UUID,
        search: HandwritingSearch,
        pageCount: Int,
        activeHighlight: SearchHighlight? = nil,
        initialPageID: UUID? = nil,
        onHighlight: @escaping (SearchHighlight?) -> Void = { _ in },
        onSelectPage: @escaping (UUID) -> Void,
        onGoToPage: @escaping (Int) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.notebookID = notebookID
        self.search = search
        self.pageCount = pageCount
        self.activeHighlight = activeHighlight
        self.onHighlight = onHighlight
        _pendingInitialPageID = State(initialValue: initialPageID)
        self.onSelectPage = onSelectPage
        self.onGoToPage = onGoToPage
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if showsResults, !trimmedQuery.isEmpty {
                Divider()
                results
            }
        }
        .frame(maxWidth: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notebook search")
        .task { isFieldFocused = true }
        .onChange(of: query) { _, value in
            // A new query reopens the list after a jump folded it away.
            showsResults = true
            scheduleSearch(value)
        }
        .onChange(of: sources) { _, _ in
            scheduleSearch(query)
        }
        .onChange(of: dateRange) { _, _ in
            scheduleSearch(query)
        }
        .onAppear { adopt(activeHighlight) }
        .onChange(of: activeHighlight) { _, highlight in
            adopt(highlight)
        }
        .onDisappear {
            searchTask?.cancel()
            onHighlight(nil)
        }
        #if os(iOS)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        #else
        .onExitCommand(perform: onClose)
        #endif
    }

    // MARK: Bar

    /// One 44 pt row. At narrow widths the count goes first, then the
    /// steppers; the field never does.
    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            barRow(showsCount: true, showsSteppers: true)
            barRow(showsCount: false, showsSteppers: true)
            barRow(showsCount: false, showsSteppers: false)
        }
        .frame(height: 44)
        .padding(.horizontal, 10)
    }

    private func barRow(showsCount: Bool, showsSteppers: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search this notebook", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .submitLabel(.go)
                .onSubmit(go)
                .layoutPriority(1)
                .frame(minWidth: 70)
            if !query.isEmpty {
                iconButton("xmark.circle.fill", label: "Clear search") {
                    query = ""
                }
            }
            #if os(iOS)
            PencilSearchButton(search: search) { query = $0 }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            #endif
            SearchFilterMenu(sources: $sources, dateRange: $dateRange)
                .labelStyle(.iconOnly)
            if showsCount, !hits.isEmpty {
                Text(matchCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsSteppers {
                iconButton("chevron.up", label: "Previous result") {
                    step(-1)
                }
                .disabled(!canStepBack)
                iconButton("chevron.down", label: "Next result") {
                    step(1)
                }
                .disabled(!canStepForward)
            }
            Button {
                showsResults.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showsResults ? Color.accentColor : .secondary)
            .accessibilityLabel(showsResults ? "Hide results" : "Show results")
            .disabled(trimmedQuery.isEmpty)
            iconButton("xmark", label: "Close search") {
                onClose()
            }
        }
    }

    private func iconButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let pageTarget {
                    pageNumberRow(pageTarget)
                    if !pageResults.isEmpty { Divider() }
                }
                ForEach(pageResults) { result in
                    pageRow(result)
                    Divider()
                }
                if pageTarget == nil, pageResults.isEmpty, settledQuery == trimmedQuery {
                    noMatches
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func pageNumberRow(_ page: Int) -> some View {
        Button {
            showsResults = false
            onGoToPage(page - 1)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "number.square")
                    .foregroundStyle(.secondary)
                Text("Go to Page \(page)")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to Page \(page)")
    }

    private func pageRow(_ result: PageResult) -> some View {
        let isSelected = result.pageID == selectedPageID
        return Button {
            jump(to: result)
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
        .accessibilityLabel(pageTitle(result))
    }

    private var noMatches: some View {
        Text("No matches for “\(trimmedQuery)”")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
    }

    // MARK: State

    private struct PageResult: Identifiable {
        let pageID: UUID
        let pageIndex: Int
        let hits: [SearchKit.SearchHit]
        var id: UUID { pageID }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The 1-based page a pure page-number query names, if any.
    private var pageTarget: Int? {
        PageNumberQuery.page(in: query, pageCount: pageCount)
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

    private var canStepBack: Bool {
        !pageResults.isEmpty && selectedIndex > 0
    }

    private var canStepForward: Bool {
        !pageResults.isEmpty && selectedIndex < pageResults.count - 1
    }

    private var matchCountText: String {
        let count = hits.count
        return "\(count) match\(count == 1 ? "" : "es")"
    }

    private func pageTitle(_ result: PageResult) -> String {
        result.pageIndex > 0 ? "Page \(result.pageIndex)" : "Page"
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            settledQuery = ""
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
            settledQuery = trimmed
            onHighlight(SearchHighlight(query: trimmed, sources: sources, dateRange: dateRange))
            // The first search lands on the page a search hit asked for; every
            // later search starts at the first result.
            let requested = pendingInitialPageID
            pendingInitialPageID = nil
            if let requested, pageResults.contains(where: { $0.pageID == requested }) {
                selectedPageID = requested
            } else {
                selectedPageID = pageResults.first?.pageID
            }
        }
    }

    /// Shows the results of a search started outside the bar, so the list
    /// matches the marks already on the pages.
    private func adopt(_ highlight: SearchHighlight?) {
        guard let highlight,
              highlight.query != query.trimmingCharacters(in: .whitespacesAndNewlines)
                || highlight.sources != sources
                || highlight.dateRange != dateRange
        else { return }
        sources = highlight.sources
        dateRange = highlight.dateRange
        query = highlight.query
    }

    /// Tapping a row jumps and folds the list away; the toggle brings it back.
    private func jump(to result: PageResult) {
        selectedPageID = result.pageID
        showsResults = false
        onSelectPage(result.pageID)
    }

    /// Moves the selection by `offset` and reports the page it lands on.
    private func step(_ offset: Int) {
        let results = pageResults
        guard !results.isEmpty else { return }
        let current = selectedIndex
        let next = min(max(current + offset, 0), results.count - 1)
        guard next != current else { return }
        let target = results[next]
        selectedPageID = target.pageID
        onSelectPage(target.pageID)
    }

    /// Return jumps to the page number, else the first text hit.
    private func go() {
        if let pageTarget {
            showsResults = false
            onGoToPage(pageTarget - 1)
        } else if let first = pageResults.first {
            jump(to: first)
        }
    }
}

#Preview("Notebook Find Bar") {
    NotebookFindBar(
        notebookID: UUID(),
        search: HandwritingSearch(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("NotebookFindBarPreview", isDirectory: true)),
        pageCount: 24,
        onSelectPage: { _ in },
        onGoToPage: { _ in },
        onClose: {}
    )
    .frame(width: 620)
    .padding()
}
