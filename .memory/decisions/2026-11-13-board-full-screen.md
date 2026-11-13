---
type: decision
title: Boards open full screen on iPad; the Mac keeps a sheet
status: accepted
updated: 2026-11-13
---

# ADR: Boards open full screen on iPad; the Mac keeps a sheet

- **Status:** accepted
- **Date:** 2026-11-13
- **Branch:** `integrate/foundation-base` (`0bde03a`)

## Context

The whiteboard editor was presented with `.sheet(item:)`. On iPad a sheet is a centred form window with the library still visible around it. A board is a drawing workspace, like a notebook or Freeform, so it looked like a small card instead of a workspace.

## Decisions

1. On iOS the editor is presented with `.fullScreenCover(item: $selectedBoard)`, so it takes the whole screen exactly as the notebook editor does.
2. macOS keeps `.sheet`: there the board is a static preview (`macCanvas`), not an editing surface.
3. Done and the toolbar's "Boards" back button both run `finishEditing()` and dismiss; a full-screen cover has no swipe-to-dismiss, so those are the only exits.

## Consequences

The board canvas, toolbar, zoom pill and grid toggle span the full screen and the library sidebar is hidden while editing. The board list and naming sheets are unchanged.

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
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Page thumbnails live in a side panel; Undo and Redo leave the default toolbar](2026-11-13-pages-side-panel.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Wave 4 lands eight research-backed feature sets on foundation-base](2026-11-13-wave4-feature-build.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
