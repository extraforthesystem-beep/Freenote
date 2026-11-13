# Foundation review 07 — Library, Boards, Text Docs, Study

Read-only audit, every finding cited. Estimates are labelled; unproven points are marked
UNVERIFIED. `research_notes/freeform/BOARD-CODE-AUDIT.md` re-checked: holds, except it says
`BoardsView` is a sheet from `LibraryView.swift:447` — it is now the split-view detail (`:465`).

## 1. Findings

### Critical

**C1 — Every metadata edit re-reads the library from disk.** `AppModel.reload()`
(`AppModel.swift:185-197`) calls `scanNotebooks()`, which opens and decodes every
`<id>/notebook.json` (`LibraryStore.swift:653-669`). `reload()` follows favourite (`:621`),
cover (`:612`), rename (`:538`), tags (`:449`), move (`:630`), delete (`:570`), restore
(`:579`), create (`:477`), duplicate (`:557`). At 1,000 notebooks one star tap costs 1,000
file opens plus a full re-sort and grid rebuild (estimate 30–100 ms; UNVERIFIED on device).
*Fix:* mutate the matching element of `notebooks` in place; rescan only at launch or on
explicit refresh.

**C2 — Sorting/filtering runs in the view body, uncached.** `visibleNotebooks`
(`AppModel.swift:234-268`) filters and sorts the whole array per read; read at
`LibraryView.swift:487` and again `:969`. `folderPaths` (`AppModel.swift:345-360`) rebuilds the
tree with an O(F) filter per node, read from `LibraryView.swift:609` and every move menu.
Each sidebar row calls `notebookCount(inFolder:)` (`LibraryView.swift:321`) =
`descendantFolderIDs` (O(F²), `:316-326`) + O(N) scan (`:328-331`). Cost is O(N log N ·
collation) per pass; `.name` sort uses `localizedCaseInsensitiveCompare` (`:277-279`).
*Fix:* one stored `LibrarySnapshot {visible, countsByFolder, paths}` recomputed on change.

**C3 — Board is a fixed 3,000 × 3,000 canvas with no spatial index.** `boardSize`
(`BoardEditorView.swift:21`) sizes a hosting view exactly (`ZoomablePageView.swift:103-108`)
holding a `PKCanvasView` whose `contentSize` is the board
(`InkKit/PencilCanvasView.swift:276-279`). All ink is one item (`BoardEditorView.swift:527-537,
539-562`), re-encoded per save (`BoardModel.swift:90-110`). `Board.items(in:)`/`bounds()`
(`BoardKit/Board.swift:142-169`) walk every point and no app code calls them (grep: tests
only), so there is no viewport culling. A 10k-stroke board is fully materialised, copied into
`inkStrokes` (`BoardEditorView.swift:534-537`) per body pass, and fully re-encoded per edit.
~144 MB per 2× canvas by arithmetic (UNVERIFIED on device) — plausible jetsam with split view.
*Fix:* windowed canvas + per-region ink items + `items(in:)` culling; save only changed items.

**C4 — macOS board body renders the whole board synchronously.** `BoardEditorView.swift:137-165`
calls `PageRenderer.image(... 3_000 × 3_000)` from `GeometryReader` inside `body`, so any state
change (`isSaving` per save tick, `undoRevision`, `board`) re-renders everything on main.
`PERFORMANCE-NOTES.md` fix 13 fixed this exact pattern for `PaperBackground`.
*Fix:* render into `@State` via `.task(id: board.updatedAt)`; keep the last image up.

### High

**H1 — One corrupt text-doc file hides the whole library.** `TextDocumentStore.list()` appends
`try load(...)` unguarded (`TextDocumentStore.swift:92`); `TextDocModel.load()` assigns directly
(`TextDocModel.swift:33-39`). One unreadable `.json` throws, `documents` stays empty, UI shows
"No Text Documents" (`TextDocumentsView.swift:80-82`). StudyKit (`StudySetStore.swift:71-91`)
and NoteCore (`LibraryStore.swift:653-669`) already do partial results. Mirror them.

**H2 — Block drag-reorder is off by one downward.** `moveBlock(_:before:)`
(`TextDocumentEditorView.swift:264-274`) passes a pre-removal index to
`TextDocument.moveBlock(from:to:)`, whose contract is post-removal (`TextDocument.swift:60-70`).
Dragging A onto C in `[A,B,C]` gives `[B,C,A]`. *Fix:* `to: source < target ? target - 1 : target`,
or add `moveBlock(id:before:)` so call sites cannot err.

**H3 — Text docs have no document-level undo.** No `UndoManager` under `NoteApp/TextDocs`
(grep: zero). Blocks are `UITextView`s (`BlockTextEditor.swift:295-312`), so only the focused
field's stack exists; split (`TextDocumentEditorView.swift:287-297`), merge (`:299-306`),
convert (`:281-285`), move (`:256-274`), delete (`:276-279`) are irreversible, and a reorder
destroys the row's stack. *Fix:* document-level `UndoManager` snapshotting `TextDocument`.

**H4 — Board saves can be lost on backgrounding.** `flush()` (`BoardEditorView.swift:632-641`)
is fire-and-forget and, unlike `RootView.swift:38-52`, takes no background-task assertion. Its
failure sets `lastError` (`BoardModel.swift:106-109`), surfaced only by the editor alert
(`BoardEditorView.swift:72-83`), gone after `onDisappear`. The 700 ms debounce (`:566-592`) is
exactly the lost window. *Fix:* assert a background task, await, surface failure later.

**H5 — Study: a failed card is never re-shown; grades can be lost.** `gradeCurrent` removes the
card for every grade (`SmartLearnSession.swift:92`), including "Again", which the scheduler
pushes one day out (`SpacedRepetitionScheduler.swift:44-48`), so "Start Another Pass"
(`StudyReviewView.swift:148-150`) completes instantly. States write 750 ms later with no
background flush (`StudyModel.swift:175-201`; no `scenePhase` under `Study/`).
*Fix:* requeue quality<3; persist on `scenePhase != .active`.

**H6 — Study due counts recomputed per row per render.** `StudyLibraryView.swift:147` →
`StudyModel.swift:124-133` rebuilds the dictionary and `:144-148` scans every card. 200 sets ×
500 cards ≈ 100k ops per body pass, and the number never refreshes while open. *Fix:* cached
`dueCounts`, refreshed on load/record and at midnight.

### Medium

**M1 — Folder depth enforced only in the UI.** `maxFolderDepth = 12` applies in `folderNodes`
(`LibraryView.swift:301-312`), `folderPaths` (`AppModel.swift:347-359`), `canAddSubfolder`
(`:332-334`) — but not `descendantFolderIDs` (`:316-326`). A deeper folder (hand-edited
`folders.json`) is invisible yet still counted and still included by `visibleNotebooks` for an
ancestor (`:261-262`): notebooks listed, unreachable by browsing. *Fix:* one depth-clamped
`descendants(of:)` used everywhere.

**M2 — Boards re-read on every visit.** `BoardsView.swift:67` reloads and re-decodes every board
file although `AppModel.swift:158` already did. Most expensive screen transition in the app.

**M3 — Board thumbnails are uncached and ink-only.** `BoardThumbnail.swift:21-26` flat-maps
strokes per render, `:69` calls `board.bounds()` on main (walks every point), `:75-77` renders
with no cache — so every list appearance re-renders all visible thumbnails, and text/shape/image
items render nothing (`:22-25`) while the row still claims `visibleItems.count` items
(`BoardsView.swift:136`).

**M4 — Cover disk cache grows one file per edit.** Key embeds `updatedAt` seconds
(`LibraryCovers.swift:126-130`), each key writes a new image (`:41-75`), pruning is age-only
after 7 days with no count cap (`:110-124`).

**M5 — Three duplicated save stacks with different semantics.** Board
(`BoardEditorView.swift:566-641`) dismisses on `hasUnsavedChanges || cameraChanged` (`:601`);
text doc (`TextDocumentEditorView.swift:325-374`) on a generation snapshot (`:339-346`). The
board can dismiss with an unsaved edit; the text doc cannot. Notebook is a third copy.

**M6 — Nested `NavigationStack`s inside the split-view detail.** `BoardsView.swift:33`,
`TextDocumentsView.swift:26`, `StudyLibraryView.swift:19` each wrap a stack while already the
detail column, which also sets title/toolbar (`LibraryView.swift:457-475`).

**M7 — Board camera is view-relative.** `currentCamera` stores raw `zoomScale`
(`BoardEditorView.swift:643-660`) and `apply` re-uses it (`:473-486`), ignoring `contentInset`;
`BoardCamera.worldPoint/viewPoint/visibleWorldRect` (`BoardCamera.swift:54-79`) are never
called by app code. On macOS `currentCamera` is always nil (`:657-659`).

### Low

- `visibleNotebooks` returns `[]` for `.textDocuments/.whiteboards/.studySets`
  (`AppModel.swift:263-264`, `:265-267`) yet search/sort/New stay live (`LibraryView.swift:67-72,
  506-533`); a query swaps in notebook results while the sidebar says "Whiteboards".
- Word count splits `plainText` per body pass (`TextDocumentEditorView.swift:230-232`).
- Tapping a sidebar row clears the query (`LibraryView.swift:76-79`).
- `TextDocModel.load()` runs twice at launch (`AppModel.swift:157`, `TextDocumentsView.swift:70`).
- `ReviewState` has no `schemaVersion`, no history; card deletion orphans states
  (`StudyModel.swift:93-102` clears only per-set).
- `defaultInkItemID` is constant and `Board.add` clears tombstones
  (`BoardEditorView.swift:25`, `Board.swift:60`) — harmless while `BoardMerge` is unused (grep).
- Dates differ per type: Unix seconds (`BoardStore.swift:190-200`), reference-date Double
  (`TextDocJSON.swift:15-31`), JSONEncoder default (`StudySetStore.swift:123`).

## 2. Is a shared document foundation needed?

**Yes — for model/persistence, not for editors.** The evidence is behavioural, not stylistic:

- Four `@Observable` models repeat load/save/sort/delete (BoardModel:35-144,
  TextDocModel:30-101, StudyModel:35-102, AppModel) with four copies of one comparator
  (BoardModel:152-160, TextDocModel:117-124, StudyModel:156-161, AppModel:270-281).
- The same bug class recurs *because* logic was copied: partial-failure handling is right in
  StudyKit/NoteCore, wrong in TextDocKit (H1); debounce/flush is right in one editor, lossy in
  another (H4, M5).
- Cross-cutting features stop at notebooks: favourites, tags, folders, recents, trash, search
  all key off `NotebookManifest` (`AppModel.swift:234-268, 439-453`). Boards, text docs and
  study sets have no folders, trash, tags, recents or search; three separate permanent-delete
  paths versus the notebook's 30-day trash.
- Schema discipline diverges: versioned + forward-refusing (Board, TextDocument) versus
  unversioned (StudySet, ReviewState).

Shape (smallest set that removes the duplication):

```
NoteCore/Document/
  DocumentMetadata { id, title, createdAt, updatedAt, schemaVersion, kind }
  DocumentFileStore (actor)   // generic Codable payload, atomic write, version probe,
                              // listReportingIssues
  DocumentIndex (actor)       // metadata only: folders, tags, trash, recents
  DocumentLibrary @Observable // in-place mutation, cached visible list + counts (kills
                              // C1/C2), one undo-capable save coordinator
```

Each type supplies its payload plus a `DocumentKind` descriptor (extension, icon, cover, search
adapter). Editors stay separate — a pencil canvas and a block editor share no interaction code.
Do **not** graft boards onto `Page`/`PageElement`; BoardKit's item model is right, it needs the
viewport work in C3.

## 3. Prioritized foundation changes

1. **In-place mutation + snapshot cache** (C1, C2) — unblocks 1,000 notebooks and is the
   prerequisite for `DocumentLibrary`.
2. **Board viewport** (C3, M7): camera as `visibleWorldRect`, window-sized canvas, per-region
   ink items, cull via `Board.items(in:)`; keep `boardSize` only for migration.
3. **Kill the body-time render** (C4) and the double board load (M2); cached off-main thumbnail
   renderer that includes non-ink items (M3).
4. **Document-level undo for text docs** (H3) with the reorder fix (H2) — cheapest correctness
   win available.
5. **Uniform failure semantics**: `listReportingIssues` everywhere (H1) and one save/flush
   coordinator with background assertions (H4, H5, M5).
6. **Study session correctness** (H5), cached due counts (H6), persisted grades.
7. **Folder depth contract** (M1), then trash/tags/folders for every document kind — what the
   shared foundation actually buys the user.
