# 02 — Ink engine audit

Scope: `Packages/InkKit/Sources/InkKit` (canvas, codec, converter, order/merge, shape, renderers) and the three hosts (`ContinuousPagesView`, `NotebookView`, `ZoomWindowView`). Read at HEAD `975715f` (branch `fix/folders-pdf-import`). ADR intent: `.memory/decisions/2026-11-13-sharp-ink-zoom.md`, `2026-11-12-page-scroll-live-canvas.md`.

Verdict: the model (records as truth, incremental converter, one live canvas, capture-and-replay) is sound. The foundation cap is **cost per finished stroke** — O(strokes on page) on the main actor — and the **zoom sharpness fix is not in this branch**.

## 1. Findings

### Critical

**C1. "Sharp ink at zoom" is not in the working tree.** `PencilCanvasView.swift:72-89` still locks the canvas to fit with the comment "*The paper is a SwiftUI image behind the canvas, so it cannot zoom with the ink yet*". Pages are zoomed by an outer `UIScrollView` (`ContinuousPagesView.swift:686-765`), so PencilKit's 1× backing store is upscaled by a layer transform (the ADR's own diagnosis). `InkCanvasHost` / `InkRenderViewport` exist only in commit `6bf87d9`/`59e29f9` on the unmerged `feat/advanced-search` branch (worktree `.claude/worktrees/sharp-ink-zoom`). **Impact:** ink looks soft the moment the user zooms in to write small — the single most visible "not GoodNotes yet" defect. **Fix:** merge that host; it is already written, tested and ADR-approved.

**C2. Every stroke lift is a full-page round trip on the main actor.** Chain per stroke: read every stroke out of PencilKit (`PencilCanvasView.swift:579`) → `StrokeSignature` for all (`IncrementalStrokeConverter.swift:98`) → build records for all (`:118-133`) → `merge` over all (`StrokeOrder.swift:74-117`) → `page = updated` + `revision &+=` (`NotebookSession.swift:831-836`) → SwiftUI rebuild → `apply` compares all again (`PencilCanvasView.swift:451-455`). PERFORMANCE-NOTES rows 2-5 measure 2.1 + 2.8 + 0.98 + 4.6 ≈ **10.5 ms at 2,000 strokes on an M1 Max**; the notes' own budget is 8 ms and a base iPad is 2-3× slower. **Impact:** every stroke end can hitch 1-2 frames on a dense page, and the cost scales with page length, so "long pages get laggy" is structural, not a tuning miss. **Fix:** report a delta, not a snapshot — see P0-2.

**C3. The Zoom View's second canvas writes into its own undo stack on every sync.** `apply` assigns `canvas.drawing` (`PencilCanvasView.swift:467-470`) without `disableUndoRegistration`, while the same codebase proves PencilKit registers undo on that assignment: `keepNonHighlighterStrokes` wraps it explicitly (`:632-636`). The delegate echo is suppressed (`isApplyingInput`), so the entry is invisible to the model but real in the stack. With two stacks and `lastUsedCanvas` routing (`:20-28`, `ZoomWindowView.swift:22-23`), an undo aimed at the panel can replay a stale drawing into the page canvas, which then *reports* strokes as removed (`IncrementalStrokeConverter` → `merge` → `deletedStrokeIDs`, `NotebookSession.swift:832`). **Impact:** extra undo steps per stroke with Zoom View open; possible silent deletion of ink drawn elsewhere. The duplicate-entry half is **derived** from the code; the deletion consequence is **UNVERIFIED** (needs a device test: draw on page, draw in panel, undo twice). **Fix:** wrap every programmatic `drawing` write in `disableUndoRegistration`, and register one explicit inverse for the *document*, not the view.

### High

**H1. Palm rejection is off when Draw with Finger is on.** `:352-359` uses `.anyInput`, so a resting palm draws and pans need two fingers (`NotebookView.swift:1028-1039`). Apple's only palm-rejecting policy is `.pencilOnly`. **Fix:** keep `.pencilOnly`; synthesize finger strokes from `.direct` touches, exactly as `InkCaptureRecognizer` already does (`ContinuousPagesView.swift:1472-1538`).

**H2. First stroke on a not-yet-live page can be lost and is not ink-faithful.** Capture is dropped after 5 s (`ContinuousPagesView.swift:263`, `:560-581`); replay goes through `CapturedStrokeBuilder`, which duplicates end points and has no nib/squeeze data (`CapturedStroke.swift:66-75`), then `appendStroke` rewrites the whole drawing (`PencilCanvasView.swift:41-47`). **Impact:** on a slow PDF page activation (77 ms prewarm miss per the perf notes) a fast pen loses ink; a caught stroke can look slightly different from a normal one. **Fix:** keep the layer visible with an overlay preview until commit (or hold activation as a write barrier), and report the loss to the user instead of dropping silently.

**H3. Eraser masks can be silently discarded.** `isSupportedMask` requires at least one line or cubic element (`StrokeCodec.swift:207-218`); a quadratic-only ring is dropped, and the stroke reloads **unerased**. S1 measured PencilKit's own bitmap-eraser masks as cubic rings (39/35 elements, `Spikes/S1-StrokeRoundTrip/RESULTS.md:93-96, 176-178`), so real-world frequency is **UNVERIFIED** — but the failure mode is silent data change on reload. **Fix:** keep an unsupported mask verbatim (store the raw element list) or refuse the erase rather than dropping the cut; add a round-trip test with a quad-only mask.

**H4. Whole-page rewrite per stroke, off main but unbounded.** `savePage` re-encodes and zlibs the entire page (`LibraryStore.swift:365-373`, `PageCodec.swift:5-19`): 0.83 s per 2,000-stroke page. Debounce is 400 ms over a serialized chain (`NotebookSession.swift:862-918`), so sustained writing builds a save queue; `commitPendingSave` gates page turns and app backgrounding. **Fix:** incremental stroke log (append-only segments) or a binary payload; a page-size cap is the cheap version.

### Medium

- **M1. Unguarded UIKit writes every SwiftUI pass.** `updateUIView` reassigns `tool` (a fresh `PKInkingTool`), ruler, style, `drawingPolicy`, `contentSize`, gesture enable (`PencilCanvasView.swift:369-384`). Tool identity change on every stroke is PencilKit re-configuration on the hot path. Guard with `!=`.
- **M2. Hold-to-shape churn during the stroke.** A main-actor `Task` timer restarts every ~4 pt of movement (`HoldToShape.swift:111-121, 145-154`): hundreds of task allocations per stroke. `captureHeldStroke` re-reads all strokes (`:208`) and `swapStroke` reassigns the drawing (`:246-251`).
- **M3. Two extra full passes to assemble the input array.** `session.visibleStrokes` is a computed filter read in the body (`NotebookSession.swift:145-149`, `NotebookView.swift:1087`) and `zoomStrokesChanged` builds a `Set` of all ids per stroke (`:1294`).
- **M4. Thumbnail strip re-renders the whole page at every writing pause.** 1.5 s debounce at scale 0.3, but each render decodes every record and calls `drawing.image` (`PageThumbnailStrip.swift:126-200`) — a second full-page PencilKit render competing with the canvas.
- **M5. The page exists in memory 3-4×.** `baselineStrokes` holds bridged copies (`PencilCanvasView.swift:416`), plus converter entries and `syncedRecords`, plus the Zoom View canvas, plus 320 MB of image caches (`ContinuousPagesView.swift:1556`, `PageBackground.swift:339`). Growth is per *open* page, not per notebook — bounded, but Zoom View roughly doubles it.
- **M6. Rendered-page sharpness is capped by design.** Inactive page images quantize to ≤3× (`ContinuousPagesView.swift:304-306`), paper ≤4× (`PageBackground.swift:336-337`); ADR-accepted, but it is the reason side-by-side pages look unequal when zoomed.
- **M7. Selection and undo don't cross views.** A programmatic `drawing` assignment clears the lasso selection; there is no selection model in the app (`ZoomWindowView.swift:12-23`), and a new canvas per page (`.id(page.id)`, `NotebookView.swift:1113`) ends undo history at the page boundary.
- **M8. Tombstones grow unboundedly per page.** `deletedStrokeIDs` unions every erase (`NotebookSession.swift:832-833`) and is never compacted; `Page` id lists are stored sorted on every write (`Page.swift:130`).

### Low

- **L1. Precision drift is real but bounded.** Round trip moves azimuth ≤9.6e-5 rad and mask vertices ≤0.01 pt, and `f(f(x)) ≠ f(x)` (S1 RESULTS:65-69) — each lasso move re-reads all points and adds one more step of drift (`StrokeCodec.swift:33-96`). Cosmetic.
- **L2. The riskiest code has no tests.** InkKit tests cover codec/order/shapes/outline/zoom band; nothing exercises `Coordinator.apply`, undo, or merge-on-undo (`Packages/InkKit/Tests/InkKitTests`).
- **L3. Highlighter-under-ink only settles once the app stores the stroke** (`PencilCanvasView.swift:456-465`); correct by design, but depends on `merge` running, so a dropped report leaves stacking wrong until reload.

## 2. Architectural limits

1. **PencilKit owns the frame.** No predicted-touch control, no coalesced-touch routing, no re-render-during-stroke, no brush textures or pressure curves; the ADR's "no custom engine" decision is right for now but caps nib realism and any real-time ink effect (`research_notes/iPad note app feature plan/technical_architecture.md:23`).
2. **Snapshot-per-change contract.** The canvas emits *all* strokes per change. Nothing in the design can be sub-linear until the app model accepts deltas.
3. **Whole-page file format.** JSON + zlib, one file, rewritten per save — no incremental persistence, no merge-friendly log, no per-layer blob.
4. **One live canvas per notebook.** Correct for memory, but it forces capture-replay (lossy, time-boxed) and blocks cross-page lasso, multi-page selection, and page-thumbnail-accurate live ink.
5. **Undo is the view's, not the document's.** Per-canvas `UndoManager` (`PencilCanvasView.swift:60-70`) means undo scope = view lifetime, and Zoom View creates a second, divergent stack.

## 3. Prioritized foundation changes

1. **P0 — Merge the ink host (`InkCanvasHost`/`InkRenderViewport`).** Fixes the visible blur; already built and ADR'd. Nothing else in the roadmap matters as much per unit of work.
2. **P0 — Make the per-stroke path a delta.** Report added/changed/removed ids from the converter; apply only those; let `merge` update in place. Target <3 ms per stroke at 2,000 strokes on device.
3. **P0 — One document undo scope.** `disableUndoRegistration` on every programmatic write; a single `UndoManager` shared by page and Zoom View canvases, with explicit inverse operations registered for shape swaps, caught strokes and erases.
4. **P1 — Palm rejection with finger drawing** (`.pencilOnly` + synthesized direct-touch strokes).
5. **P1 — Never lose a caught stroke:** overlay preview until commit, no 5 s silent drop, user-visible failure, and a preview path that uses the same nib data.
6. **P1 — Incremental page persistence** (append-only stroke segments or binary payload) so a save is not O(page).
7. **P2 — Guarded `updateUIView`, cheap hold observer (CADisplayLink-free timer or one timer per touch), incremental thumbnail regeneration.**
8. **P2 — Test the canvas behaviours that carry risk:** undo across two canvases, highlighter-only erase + undo, quad-only mask round trip, layer hide/show during a stroke, tombstone merge.
