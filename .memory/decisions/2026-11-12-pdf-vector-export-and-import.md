---
type: decision
title: PDF export is vector; import rewrites only when it must
status: accepted
updated: 2026-11-12
---

# ADR: PDF export is vector; import rewrites only when it must

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `feat/toolbar-qol`

## Context

Export rasterised every page (blurry, large, no text, not editable elsewhere). Import ignored ranges, passwords, outlines and existing annotations.

## Decisions

1. **Export draws vector content** (`VectorPageRenderer`, `VectorPDFExport`): imported pages via `drawPDFPage`, templates/shapes as paths, text via Core Text, ink as filled outlines (`StrokeOutline`) using measured PencilKit size→width tables. Only images are raster.
2. **Editable mode** writes one PDF `.ink` annotation per stroke on an ink-free page. Annotation author is cleared (PDFKit otherwise stamps the device owner's name). Outline is written via Core Graphics.
3. **Exports are always light**: page renders run under a light trait; Dark Paper never reaches export.
4. **Import** copies the PDF once (content-hash asset). Locked PDFs, or PDFs whose `.ink` annotations were converted to strokes, are stored as a rewritten unencrypted copy; the password is never stored. The PDF outline maps to device-local `PageOutline`.
5. **Renderer draws markup annotations** (highlight, underline, strike-out, notes, shapes, stamps, unconverted ink); links, widgets and popups are skipped.

## Consequences

Pencil-texture inks and chisel nibs are approximated in export. Rewritten copies lose the PDF's embedded outline.

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
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
