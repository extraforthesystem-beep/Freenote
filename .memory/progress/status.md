---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-12
---

# Status — 2026-11-12

## Done

- Phase 0 scaffold, simulator, S1 stroke round trip (H1 confirmed visually lossless).
- NoteCore: model, page format, atomic store. 34 tests.
- InkKit: eight pens, codec, template/element/PDF renderer, canvas, erasers, lasso. 20 tests.
- SearchKit: handwriting + typed-text index/search. 12 tests.
- App: library, folders, tags, trash, covers; pages, templates, thumbnails, autosave; PDF import; text/image/shape elements; PDF export; search with page jumping.
- This session: notebook tabs, split view, page bookmarks, PDF link taps with a hand/link mode. External link verified opening Safari; internal GoTo not verified with a valid test PDF.
- Source material folded in: `PLAN.md`, `reports/iPad note app feature plan.md`, Claude memory notes (all already reflected above).

## In progress / caution

- Another active T3 thread is implementing GoodNotes parity in the same tree (highlighter, layers, outline, zoom, audio, study, AI, whiteboard). Its work and this session's tab/bookmark/split/link work are uncommitted; last commit is `5fb4841`. Do not revert or mass-commit without coordination. Source snapshot: `/private/var/folders/kf/g90yn04s77vg8_sjmtt7zrmm0000gn/T/opencode/noteapp-snapshot-1605`.

## Next

1. Let the parity thread finish; verify iOS/macOS builds and tests, then commit the combined tree.
2. Physical iPad: signing, palm rejection, Pencil gestures, lasso move/copy.
3. Phase 3 Drive: blocked on the user's Google Cloud OAuth client and approval.
4. Mac annotation (PaperKit); Phase 5 audio/math/AI; Phase 6 custom engine.

## Handoff

- Key files this session: `NoteApp/Notebook/NotebookView.swift`, `AppModel.swift`, `PageBookmarks.swift`, `PDFLinkHandler.swift`, `Packages/InkKit/Sources/InkKit/PencilCanvasView.swift`.
- The tree is shared with the parity thread; check `git status` and mtimes before editing.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
