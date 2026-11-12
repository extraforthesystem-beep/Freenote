# Status — 2026-11-12

## Done

- Phase 0 scaffold: git repo on `feat/phase-0`, multiplatform Xcode project (iPadOS 27 / macOS 27), four local packages.
- iOS 27.2 simulator installed; iPad Pro 11-inch (M5) simulator boots and runs the app.
- S1 stroke round trip: all eight PencilKit inks rebuild pixel-identically; drift bounded to Apple's compressed fields. H1 (own record is truth) stands. Evidence: `Spikes/S1-StrokeRoundTrip/RESULTS.md`.
- NoteCore: document model, page format (JSON+zlib), library store, atomic writes, schema gate. 33 tests pass.
- NoteApp library UI: sidebar (all/favourites/folders/trash), notebook grid, create/rename/delete/restore, folders, favourites, tags. Notebook view with page navigation, add/delete page, paper styles, autosave session.
- InkKit (in progress): `InkTool`, `PenStyle`, `StrokeCodec`, `PageRenderer`, iOS `PencilCanvasView` with undo. Delegate is finishing tests and the iOS compile check.

## Next

1. Finish InkKit, verify tests, then wire eraser/lasso modes into the canvas toolbar.
2. Draw on the simulator, verify strokes survive relaunch; check page add/delete/reorder.
3. Page thumbnails and live-canvas window (P1.8).
4. P1.5 undo/redo polish and P1.4 lasso/stroke eraser checks.
5. Export PDF/PNG (P2.6), then Phase 3 Google Drive only after the user's approval and Google Cloud setup.

## Open user inputs

- Physical iPad model and iPadOS version.
- Apple developer account: paid or free Apple ID.
- Confirm bundle id `local.noteapp.NoteApp`.
- Before Phase 3: Google Cloud project, OAuth client (iOS, `drive.file`, production status).
