---
type: decision
title: Page thumbnails live in a side panel; Undo and Redo leave the default toolbar
status: accepted
updated: 2026-11-13
---

# ADR: Page thumbnails live in a side panel; Undo and Redo leave the default toolbar

- **Status:** accepted
- **Date:** 2026-11-13
- **Extends:** [[2026-11-13-customisable-toolbar]] (toolbar items are a persisted list; only the colours scroll)
- **Plan:** `PAGES-SIDE-PANEL-PLAN.md`; branch `feat/pages-side-panel` (`ae06ed8`, `1e54e65`, `1a528c7`), built on `feat/toolbar-customize`.

## Context

The bottom page strip took a 94 pt `LazyHStack` away from the page height, and the toolbar's leading group still
spent width on Undo and Redo. The user asked for a vertical page grid on the side so the toolbar has more room.

## Decisions

1. **Thumbnails move to a side panel.** `PagesSidePanel` (formerly `PageThumbnailStrip`) is a fixed 220 pt column
   with a header ("Pages", count, close button) and a vertical `ScrollView` over a
   `LazyVGrid(.adaptive(minimum: 84, maximum: 120))`, so a regular-width iPad shows two columns. Cells keep
   the existing lazy/off-main rendering and current-page ring; the page number sits under each cell.
   The current page is scrolled to `.center` on appear and when `session.pageIndex` changes. The last tile is
   "+ Page" (`session.addPage()`).
2. **Right by default, left on request.** `noteapp.settings.pagesPanelOnLeft` (`AppSettings.Key.pagesPanelOnLeft`)
   drives the side; Settings → Writing → "Pages Panel on Left" toggles it. The open/closed state keeps using the
   existing `noteapp.editor.showsThumbnails`, so it survives relaunch.
3. **Compact width presents the sheet.** At `.compact` horizontal size (1/3 split, Slide Over) the same grid is
   shown as a sheet instead of squeezing the page. The remembered-open flag never auto-opens that sheet; it
   waits for a Pages tap.
4. **The right edge is shared with search.** Opening the panel on the right closes search, and opening search
   closes the panel. On the left they can coexist.
5. **Undo and Redo leave the default toolbar.** `.undo` and `.redo` are opt-in `ToolbarItemID` cases appended at
   the end of the enum and are not in `defaultItems`. They remain available in Customize Toolbar and render as
   plain buttons in the tools group. ⌘Z / ⇧⌘Z stay as hidden buttons in `toolShortcuts`, disabled in Read Only;
   the two-finger double-tap undo is unchanged.
6. **No new panel features.** No drag reorder, multi-select or page deletion in this pass.

## Consequences

- The page column regains the strip's height and the toolbar's leading group has only Back and the Pages toggle.
- Removing the last toolbar item still yields a pen-only toolbar ([[2026-11-13-customisable-toolbar]]).
- Both this branch and the uncommitted `fix/folders-pdf-import` work touch `NotebookView.swift`; merge
  `feat/pages-side-panel` into `fix/folders-pdf-import` after the user commits that branch.
- The sidebar toggle icon is `sidebar.trailing` / `sidebar.leading` to match the panel side.

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
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Wave 4 lands eight research-backed feature sets on foundation-base](2026-11-13-wave4-feature-build.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
