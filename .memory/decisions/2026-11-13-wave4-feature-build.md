---
type: decision
title: Wave 4 lands eight research-backed feature sets on foundation-base
status: accepted
updated: 2026-11-13
---

# ADR: Wave 4 lands eight research-backed feature sets on foundation-base

- **Status:** accepted
- **Date:** 2026-11-13
- **Plan:** `research_notes/studies/BUILD-PLAN.md` (rows A–H); status and follow-ups in `research_notes/studies/WAVE4-STATUS.md`
- **Integration:** `feat/wave4` (`302aff2`) merged into `integrate/foundation-base` as `0e02ec8`

## Context

The study reports in `research_notes/studies/` produced ~95 missing features. Eight were cut as wave 4 and built in parallel by DeepSeek V4.1 Flash agents, each in its own worktree off `460bee3`, then merged one at a time into `feat/wave4` and re-verified.

## Decisions

1. **One agent per vertical, own worktree.** Selection, durability, AI/search, audio, study, ink, navigation and PDF each owned a file set; shared files (`NotebookView`, `EditorToolbar`, `EditorToolState`, `AppModel`, `NotebookSession`) took additive edits only. Conflicts were resolved by combining, never by dropping a side.
2. **Verify on the integration branch, not on the report.** Every merge runs the affected package tests and an iPad build; the full sweep at the end is 532 package tests plus 28 app tests.
3. **Page durability uses a sidecar, not a format bump.** `pages/<id>.sha256` records the hash after verify-after-write; `loadPage` does not gate on it (a kill between the two writes would blank a good page). Checksums are enforced by Verify All Pages and by backup restore.
4. **Backups copy whole notebook folders.** `.noteappbackup` includes `bookmarks.json` and any future per-notebook file for free; restore never overwrites, it restores a " (Restored)" copy.
5. **Dashed strokes reuse the existing mask field.** The dash pattern is baked into `PKStroke.mask`, so it stays one stroke with one undo and needs no page-format change.
6. **Selection reads PencilKit's `selection`.** `PKCanvasView.selection` (iOS 27) becomes `StrokeRecord` IDs fed into one `InkSelection` model; Select Elements feeds the same model instead of its own state.
7. **FSRS sits beside SM-2.** `ReviewState` gained optional `stability`/`difficulty` with a hand-written decoder; old `review-states.json` decodes unchanged, intervals switch to FSRS after the next grade.
8. **Spotlight and OCR text are caches.** Spotlight is rebuildable and behind a setting; OCR text goes into the existing `.pdf` segment, so the index schema is untouched.

## Consequences

- The base branch is 11k lines richer and every package suite is green; nothing has been walked on a physical iPad yet.
- Known gaps are recorded per item in `WAVE4-STATUS.md` (Spotlight deep link, OCR mark boxes, Reading Mode tab bar, selection copy of image/PDF elements, backup scope beyond the library).
- **Open:** page bookmarks now live in `notebooks/<id>/bookmarks.json`, which conflicts with `2026-11-12-page-bookmarks-app-side`; that ADR needs a keep/update/remove answer before a superseding ADR is written.
- Wave 4b (lasso → card, annotation recap, semantic search, lasso command ring) and wave 5 (SyncKit) are next; wave 4b depends on the selection model that now exists.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Advanced search uses Apple's ink engine; query syntax lives in SearchKit](2026-11-12-advanced-search.md)
- [Dark mode keeps white paper unless Dark Paper is on](2026-11-12-dark-mode-paper.md)
- [Physical iPad installs use the personal team and automatic signing](2026-11-12-device-install-signing.md)
- [GoodNotes parity build and page format v2](2026-11-12-goodnotes-parity-build.md)
- [Page saves go through one ordered write queue](2026-11-12-ordered-page-writes.md)
- [Page bookmarks stay app-side](2026-11-12-page-bookmarks-app-side.md)
- [Page operations are pure NoteCore functions; app settings live in UserDefaults](2026-11-12-page-operations-and-settings.md)
- [One live canvas per notebook; other pages are cached images](2026-11-12-page-scroll-live-canvas.md)
- [PDF export is vector; import rewrites only when it must](2026-11-12-pdf-vector-export-and-import.md)
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [A finger drag on a board object is decided at touch-down, before ink](2026-11-13-board-finger-drag-vs-ink.md)
- [Boards open full screen on iPad; the Mac keeps a sheet](2026-11-13-board-full-screen.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Page thumbnails live in a side panel; Undo and Redo leave the default toolbar](2026-11-13-pages-side-panel.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
