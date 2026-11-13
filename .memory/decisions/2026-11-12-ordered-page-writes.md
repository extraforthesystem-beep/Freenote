---
type: decision
title: Page saves go through one ordered write queue
status: accepted
updated: 2026-11-12
---

# ADR: Page saves go through one ordered write queue

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `fix/ui-basics` (uncommitted)

## Context

The notebook autosave was a 400 ms debounce, while element, layer and restore edits wrote at once. An older debounced ink snapshot could land after a newer edit and revert it on disk. Nothing flushed the debounce when leaving a notebook or backgrounding the app.

## Decision

1. The in-memory page in `NotebookSession` is the truth. Every edit queues the whole page, and writes run strictly in order, each waiting for the one before (`commitPendingSave` chains on `writeChain`).
2. `flushPendingSave()` awaits all queued writes and is called when leaving the notebook, closing a tab, and on `scenePhase` leaving `.active`, inside a background task.
3. Failures set `NotebookSession.errorMessage`, keep the page pending and retry on the next save; there are no silent catches.

## Consequences

- A stale snapshot can no longer overwrite a newer edit.
- Known gap: if a save fails and the user then edits another page, the first page's unsaved state is replaced.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Advanced search uses Apple's ink engine; query syntax lives in SearchKit](2026-11-12-advanced-search.md)
- [Dark mode keeps white paper unless Dark Paper is on](2026-11-12-dark-mode-paper.md)
- [Physical iPad installs use the personal team and automatic signing](2026-11-12-device-install-signing.md)
- [GoodNotes parity build and page format v2](2026-11-12-goodnotes-parity-build.md)
- [Page bookmarks stay app-side](2026-11-12-page-bookmarks-app-side.md)
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
