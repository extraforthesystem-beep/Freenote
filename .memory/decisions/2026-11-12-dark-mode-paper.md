---
type: decision
title: Dark mode keeps white paper unless Dark Paper is on
status: accepted
updated: 2026-11-12
---

# ADR: Dark mode keeps white paper unless Dark Paper is on

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `feat/toolbar-qol`

## Decisions

1. **Theme** (System / Light / Dark) is an app setting applied with `preferredColorScheme` at the root.
2. **Paper stays white by default**: `InkCanvasView.overrideUserInterfaceStyle = .light`, so stored ink colours display unchanged.
3. **Dark Paper in Dark Mode** (off by default) is display-only: dark template recolour, canvas in `.dark` (PencilKit adapts ink), cached page images composite a dark sheet plus colour-inverted ink. Stored colours never change; exports ignore it.

## Consequences

Saturated inks may differ slightly between the live page and cached images on dark paper. Covers and whiteboards stay light.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [GoodNotes parity build and page format v2](2026-11-12-goodnotes-parity-build.md)
- [Page saves go through one ordered write queue](2026-11-12-ordered-page-writes.md)
- [Page bookmarks stay app-side](2026-11-12-page-bookmarks-app-side.md)
- [Page operations are pure NoteCore functions; app settings live in UserDefaults](2026-11-12-page-operations-and-settings.md)
- [One live canvas per notebook; other pages are cached images](2026-11-12-page-scroll-live-canvas.md)
- [PDF export is vector; import rewrites only when it must](2026-11-12-pdf-vector-export-and-import.md)
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
