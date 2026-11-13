---
type: decision
title: Editor toolbar is customisable and only the colours scroll
status: accepted
updated: 2026-11-13
---

# ADR: Editor toolbar is customisable and only the colours scroll

- **Status:** accepted
- **Date:** 2026-11-13
- **Extends:** [[2026-11-12-page-operations-and-settings]] (settings live in UserDefaults)
- **Plan:** `TOOLBAR-CUSTOMIZE-PLAN.md`; branch `feat/toolbar-customize` (`ecd7e6c`, `82bf0d6`).

## Context

The single toolbar row fell back to one horizontal `ScrollView` for tools, colours and widths, so in split view the pen chip and width dots slid away. Ten tool buttons were always shown with no way to hide or reorder them.

## Decisions

1. **Only the colour favourites scroll.** Pen chip, palette button and width presets are always fixed. When tools do not fit, they collapse into a "More Tools" overflow menu (`ViewThatFits` stages), never a scroll.
2. **Layout is a list of `ToolbarItemID`s** in `NoteApp/Notebook/ToolbarLayout.swift`, stored as a comma-separated string under `toolbar.items.v1` (`@AppStorage`). The pen chip is not an item and cannot be removed. Unknown/duplicate ids are dropped; an empty string means pen-only; a non-empty unusable string falls back to the defaults.
3. **Default items:** highlighter, eraser, lasso, elements, insert. Laser, Zoom View, Follow Links, Favourite Pens star and new items (ruler, shapes, text box, image, sticky note, add page, search) are opt-in via the Customize Toolbar sheet (`ToolbarEditorView`).
4. **Toolbar stays decoupled from `NotebookSession`:** optional items reach existing actions through `onItemAction` and an `itemMenu` view builder passed from `NotebookView`.
5. **Read Only moved to the More menu** (still view state only, per [[2026-11-12-sticky-tape-and-search-hits]]); while on, the tools are replaced by the Read Only pill.
6. **Favourite pens live in the pen settings popover** (`FavoritePensContent`), the star is optional.
7. **App test target `NoteAppTests`** (XCTest, hosted by the app) plus shared schemes `NoteApp` and `NoteAppTests` were added; packages keep Swift Testing.

## Consequences

- Keyboard tool shortcuts work whether or not an item is shown.
- Width presets are global, so tapping a dot only sets the width (no per-preset tuning).
- Colour strip has no minimum width; at 1/3 split it may show fewer than three swatches.

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
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
