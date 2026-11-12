# Status — 2026-11-12

## Done and verified

- Phase 0 scaffold and S1 stroke experiment. H1 (own stroke record is truth) confirmed visually lossless. Simulator installed.
- NoteCore: model, page format, atomic library store, cover field, asset folder. 34 tests.
- InkKit: eight pens, stroke codec, page renderer with templates, PDF pages, images, text boxes and shapes, PencilKit canvas with undo, stroke/pixel eraser and lasso. 20 tests.
- SearchKit: PencilKit recogniser wrapper, ink+typed-text fingerprint, persisted cache index, case/diacritic-insensitive search. 12 tests.
- App: library, folders, tags, favourites, trash, covers; notebook pages, templates, thumbnails, autosave; eight pens with per-pen presets; erasers; lasso; undo/redo; page duplicate/reorder/delete; PDF import; text boxes, images and shapes; element list/edit; handwriting + typed-text search with page jumping; PDF export including templates and elements.

## Verified on the iPad simulator

Draw, erase, undo, page navigation, templates, covers, PDF import with annotation, image and text elements, search hit opening the right page, PDF export (upright, with elements).

## Still open

- Physical iPad: palm rejection, Pencil gestures, lasso move/copy, signing (P0.3/P1.4/P1.7).
- Phase 1 P1.8 live-canvas window ±1; P1.10 tabs, bookmarks, split view.
- Phase 2 P2.2 PDF link taps under the ink canvas.
- Phase 3 Google Drive: needs the user's Google Cloud project, OAuth client and approval.
- Phase 4 Mac annotation with PaperKit; Mac read-only build is shared but not run.
- Phase 5 audio/transcript/math/AI; Phase 6 custom Metal ink engine.
