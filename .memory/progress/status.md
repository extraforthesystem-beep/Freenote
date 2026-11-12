---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-12
---

# Status — 2026-11-12

## Done

- Phase 0–2, parity packages, fix/ui-basics pass.
- Goodnotes walkthrough: `research_notes/goodnotes-walkthrough/` (`WALKTHROUGH.md`, `BUILD-PLAN.md`).
- Wave 1: sticky, tape, laser, Read Only, ruler, shortcuts, search snippets/inspector. ADR [[2026-11-12-sticky-tape-and-search-hits]].
- Wave 3: Settings, page rotate/clear/delete-by-kind, page sizes, new-notebook defaults, page number. ADR [[2026-11-12-page-operations-and-settings]].
- iPad + macOS build; all package tests pass; key paths checked in simulator.

## In progress / caution

- `fix/ui-basics`, nothing committed since `5fb4841`.
- Untested by hand: listed in `BUILD-PLAN.md` wave status lines.
- More menu long; page actions need scrolling.

## Next

1. User: commit waves 1+3, or start wave 2 (shape recognition, lasso actions, eraser filter).
2. Physical iPad; Drive sync blocked on OAuth.

## Handoff

- Delegates: DeepSeek V4.1 Flash (OpenCode Go); Opus 5.5 for hard work; shared checkout, disjoint files.
- Key files: `NoteApp/Notebook/{NotebookView,NotebookSession}.swift`, `NoteApp/Settings/`, `NoteCore/Model/{PageOperations,PaperSize}.swift`.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
