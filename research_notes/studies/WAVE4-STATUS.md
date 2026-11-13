# Wave 4 build status

Plan: `BUILD-PLAN.md` (rows A–H). This file tracks who is building what and what has landed.

## Base

- `integrate/foundation-base` @ `460bee3`: sharp ink at zoom, first stroke on a new page, customisable toolbar, pages side panel, fine pen widths, freeform board + advanced search all merged.
- Base verified: iPad app build succeeded (iPad Pro 11-inch M5, iOS 27.2); NoteCore 94, InkKit 117, SearchKit 41 tests pass.
- Integration branch for this wave: `feat/wave4`, worktree `~/.t3/worktrees/NOTEAPP/wave4-integration`, forked from `460bee3`.

## Wave 4a — delegated to DeepSeek V4.1 Flash (own worktree per agent)

| ID | Feature | State | Branch | Notes |
|---|---|---|---|---|
| A | Selection model + lasso actions | merged `418d7d1` | `feat/w4-selection` | 12 app tests, InkKit 117, build green. |
| B | Durability + backup | running | t3 worktree | NoteCore store, HistoryKit, new `NoteApp/Backup` |
| C | AI + search correctness | merged `f288ec1` | `t3/52d9d85f` | SearchKit 46 tests, app build green. Follow-ups below. |
| D | Audio replay | running | t3 worktree | AudioKit playback ↔ stroke time, transcripts |
| E | Study engine | merged `6ced4a7` | `feat/w4-e` | FSRS + SM-2 migration, recall-first, one due queue, tape mode, leech. StudyKit 77 tests. |
| F | Ink tools | running | t3 worktree | stabilisation, dashed, scratch-out, shapes |
| G | Navigation + library | merged `f8651d5` | `feat/w4-g` | page history, Continue rail, page grid, tags, Last Opened, named bookmarks + pinned pages. NoteCore 100, app bookmark tests pass. |
| H | PDF reading + templates | merged `b9f4cbb` | `feat/w4-h` | writing margin, dark PDF paper, link history, custom templates, Reading Mode. NoteCore 97, InkKit 120. |

## Merge protocol

1. Agent reports branch + head SHA + test output.
2. Merge into `feat/wave4` in the integration worktree, resolve shared-file conflicts by hand (toolbar, notebook view, session).
3. Build the app and run the affected package tests on the integration branch after each merge.
4. Only then merge `feat/wave4` into `integrate/foundation-base`.

## Follow-ups from merged work

- C: Spotlight results open the app but do not jump to the page (needs `RootView`/`NoteAppApp`).
- C: OCR'd PDF pages navigate but draw no in-page mark (`PageMatchLocator.pdfMarks` reads the text layer only).
- C: auto-title suggestion lives in the Page AI panel, not the library (G owns `NoteApp/Library`).
- E: cards made by the AI panel still have no `sourceNotebookID`/`sourcePageID` (that file is C's).
- E: leech handling is text rewrite/split only; ink-crop attachment needs the lasso model from A.
- E: desired retention is a global 0.9, not per card.
- A: copying image/PDF elements is not supported (notebook-local assets); duplicate works in place. Selection actions register undo but not redo.
- A: the floating selection bar can cover the bottom of the page while active.
- H: Reading Mode hides toolbar, divider, counter and panels, but not the notebook tab bar or the system status bar.
- H: custom templates cannot be renamed after import; PDF templates use page 1 only.
- G: page history is per open notebook and in memory, not persisted across relaunch; it now shares the bottom-leading corner with H's PDF link chip (stacked).
- G: `bookmarks.json` is a new file inside each notebook folder — B's backup archive and wave 5 sync must include it.

## Next waves

- 4b (after A): lasso → study card, annotation recap, hybrid semantic search, lasso command ring.
- 5 (after B): SyncKit per `06-sync-durability.md`.
