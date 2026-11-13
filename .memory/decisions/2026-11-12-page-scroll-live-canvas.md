---
type: decision
title: One live canvas per notebook; other pages are cached images
status: accepted
updated: 2026-11-12
---

# ADR: One live canvas per notebook; other pages are cached images

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `feat/toolbar-qol`

## Context

Seamless (vertical) and single-page (horizontal) scrolling show several pages at once. A PencilKit canvas plus hosted page per visible page is too heavy for a base iPad.

## Decisions

1. **Scroll mode** is a global default (`AppSettings.pageScrollMode`) with an optional per-notebook override `NotebookManifest.pageScrollMode`; absent = default, unknown = vertical.
2. **Only the active page hosts the live canvas** (`PagedNotebookView` in `ContinuousPagesView.swift`); other pages are images from `PageImageCache`. The active page changes when scrolling settles or on touch-down via `session.goToPage`.
3. **First stroke on an inactive page is captured and replayed**: samples are recorded with a preview, then appended to the page's canvas as one undo step once it is live. Dropped after 5 s or on a locked layer.
4. **Zoom View reuses `PencilCanvasView`** with a `viewport` (zoomScale/contentOffset), synced through the session's stroke path; undo targets the last-touched canvas.
5. Pencil never scrolls; one finger scrolls when drawing is Pencil-only, two fingers when Draw with Finger is on.

## Consequences

Memory stays flat for 300+ page notebooks. Inactive pages may look soft at high zoom until activated.

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
- [PDF export is vector; import rewrites only when it must](2026-11-12-pdf-vector-export-and-import.md)
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
