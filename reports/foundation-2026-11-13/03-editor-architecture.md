# Foundation audit 03 — notebook editor architecture and SwiftUI state

Read-only review of `NoteApp/Notebook/*` (9,361 lines) and `Packages/InkKit`. Claims were read in source; anything unproven is marked **UNVERIFIED**. `PERFORMANCE-NOTES.md` was treated as prior work, not evidence.

## 1. Findings

### Critical

**C1. Undo is a per-page PencilKit stack; only ink is undoable and page changes discard it.** `PencilCanvasController.undo()` forwards to one canvas's `undoManager` (`Packages/InkKit/Sources/InkKit/PencilCanvasView.swift:12-28`, `:69-70`), and a canvas exists per page because `pageContent` stamps `.id(page.id)` (`NotebookView.swift:1113`). Every non-ink mutation goes through `saveEditedPage`, which replaces the page and writes it with no undo registration (`NotebookSession.swift:850-860`): elements (`:664-706`), layers (`:161-228`), template (`:424-453`), rotate (`:461-466`), clear (`:471-477`), page delete (`:399-421`).
*Impact:* undo after a page turn does nothing; deleting a layer, page or text box is irreversible except by a whole-page history restore. *Fix:* a document-owned command layer (P0).

**C2. Page switching has no request token, so concurrent loads can land out of order.** `loadPage` never re-checks currency after its `await`s (`NotebookSession.swift:232-269`, esp. `:246-268`); `isLoadingPage` is a bool toggled by whichever call finishes. Callers fire independently — thumbnails, page pill, Go To Page, search, zoom auto-advance (`NotebookView.swift:238-240`, `:219-221`, `:286-289`, `:421-424`, `:1199-1218`) and the UIKit activation loop, which serialises only itself (`ContinuousPagesView.swift:504-520`). Two indices both pass `index != pageIndex` (`:286`); the last to return wins.
*Impact:* fast thumbnail taps or a zoom advance racing a tap settle on the older page while counter, highlight and scroll disagree. Ink is not misfiled (`strokesChanged` is guarded by page id, `:820-822`) but the user writes on a page they did not pick. *Fix:* generation counter plus one `selectPage(_:)`.

### High

**H1. Toggling split view destroys the pane, stopping a recording and silently leaving Read Only.** `NotebookView.body` swaps between `HStack { pane; pane }` and one `pane` as different branches of an `if` (`NotebookView.swift:22-30`), so SwiftUI rebuilds `NotebookPane`. Its `onDisappear` stops playback and recording (`:257-264`), and `@State` re-initialises: `editor` (Read Only, zoom view, previous tool), `controller`, `zoomView`, `selectedElementID`, export state (`:176-190`).
*Impact:* opening or closing split ends an active recording, turns Read Only off, drops the undo stack and re-fits the zoom — read as data loss. *Fix:* stable pane identity per notebook id, split implemented inside it.

**H2. The Undo/Redo buttons never refresh.** The toolbar reads `controller.canUndo`/`canRedo` in `.disabled(...)` (`EditorToolbar.swift:107-116`), but `PencilCanvasController` is an `ObservableObject` with no `@Published` and no `objectWillChange` send (`PencilCanvasView.swift:12-28`), `UndoManager` notifications are subscribed nowhere (grep for `NSUndoManager`/`objectWillChange` finds nothing), and the controller is a plain `let` held in `@State` (`NotebookView.swift:178`).
*Impact:* after the first stroke Undo stays disabled until an unrelated observed value redraws the toolbar; undo looks broken though the two-finger double-tap works (`PencilCanvasView.swift:522-528`). *Fix:* publish undo availability and observe it.

**H3. Per-stroke work still scales with page and notebook size, and the "pane body does not depend on page" claim is untested.** `session.page` is read inside the pane's own tree at `NotebookView.swift:975`, and the page content — including `session.visibleStrokes` (`:1087`, an O(strokes) filter over a rebuilt `Set`) — is built there. Each stroke also runs `newOrder != pageOrder` (O(pages)), rebuilds the layout anchor, calls `scheduleRenders()` (`ContinuousPagesView.swift:310-367`, `:605-632`), replaces the hosting controller's `rootView` (`:164-169`), and rebuilds `PaperBackground.baseKey` as a string over every element (`PageBackground.swift:213-219`, in `body` at `:232`). The canvas re-signs every stroke on every update (`PencilCanvasView.swift:444-478`, `:454`).
*Impact:* per-stroke cost grows with page, stroke and element count. The notes' fixes #5/#11 assert decoupling but say "Not timed: needs Instruments". *Fix:* no `session.page` read above a leaf view; cache key and strokes on `(page.id, revision)`.

**H4. Page files cannot survive a newer element type, and `schemaVersion` is written but never read.** `Page` decodes `elements` as `[PageElement]` (`NoteCore/.../Page.swift:71-73`) and `ElementContent` decodes a closed `Kind` enum that throws on an unknown raw value (`PageElement.swift:85-92`). One unrecognised element fails the whole page, which `loadPage` turns into `page = nil` and "Page unavailable" (`NotebookSession.swift:264-267`). `Page.schemaVersion` (`Page.swift:6`, `:24`) is never checked; only BoardKit gates on version.
*Impact:* a future element kind, or a page synced from a newer build, makes the page unreadable instead of showing the rest. *Fix:* decode elements individually, tolerate unknown kinds.

### Medium

**M1. `NotebookSession` is a god object.** 1,041 lines, ~35 mutators, owning navigation, the write queue (`:862-919`), manifest reload (`:1033-1040`), history (`:936-971`), assets (`:575-611`), layers, elements, tape view-state (`:737`) and search highlight (`:739`); each call site re-derives the `pendingPage`/`writeChain` dance (`:62-67`). Retention is fine: `[weak self]` at `AppModel.swift:733-736` and `:865`, weak `controller` at `ContinuousPagesView.swift:206`.

**M2. `NotebookPane` is a presentation god view.** 1,374 lines, ~40 `@State`/`@AppStorage` members (`NotebookView.swift:138-190`) and **23** presentation modifiers on one body — 13 `.sheet`, 4 `.alert`, 4 importers/exporters, 1 `.inspector` (`:280-485`) — two 100-line menu builders (`:594-780`) beside zoom geometry (`:1188-1289`).

**M3. `PaperBackground` has no single-flight render.** Each `.task(id:)` restart (`PageBackground.swift:243-246`) launches an independent `Task.detached` (`:272`, `:303`) that does not inherit cancellation, so element drops queue full-page renders; the notes name the fix ("latest key wins") but it is unbuilt.

**M4. UIKit page work outlives the view.** `activationTask` (`ContinuousPagesView.swift:510-519`), `strokeCommitTask` (`:549-555`) and `renderTask` (`:625-631`) hold `self` strongly inside `while let self` loops, each render awaiting `store.loadPage` and a full page draw (`:634-673`). Scroll-mode toggles and closes re-create the representable (`NotebookView.swift:997`) while the old view drains for seconds.

**M5. Element dragging re-renders the whole element list per frame.** `previewFrames` mutates on every drag tick (`ElementEditLayer.swift:136`, `:164`), and each mutation re-sorts all elements (`:21-25`) and rebuilds every `elementView` (`:30-32`, `:42-121`).

**M6. Tool state is per-pane but persisted globally.** Each pane builds its own `EditorToolState` (`NotebookView.swift:176`) writing the same `UserDefaults` keys on a 600 ms debounce (`EditorToolState.swift:79-86`); split panes race on the tool, favourites and recents, and the last `saveNow()` wins.

### Low

- Thumbnails keyed by index, not page id (`PageThumbnailStrip.swift:15-22`): wrong identity after a page move, no animation, though contents reload via `taskKey` (`:126-130`).
- Swatches use `ForEach(..., id: \.element)` (`EditorToolbar.swift:378`), safe only because `ColorFavorites` de-duplicates (`ColorPalette.swift:149-160`).
- No force unwraps or unsafe subscripts in `NoteApp/Notebook`; indices are clamped (`NotebookSession.swift:243`, `:350`) or guarded (`PageThumbnailStrip.swift:72-76`). The three `fatalError("init(coder:)")` calls (`ContinuousPagesView.swift:286`, `:1340`, `ZoomWindowView.swift:365`) are unreachable.
- `beginBackgroundTask` has no `expirationHandler` (`RootView.swift:38-51`); a failed save retries only on the next edit (`NotebookSession.swift:910-916`).

## 2. Structural problems blocking advanced features

1. **One mutable page snapshot is the whole document model.** Ink, elements, layers and metadata sit in one `Page` re-encoded wholesale (`NotebookSession.swift:850-860`; 0.83 s at 2,000 strokes), so incremental save, per-item undo, merge and collaboration need a format change.
2. **No command layer.** Every mutation is "build a page, write it"; undo, history and sync need that absent abstraction, so history re-encodes whole pages (`:952-971`).
3. **The view/session boundary is convention.** Any view may read `session.page` and join the per-stroke update set; fixes #5/#11 patch that leak and are unmeasured.
4. **The element type is a closed enum** with hand-written Codable and six switch sites (`PageElement.swift:69-154`, `PaperSize.swift:98-107`, `PageElementRenderer`, `PageElementViews.swift:228-248`, `VectorPDFExport`, `NotebookSession`) and no unknown-kind fallback.
5. **Page lifecycle is three ad-hoc machines in the UIKit container** — activation (`:504-520`), capture/replay (`:526-595`), reveal (`:377-419`) — while tool state lives in SwiftUI; nothing singly owns "which page is current".

## 3. Refactor plan, in priority order

**P0 — single owner for page switching (C2).** Add the generation counter and one `selectPage(_:)`; route `NotebookView.swift:220/239/288/423`, `ContinuousPagesView.swift:516` and zoom auto-advance through it.

**P0 — split `NotebookSession.swift`** into a facade plus `PagePersistence` (queue, retry) · `PageHistory` · `PageEdits` (ink, elements, layers, page ops) · `PageNavigation` (load token, visited page, PDF mapping).

**P0 — add `DocumentUndo` (C1).** One `Command` (`apply`, `revert`, page id) per mutation; `saveEditedPage` becomes `perform(_ command:)`, registering with the document stack and queueing the save. PencilKit's manager stays for live strokes, mirrored in on stroke end. Ships with H2.

**P1 — break `NotebookView.swift`** into `NotebookView` (tabs) · `NotebookPane` (layout) · `NotebookPaneMenus` · `NoteExportModel` and `NotebookSheetState` (both `@Observable`). Extract `PageArea` so no ancestor body reads `session.page` — H3's structural half.

**P1 — stabilise pane identity across split view (H1).** One container keyed on `notebookID` hosting one or two panes; move stop-recording/flush to `NotebookSession.close()`, called from `AppModel.closeTab` and the back button.

**P2 — break `ContinuousPagesView.swift`** into `PagesView` (slots, updates, reveal) · `VerticalPagesView` · `HorizontalPagesView` · `PageSlotView` · `InkCapture` (recognizer, replay — also fixes M4) · `PagesRenderPipeline` (cache, queue, single-flight).

**P2 — tolerant, registry-based elements (H4).** A `PageElementKind` table (`renderer`, `icon`, `label`, `itemKind`, `defaultFrame`, `insertCommand`) for every switch site; decode elements individually, keep unknown payloads opaque, gate on `schemaVersion`.

**P3 — per-frame polish.** `PageBackground` single-flight renderer (M3); one `@Observable` element drag session (M5); cache `visibleStrokes`/`baseKey` on `(page.id, revision)`; inject `EditorToolState` so split panes share one instance (M6).
