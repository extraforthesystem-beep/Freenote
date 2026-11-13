# Wave 4 build status

Plan: `BUILD-PLAN.md` (rows A–H). This file tracks who is building what and what has landed.

## Base

- `integrate/foundation-base` @ `460bee3`: sharp ink at zoom, first stroke on a new page, customisable toolbar, pages side panel, fine pen widths, freeform board + advanced search all merged.
- Base verified: iPad app build succeeded (iPad Pro 11-inch M5, iOS 27.2); NoteCore 94, InkKit 117, SearchKit 41 tests pass.
- Integration branch for this wave: `feat/wave4`, worktree `~/.t3/worktrees/NOTEAPP/wave4-integration`, forked from `460bee3`.

## Wave 4a — delegated to DeepSeek V4.1 Flash (own worktree per agent)

| ID | Feature | State | Branch | Notes |
|---|---|---|---|---|
| A | Selection model + lasso actions | running | t3 worktree | PencilCanvasView, new `Selection*.swift`, lasso in `EditorToolState` |
| B | Durability + backup | running | t3 worktree | NoteCore store, HistoryKit, new `NoteApp/Backup` |
| C | AI + search correctness | running | t3 worktree | SearchKit, AIKit, citations, Spotlight |
| D | Audio replay | running | t3 worktree | AudioKit playback ↔ stroke time, transcripts |
| E | Study engine | running | t3 worktree | FSRS, recall-first, one due queue |
| F | Ink tools | running | t3 worktree | stabilisation, dashed, scratch-out, shapes |
| G | Navigation + library | running | t3 worktree | page history, Continue rail, page grid, tags |
| H | PDF reading + templates | running | t3 worktree | writing margin, dark PDF paper, templates |

## Merge protocol

1. Agent reports branch + head SHA + test output.
2. Merge into `feat/wave4` in the integration worktree, resolve shared-file conflicts by hand (toolbar, notebook view, session).
3. Build the app and run the affected package tests on the integration branch after each merge.
4. Only then merge `feat/wave4` into `integrate/foundation-base`.

## Next waves

- 4b (after A): lasso → study card, annotation recap, hybrid semantic search, lasso command ring.
- 5 (after B): SyncKit per `06-sync-durability.md`.
