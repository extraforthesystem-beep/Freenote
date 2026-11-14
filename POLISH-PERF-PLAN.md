# Polish and performance pass — plan

Written 2026-11-14. Base branch `integrate/polish-perf` = `main` (`0c33edb`) + `feat/search-find-bar` (`03382c8`).
Planner and reviewer: main session. Builders: DeepSeek V4.1 Flash through OpenCode Go.

## Why

The app was built in bursts by parallel agents (parity, wave 4, boards, toolbar, pages panel, find bar). Each burst chose its own spacing, corner radii, type sizes and animation curves, and one of them undid an earlier ink performance fix. This pass makes the UI one system and makes the stroke path cheap again.

## Findings checked in code today

| # | Finding | Evidence |
|---|---|---|
| F1 | Ink mode reads every stroke out of PencilKit twice per finished stroke (three times with an eraser filter). Performance fix 2 cut this to one read; wave 4's stroke decoration added the second. Each read costs 2.1 ms at 2,000 strokes on an M1 Max (PERFORMANCE-NOTES fix 2). | `PencilCanvasView.swift:1029` (`decorateNewStrokes`), `:1070` (`reportDrawingChange`), `:1100` (`keepStrokesOutsideFilter`) |
| F2 | Every finished stroke recomputes a signature for every stroke on the page and rebuilds three whole-page collections (`liveIDs`, `layerIDs`, `syncedRecords`). Work grows with the page, not with the change. | `IncrementalStrokeConverter.swift:98`, `PencilCanvasView.swift:1084-1089` |
| F3 | Every finished stroke builds two whole-page sets in the session before the merge. | `NotebookSession.swift:1041-1042` |
| F4 | The library rescans every notebook on disk from 23 call sites, most of them single-notebook edits (rename, move, pin, trash). | `AppModel.swift:200`, 23 `await reload()` call sites |
| F5 | No design tokens beyond four colours. In `NoteApp/`: 20 distinct padding values, 12 corner radii, 13 fixed font sizes, 7 animation curves. | `rg` counts over `NoteApp/**/*.swift`, 2026-11-14 |
| F6 | Reduce Motion is honoured in one file. | `BoardEditorView.swift:71` is the only `accessibilityReduceMotion` in `NoteApp/` |
| F7 | `NotebookPane` is one 1,700-line view. | `NotebookView.swift:135-1847` |
| F8 | Speed items 14–16 of the foundation plan (render gate, PDF geometry, board culling, FTS5 search) are not started. | 0 hits for `RenderGate`, `PDFPageGeometry`, `FTS5` |

Not yet known: whether the pane body re-runs per stroke through `pageArea` (`NotebookView.swift:1346` reads `session.page` inside a `GeometryReader`). Inferred safe, because the closure runs in the reader's own update. E1 adds a test that settles it.

## Waves

File ownership is exclusive inside a wave. A delegate that needs a file it does not own stops and reports.

### Wave 0 — running now

| ID | Work | Owns | Output |
|---|---|---|---|
| T0 | Design tokens: spacing, radius, motion (Reduce Motion aware), a 44 pt hit-target helper, plus a literal-count lint script. No adoption yet. | new `NoteApp/Design/`, `scripts/ui-token-lint.sh` | branch `polish/design-tokens` |
| E1 | Ink stroke path: one PencilKit read per change, append fast path with full-path fallback, signposts, benchmarks before and after. | `Packages/InkKit/Sources/InkKit/PencilCanvasView.swift`, `IncrementalStrokeConverter.swift`, InkKit tests, `strokesChanged` in `NotebookSession.swift`, new `NoteAppTests` file | branch `perf/ink-stroke-path` |
| A1 | Audit: editor chrome (pane, toolbar, tool state, palettes, selection, Zoom View, layers, outline) | read-only | `reports/polish-2026-11-14/A1-editor.md` |
| A2 | Audit: pages and reading (scroll, zoom, paper, side panel, elements, templates, PDF links, search and find bar) | read-only | `A2-pages.md` |
| A3 | Audit: library and app shell (root, library, settings, backup, import, export) | read-only | `A3-library.md` |
| A4 | Audit: boards and text documents | read-only | `A4-boards-textdocs.md` |
| A5 | Audit: study, audio, AI panel | read-only | `A5-study-audio-ai.md` |

Each audit lists findings as `file:line — what — why it hurts — proposed fix — size`, under these heads: main-thread work and view invalidation; layout and spacing off the token scale; fixed font sizes; motion; touch targets and keyboard; loading, empty and error states; accessibility; dark mode; copy.

**Gate 0 (main session):** read every audit, drop findings that do not survive a re-read of the cited lines, merge T0 and E1 after review, and write the approved finding list per area into this file.

### Wave 1 — five area builders, parallel worktrees

| ID | Area | Owns |
|---|---|---|
| U1 | Editor chrome | `NotebookView.swift`, `EditorToolbar.swift`, `Toolbar*.swift`, `EditorToolState.swift`, `ColorPalettePopover.swift`, `FavoritePens.swift`, `Selection*.swift`, `ZoomWindowView.swift`, layers and outline panels |
| U2 | Pages and reading | `ContinuousPagesView.swift`, `ZoomablePageView.swift`, `PageBackground.swift`, `PagesSidePanel.swift`, `PageElementViews.swift`, `ElementEditLayer.swift`, `PageTemplate*.swift`, `PDFLinkHandler.swift`, `NoteApp/Search/`; also a render gate that bounds concurrent page renders (F8) |
| U3 | Library and shell | `RootView.swift`, `NoteApp/Library/`, `Settings/`, `Backup/`, `Import/`, `Export/` (not `AppModel.swift`) |
| U4 | Boards and text documents | `NoteApp/Boards/`, `NoteApp/TextDocs/`, `Packages/BoardKit`, `Packages/TextDocKit`; board viewport culling if A4 confirms it is missing |
| U5 | Study, audio, AI | `NoteApp/Study/`, `NoteApp/Audio/`, `NoteApp/AI/` |

Rules for every builder:

1. Fix only approved findings for the area.
2. Off-scale literals move to the nearest token where the audit table marks the change `none` or `low` risk. Literals already on the scale are left alone unless the line is being edited anyway.
3. All animation goes through `AppMotion`; nothing animates on per-stroke state.
4. Touch targets at least 44 pt; icon-only buttons carry an accessibility label.
5. No new dependencies, no `print`, no unrelated rewrites, ADRs in `.memory/decisions/` stay in force.

### Wave 2 — engine, after Wave 1 merges

| ID | Work | Condition |
|---|---|---|
| E2 | Library mutations update the in-memory list in place instead of a disk rescan (F4). | Do it if a 200-notebook `reload()` takes over 100 ms in a release build, the limit for a response to feel instant. Measure first. |
| E3 | Lift pane subtrees that re-run per stroke into child views (F7). | Only subtrees that E1's invalidation test or Instruments shows re-running. Not a full split. |
| E4 | PDF pixel caps and tiled deep zoom. | If A2 or the device pass shows memory or hitch problems on the scanned PDF. |

### Wave 3 — integration and sign-off

Merge to `integrate/polish-perf`, run the full matrix below, install on the iPad, then the hands-on pass.

## Verification

Every branch, before it is merged:

| Check | Pass condition |
|---|---|
| Package tests, all nine packages | 0 failures; test count per package not below the baseline in `.memory/progress/status.md` |
| App tests (`NoteAppTests`, macOS destination) | 0 failures; count not below 34 |
| Builds: iOS Simulator and macOS | succeed; no new warnings |
| `scripts/ui-token-lint.sh` | off-scale literal count does not rise; after Wave 1 it is below the Wave 0 baseline in every area |
| Diff review by the main session | only owned files touched; no ADR reversed |

E1 adds:

| Check | Pass condition |
|---|---|
| Equivalence property test | For random sequences of append, erase, undo-style removal, reorder and in-place change, the fast path returns exactly what the full path returns |
| Scaling property | Stroke-end cost at 2,000 strokes is at most twice the cost at 200 strokes, same run, same machine |
| Before and after | Median of 5 release runs of `RenderBenchmarks`, baseline measured on the base commit by the same delegate |
| Invalidation test | `strokesChanged` does not fire observation on the chrome properties (`currentPageID`, `activeLayer`, `manifest`) |

Hands-on, by the user, on the physical iPad (cannot be delegated):

1. The pending walkthrough: scratch-out undo, dashes, highlighter lines, selection bar, Reading Mode, tap-to-seek, board finger drag, find bar.
2. Instruments items 1–7 in `PERFORMANCE-NOTES.md`. The signposts E1 adds mark stroke end, page activation and save in the trace.
3. Light and dark pass over each area after Wave 1.

## Gate 0 — audit review (2026-11-14)

Five audits, 170 findings (15 top severity). All 15 top-severity rows were re-read against the cited lines: 14 hold as written; A2-02 holds for first appearance only (previews are cached), so it is treated as medium. Builders re-check every other row against the code before fixing it and report any that do not hold.

Confirmed top-severity items:

| ID | Problem |
|---|---|
| A3-05 | A second tap while a notebook is loading opens it twice; two sessions then save the same pages. Data safety: fixed first. |
| A1-01 | Page pill menu builds one button per page (1,058 on the big PDF). |
| A2-01 | Paper pre-renders have no limit and can draw the same page twice. |
| A3-01 | First library frame waits for templates, sweeps, study, text documents and boards. |
| A3-02 | Every library edit rescans the disk (Wave 2, E2). |
| A3-03 | Backup sheet stats every file of every backup on the main thread. |
| A3-04 | Search results are not lazy. |
| A4-01, A4-02 | Board drag copies the whole board and rebuilds snap targets every frame. |
| A4-03 | Mac board preview rasterises ink inside the view body. |
| A4-04 | Board photos are decoded from disk inside the view body. |
| A4-05 | Text document re-lays-out every block per keystroke. |
| A5-01 | Audio replay re-applies the whole page four times a second. |
| A5-02 | Study sheet rescans the card library per keystroke. |

Wave 1 is split into nine builders so no one owns more than about 3,000 lines:

| ID | Branch | Owns |
|---|---|---|
| U1a | `polish/u1a-editor-pane` | `NotebookView.swift`, `EditorOverlays.swift`, `LaserPointerOverlay.swift`, `VersionHistoryView.swift`, `DeleteSpecificItemsView.swift` |
| U1b | `polish/u1b-editor-tools` | toolbar, tool state, palettes, pens, selection, Zoom View, layers, outline |
| U2a | `polish/u2a-pages` | scroll, zoom, paper, templates, PDF links, elements, `MemoryPressure.swift` |
| U2b | `polish/u2b-panel-search` | `PagesSidePanel.swift`, `GoToPageField.swift`, `NoteApp/Search/`, `AppColor.swift` |
| U3a | `polish/u3a-app-shell` | `AppModel.swift`, app entry, `LibraryCovers.swift`, `PageBookmarks.swift`, backup, import, export, settings |
| U3b | `polish/u3b-library` | the other files in `NoteApp/Library/` |
| U4a | `polish/u4a-boards` | `NoteApp/Boards/`, `Packages/BoardKit` |
| U4b | `polish/u4b-textdocs` | `NoteApp/TextDocs/`, `Packages/TextDocKit` |
| U5 | `polish/u5-study-audio-ai` | `NoteApp/Study/`, `NoteApp/Audio/`, `NoteApp/AI/` |

First batch: U1a, U2a, U3a, U4a, U5. Second batch (U1b, U2b, U3b, U4b) starts as those return.

Held back from Wave 1:

| IDs | Why |
|---|---|
| A3-02 | E2, Wave 2. |
| A1-02 | Moving the page area into a child view is a large edit; waits for E1's invalidation test to show it is needed (E3). |
| A1-07, A1-29, A3-18 | Each needs a file another builder owns (`PencilCanvasView.swift`, `NotebookSession.swift`, library cards). Wave 2. |
| A2-11 | Dark-paper compositing: needs a device memory trace first (E4). |
| A1-15, A1-35, A3-24, A1-11 | Change toolbar or grid layout in ways that need eyes on a screen. Decided after simulator screenshots. |
| A3-28, A5-30, A4-16, A3-33 | New behaviour (Mac restore, AI answer history, board undo, clearing the index), not polish. |
| A4-10, A5-26, A1-18, A1-31 | Low value for the size. |

Decisions taken here:

- Spelling is British everywhere ("Customise Toolbar"), matching "Favourite Pens" and "Colour".
- Fixed text sizes stay at their current default size but scale with the system text size (`@ScaledMetric` / `UIFontMetrics`), so neither platform changes at default settings.
- Board and text-document deletes get a confirmation dialog, not a trash bucket.
- App tests launch the real Mac app, so builders take a lock (`/tmp/noteapp-xctest.lock`) and run them one at a time.

## Progress

- **T0 merged** (`polish/design-tokens`, reviewed 2026-11-14): `NoteApp/Design/` tokens and `scripts/ui-token-lint.sh`. App tests on the merged base: 50 passed, 0 failed (macOS).
- **Lint baseline** (off-scale literals; Wave 1 must lower every area it owns):

  | Area | padding | spacing | radius | anim |
  |---|---|---|---|---|
  | Notebook | 21 | 44 | 7 | 18 |
  | Library | 10 | 16 | 4 | 0 |
  | TextDocs | 11 | 4 | 1 | 2 |
  | Study | 8 | 7 | 0 | 2 |
  | Search | 4 | 5 | 2 | 0 |
  | Boards | 1 | 2 | 4 | 6 |
  | AI | 1 | 9 | 0 | 0 |
  | Audio | 0 | 6 | 0 | 0 |
  | Import | 0 | 2 | 0 | 0 |
  | Backup | 1 | 0 | 0 | 0 |
  | **Total** | **57** | **95** | **18** | **28** |

- **Wave 0 + Wave 1 batch 1 merged** into `integrate/polish-perf` (`29b6c67`): E1 ink path, U1a, U2a, U3a, U4a, U5, and `BoardImageCache` wired into the memory-warning purge. On the merged base: all nine package suites pass; 89 app tests pass on macOS; iOS Simulator build succeeds. Lint total went from 57/95/18/28 to 36/56/12/12.
- **E1 measured** (M1 Max, release, median of 5): one stroke appended to a 2,000-stroke page through the converter, 4.65 ms full path → 0.18 ms fast path. One PencilKit read per stroke end (was two). The invalidation test shows `currentPageID`, `activeLayer` and `manifest` do not fire on a stroke, so the pane chrome does not re-render per stroke.
- **Wave 1 batch 2 running:** U1b, U2b, U3b, U4b, plus U6 (`polish/u6-session`) for the leftovers that needed `NotebookSession.swift`: tape IDs without a per-stroke read, reveal-all in one mutation, cancellable PDF insert, drop the retained PDF on close, version-history read errors.
- Deferred from batch 1 for a later pass: A5-09 copy without `Data(contentsOf:)` (needs a file-copy `LibraryStore.addAsset`).
- **App test command.** In a fresh worktree the test bundle is unsigned and macOS refuses to load it. Pass the signing settings on the command line:
  `xcodebuild test -project NoteApp.xcodeproj -scheme NoteApp -destination 'platform=macOS' -derivedDataPath /tmp/<dir> CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=CQ65B26KFJ`

## Carried over from the foundation plan

| Item | Status |
|---|---|
| 9 Edit log, 10 shared document store | Deferred. Structural; not part of this pass. |
| 11 Library snapshot | E2, conditional. |
| 12 Split session and pane | E3, limited to measured subtrees. |
| 13 Ink deltas | E1 (fast path, same public callback). |
| 14 PDF render gate, caps | U2 gate now; E4 conditional. `PDFPageGeometry` (rotation, crop box) deferred. |
| 15 Board culling | U4, if A4 confirms. |
| 16 FTS5 search | Deferred. Format change; no effect on frame times. |

## Left out on purpose

- Haptics: the iPad has no haptic engine for touch; Pencil feedback already goes through `UICanvasFeedbackGenerator` in InkKit.
- Swapping fixed font sizes for text styles: `.body` is 17 pt on iPad and 13 pt on Mac, so a blind swap changes the Mac app. The audits list each fixed size; the decision is made at Gate 0.

## Open decisions (yours)

- The find bar is merged into this base before its device walkthrough. If the walkthrough rejects it, Wave 1 search polish is redone.
- Page bookmarks location and the highlighter export rule are still open from `.memory/context/project.md`. This pass does not touch either.
- E1 is the one item where a mistake can lose ink. It runs on DeepSeek as instructed, guarded by the equivalence test; say so if you want it on Opus instead.
