---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-12
---

# Status — 2026-11-12

## Done

- Phase 0–2, parity, fix/ui-basics, waves 1+3; checkpoint `d07671b`.
- Competitor research: `research_notes/competitors/` (uncommitted).
- Toolbar QoL (`TOOLBAR-QOL-PLAN.md`): palettes, favourite pens, writing settings, eraser filter, hold-to-shape, scroll modes ([[2026-11-12-page-scroll-live-canvas]]), Zoom View.
- PDF vector/editable export + full import ([[2026-11-12-pdf-vector-export-and-import]]).
- Dark mode + Dark Paper ([[2026-11-12-dark-mode-paper]]).
- Performance pass: `PERFORMANCE-NOTES.md`.
- Advanced search `a354025` (parallel session).
- Head `91c0b77`: iPad + macOS build; NoteCore 83, InkKit 106, SearchKit 41 tests pass.

## In progress / caution

- Nothing driven on a physical iPad: all Pencil/gesture behaviour unverified.
- Not pushed; no PR. Finished agent worktrees still in `~/.t3/worktrees/NOTEAPP/` (removal needs user OK).

## Next

1. Physical iPad pass: `TOOLBAR-QOL-PLAN.md` checklist + `PERFORMANCE-NOTES.md` profiling.
2. User: push / PR `feat/toolbar-qol`; commit research notes or not.
3. Later: custom lasso (recolour), ink stabilisation, Drive sync (OAuth).

## Handoff

- Delegates: DeepSeek V4.1 Flash (OpenCode Go) default, Opus 5.5 medium for hard work; worktree per package, main session reviews and merges.
- Key paths: see `context/project.md`.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
