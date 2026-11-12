# ADR: GoodNotes parity build and page format v2

- **Status:** accepted
- **Date:** 2026-11-12
- **Branch:** `feat/phase-0` (uncommitted)

## Context

The app already stored its own stroke records and one-layer pages. Matching GoodNotes required highlighter, layers, movable elements, rich text, audio, study, text documents, whiteboards and AI without replacing the file-truth model.

## Decisions

1. **Page format v2 is additive and backward-compatible.** `StrokeTool.isHighlighter`, `PageElement.isLocked`/`textStyle`, and `Page.deletedElementIDs` decode as defaults when absent. Unknown schema versions are still refused.
2. **Highlighter is a marker stroke with a stored flag.** PencilKit has no highlighter ink; `isHighlighter` plus a translucent colour is the durable representation. Stored/exports sort highlighter strokes before pen ink; live PencilKit drawing remains append-only until reload.
3. **History is local-only.** `VersionHistoryStore` lives outside the synced Library; snapshots are unencrypted and pruned on launch.
4. **New document types use sidecar folders under the Library.** Text docs: `TextDocs/`; boards: `Boards/`; study sets: `StudySets/`. They are not notebook pages and do not enter the page merge path.
5. **Engine packages stay UI-free.** StudyKit, AudioKit, BoardKit, TextDocKit, AIKit, HistoryKit are linkable, tested modules; app views own presentation and integration.
6. **No commit during the build.** The user did not ask for one; all changes remain in the working tree.

## Consequences

- Sync/backup must understand element tombstones before document types ship.
- A future restyle/Smart Ink feature can operate on `StrokeRecord` without changing the stored truth.
- The highlighter layering limitation is explicit in `BUILD-STATUS.md`.
