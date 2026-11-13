---
type: progress
title: NOTEAPP status
status: active
updated: 2026-11-13
---

# Status — 2026-11-13

## Done

- Phase 0–2 + parity checkpoint `d07671b` (`91c0b77` builds iPad + macOS); toolbar QoL, scroll modes, Zoom View, PDF vector export/import, dark mode + Dark Paper, perf notes.
- Advanced search `a354025`; sharp ink `59e29f9` ([[2026-11-13-sharp-ink-zoom]]).
- Customisable toolbar `82bf0d6` ([[2026-11-13-customisable-toolbar]]); pages side panel `1a528c7` ([[2026-11-13-pages-side-panel]]).
- iPad installs work (9th gen, team `CQ65B26KFJ`).
- **Wave 4** `0e02ec8` on `integrate/foundation-base` ([[2026-11-13-wave4-feature-build]]): eight feature sets from the study reports, built by parallel DeepSeek agents and merged one at a time.
  - A selection model + lasso actions (recolour, width, duplicate, delete, copy/paste, Copy as Text).
  - B durability: verify-after-write + `.sha256` sidecars, quarantine + restore banner, `.noteappbackup` create/verify/restore, Verify All Pages, keep-awake.
  - C AI/search: grounded AI on `recognizedText`, tappable citations, Vision OCR fallback, Core Spotlight, auto-title, re-read notice.
  - D audio replay: tap a stroke to seek, now-playing bar/marker, Follow fade, per-clip transcripts in search.
  - E study: FSRS beside SM-2 with lossless migration, recall-first review, one due queue + badge, notebook review, tape mode, leeches.
  - F ink: per-tool smoothing, dashed/dotted pens, scratch-out erase, arrow/pentagon/hexagon/rhombus shapes, highlighter straight lines, eraser filter.
  - G navigation: page back/forward, Continue rail, page overview grid, tags + `tag:` search, Last Opened sort, named bookmarks in `bookmarks.json`, pinned pages.
  - H PDF: writing margin, dimmed (not inverted) PDF paper on dark paper, PDF link back/forward, custom PDF/PNG templates, Reading Mode, 44 pt link tolerance.
  - Verified: app build green; NoteCore 110, InkKit 145, SearchKit 49, StudyKit 77, AudioKit 34, HistoryKit 62, BoardKit 5, TextDocKit 49 tests; 28 app tests.

## In progress / caution

- **Nothing in wave 4 has been walked on a physical iPad.** Highest-risk device checks: scratch-out single undo, dash rendering, highlighter straight lines, selection bar occluding the page, Reading Mode chrome, tap-to-seek (simulator inks a dot instead).
- Per-item gaps are listed in `research_notes/studies/WAVE4-STATUS.md`: Spotlight deep link, OCR mark boxes, auto-title in library, AI cards without source IDs, Reading Mode tab bar, image/PDF elements not copied by selection, backup scope (library only, no study/docs/boards/history), transcript hits draw no mark.
- `fix/folders-pdf-import` is still uncommitted work off `feat/advanced-search`; those fixes are not in the base.
- Detached `ipad-combined` snapshot needs its glue redone against the merged base.
- No git remote (no push/PR); removing finished worktrees (21+) and the stray booted simulator needs user OK.
- Open ADR question: highlighter export bends the PDF vector ADR.

## Next

1. Device pass on wave 4 (list above), then commit `fix/folders-pdf-import` and re-merge.
2. Wave 4b: lasso → study card, annotation recap + backlinks, hybrid semantic search, lasso command ring (needs the selection model that now exists).
3. Wave 5: SyncKit per `06-sync-durability.md` (object store + `head.json`, iCloud Drive, set-merge, conflict adoption) — B's backup work is the foundation.
4. User: set a git remote, then push/PR; decide whether the research notes stay committed.

## Handoff

- Delegates: DeepSeek V4.1 Flash default, Opus 5.5 medium for hard work; worktree per agent, main session reviews and merges.
- `feat/wave4` worktree: `~/.t3/worktrees/NOTEAPP/wave4-integration`.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
<!-- /harness-links:autogen -->
