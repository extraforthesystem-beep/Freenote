# Notebook find bar plan

Written 2026-11-13. Builds on `feat/pages-side-panel`.
Files: `NoteApp/Search/NotebookSearchPanel.swift` (replace with `NotebookFindBar.swift`),
`NoteApp/Search/PageNumberQuery.swift` (new), `NoteApp/Notebook/NotebookView.swift`,
`NoteApp/Notebook/GoToPageField.swift`, `NoteAppTests/PageNumberQueryTests.swift` (new).

## Goal

One search surface: a find bar pinned over the top of the page, with results dropping beneath it,
and page-number search in the same field. The right-hand search inspector goes away, so Search and
the Pages panel no longer fight over the right edge.

## Find bar

- New `NotebookFindBar` (rename/replace `NotebookSearchPanel`; keep the search logic).
- Presented as an overlay pinned to the top of the page column in `NotebookView`:
  `pageArea.overlay(alignment: .top) { if showsSearch { NotebookFindBar(...) } }`, with
  `.padding(.top, 10)` and `.padding(.horizontal, 16)`. It does not scroll with the page and does
  not resize the page.
- Width: `.frame(maxWidth: 620)`, so it adapts in split view; on compact width it spans the column.
- Bar row (one line, 44 pt): magnifier, `TextField("Search this notebook")`, clear button,
  `PencilSearchButton`, `SearchFilterMenu`, match count, previous/next chevrons, results toggle,
  close. Use `ViewThatFits`-style staging so at narrow widths the count text hides first, then the
  chevrons; the field never disappears.
- Background: `.regularMaterial` in a rounded rectangle with a soft shadow; the results list uses
  the same material, joined to the bar (no gap).
- Focus: `@FocusState` focuses the field when the bar appears. Escape closes it (`.onKeyPress(.escape)`
  on iOS 17+, `.onExitCommand` on macOS). Return jumps to the page-number target, else the first result.
- Results: `ScrollView` + `LazyVStack`, `frame(maxHeight: 320)`, rows as today (page title + marked
  snippets, selected row tinted). Hidden once a result is tapped; the results toggle (chevron)
  brings the list back. Count + prev/next stay in the bar.
- Closing the bar clears `onHighlight(nil)` and cancels the search task, as the panel does now.
- Accessibility: bar labelled "Notebook search"; rows "Page N"; chevrons "Previous/Next result";
  close "Close search".

## Page-number search

- New `NoteApp/Search/PageNumberQuery.swift`:
  ```swift
  enum PageNumberQuery {
      /// 1-based page for a pure page-number query, or nil.
      static func page(in query: String, pageCount: Int) -> Int?
  }
  ```
  Accepts (case-insensitive, trimmed): `12`, `p12`, `p.12`, `page 12`, `pg 12`.
  Rejects `0`, values above `pageCount`, and anything with other words.
- When a page number matches, the results list starts with a "Go to Page N" row (icon
  `number.square`), even when handwriting search returns nothing. Text hits follow below, so a
  query like `2024` can still match ink.
- Tapping the page row (or pressing Return) calls `onGoToPage(index)` with the 0-based index.
- `GoToPageField.parsedPage` reuses `PageNumberQuery` so the sheet and the find bar agree
  (the sheet stays; it is still in the page menu).
- Pass `pageCount` and `onGoToPage` into `NotebookFindBar`; `onSelectPage` already exists for hits.

## NotebookView

- Delete the `.inspector(isPresented: $showsSearch) { NotebookSearchPanel(...) }` block.
- Delete the `onChange(of: showsSearch)` that closes the right pages panel, and the
  `if isShown && !pagesOnLeft { showsSearch = false }` line in `pagesPanelBinding`. Both surfaces
  can now be open; search floats over the page.
- Add the overlay on `pageArea` (inside the page-column `VStack`, after the banners overlay) with a
  `.move(edge: .top).combined(with: .opacity)` transition and the existing 0.2 s animation.
- Keep every existing trigger: toolbar `.search` item, More → "Search in Notebook…", ⌘F.
- Mac: the same overlay works in the Mac editor; keep the frame width cap.

## Tests

- `NoteAppTests/PageNumberQueryTests.swift`: `12`→12, `p12`→12, `p.12`→12, `Page 3`→3, `pg 7`→7,
  ` 7 `→7, `0`→nil, `99` with count 10→nil, `abc`→nil, `12a`→nil, empty→nil.
- Update the SwiftUI preview to `NotebookFindBar`.
- Run `NoteAppTests` and build the app for the iPad simulator; no new warnings.

## Device checklist (user)

- Search opens a bar pinned over the top of the page and stays put while the page scrolls.
- Typing `12` shows "Go to Page 12" first; Return jumps there.
- Page marks still highlight; tapping a text result jumps and collapses the results list, toggle reopens it.
- Pages panel can stay open on the right while search is open.
- Escape / close dismisses the bar and clears marks.
- 1/3 split: the bar still fits, field usable, results scroll.
