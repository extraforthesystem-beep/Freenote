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

- Branch `integrate/foundation-base` @ `3c3d5ee`: `origin/main` merged; wave 4 (`0e02ec8`, [[2026-11-13-wave4-feature-build]]) and the freeform board (`743d8a5`, [[2026-11-13-board-full-screen]]). `fix/folders-pdf-import` still holds uncommitted device bug fixes (off `feat/advanced-search`).
- iPad simulator: iPad Pro 11-inch (M5), iOS 27.2, bundle `local.noteapp.NoteApp`.
- Physical iPad (9th gen, 27.2.1): Developer Mode on; team `CQ65B26KFJ`; builds in `build/device` ([[2026-11-12-device-install-signing]]).
- Files are the source of truth. Page files are JSON+zlib under `Library/notebooks/<id>/pages/`; caches (thumbnails, search, drawings) are rebuildable.

## Key paths

- `NoteApp/Notebook/NotebookView.swift` — tabs, split panes, page chrome; toolbar in `EditorToolbar.swift` (items/persistence `ToolbarLayout.swift`, editor `ToolbarEditorView.swift`, branch `feat/toolbar-customize`), tool state in `EditorToolState.swift`, palettes in `ColorPalettePopover.swift`/`FavoritePens.swift`.
- `NoteApp/Notebook/PagesSidePanel.swift` — side page grid (right default, `noteapp.settings.pagesPanelOnLeft`, sheet at compact width); replaces the bottom `PageThumbnailStrip`.
- `NoteApp/Notebook/ContinuousPagesView.swift` — seamless/single-page scroll, one live canvas, first-stroke capture; `ZoomWindowView.swift` — Zoom View.
- `NoteApp/Import/PDFImportFlow.swift`, `NoteApp/Export/PDFExport.swift` — PDF import flow and vector/editable export.
- `NoteApp/Notebook/NotebookSession.swift` — open page, ordered save queue, layers, elements, history snapshots.
- `NoteApp/Notebook/PageBookmarks.swift` — bookmarks (location under review, see Open decisions).
- `NoteApp/Notebook/Selection*.swift`, `SelectionActionBar` — lasso/element selection model and actions (wave 4 A).
- `NoteApp/Backup/` + `Packages/NoteCore/.../BackupArchive.swift`, `BackupRestore.swift` — `.noteappbackup` create/verify/restore, Verify All Pages (wave 4 B).
- `NoteApp/Study/` + `Packages/StudyKit/FSRSScheduler.swift`, `ReviewPass.swift` — FSRS beside SM-2, mixed due queue, leech (wave 4 E).
- `Packages/AudioKit/ReplayTarget.swift`, `TranscriptStore.swift` — stroke-time replay and per-clip transcripts (wave 4 D).
- `Packages/InkKit/StrokeSmoothing.swift`, `StrokeDash.swift`, `ScratchOut.swift`, `EraserFilter.swift` — wave 4 F ink tools.
- `NoteApp/Library/PageHistoryControls.swift`, `ContinueRail.swift`, `PageOverviewGrid.swift`, `PinnedPagesList.swift`, `PageRecents.swift` — wave 4 G navigation.
- `NoteApp/Notebook/PageTemplates.swift`, `PageTemplatePicker.swift`, `PDFLinkHistory` — wave 4 H templates, reading mode, link history.
- `NoteApp/Notebook/PDFLinkHandler.swift` — PDF annotation hit-testing.
- `NoteApp/AppModel.swift` — library, tabs, search, import, sort, trash expiry.
- `NoteApp/Boards/` — Freeform whiteboard: `BoardEditorView.swift` (canvas, selection, objects, camera), `BoardCanvasChrome.swift` (grid, zoom pill, selection bar), `BoardsView.swift` (library, full-screen iOS cover), `BoardThumbnail.swift`, model in `BoardModel.swift`; board storage is `Packages/BoardKit`.
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
- **Conflict to resolve:** wave 4 moved page bookmarks from `UserDefaults` into `notebooks/<id>/bookmarks.json` (code + migration done), which overrides [[2026-11-12-page-bookmarks-app-side]] — keep app-side / update the ADR / remove?

<!-- harness-links:autogen -->
## Graph links

- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
