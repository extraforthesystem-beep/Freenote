---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-13
---

# Status — 2026-11-13

## Done

- Phase 0–2, parity, fix/ui-basics, waves 1+3; checkpoint `d07671b`.
- Competitor research: `research_notes/competitors/` (uncommitted).
- Toolbar QoL (`TOOLBAR-QOL-PLAN.md`): palettes, favourite pens, writing settings, eraser filter, hold-to-shape, scroll modes ([[2026-11-12-page-scroll-live-canvas]]), Zoom View.
- PDF vector/editable export + full import ([[2026-11-12-pdf-vector-export-and-import]]).
- Dark mode + Dark Paper ([[2026-11-12-dark-mode-paper]]).
- Performance pass: `PERFORMANCE-NOTES.md`.
- Advanced search `a354025`: Pencil query pad, `"phrase"`/OR/-word, source + last-edited filters, page marks for ink/text/PDF ([[2026-11-12-advanced-search]]).
- Installed on iPad (9th gen, 27.2.1), team `CQ65B26KFJ`; launches and works ([[2026-11-12-device-install-signing]]).
- Head `91c0b77`: iPad + macOS build; NoteCore 83, InkKit 106, SearchKit 41 tests pass.
- `PageElementRenderer.swift` element rendering (committed).
- Sharp ink at any zoom: merged into `feat/advanced-search` as `59e29f9` (from `fix/sharp-ink-zoom` `6bf87d9`), `InkCanvasHost` + `InkRenderViewport` ([[2026-11-13-sharp-ink-zoom]]); InkKit 112 tests, simulator before/after verified.

- Device bug fixes on `fix/folders-pdf-import` (uncommitted, built + installed on iPad): New Folder name capture; PDF ink paths bounds-relative on import; search panel adopts `session.searchHighlight`.
- 2026-11-13 bug sweep on same branch (uncommitted; app builds, InkKit 109 pass; not tried on device). DeepSeek found, main session verified/reviewed:
  - Data: stale canvas callback could save page A's ink onto page B and tombstone B's strokes — `strokesChanged(_:onPage:)` guard; element resize after page shrink went negative — clamp.
  - Search: panel `.id(notebookID)`, `initialPageID`, `SearchHighlight.dateRange`, adopt compares sources/date; marks debounce 0.6 s + cancel guard; imported PDFs indexed in background; import files into selected folder; library hits grouped once.
  - Folders: toolbar New Folder uses current folder; blank name disables Create; `AppModel.maxFolderDepth` (12) gates subfolder/move.
  - Import: partial page insert reports N of M (`PDFImportError.partialInsert`); hidden ink (`shouldDisplay`) not converted.
  - Perf (`PERFORMANCE-NOTES.md` rows 11–17): Zoom View child view, zoom writing-size 1 pt threshold, async page background, recording label isolated, PNG export off main, PDF link doc cache.
  - Export: PDFKit can't persist `/CA`, so translucent (highlighter) ink is drawn as vectors, not annotated; import reads `/CA`.

- Customisable toolbar on `feat/toolbar-customize` (`ecd7e6c` DeepSeek, `82bf0d6` pen-only fix), worktree `~/.t3/worktrees/NOTEAPP/t3-87bf97db-…`: only colours scroll, overflow menu, Customize Toolbar sheet, Read Only in More, new `NoteAppTests` (12 pass), installed on iPad ([[2026-11-13-customisable-toolbar]]). Plan `TOOLBAR-CUSTOMIZE-PLAN.md`.

## In progress / caution

- Toolbar branch: user to walk the device checklist in `TOOLBAR-CUSTOMIZE-PLAN.md` (full width, 1/2 + 1/3 split, editor persists, Read Only, favourite pens in pen popover). iPad build lacks the uncommitted `fix/folders-pdf-import` fixes. Merge into `fix/folders-pdf-import` after the user commits it (both touch `NotebookView.swift`).

- iPad: installed and launched, works; Pencil/gesture checklist still unwalked.
- iPad build 2026-11-13 15:47 is a snapshot, not a branch: `feat/advanced-search` (sharp ink) + `feat/toolbar-customize` + `feat/freeform-board` + uncommitted whiteboard and main-checkout work, in detached scratch worktree `ipad-combined`. Glue only there: board passes new toolbar params, notebook-only items hidden on boards, `EditorToolbar.audio` optional. Redo this glue when those branches merge.
- Sharp ink on device: installed, not yet walked: check Pencil latency + memory at 8×, lasso, ruler, eraser width, dark paper, horizontal mode, split panes (tracked in the device pass, not a merge blocker).
- Extra simulator "iPad sharp-ink check" (`756785F2…`) left booted; deletion needs user OK.
- `fix/folders-pdf-import`: user to check folder create, editable-PDF re-import, library search → panel on iPad; then pull container to confirm, then commit. If panel stays empty when typing in it directly, that is a separate unfound bug.
- Device-check first: Zoom View writing, element drag (background lands a frame late), editable-PDF export highlighter. `research_notes/freeform/` uncommitted, commit separately.
- Open ADR question: highlighter export bends [[2026-11-12-pdf-vector-export-and-import]] ("one .ink annotation per stroke"); needs user keep/update.
- Left: macOS board 3000² render in body (`BoardEditorView.swift:139`).
- Search UI not exercised on device; PDF mark placement only unit-tested.
- No git remote configured: cannot push or open a PR until the user picks a repo. Finished agent worktrees still in `~/.t3/worktrees/NOTEAPP/` (removal needs user OK).

## Next

1. Device-check, then commit `fix/folders-pdf-import` (user to approve).
2. Physical iPad pass: `TOOLBAR-QOL-PLAN.md` checklist (now incl. sharp ink at 8×: latency, memory, lasso, ruler) + `PERFORMANCE-NOTES.md` profiling.
3. Optional: inactive pages render the visible crop at settled zoom (still capped at 3×).
4. User: set up a remote, then push / PR `feat/advanced-search` (holds all work); commit research notes or not.
5. Device check of search: Pencil pad, marks across ink/text/PDF, Last Edited filter.
6. Later: custom lasso (recolour), ink stabilisation, Drive sync (OAuth).

## Handoff

- Delegates: DeepSeek V4.1 Flash (OpenCode Go) default, Opus 5.5 medium for hard work; worktree per package, main session reviews and merges.
- Key paths: see `context/project.md`.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
