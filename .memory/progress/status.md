# Status — 2026-11-12

## Done

- Phase 0 scaffold: git repo on `feat/phase-0`, multiplatform Xcode project (iPadOS 27 / macOS 27), four local packages. iOS 27.2 simulator installed; iPad Pro 11-inch (M5) runs the app.
- S1 stroke round trip: all eight PencilKit inks rebuild pixel-identically; drift is bounded to Apple's compressed fields. H1 stands. Evidence: `Spikes/S1-StrokeRoundTrip/RESULTS.md`.
- NoteCore: model, page format (JSON+zlib), atomic library store, schema gate. 34 tests. Fixed a real truncation bug in decompression when JSON exceeded 8x the compressed size.
- InkKit: `InkTool`, `PenStyle`, `StrokeCodec` for all eight inks, `PageRenderer`, iOS `PencilCanvasView` with undo, stroke/pixel eraser and lasso modes. 10 tests.
- App: library browser (all/favourites/folders/trash, tags, create/rename/delete/restore/move), notebook sessions with autosave, page add/duplicate/delete/reorder, drawing with eight pens, colour, width, erasers, lasso, undo/redo, page thumbnail strip, live notebook covers.
- Page templates: one InkKit `TemplateRenderer` drives live pages, thumbnails, covers and PDF. 20 templates: blank, ruled narrow/medium/wide/margin, grid small/medium/large, dotted small/medium/large, Cornell, to-do, meeting, weekly and monthly planners, daily planner, music staff, isometric, hexagon, handwriting practice, storyboard. Picker can apply to one page or every page.
- PDF export: one A4 page per page, verified 3-page PDF through the system document picker, including the selected template.
- Verified on the simulator: draw, erase, undo/redo, page navigation, duplicate, relaunch persistence, export.

## Next

1. Lasso move/copy verification with a real Pencil (mouse gestures cannot trace a lasso).
2. Search (P2.4/P2.5) and PDF import (P2.1), then images/text boxes.
3. Mac app read pass (library + rendered pages already compile).
4. Phase 3 Google Drive only after the user creates the Google Cloud project and approves.

## Open user inputs

- Physical iPad model and iPadOS version.
- Apple developer account: paid or free Apple ID.
- Confirm bundle id `local.noteapp.NoteApp`.
- Before Phase 3: Google Cloud project, OAuth client (iOS, `drive.file`, production status).
