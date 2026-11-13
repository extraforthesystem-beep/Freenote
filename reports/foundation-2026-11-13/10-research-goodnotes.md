# 10 — Competitor research: Goodnotes (late 2026)

Researched 2026-11-13 against Goodnotes 7.1.36 for iPad. The app dropped the "6"/"7" numbering in Sept 2025 and is now just "Goodnotes" `[3][6]`.

**Method.** Official help centre, product/pricing pages, release blogs, App Store listing, r/GoodNotes. This does not repeat `research_notes/competitors/goodnotes/SETTINGS-AND-GESTURES.md` (exact settings/gestures) or `GOODNOTES-PARITY-PLAN.md` (architecture gaps).

**Caveat on our column.** `.memory/features/index.md` is empty ("No feature specs yet"), so our status is read from the Swift sources and `.memory/progress/status.md`. Unverified on device = partial.

## 1. Feature table

| Feature | Goodnotes behaviour, late 2026 | Us |
|---|---|---|
| Pen types | Three types — Fountain (pressure), Ball (none), Brush — plus Tip Sharpness, Pressure, Tip Flatness, Stabilization sliders `[20]` | **Partial** — 8 PencilKit inks; no type taxonomy or dynamics controls |
| Pressure & tilt | Per-point force/azimuth/altitude; pressure "Min" still varies width `[20]` | **Yes** (PencilKit) |
| Colour/width | 3 slots default, 12 max, per-tool palettes, History tab `[20]` | **Yes** — favourites, recents, per-tool presets |
| Highlighter | Translucent, renders **under** ink, straight-line snap; typed-text highlight is a character attribute `[23]` | **Yes** — translucent marker under ink, highlighter-only erase |
| Eraser | Precision/Standard/Object, per-tool Erase Filter, Auto-Deselect `[20]` | **Partial** — stroke + pixel, filter; no object eraser |
| Ink latency | "Reduce Latency" uses predicted touches; Ball Pen uses fewer resources `[7][10]` | **Partial** — PencilKit default; no exposed control |
| Lasso | Freehand default, content allow-list, move/resize/rotate, object menu on close `[32]` | **Partial** — PencilKit lasso + move; no action menu or cross-page paste |
| Smart Ink | Cut/copy/paste, copy as text, recolour, insert space, straighten, align, **Restyle** keeping words/layout/colour `[4][12]` | **No** |
| Shapes | Shape tool, draw-and-hold snap, connectors that stay attached, Quick Diagramming from edge dots `[24]` | **Partial** — shapes + hold-to-shape; no connectors/quick diagram |
| Ruler | Both edges snap, two-finger rotate, units `[20]` | **Yes** — PencilKit ruler |
| Tape | Drawn strip, patterns, reveal with **finger only**, works in Read Only, inert in exported PDF `[25]` | **Partial** — tape + finger reveal; no patterns |
| Laser | Dot/trail, presentation only, writes nothing `[20]` | **Yes** |
| Sticky notes | Collapse to a pin, attach handwriting, comments `[20]` | **Partial** — sticky element; no collapse/thread |
| Layers | 5 fixed, active-layer scoping, hide, export visible only; Pro early access `[4]` | **Yes** — add/rename/reorder/hide/lock/delete |
| Zoom Window | Second viewport, auto-advance blue zone, return height in points, per-template `[20]` | **Partial** — Zoom View; no auto-advance/return height |
| Templates | Built-in sets, A3–A7/Letter/Tabloid/custom, colour/orientation, import custom (first page) `[20]` | **Partial** — 23 built-in + dark paper; no import |
| Text | Rich text, pin tool, save-as-default, full-page typing, links `[20]` | **Partial** — styled text; no lists/links/full-page |
| Elements/stickers | Collections, create Element from any lasso, GIPHY, marketplace `[2][4]` | **No** — images/shapes/text only |
| PDF | Import, annotate, text select/copy, links, TOC import, page reorder, editable export `[26]` | **Partial** — import, annotate, links, vector export; no text selection/reorder |
| Search | Handwriting + typed + PDF + titles + outline; **opt-in** index; PDFs without OCR unsearchable `[19]` | **Yes, stronger** — always-on, query syntax, source/date filters, page marks |
| Handwriting → text | Lasso → Convert → Text; 15+ languages `[20]` | **No** (recognition is search-only) |
| Spellcheck | Red underline on handwriting; suggestions; **redraws the fix in your own hand** `[27]` | **No** |
| Word Complete | **Discontinued 31 Mar 2025**, no replacement `[11]` | **No** (correctly not a gap) |
| Math Assist | Recognise equations, solve, teach, matrices, 2D graphs `[5]` | **Partial** — typed-expression evaluator only |
| Goodnotes AI | Q&A, summaries, mind maps, Create Mode, image generation; credit-metered `[2][3]` | **Partial** — page summary/ask/flashcards, on-device + deterministic fallback |
| AI typing | Rewrite, tone, shorten, grammar, bullets `[2]` | **Partial** — operations in AIKit; no full UI |
| Audio | Record while writing, Note Replay, speed, skip silence, replay customisation `[5][28]` | **Partial** — recording, monotonic anchor, SpeechAnalyzer; no tap-stroke-to-seek |
| Study sets | AI flashcards from handwriting, spaced repetition, quiz generator, exam prep `[2][6]` | **Yes** — sets, cards, SRS, CSV |
| Collaboration | Comments + presentation on shared docs (free); public links (Essential); private + real-time (Pro) `[2]` | **No** |
| Sync | iCloud (Apple) or Goodnotes Cloud; cross-platform library sync paid; turbo sync Pro `[2][8]` | **No** — `SyncKit` is a stub |
| Backup | Drive/Dropbox/OneDrive/WebDAV/Box, one-way, ~12 h `[2]` | **No** |
| Organization | Nested folders, colours/icons, favourites, trash, bookmarks, outline, QuickNote, tabs, multi-window, bulk ops `[20]` | **Partial** — folders, favourites, trash, bookmarks, outline, tabs; no bulk/QuickNote/folder colours |
| Export | PDF flattened/editable, images, Goodnotes doc, print, folder zip; free tier watermarked `[2][26]` | **Partial** — vector/editable PDF, PNG, ranges; no print/zip |
| Pencil Pro | Squeeze opens Palette (fixed); barrel roll affects Fountain only; hover previews stroke `[21][22]` | **Partial** — squeeze wired; no hover/barrel roll |
| Scribble | Apple Scribble separate from Goodnotes recognition `[20]` | **Partial** — system Scribble only |
| Platforms | iPad/iPhone/Mac/Windows/Android/Web; 15 languages; ~819 MB `[6]` | **No** — iPad + partial Mac |
| Performance | "99.9% reliability"; no latency number; own guide advises disabling indexing, Math Assist, spellcheck to fix lag `[7]` | **N/A** |

## 2. Ten technically advanced things and the foundation each needs

1. **Latency as a product feature.** Predicted touches shorten perceived delay, with a user-visible "Reduce Latency" switch and a "Ball Pen uses fewer resources" escape hatch `[7][10]`. Foundation: own stroke pipeline (not just `PKCanvasView`), per-point force/azimuth/altitude, prediction + reconciliation, measured frame budget per device.
2. **In-house on-device recognition.** A 10-person team over three years, 12 languages, >95% accuracy claim, fully offline, powering search, conversion, spellcheck and Restyle `[9]`. Foundation: line/word segmentation, compact recogniser, language packs, per-page index keyed by content hash + recogniser version.
3. **One recogniser, four products.** Search, convert-to-text, spellcheck and Restyle share one model `[9][27][4]`. Foundation: a recognition service returning confidence and word boxes, not a search-only path.
4. **Spellcheck that synthesises your handwriting.** Tapping a misspelling replaces the word with strokes modelled on that page's writing `[27]`. Foundation: glyph/style extraction plus a stroke synthesiser — far beyond spell suggestions.
5. **Smart Ink: handwriting as reflowable text.** Width handles reflow paragraphs and lists; insert-space shifts lines; straighten/align; Restyle preserves layout and colour `[4][12]`. Foundation: group strokes into lines/paragraphs, a layout engine over stroke geometry, reversible edit log.
6. **A second viewport built on line metrics.** Auto-advance uses a blue zone, drops one line at the page edge, and has a point-based return height `[20]`. Foundation: real zoom/pan coordinate space, paper line metrics, scroll-follow that never rewrites page coordinates.
7. **A diagram scene graph.** Connectors stay attached through moves/resizes, control points add bends, dragging an edge dot spawns a connected shape `[4][24]`. Foundation: object identity, constraint anchors, hit-testing, z-ordered vector rendering.
8. **Per-type object semantics.** Tape reveals on finger only and honours Read Only; text highlight moves with characters while PDF highlight is a stroke; layers scope every edit and filter export `[20][23][25]`. Foundation: typed elements with behaviour, explicit render order, export filter.
9. **Time-anchored audio.** Note Replay seeks from a stroke to an audio offset, with configurable stroke reveal `[5][28]`. Foundation: monotonic clock at record start, per-stroke timestamps, playback-driven partial rendering.
10. **Multi-device sync and real-time collaboration.** iCloud, Goodnotes Cloud, turbo sync, presence, comments, private/public links `[2][8]`. Foundation: stable IDs + tombstones per object, operation log, conflict resolution, server, and an explicit "sync is not a backup" model. Also their weakest area.

## 3. Top user pain points we can beat

**1. Sync fear and silent data loss.** Goodnotes' own guide says iCloud sync "is not a separate backup", interrupted syncing can *damage* documents, and recovery may need a whole-device restore `[8]`. Users report libraries vanishing after enabling iCloud and notebooks going blank `[13]`. Our local-first files, immutable assets, ordered page writes and version history are already the right shape. Win by shipping verifiable backup/restore with a conflict report — and saying so.

**2. Lag and bloat.** Huge notebooks lag, the app degrades after about an hour, updates introduce stutter `[14][15][31]`. The official fix list is revealing: disable search indexing, Math Assist and spellcheck; use the Ball Pen; close tabs `[7]`. The app is 819 MB `[6]`. Beat it with lazy pages, indexing off the ink path, no AI in the stroke pipeline, and a published latency benchmark on the oldest supported iPad. `PERFORMANCE-NOTES.md` is the start of that proof.

**3. Pricing and gating.** Free is capped at 3 notebooks/3 text docs/3 boards/3 folders/100 MB, 5 MB imports, watermarked exports, 20-minute audio. Essential $11.99/yr, Pro $35.99/yr, AI Pass +$10/mo; 525 AI credits/mo paid, 10 free. Layers are Pro-only, real-time collaboration is Pro-only, and the one-time "Special Edition" is Apple-only and cut off from Goodnotes Cloud `[2]`. Users resent watermarks and the recurring paywall `[29][30]`. No account, no watermark, no credits, no server is a clean differentiator.

**4. Search that must be switched on.** Indexing is opt-in, PDFs without OCR are never searchable, and the index can be "corrupted or incomplete" even for paying users `[19]`; people conclude search is broken `[18]`. Ours is always-on with syntax, filters and page marks; the remaining gap is OCR fallback plus a visible, cancellable re-index.

**5. Regressions from clever automation.** Scribble-to-erase misfires and deletes handwriting; lag appears after updates; crashes cluster around cloud storage `[31][16]`. Every clever gesture needs a kill switch and per-document toggle, and releases need a device regression pass. We already use that pattern (eraser filter, highlighter-only); apply it everywhere.

**6. AI that is metered and occasionally wrong.** Generating notes from a transcript costs credits, and answers can be generic `[2][30]`. On-device models with a deterministic fallback, citations to page/segment, and "not found" instead of invention is a stronger trust story — and works offline.

**7. Complexity and focus.** Long-time users call the app bloated and the AI additions irrelevant `[17][30]`. It now ships notebooks, boards, text docs, meetings, marketplace, enterprise admin and six platforms. We should win on one thing: the best handwriting surface on iPad, with PDF annotation second.

**8. Export and cross-platform detail.** Free exports are watermarked, tape becomes a solid block in PDF, typed-text highlight cannot be erased `[2][25][23]`. Goodnotes' own comparison admits the desktop app lacks tablet features `[6]`. Vector, unwatermarked, WYSIWYG export is cheap for us; on Mac, promise the same file with the same strokes, not a viewer.

**Copy next, in order:** Smart Ink-class lasso actions (move/copy/recolour/convert), hold-to-shape with live adjust, zoom-window auto-advance, per-tool erase-filter UI, OCR fallback in search, and a visible "your files are safe" backup story. Do not chase collaboration, marketplace or AI credits.

## Sources

1. https://www.goodnotes.com/pricing
2. https://support.goodnotes.com/hc/en-us/articles/13808767840015-Compare-Goodnotes-Plans-and-Features
3. https://www.goodnotes.com/blog/the-new-goodnotes
4. https://www.goodnotes.com/blog/whats-new-in-goodnotes-july-september-2026
5. https://www.goodnotes.com/blog/whats-new-in-goodnotes-april-june-2026
6. https://apps.apple.com/us/app/goodnotes-ai-notes-docs-pdf/id1444383602
7. https://support.goodnotes.com/hc/en-us/articles/14588473217423-Troubleshoot-Slow-Lagging-or-Unresponsive-Goodnotes-on-Apple-Devices
8. https://support.goodnotes.com/hc/en-us/articles/7352796404495-Troubleshoot-iCloud-Sync-issues-in-Goodnotes
9. https://www.goodnotes.com/blog/machine-learning-engineer-handwriting-recognition
10. https://www.goodnotes.com/blog/features-fixes-updates-june-2025
11. https://support.goodnotes.com/hc/en-us/articles/11917208851215-Sunsetting-Word-Complete-Frequently-Asked-Questions
12. https://www.goodnotes.com/features/tablet-stylus-experience
13. https://www.reddit.com/r/GoodNotes/comments/1xj48eb/title_urgent_all_my_goodnotes_disappeared_after/
14. https://www.reddit.com/r/GoodNotes/comments/1mxwyhl/goodnotes_6_becomes_laggy_after_about_1_hour/
15. https://www.reddit.com/r/GoodNotes/comments/1re1208/this_lag_is_absolute_garbage/
16. https://www.reddit.com/r/GoodNotes/comments/1isfy4p/bugs_in_recent_updates/
17. https://www.reddit.com/r/GoodNotes/comments/1p51e7b/goodnotes_and_notability_is_too_bloated_at_this/
18. https://www.reddit.com/r/GoodNotes/comments/1fuc41o/how_to_fix_handwriting_recognition/
19. https://support.goodnotes.com/hc/en-us/articles/7353695209743-I-can-t-search-my-notes
20. https://support.goodnotes.com/hc/en-us/articles/7353756785679-Write-and-customize-ink-with-the-Pen-tool and companion help articles listed in `SETTINGS-AND-GESTURES.md`
21. https://support.goodnotes.com/hc/en-us/articles/9757771783823-Utilize-the-new-features-of-Apple-Pencil-Pro
22. https://support.goodnotes.com/hc/en-us/articles/9756420431759-Preview-Strokes-With-Apple-Pencil-Hover-on-iPad
23. https://support.goodnotes.com/hc/en-us/articles/7353718215823-Using-the-Highlighter-tool
24. https://support.goodnotes.com/hc/en-us/articles/13682939148943-Draw-shapes-and-build-diagrams-in-Goodnotes
25. https://support.goodnotes.com/hc/en-us/articles/9489290046607-Use-the-Tape-Tool-to-hide-and-reveal-content
26. https://support.goodnotes.com/hc/en-us/articles/7353742824975-Export-documents-or-pages
27. https://support.goodnotes.com/hc/en-us/articles/14500614035471-Spellcheck-your-handwriting
28. https://support.goodnotes.com/hc/en-us/articles/7352688559631-Add-Audio-Recordings-to-your-documents
29. https://www.reddit.com/r/GoodNotes/comments/1s9l3kr/will_this_mark_on_pdf_export_not_be_there_with/
30. https://www.reddit.com/r/GoodNotes/comments/1nr0e29/goodnotes_new_update_aka_gn7_my_thoughts/
31. https://www.reddit.com/r/GoodNotes/comments/1o8ee2x/what_the_heck_is_this_laggy_writing_started/
32. https://support.goodnotes.com/hc/en-us/articles/7353695644175-Select-Move-and-Edit-Content-With-the-Lasso-Tool

**Unverified:** whether tape patterns/sticker collections are unchanged in 7.1.36 (help articles predate the rename); AI credits per action; whether Layers has left early access; whether Win/Android/Web are still web-wrapped (secondary sources); any quantitative ink latency for Goodnotes on our test iPad — no public number exists, so a comparison must be measured, not asserted.
