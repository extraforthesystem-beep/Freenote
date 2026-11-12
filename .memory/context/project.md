---
type: context
title: NOTEAPP project context
status: active
updated: 2026-11-12
---

# NOTEAPP

Personal handwritten-notes app for iPad, with a Mac companion. Personal use only; no App Store release.

## Stack

- Swift 6.4.2, Xcode 27.2, iOS 27 / macOS 27, SwiftUI.
- PencilKit (drawing, undo, recognition), PDFKit, CoreText, ImageIO, CryptoKit.
- Swift Testing for packages.
- Local packages: `NoteCore`, `InkKit`, `SearchKit`, `SyncKit` (empty), `AudioKit`, `StudyKit`, `AIKit`, `BoardKit`, `HistoryKit`, `TextDocKit` (all committed on `feat/toolbar-qol`).

## State

- Branch `feat/toolbar-qol` (from `fix/ui-basics`, checkpoint `d07671b`); head `91c0b77`, not pushed. Delegated work merges here from per-package worktree branches.
- iPad simulator: iPad Pro 11-inch (M5), iOS 27.2, bundle `local.noteapp.NoteApp`.
- Files are the source of truth. Page files are JSON+zlib under `Library/notebooks/<id>/pages/`; caches (thumbnails, search, drawings) are rebuildable.

## Key paths

- `NoteApp/Notebook/NotebookView.swift` — tabs, split panes, page chrome; toolbar in `EditorToolbar.swift`, tool state in `EditorToolState.swift`, palettes in `ColorPalettePopover.swift`/`FavoritePens.swift`.
- `NoteApp/Notebook/ContinuousPagesView.swift` — seamless/single-page scroll, one live canvas, first-stroke capture; `ZoomWindowView.swift` — Zoom View.
- `NoteApp/Import/PDFImportFlow.swift`, `NoteApp/Export/PDFExport.swift` — PDF import flow and vector/editable export.
- `NoteApp/Notebook/NotebookSession.swift` — open page, ordered save queue, layers, elements, history snapshots.
- `NoteApp/Notebook/PageBookmarks.swift` — app-side bookmarks.
- `NoteApp/Notebook/PDFLinkHandler.swift` — PDF annotation hit-testing.
- `NoteApp/AppModel.swift` — library, tabs, search, import, sort, trash expiry.
- `Packages/NoteCore` — document model and store.
- `Packages/InkKit` — stroke codec, page/template/element renderer, canvas, `VectorPageRenderer`/`StrokeOutline` (vector PDF), `HoldToShape`/`ShapeRecognizer`, `ZoomBand`, `PDFImportConversion`.
- `Packages/SearchKit` — handwriting index and search.
- `research_notes/goodnotes-walkthrough/` — live Goodnotes reference; `research_notes/competitors/` — GoodNotes/Notability/Noteshelf/others/community research (uncommitted).
- `TOOLBAR-QOL-PLAN.md` (plan + device checklist), `PERFORMANCE-NOTES.md` (profiling checklist).

## Open decisions

- Phase 3 Google Drive needs a Google Cloud project and explicit approval.
- Physical iPad and Apple developer team still needed for P0.3/P1.4/P1.7.

<!-- harness-links:autogen -->
## Graph links

- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
