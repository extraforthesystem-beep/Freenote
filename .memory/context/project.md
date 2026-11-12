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
- Local packages: `NoteCore`, `InkKit`, `SearchKit`, `SyncKit` (empty), plus uncommitted parity packages from a parallel thread: `AudioKit`, `StudyKit`, `AIKit`, `BoardKit`, `HistoryKit`, `TextDocKit`.

## State

- Branch `feat/phase-0`; last committed state `5fb4841`; the tree contains uncommitted tab/bookmark/split/PDF-link work and a parallel GoodNotes-parity implementation.
- iPad simulator: iPad Pro 11-inch (M5), iOS 27.2, bundle `local.noteapp.NoteApp`.
- Files are the source of truth. Page files are JSON+zlib under `Library/notebooks/<id>/pages/`; caches (thumbnails, search, drawings) are rebuildable.

## Key paths

- `NoteApp/Notebook/NotebookView.swift` — tabs, split panes, page chrome.
- `NoteApp/Notebook/PageBookmarks.swift` — app-side bookmarks.
- `NoteApp/Notebook/PDFLinkHandler.swift` — PDF annotation hit-testing.
- `NoteApp/AppModel.swift` — library, tabs, sessions, search, import.
- `Packages/NoteCore` — document model and store.
- `Packages/InkKit` — stroke codec, page/template/element renderer, canvas.
- `Packages/SearchKit` — handwriting index and search.

## Open decisions

- Phase 3 Google Drive needs a Google Cloud project and explicit approval.
- Physical iPad and Apple developer team still needed for P0.3/P1.4/P1.7.

<!-- harness-links:autogen -->
## Graph links

- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
