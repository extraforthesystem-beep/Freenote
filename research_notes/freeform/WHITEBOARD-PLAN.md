# Freeform-style whiteboard — plan

Sources: `FREEFORM-RESEARCH.md` (Freeform behaviour), `BOARD-CODE-AUDIT.md` (current code).
Rule: simplest thing that feels like Freeform. Tools are the notebook's tools, not new ones.

## Shape of the solution

- **Canvas**: the board's `PKCanvasView` (InkKit `InkCanvasView`) is itself the scroll view.
  It gets a huge fixed world (50 000 × 50 000 pt) and free zoom 10 %–400 %, instead of
  the notebook's locked fit-zoom. "Infinite" = a world too big to reach the edge.
  Board coordinates stay as stored; a constant world offset (25 000, 25 000) is applied
  when the drawing loads and removed when it saves, so old boards land in the middle.
- **Layers, bottom to top**: dot grid (redrawn from offset + zoom) → board items
  (sticky, text, shape, image) as views positioned by world→view transform → transparent
  ink canvas → selection chrome (only when something is selected).
  Pencil inks on top of items, which is how you annotate a sticky.
- **Gestures**: Pencil draws; finger pans (1 finger) and pinches. Respect the app's
  existing "draw with finger" setting. Finger tap on an item selects it; tap empty
  deselects; drag selected item moves it; corner handle resizes. Lasso tool selects ink,
  exactly as in the notebook.
- **Tools**: reuse `EditorToolState` + `EditorToolbar` + all popovers unchanged
  (pens, colours, favourites, eraser modes, lasso, laser, hold-to-shape, undo/redo).
  Shared state with the notebook is intended.
- **Chrome**: zoom % pill bottom-left (tap → Zoom to Fit / 50 / 100 / 200 %),
  dot-grid toggle bottom-right. Floating selection bar above the selected item:
  `Duplicate · Delete · Bring to Front · Send to Back · Colour` (colour for stickies/shapes).
- **Motion (quiet, Freeform-like)**: inserted objects spring in (scale 0.9→1, opacity,
  ~0.3 s, no bounce overshoot beyond ~5 %); selection bar fades + scales from 0.95;
  zoom-to-fit animates; everything under the finger tracks 1:1. Respect Reduce Motion.

## Phases (one DeepSeek delegate each, same branch `feat/freeform-board`)

1. **Canvas + tools** — infinite canvas, notebook toolbar, gestures, zoom pill, grid
   toggle, camera save/restore as a world rect, items drawn under ink. macOS stays a static
   render. BoardKit tests for camera maths.
2. **Objects + selection** — sticky-note kind (6 colours, paper shadow, tap to type,
   auto-shrinking text), text and shape insert from the toolbar's insert menu, image insert
   (board assets folder), selection chrome + floating bar, centre/edge snap guides,
   animations above. Schema version bump with tolerant decoding.
3. **Review** (main session) — build iOS + macOS, run package tests, read the diff.

## Out of scope

Connectors, marquee multi-select of items, scenes, collaboration, tables, files, links,
library redesign. Add later only if missed.
