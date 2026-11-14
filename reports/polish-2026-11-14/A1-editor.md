# A1 — editor chrome audit

Files read: `NotebookView.swift` (1860), `EditorToolbar.swift` (1483), `ToolbarLayout.swift` (143), `ToolbarEditorView.swift` (91), `EditorToolState.swift` (548), `ColorPalettePopover.swift` (234), `FavoritePens.swift` (291), `PenPresets.swift` (43), `Selection.swift` (45), `SelectionActionBar.swift` (273), `SelectionActions.swift` (246), `SelectionEdit.swift` (326), `ZoomWindowView.swift` (596), `LayersPanel.swift` (138), `OutlinePanel.swift` (119), `EditorOverlays.swift` (127), `LaserPointerOverlay.swift` (154), `DeleteSpecificItemsView.swift` (157), `VersionHistoryView.swift` (116). Also read: `PERFORMANCE-NOTES.md`, the four decisions, `NotebookSession.swift:75-224`, `AppColor.swift`, `PencilCanvasView.swift:1-60`, `PageBookmarks.swift:70-78` for facts I needed to judge the above.

## Findings

| ID | Sev | Head | file:line | Quoted line | Why it hurts the user | Proposed fix | Size |
|---|---|---|---|---|---|---|---|
| A1-01 | P1 | 1 | EditorOverlays.swift:23 | `ForEach(0..<session.pageCount, id: \.self) { index in` | The page pill's menu is built from the whole page list. PERFORMANCE-NOTES targets two imported PDFs with 421 and 1,058 pages; on those, tapping the pill builds a thousand `Button`s on the main thread and presents a menu nobody can scroll to the end of. The app already ships `GoToPageField` and ⌘[ / ⌘] for this. | Show the current page ± a few, plus "Go to Page…" (the existing sheet) and "Page Overview…"; or present `PageOverviewGrid` instead of a menu when `pageCount > ~30`. | S |
| A1-02 | P2 | 1 | NotebookView.swift:1348 | `if let page = session.page {` | `pageArea` is a computed view of `NotebookPane` and reads the per-stroke `session.page`. PERFORMANCE-NOTES fix 11 removed exactly this read from the pane body for the zoom panel, with a comment saying it redrew "the toolbar, both menus and every modifier" per stroke. Whether `GeometryReader`'s content gets its own observation scope is not visible in source (see Not checked), but the dependency is there and the fix is the same one fix 11 used. | Move the `GeometryReader` + `if let page` + `pageContent` into a `private struct PageArea: View`, so only it reads `session.page`. Confirm with the Instruments check in PERFORMANCE-NOTES §1. | S |
| A1-03 | P2 | 1 | NotebookView.swift:1480 | `let stroke = session.visibleStrokes.first(where: { $0.id == strokeID })` | `visibleStrokes` (NotebookSession.swift:215) builds a `Set` of visible layer ids and filters every stroke, so it is O(n) and allocates. `pageContent` runs it three times per pass: `replayCutoff()` (1467), the shown-strokes mapping (1522-1523) and `activeReplayPoint()` (1480). On the 2,000-stroke page PERFORMANCE-NOTES benchmarks, that is six thousand record copies plus three set builds added to every stroke end, on top of the 4.59 ms converter. | Compute `visibleStrokes` once in `pageContent` and pass it down (or cache it on `syncPageChrome`), and look the replay stroke up by id there instead of filtering again. | S |
| A1-04 | P2 | 1 | NotebookView.swift:585 | `guard let data = try? Data(contentsOf: url) else {` | Insert → Image reads the whole file synchronously on the main actor inside the file-importer callback. A 12 MP photo is ~5–15 MB; the editor is frozen from the picker's dismissal until the read finishes, with no banner (unlike export, which shows one). | `Task.detached` the read, keep the security-scoped access inside it, show the existing banner while it runs, and report the specific error instead of the generic "The image could not be read." | S |
| A1-05 | P2 | 1 | OutlinePanel.swift:71 | `let isBookmarked = bookmarkedIDs.contains(pageID)` | `bookmarkedIDs` is a computed property that calls `PageBookmarks.bookmarkedPageIDs` (a fresh `Set` from an array map) — and it is called once per row, so the outline is O(pages × bookmarks), recomputed on every body pass of the sheet. Cheap now, quadratic on the 1,000-page notebook the spec mentions. | Hoist `let bookmarks = bookmarkedIDs` once in `body` and pass it into `row`. | S |
| A1-06 | P2 | 1 | LayersPanel.swift:72 | `let strokeCount = session.page?.strokes.filter { $0.layerID == layer.id }.count ?? 0` | Each row filters the entire page's stroke array twice (strokes and elements) against one layer id, so opening Layers on a 2,000-stroke page with five layers does 20,000 comparisons per body pass, and the page is read for every row. | Build `[UUID: (strokes: Int, elements: Int)]` in one pass in `body` and look it up per row. | S |
| A1-07 | P2 | 5 | EditorToolbar.swift:395 | `.disabled(editor.isReadOnly \|\| !isHistoryStepAvailable(item))` | `isHistoryStepAvailable` reads `PencilCanvasController.canUndo`, which is `target?.undoManager?.canUndo` on an `ObservableObject` with no published state (PencilCanvasView.swift:12-25). Nothing the toolbar observes changes when the undo stack does, so a toolbar Undo added in Customize Toolbar stays greyed at `opacity(0.35)` after the first stroke (and stays enabled after undoing everything) until an unrelated redraw — a tool tap — rebuilds the bar. | Publish undo availability (a counter bumped from `reportDrawingChange`, or `undoManager` notifications) and read it here; `.disabled` can then be trusted. | M |
| A1-08 | P2 | 5 | NotebookView.swift:943 | `.keyboardShortcut("f", modifiers: .command)` | The shortcut is attached to a `Button` inside `moreMenuItems`, i.e. inside a `Menu`'s content builder, which SwiftUI builds only when the menu opens. Per decision 2026-11-13-find-bar, ⌘F should open the Search tab; in practice it does nothing until the user has opened More at least once. The other hidden shortcuts in this area (`pageHistoryShortcuts`, `toolShortcuts`) show the working pattern. | Add ⌘F to a hidden shortcut `Group` like `pageHistoryShortcuts` (or drop the modifier from the menu item). | S |
| A1-09 | P2 | 5 | SelectionActionBar.swift:269 | `.frame(width: 38, height: 44)` | Every action in the selection bar is 38 pt wide with zero spacing between them (7 in a row: colour, width, duplicate, copy, paste, text, delete), and the recolour swatches in its popover are 30×30 with 6 pt gaps. On a 9th-gen iPad, Delete sits one slip away from Paste. | 44×44 minimum, with 4 pt between destructive and non-destructive actions; raise the popover swatches to 44 with `GridItem(.fixed(44), spacing: 4)`. | S |
| A1-10 | P2 | 5 | LayersPanel.swift:79 | `Image(systemName: isActive ? "checkmark.circle.fill" : "circle")` | The row's three icon buttons (make active, hide, lock) are bare `Image`s with `.borderless`; their tap area is the glyph, ~17–20 pt, and the menu is a fourth. Lock and hide are destructive-ish toggles a learner will miss repeatedly on a 44 pt-spec device. | Wrap each in `.frame(width: 44, height: 44).contentShape(Rectangle())`, as `FavoritePens` already does for its Edit button. | S |
| A1-11 | P2 | 5 | ColorPalettePopover.swift:115 | `.frame(width: 30, height: 34)` | Recent swatches are 30×34 and the 64 preset swatches are 34×34 (line 139, `swatchSize = 34` at line 20). This is the main way to pick ink colour, and every target is under the 44 pt guideline with 4 pt gaps. | 44×44 swatches (8 columns still fit a 340-wide popover at 40 + 4), or keep 34 pt visuals inside a 44 pt `contentShape`. | S |
| A1-12 | P2 | 6 | ColorPalettePopover.swift:160 | `.onChange(of: hexText) { _, newValue in` | Each keystroke calls `applyHex` → `editor.setColor`, which also calls `recentColors.record` and `presets.update`. Typing `#1E90FF` therefore applies and records up to six intermediate colours ("#1", "#1E", …), so Recent fills with junk the user never chose, and the ink changes under the popover as they type. | Apply on `.onSubmit` only; keep `hexIsInvalid` live. | S |
| A1-13 | P2 | 6 | SelectionActions.swift:151 | `else { return }` | "Copy as Text" and "Convert to Text Box" both return silently when recognition yields nothing (no page, empty recogniser result, `textBox` returning nil) and `recognizedInk` swallows decode failures with `try?` (line 183). The spinner stops and nothing at all happens, which reads as a broken menu item. | Set `session.errorMessage` ("No handwriting was recognised in the selection.") on the empty path, as `apply(failure:)` does for the other actions. | S |
| A1-14 | P2 | 4 | NotebookView.swift:315 | `.animation(.easeInOut(duration: 0.2), value: bannerState)` | None of the 18 animations in this area consults `accessibilityReduceMotion`; the Boards area already does (`BoardEditorView.swift:71`, `withAnimation(reduceMotion ? nil : …)`). Banner slides, panel slides, the zoom frame, and the 0.8 s laser fade all animate for a user who asked them not to. | Use the three shared animations, and pass `nil` when `reduceMotion` is on (follow the Boards pattern). | M |
| A1-15 | P2 | 2 | EditorToolbar.swift:897 | `.frame(width: 38, height: 44)` | The same toolbar-button idea has five metrics: 44×44 (`ToolbarIcon`, 1386), 40×44 (favourite swatch, 768; add slot, 834), 38×44 (width dots, 897), 40×44 in the page pill (EditorOverlays.swift:75), 44×36 in the zoom bar (ZoomWindowView.swift:214) and 32×44 for a banner dismiss (EditorOverlays.swift:111). The bar reads as slightly misaligned columns because the widths never line up. | One 44-wide target token for every bar icon; 40×36 for the visual, 44×44 for the frame. | M |
| A1-16 | P2 | 2 | EditorToolbar.swift:1058 | `VStack(alignment: .leading, spacing: 14) {` | The tool popovers disagree on width (Pen 320, Favourite Pens 300, Zoom options 300, Width/Eraser/Laser/Width-preset 280, Colour palette 340) and on the gap under their headline (10 in `FavoritePens`, 12 in `ColorPalettePopover`, 14 in the four tool popovers). Every one is the same element: a titled popover with rows. | 320 wide for all, 12 between title and content, 16 padding; move the diverging literals onto the token scale. | M |
| A1-17 | P3 | 1 | EditorToolbar.swift:680 | `.id(index)` | The favourite swatch list keys `ForEach` by colour (`id: \.element`) and then overrides view identity with the slot index, so a reorder (`moveFavoriteColor`, line 794) rebuilds the row instead of moving it: the drag animation is lost and VoiceOver focus lands on a new element. | Keep one identity: key `ForEach` by index and `scrollTo(index)`, dropping `id: \.element`. | S |
| A1-18 | P3 | 1 | LaserPointerOverlay.swift:46 | `livePoints.append(value.location)` | Every drag sample mutates `@State` and re-runs a page-sized `Canvas` that strokes the whole trail twice, once with `addFilter(.blur(radius: 7))` (line 120). On a 60 Hz iPad with a long visit (up to 1,200 points, line 20) that is two blurred page-size rasterisations per frame while the pointer moves. | Draw into a UIKit layer/`CAShapeLayer` and update its path, or clip the canvas to the trail's bounding box plus blur radius. | M |
| A1-19 | P3 | 4 | NotebookView.swift:265 | `.transition(.move(edge: .bottom).combined(with: .opacity))` | Nothing wraps the change in `withAnimation`: `showsSelectionActions` flips from `onSelectionChanged` (line 1581), so the transition never runs — the bar pops in and snaps out. The identical transition on `ZoomViewSection` (301) does animate, because its state changes are wrapped. | Wrap the selection change, or add an explicit `.animation(standard, value: showsSelectionActions)`. | S |
| A1-20 | P3 | 4 | EditorToolbar.swift:172 | `withAnimation(.easeInOut(duration: 0.15)) { editor.isReadOnly = true }` | Three durations for the same kind of state change: 0.15 (Read Only here and at 198, Edit in `FavoritePens` 176, swatch reorder 794), 0.2 (pages panel 146, zoom view 418/646/652, page history 689/1184/1250/1262/1739), and the laser's 0.8 s fade. | Collapse to the three shared animations: quick 0.18 for toggles, standard 0.25 for panels. | S |
| A1-21 | P3 | 5 | NotebookView.swift:114 | `.frame(width: 28, height: 28)` | The tab chip's close button is 28×28, and it sits inside a chip that is itself a tap target (`onTapGesture`, line 129) — a missed xmark switches tabs instead of closing. | 44×44 hit area (`contentShape`) with the 12 pt glyph. | S |
| A1-22 | P3 | 5 | ZoomWindowView.swift:214 | `.frame(width: 44, height: 36)` | The zoom bar is 40 pt tall and its four buttons are 44×36, so their targets end 2 pt above and below the bar and run into the resize drag gesture that covers the whole bar (`DragGesture` at line 193) — a slightly low tap resizes the panel instead. | 44 pt bar, 44×44 buttons, and attach the resize drag to a dedicated grab strip. | S |
| A1-23 | P3 | 5 | ZoomWindowView.swift:369 | `let size = CGSize(width: 64 / scale, height: 30 / scale)` | The band's move tab accepts touches in a 64×30 strip; the drawn tab is 36×6 (line 414). Moving the band is the primary way to steer Zoom View, and its grip is 30 pt high. | 44 pt tall hit rect. | S |
| A1-24 | P3 | 5 | EditorOverlays.swift:111 | `.frame(width: 32, height: 44)` | The banner's dismiss button is 32 pt wide, next to the banner's action button, so dismissing and acting are adjacent narrow targets. | 44 wide, and keep 8 pt from the action. | S |
| A1-25 | P3 | 5 | EditorOverlays.swift:75 | `.frame(width: 40, height: 44)` | Page pill chevrons and plus are 40 wide with 0 spacing (line 9), so Previous/Next/Add are contiguous 40 pt targets in a floating pill. | 44 wide. | S |
| A1-26 | P3 | 5 | NotebookView.swift:665 | `.keyboardShortcut("[", modifiers: .command)` | The only notebook shortcuts in this area are ⌘[ and ⌘] (plus the iOS-only `toolShortcuts`). On the Mac companion there is no shortcut for Add Page, Zoom In/Out, Export PDF, Page Overview, Layers or Version History — all of them exist as menu items with no key equivalent. | Add ⌘+ / ⌘- / ⌘0 for zoom, ⌘⏎ for Add Page, ⌘⇧E for Export, ⌘⇧O for Page Overview, as hidden buttons in this group (the established pattern). | S |
| A1-27 | P3 | 6 | NotebookView.swift:1819 | `ProgressView()` | The page placeholder shows an unlabelled spinner for every `isLoadingPage`, including the common instant case, so a page turn flashes a spinner that then disappears; when the load actually fails, the failure path (1833) does not say why beyond `loadError`. | Keep the previous page (or nothing) for the first ~150 ms, label the spinner, and show the failure reason in the same place. | S |
| A1-28 | P3 | 6 | EditorOverlays.swift:38 | `if session.isSaving {` | A mini spinner appears inside the page pill on every debounced save (400 ms after the last stroke, so after each burst of writing) and vanishes as soon as the write lands. It flashes rather than informing: there is no "saved" state and no failure state. | Drop the spinner; show a small "Saving…" caption only when `isSaving` has lasted over ~500 ms, and a banner when a save fails. | S |
| A1-29 | P3 | 6 | VersionHistoryView.swift:45 | `snapshots = await session.pageHistory()` | The result is assigned unconditionally and `isLoading` cleared, so a failed read is indistinguishable from "no versions yet" — the user is told nothing is there when the history may be unreadable. | Give `pageHistory` a throwing/failable variant and show a `ContentUnavailableView` with the reason plus a Retry button. | S |
| A1-30 | P3 | 7 | LayersPanel.swift:132 | `Image(systemName: "ellipsis.circle")` | The row's menu (Rename, Move Up/Down, Delete Layer) is an icon-only `Menu` with no `accessibilityLabel`, so VoiceOver announces a menu with no name; every other control in the row is labelled. | `.accessibilityLabel("Layer options")`. | S |
| A1-31 | P3 | 8 | LaserPointerOverlay.swift:74 | `static let red = Color(red: 0.93, green: 0.12, blue: 0.16)` | The laser colour is hard-coded here and again as a separate literal in `EditorToolbar.swift:1341`, outside `AppColor` (`NoteApp/AppColor.swift` holds `groupedBackground`, `paper`, `pageAnnotation`, `swatchOutline`). Two copies of one chrome colour drift apart. | `AppColor.laserMark`, used by the overlay, the preview and the trail. | S |
| A1-32 | P3 | 9 | ToolbarEditorView.swift:61 | `.navigationTitle("Customize Toolbar")` | The app writes British English in this very toolbar ("Favourite Pens", "Colour palette", "Recolour selection") and American English in the customize flow ("Customize Toolbar…" at NotebookView.swift:914 and EditorToolbar.swift:83, "Customize Toolbar" here, "ColorPicker… Custom Colour"). | Pick one: "Customise Toolbar". | S |
| A1-33 | P3 | 9 | DeleteSpecificItemsView.swift:65 | `Label("Delete Page Items", systemImage: "trash")` | One action, four names: the menu says "Delete Specific Items…" (NotebookView.swift:1045), the sheet title "Delete Specific Items", the button "Delete Page Items", the confirmation "Delete Items" and its message "Delete items from this page?". | "Delete Specific Items…" for the menu and title, "Delete Selected Items" for the button and the confirm action. | S |
| A1-34 | P3 | 9 | NotebookView.swift:1093 | `isBookmarked ? "Remove Bookmark" : "Bookmark This Page",` | The Bookmarks menu says "Bookmark This Page" while the outline's button says "Bookmark page" and "Remove bookmark" (OutlinePanel.swift:99), and the empty list says "No bookmarked pages". Three registers for one action. | "Bookmark This Page" / "Remove Bookmark" in both places. | S |
| A1-35 | P3 | 2 | EditorToolbar.swift:76 | `.frame(height: 52)` | The bar is 52 pt with a 36 pt visual inside a 44 pt frame, and no other chrome height in this area is derived from the same scale (zoom bar 40, banner min 44, selection bar min 48, page pill 44). | 48 or 56 from the spacing scale, shared by the toolbar and the zoom bar. | S |

## Head 2 — layout values off the token scale

Scale: spacing 2, 4, 8, 12, 16, 20, 24, 32; radius 4, 8, 10, 12, 16, 20. Counted only literal `padding`, stack `spacing` and `cornerRadius` values (frame widths/heights are covered by A1-15/A1-35, not here). Values already on the scale are not listed.

| File | value | count | proposed token | risk of visual change |
|---|---|---|---|---|
| NotebookView.swift | 3 | 1 | 4 | low |
| NotebookView.swift | 5 | 1 | 4 | low |
| NotebookView.swift | 6 | 1 | 8 | low |
| NotebookView.swift | 10 | 1 | 8 | low |
| NotebookView.swift | 14 | 4 | 12 | low |
| EditorToolbar.swift | 3 | 2 | 4 | low |
| EditorToolbar.swift | 5 | 2 | 4 | low |
| EditorToolbar.swift | 6 | 2 | 8 | low |
| EditorToolbar.swift | 14 | 5 | 12 | low |
| ColorPalettePopover.swift | 6 | 1 | 4 | low |
| ColorPalettePopover.swift | 10 | 1 | 8 | low |
| ColorPalettePopover.swift | -6, -5 | 2 | optical; keep, but as one named `hexBorderInset` | none |
| FavoritePens.swift | 1 | 1 | 2 | low |
| FavoritePens.swift | 10 | 2 | 8 | low |
| SelectionActionBar.swift | 6 | 4 | 4 | low |
| SelectionActionBar.swift | 10 | 1 | 8 | low |
| ZoomWindowView.swift | 6 | 1 | 8 | low |
| ZoomWindowView.swift | 14 | 1 | 12 | low |
| EditorOverlays.swift | 6 | 2 | 8 | low |
| EditorOverlays.swift | 10 | 1 | 8 | low |
| EditorOverlays.swift | 14 | 2 | 12 | low |
| VersionHistoryView.swift | 3 | 2 | 4 | low |
| VersionHistoryView.swift | 14 | 1 | 12 | low |
| LayersPanel.swift | — | 0 | — | none |
| OutlinePanel.swift | — | 0 | — | none |
| DeleteSpecificItemsView.swift | — | 0 | — | none |
| ToolbarEditorView.swift | — | 0 | — | none |
| ToolbarLayout.swift | — | 0 | — | none |
| EditorToolState.swift | — | 0 | — | none |
| Selection.swift / SelectionActions.swift / SelectionEdit.swift / PenPresets.swift | — | 0 | — | none |

Radii in this area are already on the scale: 10 at `EditorToolbar.swift:1002, 1241, 1325`, 8 at `ColorPalettePopover.swift:171`; everything else is a `Capsule` or `.continuous` list style. The UIKit corner radius at `ZoomWindowView.swift:415` is `3 / scale` on a 6 pt grab tab and is not a layout token.

Same element, different metrics (all one row each in the findings): toolbar/bar icon targets 32/38/40/44 wide (A1-15); popover widths 280/300/320/340 with header gaps 10/12/14 (A1-16); bar heights 40/44/48/52 (A1-35).

## Head 3 — fixed font sizes

| file:line | size | styles | text or glyph |
|---|---|---|---|
| NotebookView.swift:1536 | 11 medium monospacedDigit | the page number printed on the page corner | **text** — should be `.caption2.monospacedDigit()` so it follows Dynamic Type and the app's own type ramp |
| NotebookView.swift:1823 | 40 | `doc.badge.plus` in the empty-notebook placeholder | glyph |
| EditorToolbar.swift:535 | 17 medium | pen-style symbol in the pen chip | glyph |
| EditorToolbar.swift:543 | 9 bold | chevron in the pen chip | glyph |
| EditorToolbar.swift:825 | 11 semibold | `plus` in the add-favourite slot | glyph |
| EditorToolbar.swift:991 | 20 | pen-style symbol in the pen settings grid | glyph |
| EditorToolbar.swift:1382 | 17 medium | every toolbar icon (`ToolbarIcon`) | glyph |
| FavoritePens.swift:243 | 16 | pen-style symbol in a saved-pen row | glyph |
| SelectionActionBar.swift:93 | 13 semibold | lasso symbol in the selection count | glyph |
| SelectionActionBar.swift:267 | 15 regular | every selection-bar action icon | glyph |
| ZoomWindowView.swift:213 | 16 medium | zoom bar buttons | glyph |
| ZoomWindowView.swift:282 | 12 semibold | `arrow.right` in the advance area | glyph |

Only one fixed size sets running text (NotebookView.swift:1536). The rest are symbols and may stay fixed.

## Head 4 — animation list

| file:line | curve | animates |
|---|---|---|
| NotebookView.swift:315 | `.easeInOut(0.2)` | banners appearing/leaving (error, quarantine, layer block, lasso hint, export) |
| NotebookView.swift:649 | `.easeInOut(0.2)` | closing the inline pages panel |
| NotebookView.swift:689 | `.easeInOut(0.2)` | opening Search (side panel + compact sheet) |
| NotebookView.swift:1184 | `.easeInOut(0.2)` | Mac pages-panel toggle |
| NotebookView.swift:1250 | `.easeInOut(0.2)` | entering Reading Mode (panel close + chrome hide) |
| NotebookView.swift:1262 | `.easeInOut(0.2)` | leaving Reading Mode |
| NotebookView.swift:1739 | `.easeInOut(0.2)` | closing the Zoom View panel |
| NotebookView.swift:265 | transition only, **no driver** | selection action bar move+fade (dead, see A1-19) |
| NotebookView.swift:301 | transition, driven by the callers above | zoom panel move+fade |
| EditorToolbar.swift:146 | `.easeInOut(0.2)` | pages panel toggle |
| EditorToolbar.swift:172 | `.easeInOut(0.15)` | entering Read Only |
| EditorToolbar.swift:198 | `.easeInOut(0.15)` | leaving Read Only |
| EditorToolbar.swift:418 | `.easeInOut(0.2)` | Zoom View toggle from the overflow menu |
| EditorToolbar.swift:646 | `.easeInOut(0.2)` | opening Zoom View from its button |
| EditorToolbar.swift:652 | `.easeInOut(0.2)` | closing Zoom View from its options popover |
| EditorToolbar.swift:732 | `.easeInOut(0.2)` | scrolling the colour strip to the selected colour |
| EditorToolbar.swift:794 | `.easeInOut(0.15)` | moving a dragged favourite colour |
| FavoritePens.swift:176 | `.easeInOut(0.15)` | entering/leaving Edit mode in the saved-pen list |
| EditorOverlays.swift:125 | transition only | banner move+fade (driven by NotebookView:315) |
| LaserPointerOverlay.swift:64 | `.easeOut(0.25 / 0.8)` | laser mark fading after the pointer lifts |

Four curves for one kind of change (0.15, 0.2, 0.25, 0.8), none of them the shared quick/standard/emphasized trio, and none gated on Reduce Motion (A1-14, A1-20). No animation sits on per-stroke state; the per-stroke redraws are structural (A1-02, A1-03), not animated.

## Not checked

- **Whether `GeometryReader`'s content registers observation on `NotebookPane` or on its own node.** This decides whether A1-02 is a live per-stroke pane redraw or harmless. It cannot be settled from source and I could not run a build, a simulator or Instruments (READ-ONLY audit). PERFORMANCE-NOTES §1 is the check.
- **The real device cost of A1-03 and A1-18.** Both are estimated from the shapes of the loops and the numbers in PERFORMANCE-NOTES (2,000 strokes, 60 Hz), not measured. No Instruments runs were allowed.
- **`Menu` item construction cost on iOS 27.** A1-01 assumes the current behaviour (menu content built on presentation, all items materialised). I did not measure the threshold at which it hangs, so the "~30 pages" cut-off in the fix is a guess about the remedy, not the finding.
- **`SearchHighlightOverlay`, `TapeOverlay`, `PaperBackground`, `PencilCanvasView`, `NowPlayingBar`, `PagesSidePanel`, `PDFExportOptionsSheet`, `GoToPageField`** — all instantiated from `NotebookView.swift` but implemented outside this area; I judged the call sites only and did not audit their bodies.
- **Whether `.help(...)` / pointer affordances render on iPad** — out of scope by instruction (no pointer hover findings), and `.help` is used on every toolbar button.
- **`ToolbarItemID` keyboard conflicts** (bare `P`, `H`, `E`, `L`, `V`, `Z`, `[`, `]` with a hardware keyboard attached to an iPad): I could not confirm whether SwiftUI suppresses bare-key shortcuts while a text field is focused in this app's flows, so I make no finding.
