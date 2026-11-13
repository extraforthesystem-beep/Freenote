---
type: decision
title: "Advanced search uses Apple's ink engine; query syntax lives in SearchKit"
status: accepted
updated: 2026-11-12
---

# ADR: Advanced search uses Apple's ink engine; query syntax lives in SearchKit

- **Status:** accepted
- **Date:** 2026-11-12
- **Commit:** `a354025` (on `feat/advanced-search`)
- **Extends:** [[2026-11-12-sticky-tape-and-search-hits]]

## Context

User asked for search beyond plain text: written with Apple Pencil, using Apple's engine where it exists. iOS/macOS 27 `PKStrokeRecognizer` exposes `recognizedText()`, `indexableContent` and `search(_:)`, which returns stroke IDs and bounds.

## Decisions

1. **Query syntax is parsed once, in SearchKit (`SearchQuery`).** Words (tolerant match), `"phrase"` (exact; a space also matches a line break), `a OR b`, `-word` or `-"phrase"` (exclude). The old `search(String, in:)` goes through it, and notebook-title matching uses the same rules.
2. **`SearchFilter` = sources + notebook IDs + `editedAfter`.** The UI picks a `SearchDateRange`, which becomes a date at each search.
3. **Edit date comes from content, not index time.** `PageSearchRecord.editedAt` = newest stroke `createdAt` or element `updatedAt`, so it survives Rebuild Search Index. Optional field, **no schema bump**: old records fall back to `updatedAt` and get it backfilled on the fast path without running recognition again.
4. **Pencil query = `PKStrokeRecognizer.recognizedText()` on a small `PKCanvasView` pad** (iOS only; macOS has no canvas for it).
5. **Page marks are computed live, never stored.** Handwriting: `PKStrokeRecognizer.search` run on the recogniser's actor (its results are not Sendable). Typed text: the whole element frame, with its rotation. PDF: `PDFPage.selection(for:)` mapped like `PDFLinkHandler` (aspect-fit, y flipped; PDF elements rotated on the page are skipped). `NotebookSession.searchHighlight` holds the query and sources for the session only.
6. **The overlay never takes touches.** Writing on the page clears the marks unless the search panel is open.

## Consequences

- Ink marks depend on Apple's recogniser version and language; they can disagree with the stored text (by design: they find what the text misread).
- Typed-text marks cover the whole text box, not the single word.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
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
- [Wave 4 lands eight research-backed feature sets on foundation-base](2026-11-13-wave4-feature-build.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
