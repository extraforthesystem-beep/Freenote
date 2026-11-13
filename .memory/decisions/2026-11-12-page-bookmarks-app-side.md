---
type: decision
title: Page bookmarks stay app-side
status: accepted
date: 2026-11-12
---

# Page bookmarks stay app-side

## Decision

Page bookmarks are stored in `UserDefaults` keyed by notebook UUID and page UUID (`PageBookmarks`), not in `notebook.json`.

## Why

- Bookmarks are a view preference, not document content; they should not force a page or manifest rewrite.
- `notebook.json` is the document truth that will be synced; adding a per-device list there would create needless merge conflicts.
- Bookmarks can move into the document later if the user wants them on every device; the page IDs are stable.

## Consequence

Bookmarks do not sync through Google Drive and do not survive a restore on another device until they are promoted to document data. A future ADR must record that change.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Advanced search uses Apple's ink engine; query syntax lives in SearchKit](2026-11-12-advanced-search.md)
- [Dark mode keeps white paper unless Dark Paper is on](2026-11-12-dark-mode-paper.md)
- [Physical iPad installs use the personal team and automatic signing](2026-11-12-device-install-signing.md)
- [GoodNotes parity build and page format v2](2026-11-12-goodnotes-parity-build.md)
- [Page saves go through one ordered write queue](2026-11-12-ordered-page-writes.md)
- [Page operations are pure NoteCore functions; app settings live in UserDefaults](2026-11-12-page-operations-and-settings.md)
- [One live canvas per notebook; other pages are cached images](2026-11-12-page-scroll-live-canvas.md)
- [PDF export is vector; import rewrites only when it must](2026-11-12-pdf-vector-export-and-import.md)
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
