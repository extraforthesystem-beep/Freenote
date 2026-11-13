---
type: decision
title: Page operations are pure NoteCore functions; app settings live in UserDefaults
status: accepted
updated: 2026-11-12
---

# ADR: Page operations are pure NoteCore functions; app settings live in UserDefaults

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `fix/ui-basics` (uncommitted)

## Context

The second Goodnotes pass (`research_notes/goodnotes-walkthrough/WALKTHROUGH.md` §8b) opened the More menu and Settings item by item. Wave 3 built rotate / clear / delete-by-kind, page sizes, new-notebook defaults and a Settings screen.

## Decisions

1. **Page edits are pure `extension Page` functions in NoteCore** (`PageOperations.swift`): `rotated(quarterTurns:)`, `removingItems(of:)`, `cleared()`, `resized(width:height:)`. `NotebookSession` only saves their result through the ordered write queue ([[2026-11-12-ordered-page-writes]]).
2. **Rotation is baked into the content, not stored as a page flag.** The page map is appended to each stroke's `transform`; element frames move their centre and add π/2 per turn; width/height swap on odd turns. Imported PDF pages are elements, so they rotate the same way.
3. **Clear and Delete Specific Items never remove imported PDF pages**, write tombstones for every removed id, and record a version snapshot first.
4. **Resizing keeps content in place** (no scaling). Shared types `PaperSize`, `PageOrientation`, `PageItemKind` live in `NoteCore/Model/PaperSize.swift`.
5. **App settings are `UserDefaults` keys prefixed `noteapp.settings.`** (`NoteApp/Settings/AppSettings.swift`), read with explicit defaults; device-local, like bookmarks ([[2026-11-12-page-bookmarks-app-side]]). Turning off handwriting recognition stops all search indexing.
6. **No horizontal scrolling option:** the editor shows one page at a time.

## Consequences

- Rotating a page changes stroke transforms, so the search index re-recognises it.
- Settings do not sync between devices.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Advanced search uses Apple's ink engine; query syntax lives in SearchKit](2026-11-12-advanced-search.md)
- [Dark mode keeps white paper unless Dark Paper is on](2026-11-12-dark-mode-paper.md)
- [Physical iPad installs use the personal team and automatic signing](2026-11-12-device-install-signing.md)
- [GoodNotes parity build and page format v2](2026-11-12-goodnotes-parity-build.md)
- [Page saves go through one ordered write queue](2026-11-12-ordered-page-writes.md)
- [Page bookmarks stay app-side](2026-11-12-page-bookmarks-app-side.md)
- [One live canvas per notebook; other pages are cached images](2026-11-12-page-scroll-live-canvas.md)
- [PDF export is vector; import rewrites only when it must](2026-11-12-pdf-vector-export-and-import.md)
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
