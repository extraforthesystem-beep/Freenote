# Pages side panel plan

Written 2026-11-13. Builds on `feat/toolbar-customize` (`TOOLBAR-CUSTOMIZE-PLAN.md`).
Files: `NoteApp/Notebook/PageThumbnailStrip.swift`, `NotebookView.swift`, `EditorToolbar.swift`,
`ToolbarLayout.swift`, `NoteApp/Settings/SettingsView.swift`, `NoteApp/Settings/AppSettings.swift`,
`NoteAppTests/ToolbarLayoutTests.swift`.

## What changes

1. The page thumbnails stop living in a bottom strip (`PageThumbnailStrip`, 94 pt `LazyHStack` under the page).
   They move into a side panel next to the page: a vertical `ScrollView` with a `LazyVGrid` of thumbnails.
2. The panel sits on the right by default. Settings → Writing gets a "Pages Panel on Left" toggle
   (`AppSettings.Key.pagesPanelOnLeft`, `@AppStorage`, default false).
3. Undo and Redo buttons leave the toolbar's leading group so the tools get more room.

## Side panel (`PageThumbnailStrip.swift` → rename type to `PagesSidePanel`, keep the file or rename it)

- Width: fixed 220 pt column on regular width. On compact width (Slide Over, 1/3 split) do not show it inline;
  present the same grid as a `.sheet` with `.presentationDetents([.medium, .large])` instead.
- Grid: `LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)])`, so a 220 pt panel
  shows 2 columns. Vertical `ScrollView`, `ScrollViewReader` scrolls the current page into view on appear and
  when `session.pageIndex` changes (anchor `.center`), like the strip does now.
- Cells: reuse `PageThumbnailCell` unchanged (lazy decode, off-main rendering, dark paper, current-page ring).
  Let the cell size come from the grid column width with the page aspect ratio instead of the fixed
  54×76 frame. Under each cell show the page number (`caption2`, secondary; current page in accent).
- Tap a cell → `onSelect(index)` (same as now). Last grid item is the dashed "+ Page" tile (same action
  `session.addPage()`), sized like a cell.
- Header row (44 pt): title "Pages" + page count, and a close button (`sidebar.trailing` / `sidebar.leading`
  depending on side) that sets `showsThumbnails = false`.
- Background `.bar`, a `Divider` on the edge that faces the page.
- Keep accessibility: each cell labelled "Page N", current one has `.isSelected`.
- No new features (no drag reorder, no multi-select) in this pass.

## NotebookView layout

- Today: `VStack { toolbar; Divider; pageArea…; zoomPanel?; if showsThumbnails { Divider; strip } }`.
- New: `VStack { toolbar; Divider; HStack(spacing: 0) { [panel if left] ; VStack { pageArea…; zoomPanel? } ; [panel if right] } }`.
  The page counter pill, banners and zoom panel stay attached to the page column, not the panel.
- Transition `.move(edge: .trailing)` / `.leading` matching the side, animated with the existing
  `.easeInOut(duration: 0.2)`.
- Reuse the existing `@AppStorage("noteapp.editor.showsThumbnails")` as the open/closed state, so it is
  remembered. Read `horizontalSizeClass`: regular → inline panel, compact → sheet bound to the same flag.
- Search uses `.inspector` on the right. When the panel is on the right and search opens, close the panel
  (and do not reopen it automatically); opening the panel while search is open closes search. On the left
  they can coexist.
- More menu "Pages" item: change its icon to `sidebar.trailing` (or `sidebar.leading` when on left).

## Toolbar

- `EditorToolbar.leading`: keep Library (back) and the Pages toggle; remove the Undo and Redo buttons.
  The Pages toggle icon becomes `sidebar.trailing` / `sidebar.leading` (filled variant
  `sidebar.trailing` with `.symbolVariant(.fill)` or accent tint when open). Label "Show Pages"/"Hide Pages"
  stays. The toolbar needs the panel side, pass it as a `let pagesOnLeft: Bool` or read the same
  `@AppStorage` key.
- Keep ⌘Z and ⇧⌘Z working: move them to hidden buttons in the existing `toolShortcuts` view (same
  `controller.undo()` / `redo()`, disabled when read only). Two-finger double tap undo already exists.
- Add `undo` and `redo` to `ToolbarItemID` as opt-in items (titles "Undo"/"Redo", symbols
  `arrow.uturn.backward` / `arrow.uturn.forward`), NOT in `defaultItems`. Render them in the customisable
  tools group as plain buttons (not tool-selection style), disabled with `!controller.canUndo` /
  `!controller.canRedo` or read only. They go to the overflow menu like any other item when space is short.
  Put the new cases at the end of the enum so `available` order stays stable for existing items.
- Update the doc comment at the top of `EditorToolbar.swift` (leading group no longer has undo/redo).

## Tests

- `ToolbarLayoutTests`: `testEveryItemHasATitleAndSymbol` covers the new cases automatically; add one test
  that `undo` and `redo` are not in `defaultItems` and are in `ToolbarLayout().available`.
- Run `NoteAppTests` (scheme `NoteAppTests`) and an iPad simulator build of `NoteApp`. No new warnings.

## Device checklist (user)

- Full-width iPad: pages panel opens on the right, 2-column grid scrolls vertically, current page centred.
- Tap a thumbnail jumps to that page; "+ Page" adds a page and it appears in the grid.
- Settings → Pages Panel on Left moves it to the left.
- 1/3 split: Pages opens as a sheet instead of squeezing the page.
- Search on the right closes the right-side panel, no overlap.
- Toolbar has no Undo/Redo; ⌘Z, ⇧⌘Z and two-finger double tap still undo/redo; Undo/Redo can be added back
  in Customize Toolbar.
