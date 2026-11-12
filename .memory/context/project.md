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
- Local packages: `NoteCore`, `InkKit`, `SearchKit`, `SyncKit` (empty), `AudioKit`, `StudyKit`, `AIKit`, `BoardKit`, `HistoryKit`, `TextDocKit` (parity packages still uncommitted).

## State

- Branch `fix/ui-basics` (from `feat/phase-0`); last committed state `5fb4841`; the tree holds the uncommitted parity build plus the UI/basics fix pass.
- iPad simulator: iPad Pro 11-inch (M5), iOS 27.2, bundle `local.noteapp.NoteApp`.
- Files are the source of truth. Page files are JSON+zlib under `Library/notebooks/<id>/pages/`; caches (thumbnails, search, drawings) are rebuildable.

## Key paths

- `NoteApp/Notebook/NotebookView.swift` — tabs, split panes, page chrome; toolbar in `EditorToolbar.swift`, tool state in `EditorToolState.swift`.
- `NoteApp/Notebook/NotebookSession.swift` — open page, ordered save queue, layers, elements, history snapshots.
- `NoteApp/Notebook/PageBookmarks.swift` — app-side bookmarks.
- `NoteApp/Notebook/PDFLinkHandler.swift` — PDF annotation hit-testing.
- `NoteApp/AppModel.swift` — library, tabs, search, import, sort, trash expiry.
- `Packages/NoteCore` — document model and store.
- `Packages/InkKit` — stroke codec, page/template/element renderer, canvas.
- `Packages/SearchKit` — handwriting index and search.
- `research_notes/goodnotes-walkthrough/` — live Goodnotes reference (`WALKTHROUGH.md`, screens) and the feature build plan (`BUILD-PLAN.md`).

## Open decisions

- Phase 3 Google Drive needs a Google Cloud project and explicit approval.
- Physical iPad and Apple developer team still needed for P0.3/P1.4/P1.7.

<!-- harness-links:autogen -->
## Graph links

- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
