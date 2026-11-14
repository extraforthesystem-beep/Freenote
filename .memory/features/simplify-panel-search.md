---
type: feature
title: Simplify the notebook chrome and merge panel search into the pages panel
status: in-progress
priority: high
updated: 2026-11-14
---

# Simplify notebook chrome + one search field in the pages panel (iPad)

User request (from an annotated iPad screenshot): move the panel toggle to the right of the toolbar,
remove the permanent bottom page pill and the bottom-left page back/forward pill, show the page number
only briefly while pages change, and replace the panel's `Pages | Search` tabs with one always-visible
search field whose filter button sits where the close button was.

Work only in the files listed. Do not reformat or rewrite unrelated code. No new packages.
Follow existing patterns: `AppSpacing`, `AppRadius`, `AppMotion.animate(_, reduceMotion:)`,
`.hitTarget()`, `ToolbarIconButton`, `@AppStorage(AppSettings.Key...)`.

## 1. Toolbar: panel toggle moves to the right — `NoteApp/Notebook/EditorToolbar.swift`

- In `leading`, keep only the back button. Move the existing Pages toggle (`ToolbarIconButton`
  with `sidebar.leading`/`sidebar.trailing`, gated by `showsPageControls`) into `trailing`,
  placed **last, after the More menu** (far right edge).
- Update the doc comment at the top of the struct (Left: back. Right: read only, recording, More, Pages toggle).

## 2. Remove the bottom page chrome — `NoteApp/Notebook/NotebookView.swift`

- Delete the `PageCounterPill(...)` block in the `.overlay(alignment: .bottom)` (keep the
  `SelectionActionBar` and `NowPlayingBar` in that VStack).
- Delete `PageHistoryControls(session: session)` from the `.overlay(alignment: .bottomLeading)`;
  keep `pdfLinkHistoryChip` there. Keep `pageHistoryShortcuts` (⌘[ / ⌘]) — keyboard only.
- Do not delete `PageCounterPill` / `PageHistoryControls` source files (Mac header or tests may use them);
  only remove these two usages. If either type becomes completely unused, leave it anyway.

## 3. Transient page indicator — new `NoteApp/Notebook/PageChangeIndicator.swift`

- `struct PageChangeIndicator: View { let session: NotebookSession }` — a small capsule
  `Text("\(session.currentPageNumber) / \(session.pageCount)")` (`.subheadline.monospacedDigit().weight(.medium)`,
  `.regularMaterial` capsule, thin `.separator` stroke, padding h 12 / v 6).
- Hidden by default. On `.onChange(of: session.pageIndex)` show it, then hide after 1.5 s
  (use `.task(id: showToken)` with `Task.sleep`, cancelled by the next change so scrolling keeps it up).
  Fade in/out with `AppMotion.animate(AppMotion.quick, reduceMotion:)`. Never shown on first appear.
  `.allowsHitTesting(false)`, accessibility: `.accessibilityHidden(true)` is fine (VoiceOver gets the page from the panel).
- Respect the existing setting `@AppStorage(AppSettings.Key.showPageNumber)`: when false, never show.
- In `NotebookView.swift` add it as `.overlay(alignment: .topLeading)` on `pageArea` with
  `.padding(.leading, 12).padding(.top, 12)`, only when `!editor.isReadingMode`.
  (Top-left of the page area = just below the toolbar.)
- New file is auto-included (project uses file-system synchronized groups). Verify it compiles.

## 4. Panel: one search field, no tabs, filter replaces close — `PagesSidePanel.swift`, `NotebookFindBar.swift`, `NotebookView.swift`

`NotebookFindBar` is only used embedded in `PagesSidePanel` (plus its #Preview). Make it embedded-only:

- Make it generic: `struct NotebookFindBar<Idle: View>: View` with a new init param
  `@ViewBuilder idle: () -> Idle` stored as `let idle: Idle`. Remove `isEmbedded`, the floating
  layouts (`compactBarRow`, `FindBarChrome`, floating `barRow` variants, the 620/320 frames) and `onClose`
  if unused after the changes below. Update the #Preview (pass `idle: { Color.clear }`).
- Add `@Binding var focusRequest: Bool`. Replace `.task { isFieldFocused = true }` with
  `.task(id: focusRequest) { if focusRequest { isFieldFocused = true; focusRequest = false } }`
  so the keyboard only opens when asked (⌘F / toolbar Search / More → Search), never just because the panel shows.
- **Header row (44 pt, horizontal padding `AppSpacing.s`):** a rounded search field capsule
  (`Color.secondary.opacity(0.12)` fill, `AppRadius.s` continuous corners, height 34) containing
  `magnifyingglass` (secondary), the `TextField("Search pages", ...)`, and when non-empty a small
  `xmark.circle.fill` clear button (`.frame(width: 28, height: 34)`). To the right of the capsule:
  the filter button (section 5) at `.hitTarget()`. Nothing else in the row (no pencil button,
  no ellipsis menu, no list toggle, no close button). Apple Pencil Scribble writes into the field natively.
- **Body:**
  - query trimmed empty → `idle` (the page grid) fills the rest.
  - query non-empty → a results header row then the results list (grid hidden):
    results header = `Text(matchSummary)` (e.g. "5 matches · 3 pages", `.caption`, secondary) + `Spacer` +
    chevron.up / chevron.down `iconButton`s with the existing `ResultShortcut` (⌘G / ⇧⌘G) and existing
    `step(_:)` / `canStepBack` / `canStepForward`. Then `Divider`, then the existing `results` list
    (page-number "Go to Page N" row first, then one row per page titled "Page N" with snippets — keep `pageRow`).
  - Tapping a result row selects + jumps but does **not** fold the list (remove `showsResults` and `resultsToggle` entirely).
  - Return / "Go to Page N" on a page-number query: jump, then set `query = ""` so the grid returns showing that page.
  - Remove `searchHint`.
- Escape: if query non-empty clear it; otherwise do nothing (remove `onClose` usage).
- Keep `adopt(activeHighlight)`, debounce, `pendingInitialPageID`, `onHighlight` behaviour. Clearing the query
  already calls `onHighlight(nil)`. Keep the `.onDisappear` that clears marks.

`PagesSidePanel.swift`:
- Delete `enum NotebookPanelTab`, the `tab` binding, the segmented `Picker` header, the close button and `onClose`.
- Add `@Binding var searchFocusRequest: Bool`.
- Body: `VStack(spacing: 0) { NotebookFindBar(..., focusRequest: $searchFocusRequest, idle: { pagesGrid }) }`
  — the find bar's header replaces the old header; a `Divider` sits under the header inside the find bar.
  Keep `.id(session.notebookID)` on the find bar, the edge divider, `.background(.bar)` and the aspect refresh.

`NotebookView.swift`:
- Remove `pagesPanelTab`; add `@State private var searchFocusRequest = false`.
- `pagesPanelBinding.set`: drop the `pagesPanelTab = .pages` line.
- Both `PagesSidePanel(...)` call sites: drop `tab:` and `onClose:`, pass `searchFocusRequest: $searchFocusRequest`.
- `isSearchVisible` → `pagesPanelIsInline ? showsThumbnails : showsCompactPages`.
- `openSearch()`: set `searchFocusRequest = true` and open the panel (keep the existing animate block).

## 5. Filter popover — new `NoteApp/Search/PanelSearchFilter.swift`

- `struct PanelSearchFilterButton: View` with bindings `sources: Set<PageTextSource>`,
  `dateRange: SearchDateRange`, `pageRange: ClosedRange<Int>?` and `let pageCount: Int`.
  Icon `line.3.horizontal.decrease.circle` (`.fill` variant when any filter is active), plain button,
  `.hitTarget()`, accessibilityLabel "Search Filters", opens a `.popover` (iOS) with a `Form`/`VStack`:
  - **Search In** — a `Toggle` per `PageTextSource.allCases` using `sectionTitle`
    ("Written Notes" = handwriting), never allowing the last one off (same rule as `SearchFilterMenu`).
  - **Pages** — `Picker` All Pages / Range (segmented). Range shows two `Stepper`s "From N" / "To N"
    clamped to `1...pageCount`, from ≤ to. Range off → `pageRange = nil`.
  - **Last Edited** — `Picker` over `SearchDateRange.allCases` (`.title`).
  - A footnote: `Type a page number (e.g. 12 or p12) to jump to it.`
  - A "Reset" button that restores all sources, nil range, `.anyTime`.
  - Popover width ~300, `.presentationCompactAdaptation(.popover)`.
- In `NotebookFindBar` add `@State private var pageRange: ClosedRange<Int>?`; re-search on change; after
  `search.search(...)` drop hits whose `pageIndex` (1-based; 0 = unknown, keep those) is outside the range
  **before** grouping. Put that filtering in a small pure `static func` on `FindBarPageResult`
  (e.g. `filter(_ hits:, pageRange:)`) so it is unit-testable.
- Leave `SearchFilterMenu` in `PencilSearchPad.swift` untouched (library search uses it).

## 6. Tests — `NoteAppTests/FindBarPageRangeTests.swift` (new)

- range nil keeps all; range 2...3 keeps pages 2 and 3, drops 1 and 4; pageIndex 0 always kept.

## Out of scope

Mac header (`macHeader`) layout, Settings UI, library search, any InkKit/package code, memory files.

## Done when

- `xcodebuild build -project NoteApp.xcodeproj -scheme NoteApp -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/simplify-panel-ios CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -30` → BUILD SUCCEEDED
- `xcodebuild test -project NoteApp.xcodeproj -scheme NoteApp -destination 'platform=macOS' -derivedDataPath /tmp/simplify-panel-mac CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=CQ65B26KFJ 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -15` → TEST SUCCEEDED
- `grep -rn "NotebookPanelTab\|PageCounterPill(" NoteApp/Notebook/NotebookView.swift NoteApp/Notebook/PagesSidePanel.swift` → nothing
- Commits use `feat:/refactor:/test:` prefixes, imperative, < 70 chars. No `print`/console logging added.

## Worker report
- Status: done
- Changed: NoteApp/Notebook/EditorToolbar.swift — Pages toggle moved to the trailing edge, last after More
- Changed: NoteApp/Notebook/NotebookView.swift — bottom page pill and history pill removed, transient indicator, search focus plumbing
- Changed: NoteApp/Notebook/PagesSidePanel.swift — tabs and close button replaced by the embedded find bar
- Changed: NoteApp/Search/NotebookFindBar.swift — generic bar: one field, results header, list stays after a jump
- Changed: NoteApp/Search/PanelSearchFilter.swift — new filter popover for sources, page range and last edited
- Changed: NoteApp/Notebook/PageChangeIndicator.swift — new capsule that fades out 1.5 s after a page change
- Changed: NoteAppTests/FindBarPageRangeTests.swift — page-range filter unit tests
- Checks: iOS Simulator build → pass | macOS test (114) → pass | chrome grep → nothing
- Open: AppModelOpenTests concurrent-open test flaked once, passed on rerun; unrelated to this change
