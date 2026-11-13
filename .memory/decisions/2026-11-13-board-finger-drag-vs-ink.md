---
type: decision
title: A finger drag on a board object is decided at touch-down, before ink
status: accepted
updated: 2026-11-13
---

# ADR: A finger drag on a board object is decided at touch-down, before ink

- **Status:** accepted
- **Date:** 2026-11-13
- **Branch:** `integrate/foundation-base` (`743d8a5`, from `feat/freeform-board` `168387d`)

## Context

With "draw with finger" on, the canvas's drawing gesture owns every finger touch, so a selected board object could not be dragged. The previous drag pan was only enabled when finger drawing was off, and it decided after the pan slop — by then ink had already started.

## Decisions

1. `CanvasFingerInteraction` gains `onDragPossible`, asked at touch-down and required to be side-effect free.
2. InkKit's `FingerDragGestureRecognizer` begins only when that answer is true; it fails at once on empty canvas and on Pencil touches. The ink gesture requires the drag to fail only on a canvas that draws with any input, so ordinary strokes start without a delay.
3. `BoardEditorView.dragTarget(at:)` answers from the live selection and its resize handles. A drag that never moves saves nothing.
4. The dependency is installed when the canvas is made, from its then-current drawing policy; the app's draw-with-finger setting is changed outside an open board.

## Consequences

Finger drag moves or resizes the selected object with no stray ink, and empty-canvas drawing still inks immediately. The simulator always draws with any input, which covers this path; real Pencil + finger switching still needs a hands-on iPad check.

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
- [Boards open full screen on iPad; the Mac keeps a sheet](2026-11-13-board-full-screen.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Page thumbnails live in a side panel; Undo and Redo leave the default toolbar](2026-11-13-pages-side-panel.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Wave 4 lands eight research-backed feature sets on foundation-base](2026-11-13-wave4-feature-build.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
