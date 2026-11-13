# Wave 4 build plan — from research_notes/studies/00–06

Source reports: `00-gap-audit.md` (95 missing, 20 partial, 15 half-built), `01`–`06` (study-backed ideas). All 93 DOIs cited resolve (Crossref/doi.org check, 2026-11-13).

## Rules for every build agent

- Work only in your own worktree on your own branch `feat/w4-<id>`. Do not merge or push. Commit with `feat:`/`fix:`/`test:` messages, imperative, under 70 chars. No `print`/`console.log` left in.
- Stay inside the files you own (list below). If you must touch a shared file (`NotebookView.swift`, `EditorToolbar.swift`, `EditorToolState.swift`, `AppModel.swift`, `NotebookSession.swift`), keep the change small and additive (new method / new case / one call site) so it merges cleanly.
- Smallest change that works. Reuse what exists; no new dependencies.
- Data is the source of truth: never change the on-disk page/notebook format without a version bump and a decoder that still reads old files. Add a round-trip test for any format change.
- Verify before you finish: build the iPad app for the simulator and run the affected package tests. Report the exact commands and results. If something fails, say so.
  - Packages: `cd Packages/<Pkg> && swift test 2>&1 | tail -20`
  - App: `xcodebuild -project NoteApp.xcodeproj -scheme NoteApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build 2>&1 | grep -E 'error|warning: unre|BUILD' | head -30`
- Final message: branch, head SHA, what is done, what is not, test output summary, any risk.

## Wave 4a — run in parallel

| ID | Name | Agent | Scope (in order) | Owns | Research |
|---|---|---|---|---|---|
| A | Selection model + lasso actions | Opus 5.5 medium | Replace bare `PKLassoTool` use with an inspectable selection (selected stroke IDs + element IDs). Actions on a selection: recolour, change width, duplicate, delete, copy/paste (same page, other page, other notebook via pasteboard), Copy as Text / Convert to Text box (uses `recognizedText` from SearchKit). One undo step each. | `PencilCanvasView.swift`, new `NoteApp/Notebook/Selection*.swift`, lasso parts of `EditorToolState.swift` | 00 #2/#3/#9, 02 #5/#6, 03 #3 |
| B | Durability + backup | Opus 5.5 medium | 1) verify-after-write (re-decode + SHA-256 recorded); 2) quarantine undecodable page + open notebook + restore banner via HistoryKit; 3) autosnapshot before destructive ops (clear page, delete items, PDF replace); 4) "Back up now" `.noteappbackup` archive (JSON + assets + manifest.sha256) and verified restore into a library; 5) keep-iPad-awake setting. | `Packages/NoteCore/Sources/NoteCore/Store/*`, `Packages/HistoryKit`, new `NoteApp/Backup/*` | 06 #1/#3/#4/#15, 00 #11/#15 |
| C | AI + search correctness | DeepSeek | 1) AI reads `recognizedText` (single best), index keeps `indexableContent`; 2) show AI citations, tap → page + highlight via `pageMarks`; 3) Vision OCR fallback when `pdfPage.string` empty; 4) Core Spotlight indexing; 5) auto-title suggestion for untitled notebooks; 6) re-run recognition on `recognitionVersion` change with a small notice. | `Packages/SearchKit`, `Packages/AIKit`, `NoteApp/AI/*`, `NoteApp/Search/*` | 03 #1/#2/#4/#8/#11/#14 |
| D | Audio replay | DeepSeek | Wire `PlaybackController`: tap a stroke during/after a recording → seek to its time; now-playing marker; optional "follow mode" fading strokes written after the playhead; transcript per clip via `SpeechTranscriber`, tap a line to seek, transcript text into the search index. | `Packages/AudioKit`, `NoteApp/Audio/*`, one hook in canvas tap handling | 00 #4, 04 #1/#10/#11 |
| E | Study engine | DeepSeek | 1) FSRS scheduler alongside SM-2 (migrate state, keep 4 grade buttons); 2) recall-first review (think/write, then reveal; no bare "Show Answer"); 3) one due queue across sets + "N due" badge in library; 4) "Review this notebook/page" entry from notebook; 5) populate `sourceNotebookID/sourcePageID` and jump back from a card; 6) tape study mode (reveal all / count); 7) leech handling at 4 lapses. | `Packages/StudyKit`, `NoteApp/Study/*` | 01 #3/#4/#5/#10/#12 |
| F | Ink tools | DeepSeek | 1) stroke smoothing/stabilisation, per tool, setting 0–100; 2) dashed/dotted stroke style; 3) scratch-out erase with on/off setting (off by default), one undo step; 4) hold-to-shape keeps taper + adds arrow/pentagon/hexagon/rhombus; 5) highlighter straight-line mode; 6) eraser filter by tool (pen/highlighter/shape) — finishes the existing tooltip promise. | `Packages/InkKit` (HoldToShape, ShapeRecognizer, StrokeOutline, codec), pen settings UI | 00 #1/#6/#7/#8/#13, 02 #1/#3/#4 |
| G | Navigation + library | DeepSeek | 1) page history back/forward in a notebook (⌘[ ⌘], chevrons); 2) "Continue" rail: last ~8 pages written on; 3) page overview grid (all pages, number, title, bookmark); 4) tags sidebar with counts + tag filter + `tag:` search filter; 5) `lastOpenedAt` + "Last opened" sort; 6) named bookmarks stored in the notebook folder (migrate from UserDefaults) + "Pinned pages" list. | `NoteApp/Library/*`, `PageBookmarks.swift`, `PageOutline.swift`, `goToPage` in `NotebookSession`, `AppModel` (sort/recents only) | 04 #2/#3/#4/#5/#9/#16 |
| H | PDF reading + templates | DeepSeek | 1) writing margin on PDF import (None/Left/Right/Both); 2) dim PDF paper on dark paper (never invert text); 3) PDF link back/forward; 4) custom page templates from PDF/PNG (import, name, picker section); 5) reading/focus mode extending Read Only (hide chrome, tap zones to turn pages); 6) PDF link hit tolerance 44 pt. | `NoteApp/Import/*`, `PageBackground.swift`, `PDFLinkHandler.swift`, `PageTemplates.swift` | 05 #1/#6/#7/#12/#16, 00 #5/#14 |

## Wave 4b — after A merges (selection model needed)

- I. Lasso → study card (ink crop front/back) + cloze by hiding strokes + highlight → card (01 #1/#2, 05 #4).
- J. Annotation recap panel + backlink mark → source region (05 #2/#3) + excerpt capture.
- K. Hybrid semantic search (NLEmbedding re-rank) + grounded notebook Q&A with page citations (03 #5/#6/#10).
- L. Shape-on-lift ghost + self-closing lasso + lasso command ring (02 #2/#5/#6).

## Wave 5 — sync (after B)

SyncKit per `06-sync-durability.md`: object store + `head.json`, iCloud Drive transport, per-page set-merge (UUID union, tombstones win), conflict-version adoption, delete epochs, sync status surface. Opus for the merge core; DeepSeek for UI.

## Deferred

Mac ink editing, page↔page backlinks, maths→LaTeX, diagram/table recognition, handwriting beautification, collaboration.
