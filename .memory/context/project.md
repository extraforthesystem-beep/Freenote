---
type: context
title: NOTEAPP project context
status: active
updated: 2026-11-13
---

# NOTEAPP

Personal handwritten-notes app for iPad, with a Mac companion. Personal use only; no App Store release.

## Stack

- Swift 6.4.2, Xcode 27.2, iOS 27 / macOS 27, SwiftUI.
- PencilKit (drawing, undo, recognition), PDFKit, CoreText, ImageIO, CryptoKit.
- Swift Testing for packages.
- Local packages: `NoteCore`, `InkKit`, `SearchKit`, `SyncKit` (empty), `AudioKit`, `StudyKit`, `AIKit`, `BoardKit`, `HistoryKit`, `TextDocKit` (all committed).

## State

- Branches: main checkout `integrate/foundation-base` (`a8a7d13`; research notes + foundation reports `d1ba21e`, sharp-ink and first-stroke merges). `fix/folders-pdf-import` holds device bug fixes (uncommitted, off `feat/advanced-search`). `feat/advanced-search` holds toolbar QoL, PDF, dark mode, perf and search (`4a27893`); `feat/toolbar-customize` (`ecd7e6c`, `82bf0d6`) and `feat/pages-side-panel` (`ae06ed8`, `1e54e65`, `1a528c7`) build on it in worktree `t3-87bf97db-…`. No git remote; delegated work merges from per-package worktree branches.
- iPad simulator: iPad Pro 11-inch (M5), iOS 27.2, bundle `local.noteapp.NoteApp`.
- Physical iPad (9th gen, 27.2.1): Developer Mode on; team `CQ65B26KFJ`; builds in `build/device` ([[2026-11-12-device-install-signing]]).
- Files are the source of truth. Page files are JSON+zlib under `Library/notebooks/<id>/pages/`; caches (thumbnails, search, drawings) are rebuildable.

## Key paths

- `NoteApp/Notebook/NotebookView.swift` — tabs, split panes, page chrome; toolbar in `EditorToolbar.swift` (items/persistence `ToolbarLayout.swift`, editor `ToolbarEditorView.swift`, branch `feat/toolbar-customize`), tool state in `EditorToolState.swift`, palettes in `ColorPalettePopover.swift`/`FavoritePens.swift`.
- `NoteApp/Notebook/PagesSidePanel.swift` — side page grid (right default, `noteapp.settings.pagesPanelOnLeft`, sheet at compact width); replaces the bottom `PageThumbnailStrip`.
- `NoteApp/Notebook/ContinuousPagesView.swift` — seamless/single-page scroll, one live canvas, first-stroke capture; `ZoomWindowView.swift` — Zoom View.
- `NoteApp/Import/PDFImportFlow.swift`, `NoteApp/Export/PDFExport.swift` — PDF import flow and vector/editable export.
- `NoteApp/Notebook/NotebookSession.swift` — open page, ordered save queue, layers, elements, history snapshots.
- `NoteApp/Notebook/PageBookmarks.swift` — app-side bookmarks.
- `NoteApp/Notebook/PDFLinkHandler.swift` — PDF annotation hit-testing.
- `NoteApp/AppModel.swift` — library, tabs, search, import, sort, trash expiry.
- `Packages/NoteCore` — document model and store.
- `Packages/InkKit/Sources/InkKit/InkCanvasHost.swift` + `InkRenderViewport.swift` — live ink re-rendered at the seen zoom ([[2026-11-13-sharp-ink-zoom]]; branch `fix/sharp-ink-zoom`).
- `Packages/InkKit` — stroke codec, page/template/element renderer, canvas, `VectorPageRenderer`/`StrokeOutline` (vector PDF), `HoldToShape`/`ShapeRecognizer`, `ZoomBand`, `PDFImportConversion`.
- `Packages/SearchKit` — handwriting index, `SearchQuery` syntax/filters, `PageMatchLocator`.
- `NoteApp/Search/` — library/notebook search, Pencil pad and page-mark overlay.
- `research_notes/goodnotes-walkthrough/` — live Goodnotes reference; `research_notes/competitors/` — GoodNotes/Notability/Noteshelf/others/community research (uncommitted).
- `TOOLBAR-QOL-PLAN.md`, `TOOLBAR-CUSTOMIZE-PLAN.md`, `PAGES-SIDE-PANEL-PLAN.md` (plans + device checklists); `reports/foundation-2026-11-13/` and `research_notes/studies/` (audit + research, committed `d1ba21e`); app tests in `NoteAppTests/` (XCTest), `PERFORMANCE-NOTES.md` (profiling checklist).

## Open decisions

- Phase 3 Google Drive needs a Google Cloud project and explicit approval.
- Physical iPad and developer team are set up; P0.3/P1.4/P1.7 hands-on checks still pending.

<!-- harness-links:autogen -->
## Graph links

- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
