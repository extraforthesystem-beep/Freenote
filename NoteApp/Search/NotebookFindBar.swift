import SearchKit
import SwiftUI

/// One result row: every hit on one page, with the page's hits kept in the
/// order the search returned them.
struct FindBarPageResult: Identifiable, Hashable {
    let pageID: UUID
    let pageIndex: Int
    let hits: [SearchKit.SearchHit]

    var id: UUID { pageID }

    /// One row per page, in page order, with every source's hit on that page.
    /// Computed when the hits change, never while the bar draws.
    static func group(_ hits: [SearchKit.SearchHit]) -> [FindBarPageResult] {
        var order: [UUID] = []
        var grouped: [UUID: [SearchKit.SearchHit]] = [:]
        for hit in hits {
            if grouped[hit.pageID] == nil { order.append(hit.pageID) }
            grouped[hit.pageID, default: []].append(hit)
        }
        return order.compactMap { pageID in
            guard let pageHits = grouped[pageID] else { return nil }
            return FindBarPageResult(
                pageID: pageID,
                pageIndex: pageHits.first?.pageIndex ?? 0,
                hits: pageHits
            )
        }
        .sorted { $0.pageIndex < $1.pageIndex }
    }

    /// The hits on the pages inside `pageRange`. A hit with no page number (0)
    /// has no page to judge it by, so it stays.
    static func filter(
        _ hits: [SearchKit.SearchHit],
        pageRange: ClosedRange<Int>?
    ) -> [SearchKit.SearchHit] {
        guard let pageRange else { return hits }
        return hits.filter { $0.pageIndex == 0 || pageRange.contains($0.pageIndex) }
    }

    var title: String {
        pageIndex > 0 ? "Page \(pageIndex)" : "Page"
    }

    /// What VoiceOver reads: the page, the first match and the hit count.
    var accessibilityLabel: String {
        let snippet = hits.first?.snippet.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts = [title]
        if !snippet.isEmpty { parts.append("“\(snippet)”") }
        if hits.count > 1 {
            parts.append("\(hits.count) matches")
        }
        return parts.joined(separator: ", ")
    }
}

/// The pages panel's search: one field over the page grid it filters.
///
/// The bar owns where a jump goes and what the pages mark; `idle` is what fills
/// the panel while the field is empty, which is the page grid it lives above.
struct NotebookFindBar<Idle: View>: View {
    private let notebookID: UUID
    private let search: HandwritingSearch
    private let pageCount: Int
    /// The search the pages already mark, e.g. from the library search.
    private let activeHighlight: SearchHighlight?
    private let onHighlight: (SearchHighlight?) -> Void
    private let onSelectPage: (UUID) -> Void
    private let onGoToPage: (Int) -> Void
    private let idle: Idle

    /// Asks for the keyboard. Set by ⌘F, the toolbar's Search item and the More
    /// menu; cleared as soon as it is honoured, so showing the panel alone never
    /// opens the keyboard.
    @Binding var focusRequest: Bool

    @State private var query = ""
    @State private var sources = Set(PageTextSource.allCases)
    @State private var dateRange = SearchDateRange.anyTime
    @State private var pageRange: ClosedRange<Int>?
    @State private var hits: [SearchKit.SearchHit] = []
    /// The hits grouped into rows when they arrive, so a body pass never
    /// regroups or re-sorts them.
    @State private var pageResults: [FindBarPageResult] = []
    @State private var selectedPageID: UUID?
    /// Consumed by the first search, so later searches start at the first result.
    @State private var pendingInitialPageID: UUID?
    /// The query whose hits are in `hits`, so an empty list is not shown mid-search.
    @State private var settledQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    /// - Parameters:
    ///   - notebookID: the notebook to search; the index is scoped to it.
    ///   - search: the app's shared `HandwritingSearch`, which owns the index.
    ///   - pageCount: the notebook's pages, so page numbers can be range-checked.
    ///   - activeHighlight: the search the pages already mark; the bar adopts it.
    ///   - initialPageID: the page the first search should land on, when it has a match.
    ///   - focusRequest: set to focus the field; the bar clears it once it has.
    ///   - onHighlight: called with the query the page should mark, or nil to clear the marks.
    ///   - onSelectPage: called with the page ID of the chosen text hit.
    ///   - onGoToPage: called with the 0-based page of a page-number query.
    ///   - idle: what fills the panel while the field is empty.
    init(
        notebookID: UUID,
        search: HandwritingSearch,
        pageCount: Int,
        activeHighlight: SearchHighlight? = nil,
        initialPageID: UUID? = nil,
        focusRequest: Binding<Bool>,
        onHighlight: @escaping (SearchHighlight?) -> Void = { _ in },
        onSelectPage: @escaping (UUID) -> Void,
        onGoToPage: @escaping (Int) -> Void,
        @ViewBuilder idle: () -> Idle
    ) {
        self.notebookID = notebookID
        self.search = search
        self.pageCount = pageCount
        self.activeHighlight = activeHighlight
        self.onHighlight = onHighlight
        _pendingInitialPageID = State(initialValue: initialPageID)
        _focusRequest = focusRequest
        self.onSelectPage = onSelectPage
        self.onGoToPage = onGoToPage
        self.idle = idle()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if trimmedQuery.isEmpty {
                idle
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsHeader
                Divider()
                results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notebook search")
        .task(id: focusRequest) {
            guard focusRequest else { return }
            isFieldFocused = true
            focusRequest = false
        }
        .onChange(of: query) { _, value in
            scheduleSearch(value)
        }
        .onChange(of: sources) { _, _ in
            scheduleSearch(query)
        }
        .onChange(of: dateRange) { _, _ in
            scheduleSearch(query)
        }
        .onChange(of: pageRange) { _, _ in
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
            guard !trimmedQuery.isEmpty else { return .ignored }
            query = ""
            return .handled
        }
        #else
        .onExitCommand {
            if !trimmedQuery.isEmpty { query = "" }
        }
        #endif
    }

    // MARK: Header

    /// One 44 pt row: the field's capsule and the filter button. The field
    /// takes Pencil Scribble as typed text; nothing else competes with it.
    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                searchField
                clearButton
            }
            .padding(.horizontal, AppSpacing.s)
            .frame(height: 34)
            .background(
                Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppRadius.s, style: .continuous)
            )

            PanelSearchFilterButton(
                sources: $sources,
                dateRange: $dateRange,
                pageRange: $pageRange,
                pageCount: pageCount
            )
        }
        .padding(.horizontal, AppSpacing.s)
        .frame(height: 44)
    }

    private var searchField: some View {
        TextField("Search pages", text: $query)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .focused($isFieldFocused)
            .submitLabel(.go)
            .onSubmit(go)
            .layoutPriority(1)
    }

    private var clearButton: some View {
        Group {
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
    }

    // MARK: Results

    /// How many matches over how many pages, above the list.
    private var matchSummary: String {
        guard !hits.isEmpty else {
            // A page-number query has no text matches, but is still a target.
            if let pageTarget { return "Page \(pageTarget)" }
            return settledQuery == trimmedQuery ? "No matches" : "Searching…"
        }
        let matchWord = hits.count == 1 ? "match" : "matches"
        let pageWord = pageResults.count == 1 ? "page" : "pages"
        return "\(hits.count) \(matchWord) · \(pageResults.count) \(pageWord)"
    }

    private var resultsHeader: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(matchSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            iconButton("chevron.up", label: "Previous Result", shortcut: .previousResult) {
                step(-1)
            }
            .disabled(!canStepBack)
            iconButton("chevron.down", label: "Next Result", shortcut: .nextResult) {
                step(1)
            }
            .disabled(!canStepForward)
        }
        .padding(.leading, AppSpacing.m)
        .padding(.trailing, AppSpacing.xs)
        .frame(minHeight: 44)
    }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageNumberRow(_ page: Int) -> some View {
        Button {
            jumpToPage(page)
        } label: {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "number.square")
                    .foregroundStyle(.secondary)
                Text("Go to Page \(page)")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to Page \(page)")
    }

    private func pageRow(_ result: FindBarPageResult) -> some View {
        let isSelected = result.pageID == selectedPageID
        return Button {
            jump(to: result)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.s) {
                    Text(result.title)
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
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.accessibilityLabel)
    }

    private var noMatches: some View {
        Text("No matches for “\(trimmedQuery)”")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.m)
    }

    private func iconButton(
        _ systemImage: String,
        label: String,
        shortcut: ResultShortcut? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .hitTarget()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .modifier(ResultShortcutModifier(shortcut: shortcut))
    }

    // MARK: State

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The 1-based page a pure page-number query names, if any.
    private var pageTarget: Int? {
        PageNumberQuery.page(in: query, pageCount: pageCount)
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

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            pageResults = []
            settledQuery = ""
            selectedPageID = nil
            onHighlight(nil)
            return
        }
        let sources = sources
        let dateRange = dateRange
        let pageRange = pageRange
        searchTask = Task {
            // Debounce: one scoped search per pause, not per keystroke.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = await search.search(trimmed, in: notebookID, sources: sources, dateRange: dateRange)
            guard !Task.isCancelled else { return }
            // The page filter is applied before grouping, so a page outside the
            // range never gets a row of its own.
            let kept = FindBarPageResult.filter(found, pageRange: pageRange)
            // Group once, here, so the body never sorts the whole result set.
            let grouped = FindBarPageResult.group(kept)
            hits = kept
            pageResults = grouped
            settledQuery = trimmed
            onHighlight(SearchHighlight(query: trimmed, sources: sources, dateRange: dateRange))
            // The first search lands on the page a search hit asked for; every
            // later search starts at the first result.
            let requested = pendingInitialPageID
            pendingInitialPageID = nil
            if let requested, grouped.contains(where: { $0.pageID == requested }) {
                selectedPageID = requested
            } else {
                selectedPageID = grouped.first?.pageID
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

    /// Tapping a row jumps and keeps the list, so the reader can try the next one.
    private func jump(to result: FindBarPageResult) {
        selectedPageID = result.pageID
        onSelectPage(result.pageID)
    }

    /// Jumps to a page-number query and drops the query, so the panel goes back
    /// to the grid showing that page.
    private func jumpToPage(_ page: Int) {
        onGoToPage(page - 1)
        query = ""
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
            jumpToPage(pageTarget)
        } else if let first = pageResults.first {
            jump(to: first)
        }
    }
}

/// The two result steppers and the Mac shortcuts that reach them: ⌘G next,
/// ⇧⌘G previous.
enum ResultShortcut {
    case nextResult
    case previousResult

    var key: KeyEquivalent { "g" }

    var modifiers: EventModifiers {
        self == .nextResult ? .command : [.command, .shift]
    }
}

private struct ResultShortcutModifier: ViewModifier {
    let shortcut: ResultShortcut?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}

#Preview("Notebook Find Bar") {
    NotebookFindBar(
        notebookID: UUID(),
        search: HandwritingSearch(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("NotebookFindBarPreview", isDirectory: true)),
        pageCount: 24,
        focusRequest: .constant(false),
        onSelectPage: { _ in },
        onGoToPage: { _ in },
        idle: { Color.clear }
    )
    .frame(width: 240, height: 500)
    .padding()
}
