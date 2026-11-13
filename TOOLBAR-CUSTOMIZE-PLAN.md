# Toolbar customisation and layout plan

Written 2026-11-13. Follows `TOOLBAR-QOL-PLAN.md`. Files: `NoteApp/Notebook/EditorToolbar.swift`,
`EditorToolState.swift`, `NotebookView.swift` (Insert / More menus), `NoteApp/Settings/SettingsView.swift`.

## Problems today

1. Tools + colours + widths share one `ScrollView` fallback (`EditorToolbar.body`, `ViewThatFits`), so on a
   narrow window the whole middle scrolls, the pen chip and width dots slide off screen.
2. Ten tool buttons are always shown, including rarely used ones (Follow Links, Laser, Zoom View, Favourite
   Pens star). There is no way to hide, add or reorder anything.
3. Read Only takes a permanent slot on the right even though it is used rarely.
4. Width dots cannot be tuned from the toolbar; the colour row does not scroll the selected colour into view.

## Target layout (one row, 52 pt, never scrolls as a whole)

```
[‹ Library][Pages][Undo][Redo] | [Pen chip ▾][tool items…] | [◀ colour favourites ▶ (scrolls)][Palette] | [• ● ⬤ widths] | [Read Only pill?][Rec][⋯ More]
        pinned                     fixed, customisable          only this part scrolls     fixed         fixed            pinned
```

- Only the colour favourites live in a horizontal `ScrollView`. It takes the leftover width
  (`layoutPriority(-1)`, `minWidth` ≈ 3 swatches = 120 pt), with a soft fade mask on an edge that has more
  content, and `ScrollViewReader.scrollTo` the selected colour on appear and when the colour changes.
- Palette button stays fixed right of the scroll area (not inside it). The "+" add slot stays at the end of
  the scrolling list.
- Pen chip and width presets are always fixed and visible (this is the "pen tip" part).
- When the tool items do not fit (split view / Slide Over), tools collapse instead of scrolling: keep the pen
  chip, highlighter, eraser and the active tool visible; move the rest into a "chevron.down.circle"
  overflow `Menu`. Implement with `ViewThatFits` over (all items) → (priority items + overflow menu).
- Read Only: remove the permanent `lock.doc` button. Add "Read Only" as a toggle in the More menu. While read
  only is on, hide the tools / colours / widths groups and show the existing accent "Read Only" pill in the
  centre (tap = edit again).

## Customisable items

New file `NoteApp/Notebook/ToolbarLayout.swift`:

```swift
enum ToolbarItemID: String, CaseIterable, Codable, Identifiable {
    case highlighter, eraser, lasso, elements, insert,      // default on
         laser, zoomView, followLinks, ruler, shapes,       // available
         textBox, image, stickyNote, addPage, search, favoritePens
    var title: String; var systemImage: String
}
struct ToolbarLayout: Equatable {
    var items: [ToolbarItemID]
    static let defaultItems: [ToolbarItemID] = [.highlighter, .eraser, .lasso, .elements, .insert]
    init(storage: String)          // comma-separated rawValues; drop unknown + duplicates; empty/invalid → default
    var storage: String
    var available: [ToolbarItemID] // allCases not in items, in allCases order
    mutating func move/remove/add/reset
}
```

- Pen chip is not an item: it is always first and cannot be removed (the app always needs a pen).
- Persist with `@AppStorage("toolbar.items.v1")` on the `storage` string.
- Default set (what stays): Pen chip, Highlighter, Eraser, Lasso, Select Elements, Insert (+).
- Removed from the default bar (still addable in Edit Toolbar): Laser, Zoom View, Follow Links, Favourite
  Pens star. Favourite pens also move into the pen popover: add a "Favourite Pens" row/section at the top of
  `PenSettingsPopover` that shows the saved pens (reuse `FavoritePensPopover` content) so the star button is
  no longer needed by default.
- New optional items (each calls an existing action, no new features): Ruler toggle, Shapes (menu: Rectangle /
  Ellipse / Line), Text Box, Image, Sticky Note (menu of colours), Add Page, Search in Notebook.
  Pass these actions in from `NotebookView` through one closure `onItemAction: (ToolbarItemID) -> Void` plus a
  `@ViewBuilder itemMenu: (ToolbarItemID) -> some View` for the menu-style items (shapes, sticky note), so the
  toolbar does not need to know `NotebookSession`. Ruler needs an `isRulerActive` binding for its selected state.
- Keyboard shortcuts (P/H/E/V/L/Z) keep working whether or not the item is shown.

## Edit Toolbar sheet

New `ToolbarEditorView` (sheet, `.presentationDetents([.medium, .large])`):

- Section "In Toolbar": fixed row "Pen" (lock icon, no delete), then `ForEach(layout.items)` with
  `.onMove` and `.onDelete`, list always in edit mode (`.environment(\.editMode, .constant(.active))`).
- Section "More Items": `layout.available`, each row with a green `plus.circle.fill` button to add.
- Toolbar items: "Reset to Default" (confirmation) and "Done".
- Live preview: changes apply to the real toolbar immediately (it is right behind the sheet).

Entry points: More menu → "Customize Toolbar…" (`slider.horizontal.3`), a `.contextMenu` on the toolbar's
empty background (`Customize Toolbar…`), and Settings → Writing → "Customize Toolbar…".

## Small UX fixes in the same pass

- Width presets: tapping the already-selected dot opens a popover with the existing `WidthSlider` to tune that
  preset (only if `EditorToolState` already stores presets per tool; otherwise just set the current width).
  Selected dot keeps the accent background; dim to 0.4 when the tool has no width (unchanged).
- Every tool item uses the same selected style (accent capsule like the pen chip) and 44 pt hit target.
- Keep accessibility labels/hints for every item; overflow menu labelled "More Tools".
- Dividers only between groups that are visible (no double divider when a group is hidden).

## Tests

- `ToolbarLayout` unit tests: default when empty, unknown + duplicate IDs dropped, round-trip storage,
  move/remove/add/reset, `available` excludes shown items. Put them in the app test target if one exists; if
  none exists, make `ToolbarLayout` pure Swift and test it from a small test in the nearest existing test
  target that can reach it, or report that no target can.
- Build: iPad simulator build of the `NoteApp` scheme must succeed with no new warnings.

## Device checklist (user)

- Full-width iPad: whole bar visible, no scrolling except colours.
- Split view 1/2 and 1/3: pen chip + widths stay visible, tools collapse to overflow menu, colours scroll.
- Edit Toolbar: remove, add, reorder, reset; survives relaunch.
- Read Only from More menu hides tools and shows the pill.
