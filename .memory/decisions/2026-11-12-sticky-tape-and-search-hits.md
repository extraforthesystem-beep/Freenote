---
type: decision
title: Sticky notes and tape are page elements; search hits carry source and snippet
status: accepted
updated: 2026-11-12
---

# ADR: Sticky notes and tape are page elements; search hits carry source and snippet

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `fix/ui-basics` (uncommitted)

## Context

The live Goodnotes walkthrough (`research_notes/goodnotes-walkthrough/WALKTHROUGH.md`) showed sticky notes, tape that hides content until tapped, and search results grouped by source with highlighted snippets. Wave 1 built these.

## Decisions

1. **New `PageElementContent` cases `stickyNote(text, color)` and `tape(color)`.** Additive to page format v2 (see [[2026-11-12-goodnotes-parity-build]]): old files decode unchanged; an unknown kind still fails as before.
2. **Tape reveal state is session-only.** `NotebookSession.revealedTapeIDs` is never encoded; every reopen starts with tape hidden.
3. **Live tape is drawn above the ink by `TapeOverlay`, not in the page background.** The live editor passes the background a page with tape removed, so revealed tape is faint. Exports and the macOS reader still render tape from `PageElementRenderer` at 90% opacity under the ink.
4. **Search records gained a schema version, per-source segments and a page index.** `SearchHit` carries source (handwriting / typed text / PDF), a ~80-char snippet and the match range. Older index files are dropped on load and rebuilt; the index stays a rebuildable cache. Sticky-note text is indexed as typed text.
5. **Laser pointer and Read Only are view state only.** Neither is persisted; laser never creates strokes.

## Consequences

- Sync/merge must treat the two new element kinds like other elements (tombstones already cover removal).
- The first launch after this change re-runs handwriting recognition for every notebook.

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
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Page thumbnails live in a side panel; Undo and Redo leave the default toolbar](2026-11-13-pages-side-panel.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
