# Toolbar and quality-of-life plan (second update)

Written 2026-11-12 from the competitor research in `research_notes/competitors/` (GoodNotes, Notability, Noteshelf, other apps, community).

Scope, as asked: the main toolbar and daily writing comfort, usable on any iPad including the base model with a USB-C or 1st-gen Pencil. Out of scope: AI, audio, new document types, Pencil Pro-only features (squeeze, barrel roll, hover), and library/new-notebook flows.

## Already in the app (do not rebuild)

- "Tap the active tool again" opens its settings popover (`EditorToolbar.select`).
- Eraser Auto-Deselect back to the previous tool (`EditorToolState.didEndToolGesture`).
- Five recent colour swatches + system colour picker; three width dots.
- Single-key tool shortcuts P / H / E / V / L, ⌘Z / ⇧⌘Z.
- Pinch zoom and pan of one page (`ZoomablePageView`). Pages change only from the thumbnail strip, the page pill or Go To Page.

## Work packages

| WP | Feature | Seen in | Who | Main files |
|---|---|---|---|---|
| A | Colour palettes + favourite pens | all three apps | DeepSeek | `EditorToolState`, `EditorToolbar`, `PenPresets`, new `ColorPalettePopover`, new `FavoritePens` |
| B | Writing-input settings, eraser filter, optimised paper | GoodNotes, Notability, Noteshelf, Apple | DeepSeek | `AppSettings`, `SettingsView`, `PencilCanvasView`, `EditorToolState`, `PaperSize` |
| C | Hold to straighten / snap to shape | GoodNotes, Notability, Apple | Opus | new `InkKit/ShapeRecognizer`, `PencilCanvasView` coordinator |
| D | Seamless (vertical continuous) vs single page (horizontal swipe) | Notability, Noteshelf, GoodNotes | Opus | `NotebookView.pageArea`, `ZoomablePageView`, new `ContinuousPagesView`, `NotebookSession` |
| E | Zoom View (magnified writing band, auto-advance, wrap) | Notability, GoodNotes, Noteshelf, Nebo | Opus, after D | new `ZoomWindowView`, `NotebookView` |

### A — Colour palettes and favourite pens
- 8 favourite colours for the pen and 8 for the highlighter (separate), shown in the toolbar in place of the 5 recents. Highlighter favourites default to pastel highlight colours.
- Palette popover (tap the "+" / last swatch): a 8×8 preset grid (64 colours), a "Recent" row (last 8 used), a hex field, and the system picker for anything else.
- Long-press a favourite: Replace with current colour, Edit…, Remove. Drag to reorder is optional.
- Favourite pens: save the current pen (style + colour + width) as a favourite; up to 6; shown as a compact strip/menu next to the pen chip; tap recalls it; long-press removes.
- Persist in `UserDefaults` with versioned keys; migrate the old `swatches.v1` list into the pen favourites.

### B — Writing-input settings (new Settings section "Writing" + "Apple Pencil")
- "Draw with Finger" (default off) → `drawingPolicy` `.anyInput` vs `.pencilOnly`. When off, one finger scrolls.
- "Two-Finger Double-Tap to Undo" and "Three-Finger Double-Tap to Redo" (default on).
- "Pencil Double-Tap" action: Switch to Eraser / Switch to Previous Tool / Show Colour Palette / Off (default: system preference). Uses `UIPencilInteraction`; harmless on Pencils without double-tap.
- Eraser popover: "Erase Highlighter Only" toggle (stroke eraser only) and "Clear Page" button (existing confirmation).
- Paper size "Screen (Optimised)": an iPad-screen-shaped page (no letterboxing) added to `PaperSize`, available in Settings and the template picker.

### C — Hold to straighten
- Pause the Pencil ~0.5 s at the end of a stroke, then lift: the stroke is replaced by a straight line, or a clean rectangle / ellipse / triangle / polyline when it matches.
- Setting "Hold to Draw Shape" (default on). Pure, unit-tested recognizer in InkKit; undo restores the freehand stroke in one step.

### D — Seamless vs single page
- Per-notebook "Scrolling": Vertical (seamless, pages stacked with a gap, continuous scroll) or Horizontal (single page, swipe with one finger when Pencil-only, two fingers otherwise). Global default in Settings; also in the notebook More menu.
- Only the page nearest the viewport centre hosts the live PencilKit canvas; the others draw from cached renders. Writing on a visible neighbour page activates it.
- Must keep zoom, elements, layers, links, laser and thumbnails working.

### E — Zoom View (after D)
- Toggle in the toolbar. A bottom panel shows a magnified band of the page; a frame on the page shows the band. Writing in the panel inks the page.
- Auto-advance: when writing reaches the right advance area the band moves right; at the right margin it wraps to the next line at the left margin. Adjustable magnification and band height.

## Verification for every package
- `xcodebuild` for the iPad simulator and macOS both succeed.
- Package tests pass (`swift test` in each touched package); new pure logic gets tests.
- No `print`/`console` logging left in; no unrelated rewrites.
