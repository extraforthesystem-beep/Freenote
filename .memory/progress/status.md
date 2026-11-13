---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-13
---

# Status — 2026-11-13

## Done

- Phase 0–2 + parity checkpoint `d07671b` (`91c0b77` builds iPad + macOS); toolbar QoL, scroll modes, Zoom View, PDF vector export/import, dark mode + Dark Paper, perf notes.
- Advanced search `a354025`; sharp ink `59e29f9` ([[2026-11-13-sharp-ink-zoom]]).
- iPad installs work (9th gen, team `CQ65B26KFJ`).
- `feat/toolbar-customize` `82bf0d6`: only colours scroll, Customize sheet, Read Only in More, tests pass ([[2026-11-13-customisable-toolbar]]).
- `feat/pages-side-panel` `1a528c7`: side page grid (right default, left setting, sheet at compact width), Undo/Redo out of the default toolbar; iPad build installed ([[2026-11-13-pages-side-panel]]).
- `integrate/foundation-base` `a8a7d13` (main): research + foundation reports `d1ba21e`, sharp-ink/first-stroke merges.
- `fix/folders-pdf-import` (uncommitted): folder naming, PDF import/search fixes, perf rows 11–17.

## In progress / caution

- Device checklist not walked for pages panel/toolbar; build lacks `fix/folders-pdf-import`.
- Merge order: commit `fix/folders-pdf-import` → merge `feat/pages-side-panel` (brings toolbar) → `integrate/foundation-base`. Both touch `NotebookView.swift`.
- Detached `ipad-combined` snapshot needs glue redone after merges.
- Not device-tested: sharp ink at 8×, search UI, PDF mark placement. Open ADR question: highlighter export bends the PDF ADR.
- No git remote (no push/PR); removing worktrees/stray simulator needs user OK.

## Next

1. Device-check pages panel + toolbar, then commit `fix/folders-pdf-import`.
2. Merge branches, then physical iPad pass and `PERFORMANCE-NOTES.md` profiling.
3. User: set a remote, push/PR; decide whether research notes stay committed.
4. Later: custom lasso, ink stabilisation, Drive sync.

## Handoff

- Pages/toolbar work in `~/.t3/worktrees/NOTEAPP/t3-87bf97db-…` on `feat/pages-side-panel`.
- Delegates: DeepSeek V4.1 Flash default, Opus 5.5 for hard work; main session reviews/merges.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
