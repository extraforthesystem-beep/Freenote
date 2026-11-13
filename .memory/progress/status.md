---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-13
---

# Status — 2026-11-13

## Done

- Phase 0–2 parity `d07671b`; advanced search + sharp ink; customisable toolbar `82bf0d6`; pages side panel `1a528c7`; iPad installs (9th gen, team `CQ65B26KFJ`).
- **Phase 0 integration PR #1 merged** (head `39a0412`, merge `0ce4492`): folders/PDF fixes committed, seven branches merged into `integrate/foundation-base`; build green, 117 InkKit + 94 NoteCore + 41 SearchKit + BoardKit tests.
- Fine pen widths shipped in that head: 0.5 / 0.7 / 0.9 mm preset dots, editable via hold (mm slider), "Set to Current Width" and "Reset Widths"; edits persist across relaunch. The earlier 1.5 mm reading was saved test data, not a bug. iPad installed from `39a0412`.
- **Wave 4** `0e02ec8` ([[2026-11-13-wave4-feature-build]]): selection/lasso, page durability, AI/search, audio replay, study (FSRS), ink tools, navigation, PDF margin/Reading Mode. 532 package + 28 app tests.
- **Freeform board** `743d8a5`: full-screen editor on iPad ([[2026-11-13-board-full-screen]]); known limitations fixed — finger drag vs ink ([[2026-11-13-board-finger-drag-vs-ink]]), shape fills, object thumbnails, board-only asset cleanup, "Clear Board…" label. BoardKit 50, InkKit 145 tests; iOS, macOS and iPad builds green; installed on iPad.

## In progress / caution

- Wave 4 and board changes have not been walked on a physical iPad. Highest-risk checks: scratch-out undo, dash rendering, highlighter straight lines, selection bar occlusion, Reading Mode, tap-to-seek, board finger drag with a real Pencil.
- `origin` now exists; `origin/main` merged as `3c3d5ee`. The working tree holds uncommitted changes from another session.
- `fix/folders-pdf-import` still uncommitted off `feat/advanced-search`; detached `ipad-combined` needs glue redone.
- Open ADR question: highlighter export bends the PDF vector ADR. Removing 21+ worktrees needs user OK.

## Next

1. Physical iPad pass on wave 4 + boards, then commit `fix/folders-pdf-import`.
2. Wave 4b: lasso → study card, recap + backlinks, semantic search, command ring.
3. Wave 5: SyncKit object store + iCloud Drive, building on B's backups.
4. Push/PR on `origin`; decide whether research notes stay committed.

## Handoff

- Delegates: DeepSeek V4.1 Flash default, Opus 5.5 for hard work; worktree per agent, main session reviews and merges.
- Board work came from `feat/freeform-board`, merged at `743d8a5`.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
