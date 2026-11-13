# Foundation plan — 2026-11-13

Synthesis of reports 01–14 in this folder. Items marked ✔ were re-checked by hand against the code on `fix/folders-pdf-import`.

## Phase 0 — Land the work in flight (before any refactor)

- ✔ `fix/folders-pdf-import` is 57 commits ahead of `main` plus a large uncommitted diff. `main` has none of it.
- ✔ 7 branches hold commits not on this branch: `feat/advanced-search`, `feat/freeform-board`, `feat/pages-side-panel`, `feat/toolbar-customize`, `fix/first-stroke-new-page`, `fix/sharp-ink-zoom`, `zoom-view-writing-band`. Several were touched in the last hour by other sessions.
- ✔ The sharp-ink-zoom ADR is accepted, but the canvas zoom is still locked on this branch (`PencilCanvasView.swift:84-88`).
- Action: commit this branch, merge to `main`, rebase or merge the 7 branches, and freeze new feature branches until Phase 1 lands. Refactoring `NotebookSession` against 7 live branches will produce conflicts.

## Phase 1 — Stop losing data (P0)

| # | Problem | Evidence | Fix |
|---|---|---|---|
| 1 | One damaged `folders.json` empties the grid; a damaged `library.json` blocks launch | ✔ `AppModel.swift:185-196`, ✔ `LibraryStore.swift:71-73`, `TextDocumentStore.swift:92` | Load each file independently; quarantine damaged files and regenerate defaults |
| 2 | A failed save is dropped on page change; one retry slot | ✔ `NotebookSession.swift:232-269`, `:909-913` | Pending saves keyed by page ID; `loadPage` request token; delete awaits flush |
| 3 | Page-load race leaves an older page on screen | ✔ no token in `loadPage` | Generation counter, checked after every `await` |
| 4 | Recording lives in `tmp` until Stop; crash loses the lecture | ✔ `NotebookAudio.swift:75` | Record into the notebook bundle, recover on launch, handle interruptions, fix the `onFinish` thread race |
| 5 | No schema migration; one new field breaks every old file; closed `ElementContent` enum | 01, 03 | Versioned codecs, tolerant decoding, unknown-element passthrough |
| 6 | Deleted notebooks keep their history; page delete can resurrect; orphan pages wedge reorder | 01 | Purge history; reconcile manifest against files on open |
| 7 | No fsync in `writeAtomically`; `notebook.json` rewritten per stroke | 01 | fsync on write; touch the manifest only when it changes |
| 8 | Board flush, study grades and text docs have no background flush; text docs have no undo; block reorder is off by one | 07 | One flush-on-background path for every document type |

## Phase 2 — Document core (unblocks everything advanced)

9. **Edit operations instead of whole-page snapshots.** Strokes added/removed by ID, element and layer ops. This one layer gives notebook-wide undo (today: per-canvas PencilKit undo, lost on page turn), incremental save, the delta report the ink path needs, and the per-page merge rule sync needs.
10. **Shared document store** in NoteCore for notebooks, boards and text docs: atomic + fsync, quarantine, versioning, one index. Editors stay separate.
11. **Library as an in-memory snapshot** mutated in place; no `reload()` disk rescan per rename. Add a rebuildable `index.sqlite` sidecar.
12. **Split** `NotebookSession` (1,041 lines) and `NotebookPane` (1,374 lines). Split view must stop tearing down the pane (recording, Read Only, undo).

## Phase 3 — Speed and scale

13. **Ink:** report deltas per stroke lift rather than a full-page convert/merge/re-apply (≈10.5 ms at 2,000 strokes on M1 Max; budget 8 ms). Merge `fix/sharp-ink-zoom`.
14. **PDF:** one `PDFPageGeometry` (✔ rotation ignored at `PDFImporter.swift:254`; crop box unused), a bounded shared `PDFDocument` cache, an `actor RenderGate` limiting the 15 `Task.detached` render sites, pixel caps, tiled rendering for deep zoom, import precheck, batched `savePages`.
15. **Boards:** drop the fixed 3,000² canvas; viewport culling via the unused `Board.items(in:)`; 512-pt tiles.
16. **Search:** SQLite FTS5 replaces the whole-file blob; update on page save (today not updated while a notebook is open); real ranking (✔ `matchedTermCount` is a constant, `SearchIndex.swift:446`).

## Phase 4 — Safety net (runs alongside Phase 1)

17. Hosted `NoteAppTests` target; move save/export/import/search glue into packages so `swift test` covers it; package-matrix CI; warnings-as-errors. Today: 502/502 package tests pass, app layer has zero tests, no CI.

## Phase 5 — Advanced features this foundation unlocks

- Sync: SyncKit is an empty stub. Per-page observed-remove set (stroke IDs + tombstones + LWW attributes) over `CKSyncEngine`, chunked under 1 MB. Sync data loss is the #1 complaint across GoodNotes, Notability and Noteshelf users.
- Word/line layer over ink plus content anchors and links (Nebo, MarginNote, LiquidText territory).
- Tap ink to seek audio (data already stored), transcripts in the same index.
- Lasso action menu, handwriting→text, spellcheck, presenter mode, custom template import.
- Handwritten math (no Apple API; our own build).
- Skip: Word Complete (GoodNotes discontinued it March 2025).

## Research claims still unverified

- `PKStrokeRecognizer` is real (we already use it in `SearchKit/HandwritingRecognizer.swift`).
- PaperKit `subelements` / board-camera APIs, Foundation Models 2026 tools, iOS 27 stable stroke IDs and `renderGroupID`: check against Apple docs before Phase 2/3 designs depend on them.
