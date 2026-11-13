---
type: decision
title: Live ink renders at its own zoom through a counter-scaled host
status: accepted
updated: 2026-11-13
---

# ADR: Live ink renders at its own zoom through a counter-scaled host

- **Status:** accepted
- **Date:** 2026-11-13
- **Branch:** `fix/sharp-ink-zoom` (commit `6bf87d9`, worktree `.claude/worktrees/sharp-ink-zoom`)

## Context

Ink looked blurry when zoomed in to write. The page is zoomed by an outer `UIScrollView` transform, and the live `PKCanvasView` had its own zoom locked to 1, so its 1× bitmap was stretched. Setting `contentScaleFactor` does not make PencilKit re-render (Apple forums 698317, 757202, 792941). PencilKit only redraws sharply for its own `zoomScale`, as Apple Notes/Freeform do and as Zoom View already did.

## Decisions

1. `PencilCanvasView` returns `InkCanvasHost` (page-sized, keeps z-order with paper/elements); the `InkCanvasView` inside is sized in screen points, given the zoom as its own `zoomScale` via `renderViewport`, and shrunk back by a `1/k` transform.
2. `InkRenderViewport` (pure, tested): whole page while it fits a 12 Mpx budget; past it, the visible page plus a 25% margin, clamped to the page.
3. The host observes ancestor scroll views (KVO): it re-places the canvas as soon as the visible part leaves the rendered rect, and re-zooms ~0.12 s after scrolling settles. Never mid-stroke (deferred to tool lift).
4. Zoom View canvases (`viewport` set) are not managed; they already zoom themselves.
5. Keep PencilKit; no custom engine (GoodNotes/Notability-style engines are months of work).

## Consequences

Sharp ink at any zoom on notebook pages and whiteboards; brief stretch during a pinch. Inactive pages are still cached images capped at 3× ([[2026-11-12-page-scroll-live-canvas]]). Device latency/memory and lasso/ruler/eraser behaviour still need a hands-on check.

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
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
