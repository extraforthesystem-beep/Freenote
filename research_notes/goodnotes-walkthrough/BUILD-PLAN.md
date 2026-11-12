# Build plan — features from the Goodnotes walkthrough

Written 2026-11-12. Source: `WALKTHROUGH.md` in this folder. Branch `fix/ui-basics` (uncommitted work present — no worktrees, no commits by delegates).

## Wave 1 — three DeepSeek V4.1 Flash delegates in parallel, disjoint files

| Delegate | Features | Owns (only these may change) |
|---|---|---|
| D1 Editor tools | One-key tool shortcuts + shortcut in tooltips; Read-Only mode toggle; Ruler (PencilKit `isRulerActive`); Laser pointer (dot / fading line, never saved); eraser Auto-Deselect | `NoteApp/Notebook/EditorToolState.swift`, `EditorToolbar.swift`, `EditorOverlays.swift`, `NotebookView.swift`, `ZoomablePageView.swift`, `Packages/InkKit/Sources/InkKit/PencilCanvasView.swift`, new files under `NoteApp/Notebook/` prefixed `Laser` |
| D2 Sticky notes + Tape | New element kinds `sticky` and `tape`; backward-compatible codec; rendering; tape tap-to-reveal; session insert APIs | `Packages/NoteCore/.../Model/PageElement.swift` (+ tests), `Packages/InkKit/.../PageElementRenderer.swift` (+ tests), `NoteApp/Notebook/PageElementViews.swift`, `ElementEditLayer.swift`, `NotebookSession.swift` |
| D3 Search results | Global search grouped by notebook and source (handwriting / typed / PDF) with page chips and text snippet, matched term highlighted; a standalone in-notebook search panel view | `NoteApp/Search/*`, `Packages/SearchKit/**`, search section of `NoteApp/Library/LibraryView.swift`, new `NoteApp/Search/NotebookSearchPanel.swift` |

Main session afterwards: wire sticky/tape into the Insert menu and the search panel into the editor; build iPad + macOS; run package tests; review diffs.

**Wave 1 status (2026-11-12): done, uncommitted.** iPad + macOS builds succeed; 380 package tests pass. Checked by hand on the iPad simulator: sticky note insert, tape insert, tape hides ink and survives relaunch, tap-to-reveal, Read Only disables tools, search panel opens as an inspector. Not checked by hand: laser pointer drawing, ruler, single-key shortcuts, eraser auto-deselect, library search result cards with real handwriting.

## Wave 2 (after review)

- Draw-and-hold shape recognition (hard → Opus medium).
- Lasso actions: cut / copy / duplicate / delete, Convert → Text with editable preview.
- Eraser filter by tool and object eraser.
- Time Keeper, toolbar customisation, colour history.

## Wave 3 — from the More menu / Settings pass (WALKTHROUGH §8b)

- App **Settings** screen (Document Editing: page number, scroll direction, open as tabs; Handwriting recognition on/off and language; Troubleshooting: rebuild thumbnails and search index).
- Page **Rotate** (90° / 180°), **Clear Page**, **Delete Specific Items** by kind.
- **Page size and orientation** (A4, A5, Letter, Custom; portrait/landscape) in the template sheet; **default template** for new notebooks.
- Horizontal page scrolling option; on-page page number.
- Later: spellcheck for typed text, notebook lock (Keychain + Face ID).

**Wave 3 status (2026-11-12): done, uncommitted.** Delegates D4 (Settings), D5 (page operations, 9 new NoteCore tests), D6 (size picker, Delete Specific Items, Go to Page); main session wired the editor More menu and the on-page number. iPad + macOS builds succeed; all package tests pass. Checked on the iPad simulator: Settings sheet, page number, Rotate 90° and back (ink, elements and PDF move together), Delete Specific Items counts. Not checked by hand: Clear Page, resizing pages, Go to Page sheet, Rebuild Search Index / Regenerate Thumbnails, Open as New Tabs off, new-notebook defaults. Dropped: horizontal scrolling (the editor shows one page at a time).
