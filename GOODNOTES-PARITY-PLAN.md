# GoodNotes parity plan

Written 2026-11-12. This is the gap analysis and implementation plan for matching the GoodNotes feature set in NOTEAPP. It sits beside `PLAN.md`; it does not replace the architecture or the Drive plan.

Evidence tags:

- `[B]` — read from the installed **Goodnotes 7.1.34** app bundle on this Mac (`/Applications/Goodnotes.app`): `Info.plist`, `en.lproj/*.strings`, extension list, document types.
- `[S]` — fetched from `goodnotes.com` or `goodnotes.com/pricing` in this session.
- `[C]` — read in this repository, with `file:line`.
- `[R]` — from `reports/iPad note app feature plan.md` and `research_notes/iPad note app feature plan/`.
- `[A]` — believed, not verified; every `[A]` is mapped to a spike or risk below.

## 0. What was and was not checked

> **Update 2026-11-12:** a live click-through of Goodnotes 7.1.34 for Mac is now in `research_notes/goodnotes-walkthrough/WALKTHROUGH.md`, with screenshots. Its §10 corrects several rows below (layers not exposed, no tags, per-tool eraser filter, three pen types plus sliders).

Computer use is **not available in this session** — no `computer-use` tools are connected — so this is not a click-through of the live GoodNotes UI. The installed app was inspected instead:

- Bundle version `7.1.34` (`CFBundleShortVersionString`), document types for GoodNotes, PDF, PowerPoint, Word, image and zip `[B]`.
- 61 English `.strings` tables, including `Tools`, `GN6ToolbarUI`, `Canvas`, `Learn`, `ExamPrep`, `MathConversion`, `HandwritingBeautification`, `Transcription`, `Tape`, `TimeKeeper`, `PasswordProtection`, `ElementCollection`, `TemplateLibrary`, `FolderCustomization` `[B]`.
- 2,462 keys in `Localizable.strings`; feature terms include Whiteboard, Text Document, Study Set, Flashcard, Layer, Tape, Ruler, Laser Pointer, Sticky Notes, Comments, Marketplace, Collaboration, Outline, Bookmarks, Scan Documents, QuickNote, Presentation Mode, Password Protection, Read-Only `[B]`.
- Official product pages show three document types (Notebook, Whiteboard, Text Document) and the current feature/pricing matrix `[S]`.

What this cannot prove: exact gestures, layout, edge cases and animation. Those need a live walkthrough or the physical iPad. The plan therefore puts every uncertain mechanism behind a spike rather than assuming it.

**Working-tree work in progress (not made by this planning run).** When this plan was written, the tree already contained uncommitted work: a tab bar and split view in `NotebookView`, app-side page bookmarks (`PageBookmarks.swift`), and finger-tap PDF link handling (`PDFLinkHandler.swift`, `PencilCanvasView.onFingerTap`). These are treated below as **implemented but unverified**, not as missing. They were not modified by this planning run.

## 1. What GoodNotes has now

The installed build is a three-format app with five layers of capability:

1. **Documents**: notebook, infinite whiteboard, reflowing text document, PDF annotation, QuickNote, scan/camera import.
2. **Ink and page tools**: eight pen styles plus highlighter, stroke/pixel/object/selective eraser, lasso, shape recognition, shapes and connectors, ruler, tape, laser pointer, sticky notes, layers, elements, rich text boxes, full-page typing, outline, bookmarks, presentation mode.
3. **Capture and study**: audio recording, stroke-anchored playback, transcription, live summary, study sets, flashcards, Smart Learn spaced repetition, exam prep, Smart Textbooks, Math Assist, handwriting Restyle.
4. **AI**: AI typing (rewrite/tone/grammar/shorten), ask-your-notes chat, summaries, mind maps, image generation, math solving.
5. **Platform**: iPad/Mac/iPhone/Windows/Android/Web, iCloud or Goodnotes Cloud sync, backup to Google Drive/OneDrive/Dropbox/WebDAV, password protection, read-only mode, collaboration, marketplace.

NOTEAPP today is a credible **notebook + PDF annotation** app. It is not yet a whiteboard, text-document, audio, study or AI app. The gap is large but mostly additive; the data model already has the two fields that are hardest to retrofit: every stroke has a stable ID, a layer ID and a creation date `[C StrokeRecord.swift:7-23]`, and every page already stores layers `[C Page.swift:40-52]`.

## 2. Feature matrix

Legend: ✅ parity; 🟡 partial; ❌ missing; 🚫 deliberately not planned.

### 2.1 Documents and library

| Feature | GoodNotes | NOTEAPP | Note |
|---|---|---|---|
| Paged notebook | ✅ | ✅ | `NotebookManifest`, `Page` |
| Infinite whiteboard | ✅ `[B][S]` | ❌ | No document kind, no world-coordinate canvas |
| Reflowing text document | ✅ `[B][S]` | ❌ | No text-document model |
| QuickNote | ✅ `[B]` | ❌ | Double-tap `+` in GoodNotes |
| PDF import and annotation | ✅ | ✅ | `PDFImporter.swift:50-81` |
| PDF link taps under ink | ✅ `[B]` | 🟡 | Finger-tap handler in the working tree `[C PDFLinkHandler.swift, NotebookView.swift:238-260]`; needs a device test |
| PDF text search | ✅ `[B]` | ❌ | Index covers ink + text boxes only `[C SearchIndex.swift:178-187]` |
| Image / photo import | ✅ | ✅ | Image elements |
| Word / PowerPoint file support | ✅ `[B]` | ❌ | Declared document types in Info.plist; the import flow itself was not exercised |
| Scan documents / camera | ✅ `[B]` | ❌ | No camera or scan path |
| Nested folders | ✅ | ✅ | `Folder`, `FolderTree` |
| Favourites | ✅ | ✅ | `folderTree.favourites` |
| Tags | not verified | ✅ | NOTEAPP has library tags |
| Trash / restore | ✅ | ✅ | `Recently Deleted` |
| Covers | ✅ | ✅ | `NotebookCoverStyle`, first-page cover |
| Custom folder colours/icons | ✅ `[B]` | ❌ | `FolderCustomization.strings` |
| Templates / digital stationery | ✅ | 🟡 | 21 built-in templates `[C PageTemplates.swift:31-56]`; no import |
| Custom template import | ✅ `[B]` | ❌ | `TemplateLibrary.strings` |
| Marketplace | ✅ `[S]` | 🚫 | Personal app; no storefront |
| Workspaces | announced for 2026, not shipped `[S]` | 🚫 | Multi-tenant concept |
| Multi-select / bulk move / bulk delete | not verified | ❌ | Context menu only `[C LibraryView.swift:376-408]` |
| Sort, list/grid, recent documents | 🟡 recents verified `[B]`; sort not verified | 🟡 | Grid + search; no sort control or recents |
| Outline and bookmarks | ✅ `[B]` | 🟡 | App-side page bookmarks in the working tree `[C PageBookmarks.swift]`; no outline or PDF TOC |
| Tabs and split view | ✅ tabs `[B]`; split not verified | 🟡 | Tab bar and split view in the working tree `[C NotebookView.swift:9-100, AppModel.swift:35-51]`; not yet run |
| Password protection | ✅ `[B]` | ❌ | `PasswordProtection.strings` |
| Read-only mode | ✅ `[B]` | ❌ | No app-level read-only |
| Version history | not verified | ❌ | Do not claim GoodNotes parity here |
| Export PDF | ✅ | ✅ | Raster PDF `[C PDFExport.swift:74-90]` |
| Export PNG / selected pages / print | ✅ | ❌ | PDF only |
| GoodNotes-format export | ✅ `[B]` | 🚫 | Proprietary format; no public spec |
| Collaboration / share links / comments | ✅ `[S]` | 🚫 | Personal app |
| Presentation mode / laser / mirror | ✅ `[B]` | ❌ | `Presentation Mode`, `Laser Pointer` |

### 2.2 Canvas and ink

| Feature | GoodNotes | NOTEAPP | Note |
|---|---|---|---|
| Eight pen styles | ✅ | ✅ | `PenStyle` `[C InkTool.swift:23-31]` |
| Highlighter | ✅ | ❌ | `PenStyle` has no highlighter case |
| Colour and width per pen | ✅ | ✅ | `PenPresets` `[C PenPresets.swift:5-30]` |
| Palette / favourites | ✅ | 🟡 | Colour picker + slider; no palette strip |
| Pressure and tilt | ✅ | ✅ | PencilKit |
| Palm rejection | ✅ | 🟡 | `.pencilOnly` on device `[C PencilCanvasView.swift:136-141]`; needs physical iPad |
| Pinch zoom and pan | ✅ | ❌ | Zoom is locked to fit `[C PencilCanvasView.swift:38-44]` |
| Zoom window for small writing | ✅ `[B]` | ❌ | No magnifier |
| Stroke and pixel eraser | ✅ | ✅ | `CanvasMode.eraser` `[C PencilCanvasView.swift:61-79]` |
| Selective eraser (highlighter/tape only) | ✅ `[B]` | ❌ | `Erase Highlighter Only`, `Erase Tape Only` |
| Object eraser | ✅ `[B]` | ❌ | `Object Eraser` |
| Lasso select | ✅ | 🟡 | PencilKit lasso only `[C PencilCanvasView.swift:76-77]` |
| Lasso move / resize / copy / cross-page paste | ✅ | ❌ | No action menu or own transform |
| Shape recognition (hold to perfect) | ✅ `[B][S]` | ❌ | Only “Add Shape” elements |
| Shapes, arrows, connectors | ✅ | 🟡 | Rect/ellipse/line elements only `[C PageElement.swift:31-36]` |
| Ruler | ✅ `[B][S]` | ❌ | |
| Tape with reveal | ✅ `[B][S]` | ❌ | |
| Laser pointer | ✅ `[B]` | ❌ | |
| Sticky notes | ✅ `[B]` | ❌ | |
| Layers (add/hide/lock/reorder) | ✅ `[B][S]` | 🟡 | Model only; UI always uses first layer `[C NotebookView.swift:563]` |
| Element move / resize / rotate | ✅ | ❌ | Elements are add/delete only `[C PageElementViews.swift:57-141]` |
| Element lock / z-order / align / snap | ✅ `[B]` | ❌ | `zIndex` exists, no UI |
| Rich text boxes | ✅ | 🟡 | Plain text + font size `[C PageElementViews.swift:28-54]` |
| Full-page typing | ✅ `[B]` | ❌ | |
| Handwriting to text | ✅ | ❌ | Recognition exists for search only |
| Restyle / Smart Ink | ✅ `[B][S]` | ❌ | `HandwritingBeautification.strings` |
| Spellcheck / word complete | ✅ `[B]` | ❌ | `WritingAids.strings` |
| Audio recording | ✅ | ❌ | No audio field or view |
| Stroke-anchored replay | ✅ `[B][R]` | ❌ | `createdAt` makes it possible |
| Transcription / summary | ✅ `[B]` | ❌ | |
| Study sets / flashcards | ✅ `[B]` | ❌ | `Learn.strings` |
| Spaced repetition (Smart Learn) | ✅ `[B]` | ❌ | |
| Exam prep / Smart Textbook | ✅ `[B]` | 🚫 | Content product, not a note feature |
| Math Assist / LaTeX conversion | ✅ `[B][S]` | ❌ | `MathConversion.strings` |
| AI typing / ask-your-notes / summaries | ✅ `[B][S]` | ❌ | `AITyping.strings`, `LLMChat.strings` |

### 2.3 Platform and trust

| Feature | GoodNotes | NOTEAPP | Note |
|---|---|---|---|
| iPad native | ✅ | ✅ | |
| Mac native | ✅ | 🟡 | Read-only renderer `[C NotebookView.swift:574-584]` |
| iPhone | ✅ | ❌ | Not in scope |
| Windows / Android / Web | ✅ `[S]` | 🚫 | |
| Offline editing | ✅ | ✅ | Files are truth |
| iCloud sync | ✅ | ❌ | Drive is the chosen path `[R]` |
| Google Drive backup/sync | ✅ | 🟡 | Planned Phase 3, not started |
| OneDrive / Dropbox / WebDAV backup | ✅ `[B]` | ❌ | Drive first, others not planned |
| Cross-device sync | ✅ | ❌ | Phase 3 |
| Keyboard shortcuts / menu commands | ✅ | 🟡 | A few canvas shortcuts |
| Apple Pencil Pro squeeze / hover | not verified | 🟡 | PencilKit defaults; no palette |
| Accessibility / Dynamic Type / VoiceOver | not verified | 🟡 | SwiftUI baseline |
| Localisation | ✅ many | ❌ | English only |
| Enterprise / SSO / admin | ✅ | 🚫 | |

## 3. The gaps that matter, ranked

### P0 — daily writing feels worse than GoodNotes

1. **No zoom.** The canvas is locked to fit the page. Writing small, annotating a dense PDF or fixing a letter is impossible. This is the single biggest usability gap and a prerequisite for ruler, tape and the zoom window.
2. **No highlighter.** Marking notes and PDFs is table stakes. PencilKit has no public highlighter ink, so this needs a render-path decision, not just a toolbar button.
3. **Elements cannot be moved, resized or rotated.** Text boxes, images and shapes are currently fire-and-forget.
4. **No shape recognition, ruler or tape.** Diagrams and self-testing are the two most common handwriting workflows after plain writing.
5. **Lasso has no actions.** PencilKit's lasso can select, but cut/copy/paste/duplicate/cross-page move are not implemented.
6. **Layers have a model but no UI.** The data is ready; the panel is missing.
7. **Text boxes are plain text.** No bold/italic/underline, font family, alignment, lists or links.
8. **No outline.** Page bookmarks landed in the working tree, but there is no outline or PDF table of contents; long notebooks are still navigated by a thumbnail strip.
9. **PDF is second class.** Link taps landed in the working tree; there is still no PDF text search and no page insert/delete inside an imported PDF.
10. **Export is one format.** PDF only, raster, all pages.

### P1 — makes it a serious notebook

11. Audio recording with stroke-anchored replay and transcription.
12. Study sets and spaced repetition.
13. Math Assist and LaTeX conversion.
14. Scan/camera import.
15. Presentation mode, laser pointer, read-only mode.
16. Password protection and version history.
17. Verify the working-tree tabs/split, and add the quick switcher.
18. QuickNote and library bulk operations.
19. Custom templates and folder colours.

### P2 — big bets, only after P0/P1

20. Whiteboard (infinite canvas).
21. Text document (reflowing).
22. Restyle / Smart Ink (handwriting editing that preserves the hand).
23. Ask-your-notes AI and AI typing.
24. Mac annotation and full editing.

## 4. Architecture changes required before the features

### 4.1 Canvas viewport (must be first)

Today the paper is a SwiftUI view behind `PKCanvasView`, so PencilKit zooms ink but not paper; the code locks zoom to avoid the mismatch `[C PencilCanvasView.swift:38-44]`. The fix is to put paper, elements and ink into **one zoomable content coordinate space**:

- Preferred: a `UIScrollView` hosting a page content view that contains the paper renderer, element layer and a non-scrolling `PKCanvasView`. The canvas is sized to the page; zoom and pan are the scroll view's job.
- Fallback: use `PKCanvasView`'s own zoom and apply the same transform to the paper and element layers.
- The stroke coordinate system must stay page-absolute. Zoom is a view transform only; it never rewrites points.
- The zoom window is a second viewport over the same page, not a second canvas.

Spike **S7** decides between these before P7.1 is built.

### 4.2 Highlighter render path

`PenStyle` has eight cases and no highlighter `[C InkTool.swift:23-31]`. PencilKit exposes `.marker`, but a marker is opaque; a highlighter must be translucent and render **under** pen ink.

Options:

- **H1:** one `PKDrawing` with highlighter strokes first and pen strokes after, using a translucent marker colour. Cheapest, but PencilKit may composite strokes in creation order and may not honour alpha the way a highlighter needs.
- **H2:** two canvases sharing one scroll view: a highlighter canvas below and the ink canvas above. Correct layering guaranteed; undo, lasso and hit-testing must be coordinated between two canvases.
- **H3:** store highlighter strokes in the app's records and render them in the page renderer as a lower layer; the PencilKit canvas draws only pen ink. Best control; live highlighter drawing then needs a custom overlay or a temporary canvas.

Spike **S8** tests H1 first, then H2; H3 is the fallback if neither preserves the “text stays readable under highlight” property.

### 4.3 Tool model

Replace the current `InkTool` + `CanvasMode` pair with a tool model that covers all tools without special cases:

- `ToolKind`: pen, highlighter, eraser, lasso, shape, tape, ruler, laser, text, image, sticky note.
- Each tool keeps its own presets (colour, width, opacity, pattern).
- `CanvasMode` remains the canvas's current interaction state; `ToolKind` is the user-facing choice.
- Toolbar slots persist; hidden tools stay reachable from an overflow menu (GoodNotes does this `[B]`).

### 4.4 Document model v2

- `DocumentKind`: notebook, whiteboard, textDocument. `NotebookManifest` becomes `DocumentManifest` with `kind`, `defaultTemplate`, `pageSize`, `coverName`.
- `Page` gains `deletedElementIDs` for merge, and `PageElement` gains `isLocked`, `rotation`, `opacity`, `textStyle`.
- `Layer` gains `opacity` and `blend`? GoodNotes layers only hide/lock; keep v1 to hide/lock, add opacity later.
- `AudioClip` lives on the document, not the page: `id`, `assetName`, `startedAt`, `duration`, `transcriptSegments`. A clip can span pages; `stroke.createdAt` provides the anchor.
- `OutlineItem` and `Bookmark` live on the document.
- `StudySet` is a separate document type with cards; cards reference a page/region or hold text/image.
- `VersionSnapshot` is local-only history, not synced.
- Schema bump to v2 with a migration that reads v1 and refuses unknown versions; never half-load.

### 4.5 Render and export

- `PageRenderer` gains a layer pass (highlighter below ink), element transforms and hit-test rectangles.
- Export should keep vector where possible: PDF text and PDF pages can stay vector; PencilKit ink is rasterised today. Keep raster at 2x and state the limitation; a vector ink export is a later spike, not a parity requirement.
- Export selection, PNG and print are cheap once the renderer takes a page subset.

### 4.6 Sync impact

Phase 3 (Google Drive) must understand v2 before document types ship:

- Strokes: union by ID, deleted IDs win (already planned).
- Elements: union by ID; `updatedAt` last-writer-wins; `deletedElementIDs` tombstones.
- Layers: union by ID; tombstones for deleted layers; a stroke whose layer is gone is reassigned to the default layer, never dropped.
- Assets: content-hash named, immutable (already).
- Audio/transcripts: audio immutable; transcript is derived and can be rebuilt.
- History: never synced.

## 5. Phased plan

No calendar estimates: none of the source material supports one, and effort is dominated by spikes. Order is dependency order.

### Phase 7 — Canvas and tool foundation (P0)

| ID | Task | Check |
|---|---|---|
| P7.1 | Zoomable page viewport: pinch 25–800%, two-finger pan, double-tap zoom, fit page/width; paper, elements and ink in one coordinate space. Spike S7 first | At 400% zoom a tap at a known screen point maps to the same page point within 0.5 pt; zoom/pan leaves the page file unchanged; a pinch during a live stroke does not corrupt the stroke |
| P7.2 | Tool model v2 and toolbar: `ToolKind`, per-tool presets, slots, overflow, show/hide/reorder | After relaunch, tool order and every tool's colour/width are restored; a hidden tool is still reachable from overflow |
| P7.3 | Highlighter: translucent, straight-line snap optional, renders under ink; “erase highlighter only”. Spike S8 first | Text under a highlight stays legible; the pen eraser does not remove highlighter; export preserves the order; stroke round-trip still passes |
| P7.4 | Shape recognition: hold at stroke end to snap line, arrow, rectangle, ellipse, triangle; shape tool draws by drag; stroke/fill styles | A rough hand-drawn rectangle within tolerance becomes a rectangle; undo restores the raw stroke; the page has no duplicate stroke after conversion |
| P7.5 | Element manipulation: select, drag, resize, rotate, z-order, lock, align/distribute, snap guides; drag-and-drop from Files/Photos | Moving or resizing changes only `frame`/`rotation`; ID and content unchanged; undo restores the exact prior frame; a locked element cannot move |
| P7.6 | Layers panel: add, rename, reorder, hide, lock, delete, merge down; active layer | Hiding a layer changes rendering only and leaves `strokes` unchanged; a locked layer rejects new ink; deleting a non-empty layer either refuses or moves strokes to the layer below, never orphans them |
| P7.7 | Lasso v2: cut, copy, paste, duplicate, delete, resize, move across pages, convert to text | Pasted strokes get new IDs and the originals keep theirs; pasted count equals copied count; cross-page paste preserves relative positions; undo restores the page exactly |
| P7.8 | Text boxes v2: bold/italic/underline, font family, size, colour, alignment, lists, indent, highlight, links; full-page typing mode | Formatting survives save, reload and PDF export; links are clickable in the exported PDF; full-page typing edits the document body, not ink |
| P7.9 | Document model v2: `DocumentKind`, page size/orientation, custom size, insert page from PDF/image, multi-page move, custom template import | A v1 library migrates to v2 and opens; `pageOrder` lists exactly the page files present; an unknown schema version is refused with a clear error |
| P7.10 | Outline and PDF table of contents: outline items with hierarchy, TOC import, jump; keep the working-tree page bookmarks and add them to the panel | Every outline item points to a page ID that exists; deleting a page prunes its outline items; every imported TOC page index is within bounds; a bookmarked page survives relaunch |
| P7.11 | Search v2: index PDF text, rich text and outline titles; highlight hit rectangles; filters by notebook/folder/tag | A term on a PDF page is found; the hit rectangle lies inside the page; changing the PDF or page invalidates that page's index record |
| P7.12 | Export v2: selected pages, PDF/PNG, with/without layers, print, share, zip the notebook folder | Exported page count equals the selected count; PNG pixel size equals page size × scale; a zipped export restores to a byte-identical library |

### Phase 8 — Annotation and content parity (P0/P1)

| ID | Task | Check |
|---|---|---|
| P8.1 | Tape: rectangular tape, hide/reveal, patterns and colours, “erase tape only” | Tape hides and reveals the same region without changing the underlying strokes; tape survives save and export; erasing tape never erases ink |
| P8.2 | Ruler: draggable and rotatable, lines snap to the edge, angle readout | A line drawn along the ruler is straight within 0.5 pt; rotating the ruler changes the snap angle; the ruler is not saved in the page |
| P8.3 | Laser pointer: ephemeral, colour/size, works in presentation mode | The laser leaves no stroke in the page file after the pointer is released |
| P8.4 | Sticky notes: pinned note, text, colour, lock, collapse to a pin; comments thread | The note keeps its page position after zoom and export; collapsing hides the body but not the pin; deleting the note removes its comments |
| P8.5 | Scan/camera import and image editing: crop, rotate, perspective, multi-page capture | A scanned page has the same page count as the capture; the stored asset hash is stable; crop/rotate do not alter the original asset |
| P8.6 | PDF v2: verify the working-tree link taps, then add text selection/copy, PDF outline, insert/delete/reorder pages, flatten | Tapping a link with a finger navigates while Pencil still draws; copied PDF text matches the source; page count after edits equals the manifest |
| P8.7 | Handwriting to text: select ink, convert to a text box at the same position, undo | Converted text is searchable and editable; undo restores the exact strokes; no duplicate ink remains |
| P8.8 | Scribble gestures: scratch to erase, circle to lasso, insert space between lines | A scratch gesture deletes only the crossed strokes; a circle selects the enclosed strokes; insert-space shifts the line and its strokes together |
| P8.9 | Templates and covers v2: import PDF/image template, groups, default template, custom cover; folder colours/icons | An imported template appears in the library and renders identically on iPad and Mac; the default template applies to new pages; a folder colour survives relaunch |

### Phase 9 — Audio, study, math and AI (P1)

This phase supersedes `PLAN.md` Phase 5. Its five open tasks are carried forward here as P9.1–P9.6, and P5.1–P5.5 are retired only when their replacements pass.

| ID | Task | Check |
|---|---|---|
| P9.1 | Audio recording: record while writing, waveform, playback speed, ±10 s skip, noise reduction, clip library | A 10-minute recording plays back at the same duration within 1 s; the audio asset is stored once; closing the document stops and saves the clip |
| P9.2 | Stroke-anchored replay: tap a stroke to seek to `stroke.createdAt − clip.startedAt` | Replay position for a stroke is within 1 s of that stroke's time minus the recording start |
| P9.3 | Transcription with `SpeechAnalyzer`: on-device, segments with timestamps, transcript synced to playback | Every segment time lies inside the clip duration; the transcript survives relaunch; a missing language pack is shown, never silently dropped |
| P9.4 | Summaries and action items with Foundation Models: page, selection, recording | The feature is absent, not broken, when `SystemLanguageModel.isAvailable` is false; a summary cites the page or segment it came from |
| P9.5 | Study sets: create cards from a selection/page, flip, shuffle, Smart Learn spaced repetition, progress, CSV import/export | A card created from a page region re-renders that region after relaunch; the scheduler is deterministic for a fixed review history; `review(set, now)` is idempotent for the same day |
| P9.6 | Math Assist: recognise a handwritten equation, solve, show steps, convert to LaTeX; typed math | On the fixed 20-expression set, the score is recorded and the ship/no-ship rule from `PLAN.md` section 6 is applied; solved steps do not alter the original ink |
| P9.7 | AI typing: rewrite, shorten, lengthen, tone, grammar, bulletise; diff preview; undo | The original text is restorable with one undo; no network call is made when the on-device model is unavailable |
| P9.8 | Ask-your-notes: chat over a page or notebook with citations; on-device only | Every answer cites at least one page or passage; a question with no supporting passage returns “not found”, not a fabricated answer |
| P9.9 | Restyle / Smart Ink spike: selected handwriting → same words and layout in a chosen style | Spike only. Ship only if a fixed 20-sample set preserves word count, line breaks, colour and position; otherwise retire and say so |

### Phase 10 — Document types (P2)

| ID | Task | Check |
|---|---|---|
| P10.1 | Text document: reflowing rich text, headings, lists, images, links; export PDF; open in the same library | Text reflows on resize; export page count matches the rendered document; a text document never silently becomes a notebook |
| P10.2 | Whiteboard: infinite canvas, zoom/pan, frames, shapes, connectors, images, text, export; no page concept | Panning 10,000 pt away and back returns to the same camera; a board with 10k strokes and 100 elements stays interactive on the test iPad; export bounds contain every element |
| P10.3 | Unified open/search across notebooks, boards and text documents | A search term in any document kind returns the document and a jump target; the library filter counts each kind separately |

### Phase 11 — Platform, trust and polish (P1/P2)

| ID | Task | Check |
|---|---|---|
| P11.1 | Verify and harden the working-tree tabs and split view; add the quick switcher | Two notebooks are visible at once; closing one leaves the other's unsaved page committed; the quick switcher lists every open tab |
| P11.2 | Multiple windows: open a document in a new window on iPad Stage Manager and Mac | Two windows on the same notebook show the same page set and never double-save a page |
| P11.3 | Presentation mode: full screen, hide UI, laser, mirror page/screen, external display | The audience view never shows the toolbar; the presenter can advance pages and use the laser; the page file is unchanged |
| P11.4 | Password protection: per-document/folder, Face ID, auto-lock, encrypted at rest, excluded from search | A locked document cannot be opened, indexed or exported without the password; Face ID unlock works after relaunch; a forgotten password has no recovery path and the UI says so |
| P11.5 | Version history: local snapshots on save, time-based retention, restore page/notebook | Restoring a snapshot reproduces the saved bytes; history is never uploaded; retention deletes only the oldest snapshots |
| P11.6 | Read-only mode, duplicate document, archive | Read-only rejects ink, text and element edits but allows search and export; duplicate produces a new ID and no shared assets are rewritten |
| P11.7 | QuickNote: global quick capture from the library, widget or Pencil gesture | A QuickNote created from the library appears as a normal notebook after save; discarding it leaves no file |
| P11.8 | Library polish: sort, list/grid, multi-select, bulk move/delete/tag, recents, drag-and-drop | A bulk move of N notebooks changes N folder links and zero page files; sort order is stable across relaunch |
| P11.9 | Mac: annotation or native canvas, keyboard shortcuts, menu commands, print, drag-and-drop | An annotation made on Mac appears on iPad after sync with the same stroke IDs; every toolbar action has a menu command and shortcut |
| P11.10 | Pencil Pro: squeeze palette, hover preview, barrel-roll where useful | Squeeze opens the tool palette at the Pencil tip; hover shows the brush footprint; disabling the feature restores the system default |
| P11.11 | Accessibility and localisation: Dynamic Type, VoiceOver labels, contrast, reduce motion; string catalogue | Every toolbar control has a VoiceOver label; the app is usable at the largest Dynamic Type size; no hard-coded user-facing string remains in views |

### Phase 12 — Custom ink engine (was Phase 6)

Unchanged from `PLAN.md`. It stays last and nothing in Phases 7–11 depends on it. The only addition: the engine must render highlighter strokes below ink (P7.3) and respect layer visibility (P7.6).

### Where the existing phases fit

- **Phase 3 (Google Drive)**: still runs before Phase 10. Add P3.10 “sync v2 fields”, covering `deletedElementIDs`, element `updatedAt`, layer tombstones and audio assets. Phase 7 can start before Drive, but Phase 10 cannot ship without it.
- **Phase 4 (Mac)**: its open tasks move to P11.9. The read-only Mac build stays as the current state.
- **Phase 5 (Apple features)**: superseded by Phase 9; the five tasks are carried into P9.1–P9.6.
- **Phase 6 (custom engine)**: becomes Phase 12 here; unchanged.

## 6. What we deliberately will not build

| Not building | Why |
|---|---|
| Real-time collaboration, share links, multi-user comments | One user, two devices. The sync design already merges conflicts; collaboration is a server product. |
| Marketplace, content store, exam-prep courses, Smart Textbooks | Content commerce, not note-taking. Local template import covers the real need. |
| Workspaces, Teams/Enterprise, SSO, admin console | No organisation to administer. |
| Windows, Android, web, iPhone | The brief is iPad + Mac. Each extra platform multiplies the test matrix. |
| GoodNotes file import/export | The `.goodnotes` format is proprietary and undocumented. Migrate through PDF; export PDF/PNG/zip. |
| Cloud AI, AI credits, image generation | The app is personal and offline-first. On-device Foundation Models only, with the feature hidden when unavailable. |
| 3D graphing, exam content, meeting integrations | Out of proportion to a personal notebook. |

## 7. Spikes and risks

| ID | Unknown | Discriminating check | Fallback |
|---|---|---|---|
| S7 | Can paper, elements and ink share one zoomable coordinate space without drift? | Draw at 400%, zoom out, compare page coordinates; a 10-round zoom/pan cycle returns to the same transform | Lock zoom per tool and add a separate zoom window only |
| S8 | Does PencilKit render a translucent highlighter under ink? | Highlight over black text, export, measure text contrast; check stroke order in the exported image | Two-canvas highlighter layer; then app-rendered highlighter |
| S9 | Is shape recognition good enough to be invisible? | 30 hand-drawn shapes per class; count wrong snaps and false positives | Shape tool only, no hold-to-snap |
| S10 | Does stroke time stay aligned with audio across clock changes and pauses? | Record across a manual clock change and a pause; compare stroke offset to audio position | Store a monotonic anchor at record start; recompute offsets from it |
| S11 | Is handwritten math recognition accurate enough? | The existing S5 fixed set of 20 expressions | Typed math only; LaTeX conversion later |
| S12 | Can Restyle preserve words, layout and colour? | 20 samples; count word/line/position mismatches | Retire Restyle; keep Smart Ink out |
| S13 | Does an infinite canvas stay interactive? | 10k strokes + 100 elements; measure pan/zoom frame time on the test iPad | Bound the board to a large finite canvas |
| S14 | Can a text document export with fidelity? | Export a document with headings, lists, images and links; compare page count and content | PDF-only text documents; no DOCX |
| S15 | Can password protection be added without a recovery backdoor? | Lock, relaunch, unlock with password and Face ID; attempt search/export while locked | App-level lock plus iOS Data Protection, with the limitation stated |
| S16 | Can PDF export keep text and PDF pages vector? | Export a PDF-imported notebook; select text in the output | Keep 2x raster and state the limitation |

Open risks carried from `PLAN.md`: physical iPad signing and Pencil tests (P0.3/P1.4/P1.7), Google OAuth project, PDF link taps on device (handler exists, untested), handwritten math quality, on-device model availability, PaperKit bridge, free-account signing expiry, background upload behaviour.

## 8. Invariants and their timing

| Invariant | When it can be false | Design |
|---|---|---|
| Every stroke's `layerID` names a layer on the page | After a layer is deleted or a v1 page is migrated | Deletion moves strokes to the layer below or refuses; migration creates a default layer before assigning |
| `pageOrder` lists exactly the page files present | Between writing a page and rewriting the manifest; after a crash | Page first, manifest second; orphans are appended and reported, never dropped |
| Element z-order is total and stable | Two elements share a `zIndex` | Order by `(zIndex, id)`; normalise on save |
| Audio offset equals stroke time minus clip start | Clock change, pause/resume, device sleep | Store a monotonic anchor at record start; freeze offsets when the clip ends; S10 measures the error |
| Search index reflects page content | Between an edit and the idle re-index; PDF text changes; recogniser version changes | Content hash includes ink, typed text, PDF page refs and outline titles; recogniser version is part of freshness |
| Export page count equals the selected page count | A page fails to render or an asset is missing | Fail the whole export with the page number; never write a partial PDF silently |
| Merge is commutative, associative and idempotent | Elements without tombstones; layers deleted on one device | Add `deletedElementIDs` and layer tombstones before two-way sync; property tests over generated pages |
| Locked documents never enter the search index or an export | Auto-lock races with an idle index job | The index and exporter check the lock state at read time, not at enqueue time |

## 9. Decisions needed

1. **Scope confirmation.** This plan assumes personal use: no collaboration, marketplace, enterprise, non-Apple platforms or cloud AI. Confirm, or name which of those you actually want.
2. **Order.** Recommended: Phase 7 (zoom, highlighter, elements, lasso, layers, text, outline, export) → Phase 8 (shapes, tape, ruler, PDF, scan) → Phase 9 (audio, study, math, AI) → Phase 11 (tabs, presentation, password, history) → Phase 10 (whiteboard, text document). The alternative is audio/study first if lectures matter more than annotation.
3. **Big bets.** Whiteboard, text document and Restyle are each larger than the rest of a phase. Pick at most one for the next 12 months; my recommendation is whiteboard last, Restyle only if S12 passes.
4. **Physical iPad.** Palm rejection, Pencil gestures, lasso and audio timing cannot be closed on the simulator. Which iPad and iPadOS version, and is a paid developer account available?
5. **Google Cloud project.** Phase 3 still needs your OAuth client and approval before any auth code is written.
6. **Password protection.** This is a Tier 3 auth change; it needs explicit approval and a decision on recovery (none vs. recovery key).
7. **Mac ambition.** Read-only plus search, or full annotation/editing? The current plan says annotation later; this plan schedules it at P11.9.
8. **GoodNotes migration.** Is PDF import enough, or do you need a one-time converter for existing `.goodnotes` files? A converter is reverse engineering, not a feature.

## 10. Review of this plan against itself

- **Prior decisions:** `PLAN.md` locks H1 (own stroke record is truth), pages-only for now, Drive backup then sync, native Mac, iPadOS 27/macOS 27. This plan keeps H1 and pages-first; it adds document kinds as Phase 10, not Phase 1. The only reversal is Phase 5, explicitly superseded by Phase 9 and carried forward task by task.
- **`ponytail:` markers:** two exist (JSON+zlib page encoding, contains-scan search). P7.11 replaces the contains-scan with indexed text only if the library search becomes slow; the marker stays until measured. No new dependency is introduced by Phases 7–9; Foundation Models, SpeechAnalyzer, PencilKit, PDFKit and CryptoKit are system frameworks.
- **Strongest objection:** the plan is too broad for a personal app and could delay the one thing that matters — a writing canvas that feels good. Answer: P0 is deliberately only the canvas and annotation gaps; Phases 9–10 are gated behind P0/P1 and the decision in section 9.2. If only one phase ships, ship Phase 7.
- **Second objection:** highlighter and zoom are architectural, not features; if S7/S8 fail, P7.1/P7.3 change shape. Answer: both are spikes before their tasks, with fallbacks named.
- **Third objection:** adding document kinds before sync is dangerous. Answer: Phase 10 is gated on Phase 3 plus P3.10 sync-v2 fields.
- **Finding conservation:** every open item from `PLAN.md` section 12 is mapped: P1.8 → P7.1; P1.10 → P7.10/P11.1; P2.2 → P8.6; Phase 3 → Phase 3 + P3.10; Phase 4 → P11.9; Phase 5 → P9.1–P9.6; Phase 6 → Phase 12. No open item is silently dropped. Uncommitted tabs, page bookmarks and PDF-link work found in the tree are carried as “verify”, not re-planned as new work.
- **Numbers:** no time estimates and no accuracy percentages. The 20-expression math set, 30-shape set, 10k-stroke board and 2,000-stroke page are test sizes chosen for verification, not measurements.

## 11. Resolution report

```text
🟡 SRE [Tier 2 now, Tier 3 at P11.4 password] | Root Cause: n/a, parity planning
Evidence: 18 VERIFIED file:line / 5 TESTED bundle+site reads (Goodnotes 7.1.34, 61 strings tables, 2,462 Localizable keys, official product and pricing pages) / 7 ASSUMED mapped to S7-S13
Recheck: n/a, planning run; every code claim re-read in this session
Confidence: MEDIUM — the two load-bearing mechanisms (zoom coordinate space, highlighter layering) are unproven and gated by S7/S8
Gate: A ✓ one supersession (Phase 5) stated, ponytail markers preserved. B ✓ section 8. C ✓ no ratios. D ✓ every check is relational. E ✓ section 6. F ✓ section 10. G ✓ three objections answered. H rung 4 (native frameworks), no new dependency before Phase 10
Ladder: rung 4 (PencilKit, PDFKit, SpeechAnalyzer, Foundation Models, CryptoKit) | net: 0 lines | ponytail: 2 existing markers
Fix: n/a
Predict: S7 and S8 decide whether Phase 7 is one canvas or two; not yet run
T2/3: Impact: none yet | Fail mode: if S8 fails, highlighter uses a second canvas; if S7 fails, zoom ships as a zoom window only
Action: PLAN ONLY — no code, nothing staged
```
