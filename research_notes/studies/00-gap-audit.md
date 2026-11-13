# GAP AUDIT — what NOTEAPP still lacks vs Goodnotes, Notability, Noteshelf and the field

Audit date: 2026-11-13. Scope: every feature claimed in the in-repo competitor research, checked against `NoteApp/` and `Packages/` by grep/read. No new web research was needed.

**How to read this.** DONE = implementable feature is present and reachable in the UI. PARTIAL = present but narrower than the competitor version. MISSING = not found anywhere in app code or packages. Effort is for this codebase (SwiftUI/PencilKit, one developer): **S** ≈ ≤3 days, **M** ≈ 1–2 weeks, **L** ≈ 3+ weeks. Impact 1–5 is personal-use value, not market value.

**Competitor key.** GN = Goodnotes, NB = Notability, NS = Noteshelf 3, MS = MyScript Notes (Nebo), FX = Flexcil, CN = CollaNote, ZN = ZoomNotes, NW = Notewise, ON = OneNote, AN = Apple Notes, FF = Freeform, PB = Penbook, SN = Samsung Notes, RM = reMarkable. Evidence for every competitor column is in `research_notes/competitors/**` and `research_notes/iPad note app feature plan/competitor_features.md` (per-app teardown tables); the "Has it" column names the app, and the full feature/source mapping is in those files.

**Baseline (verified DONE, so not listed as gaps):** pressure ink with 8 pen styles and per-style presets, highlighter with its own palette, stroke/pixel eraser, hold-to-shape (line/rectangle/triangle/ellipse), PencilKit ruler, laser (dot/line), lasso move, per-page layers (add/rename/hide/lock/reorder/delete), Zoom View with auto-advance, Read Only mode, seamless and single-page scroll, 22 built-in templates, per-page template change, covers, outline titles, bookmarks, page add/insert/duplicate/move/delete/rotate/resize/clear, PDF import (including ink→strokes, outline import, password unlock, page range), PDF export (flattened or editable annotations, bookmarks→outline) and PNG export, local version history, library-wide handwriting/typed/PDF search with query syntax and filters, on-device AI summary/flashcards/Q&A, study sets with CSV import/export and SM-2-style scheduling, audio record/play/delete, nested folders (depth 12), notebook tags, favourites/recents/trash (30 days), tabs and two-pane split, whiteboards with connectors, reflowing text documents.

---

## 1. MISSING features, grouped by area

### 1.1 Ink tools

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 1 | **Ink smoothing / stabilisation** (Low/Med/High, per tool) | NB, GN, CN, MS | S | 4 | `InkTool` stores style/colour/width only (`Packages/InkKit/Sources/InkKit/InkTool.swift:69`). No smoothing stage before commit. NB's default is Low and it is the top "cheap stylus" fix; CN and MS expose it too. |
| 2 | **Dashed and dotted pen styles** | NB, GN, NS | S | 3 | No line-style field on `InkTool`; every stroke is solid. |
| 3 | **Shape fill toggle + ink flood fill** | NB, GN, NS | M | 3 | `PageElement.shape` already carries an optional `fill` (`Packages/NoteCore/Sources/NoteCore/Model/PageElement.swift:72`) but no UI sets it; no press-and-hold flood fill. |
| 4 | **Scribble-to-erase** (with off switch) | GN, MS, ON, AN | M | 4 | Erasing requires the eraser tool. GN ships it on by default and documents the "vanishing letters" cost of not having an off switch. |
| 5 | **Circle-to-lasso** (circle ink, long-press, it becomes a selection) | GN | M | 3 | Lasso is PencilKit's `PKLassoTool` behind a tool switch (`PencilCanvasView.swift:150`). |
| 6 | **Highlighter that draws a straight line on hold** | GN, NS | S | 3 | Hold-to-shape runs through `HoldToShape.swift` for the pen; the highlighter path does not expose a straight-line option. |
| 7 | **Smart highlighter that snaps to PDF/typed text** | NB, MS | L | 3 | Requires text-line runs in the PDF/textbox model; nothing selects text today. |
| 8 | **Calligraphy nib angle + lock angle + barrel-roll ink** | NB, GN, MS | M | 2 | `.fountainPen` exists as a `PenStyle`; no nib-angle control, no lock, no roll handling in app code. |
| 9 | **Mirror ink** (duplicate + flip a selection) | NB | S | 2 | No transform on a selection at all. |
| 10 | **Colour eyedropper** | NB, NS | S | 3 | Palette has 64 swatches, hex and the system picker (`NoteApp/Notebook/ColorPalettePopover.swift`), but cannot sample the page. |
| 11 | **Quick diagramming / connectors inside notebooks** | GN, NW | M | 3 | Connectors exist only on boards (`Packages/BoardKit/Sources/BoardKit/BoardItem.swift:44`). |
| 12 | **Shape set beyond 3** (arrow, star, polygon, line style, lock) | GN, NB, NS | M | 4 | Insert menu offers rectangle/ellipse/line only (`NoteApp/Notebook/NotebookView.swift:607`). Move/resize/rotate already exist in `ElementEditLayer.swift`. |

### 1.2 Lasso and editing

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 13 | **Lasso restyle** — recolour/re-width/resize ink after writing | NB, GN, NS | M | 5 | The single biggest editing gap. `PKLassoTool` moves strokes but reports no selection, so the app cannot mutate them; no `didChangeSelection` callback in `PencilCanvasView`. Named as a switch-trigger by users ("use the select tool to change the colour of whatever you wrote"). |
| 14 | **Rectangular lasso mode + per-type inclusion** (handwriting/images/shapes) | GN, MS, NS, SN | S | 3 | Freehand only; `CanvasMode.lasso` has no variant. |
| 15 | **Copy / paste / duplicate a selection, and drag it to another page or notebook** | GN, NB, NS | M | 4 | Needs the selection model from #13. Only `UIPasteboard` use today is copying AI text (`NoteApp/AI/NoteAIPanel.swift:394`). |
| 16 | **Convert selection to text** | GN, NB, NS, MS, AN | M | 5 | The recogniser exists (`Packages/SearchKit/Sources/SearchKit/HandwritingRecognizer.swift`) but only feeds search; no convert action anywhere. |
| 17 | **Save selection as an element / sticker / saved clip** | GN, NB, NS | M | 3 | No reusable element library; "Page Elements…" is a list of objects already on the page (`NoteApp/Notebook/PageElementViews.swift:102`). |
| 18 | **Object lock** (images, shapes, stickies) | NB, NS | S | 2 | Z-order exists; lock does not. |
| 19 | **Text-editing gestures on handwriting** (double-tap word, drag to select) | AN | L | 2 | Requires a text-run model over strokes; furthest-out item in this table. |

### 1.3 Pages and templates

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 20 | **Custom page templates** — import a PDF or PNG, name it, categorise it, set as default | GN, NB, NS, MS | M | 5 | 22 built-in templates only (`NoteApp/Notebook/PageTemplates.swift:31`). `PageTemplatePicker` has no import path. Biggest single "why digital" feature for planners, client notebooks and forms. |
| 21 | **Add space to a page / grow the canvas** | NS 8.1.2, NB (PDF gutter), MS | M | 3 | `resizePages` exists (`NotebookSession.swift:491`) but only changes the sheet frame (`PageOperations.resized` keeps stroke/element coordinates); there is no insert/remove vertical room mid-page. |
| 22 | **Two-page / multi-page view** | FX (1/2/4), GN | M | 3 | Only one page at a time; split view is two notebooks, not two pages of one. |
| 23 | **Write across a page boundary in seamless scroll** | NB (seamless) | M | 3 | Only the active page hosts a live canvas (`NoteApp/Notebook/ContinuousPagesView.swift:24-47`); a stroke that starts on an inactive page is replayed after load, not continued across the break. |
| 24 | **Page-level trash / recover a deleted page** | NS | S | 3 | Notebooks go to trash for 30 days (`AppModel.swift:65`); `deleteCurrentPage` has no recovery. |
| 25 | **Focus mode** (4-finger tap, one movable tool) | NB, NS | S | 3 | Read Only hides the toolbar but blocks editing. |
| 26 | **Presentation mode** (clean audience output, private second note, laser) | GN, NB, NS | L | 3 | Laser exists, but there is no external-screen mode or UI hiding. |
| 27 | **Named, coloured bookmarks that read as a chapter list** | NS, GN | S | 2 | Bookmarks are a boolean per page (`NoteApp/Notebook/PageBookmarks.swift`); outline titles are separate and invisible in a chapter list together. |
| 28 | **Auto-add a page when writing at the end** ("pull to add page") | GN | S | 2 | Page add is explicit. |
| 29 | **Saved scenes / camera views** (named pan-zoom, presentable) | FF, ZN | M | 2 | Board cameras persist per board, not as named scenes. |
| 30 | **Drag-reorder pages in the thumbnail strip** | GN, NB, NS | S | 3 | Strip has no drag reorder; ordering is via `moveCurrentPage(by:)` in the menu. |

### 1.4 PDF

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 31 | **PDF text selection** — highlight/strikeout/copy/define/speak | GN, NB | M | 4 | PDF pages are imported as ink + image; `PDFLinkHandler` handles links only. No text layer hit-testing. |
| 32 | **Add-margin / gutter on PDF import** | NB | M | 4 | Import preserves page size; no "write beside the slide" space. |
| 33 | **Fill PDF form fields** | GN, NB | L | 2 | Explicitly out of scope in `PageElementRenderer` (links/widgets stay in the file). |
| 34 | **Merge PDFs / PDF page surgery** | FX, GN, MS | M | 3 | Insert pages exists; no merge, extract or reorder of the underlying PDF. |
| 35 | **Bulk / folder import** | NB, MS, NS | S | 3 | One file per import (`NoteApp/Import/PDFImportFlow.swift`). |

### 1.5 Text and media

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 36 | **Web clip** (URL → cropped card) | NB, NS | M | 3 | No URL import path. |
| 37 | **Tables** | GN, NB | L | 2 | Text docs are block/markdown based (`Packages/TextDocKit`); notebooks have no table element. |
| 38 | **Code blocks / quotes / checklists inside notebook text** | NB, GN | M | 2 | Text boxes are plain styled text; `TextDocKit` has the block vocabulary for documents only. |
| 39 | **Text-to-speech of a note** | NB | S | 2 | — |
| 40 | **Custom / imported fonts** | GN, NS, NW | M | 2 | Font is a name string on a text element; no font import or picker. |
| 41 | **Image crop** (and non-uniform crop) | NS, NB | S | 3 | Image elements can be moved/resized/rotated, not cropped. |
| 42 | **Sticky note collapse to a pin** | GN, NS | S | 2 | Sticky notes are always expanded. |
| 43 | **Function → graph** | NB, AN | L | 2 | — |
| 44 | **Built-in stock media library** | NS | M | 1 | — |

### 1.6 Audio

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 45 | **Stroke-anchored audio replay** — play back and watch ink re-draw; tap a stroke to seek | NB, CN, ON | M | 5 | `AudioAnchor` and stroke `createdAt` exist (`Packages/AudioKit/Sources/AudioKit/AudioAnchor.swift`), and `NotebookAudio` records clips, but nothing joins them: no replay, no seek-on-tap. Highest-value half-built feature in the repo. |
| 46 | **Transcription / live transcript** | NB, GN, NS, CN | L | 4 | `SpeechAnalyzerTranscriber` and `Transcript` exist in AudioKit; the app shows no transcript UI. |
| 47 | **Playback speed, ±10 s skip, voice boost** | NB | S | 3 | Playback is play/pause only (`AudioRecordingsView.swift`). |
| 48 | **Trim / split / merge / rename clips** | NB | M | 2 | Clips are immutable; only delete. |
| 49 | **One-tap "record a lecture"** from the library | NB | S | 2 | Record lives inside a notebook. |

### 1.7 Search

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 50 | **Page-level tags, searchable** | NS, ZN | M | 3 | Tags are notebook-level only (`AppModel.swift:439`) and have no library filter/view. |
| 51 | **Saved searches / smart folders** | AN | M | 3 | Query syntax exists (`Packages/SearchKit/Sources/SearchKit/SearchQuery.swift`); queries are not saved. |
| 52 | **Visible indexing progress + per-notebook recognition language** | GN | S | 2 | Settings has rebuild + on/off only; language is device-default. |
| 53 | **Search results for a *page* inside a 300-page PDF as a jump list** | NB (Notes/Bookmarks filter) | S | 2 | In-notebook search lists pages; no annotated-only/bookmarked filter. |

### 1.8 AI

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 54 | **Handwriting → text conversion** (see #16) | GN, NB, NS, MS, AN | M | 5 | Duplicate of #16 from the AI angle; listed once in the ranking. |
| 55 | **Handwriting beautification / restyle that keeps the writer's hand** | GN (Restyle), AN (Refine) | L | 3 | No stroke synthesis or style model. |
| 56 | **Handwriting spellcheck that re-draws in your hand** | GN, AN | L | 2 | — |
| 57 | **Math solve + LaTeX** | GN, AN, NB, MS | L | 3 | `AIKit` mentions math in its model prompts but there is no maths surface. |
| 58 | **Chat with the note / library** | NB | L | 3 | Page AI answers one question at a time; no multi-turn thread, no library-wide context. |
| 59 | **Translate a selection in the margin** | NS, CN | M | 2 | — |
| 60 | **Live structured notes from a recording** | NB (Smart Notes) | L | 2 | Depends on #46. |

### 1.9 Study

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 61 | **Anki `.apkg` import** | NB | M | 3 | CSV only (`Packages/StudyKit/Sources/StudyKit/StudySetCSV.swift`). |
| 62 | **Study timer / Pomodoro with breaks** | NB | S | 2 | — |
| 63 | **Multiple-choice quiz generation** | NB, GN | M | 2 | AI generates flashcards, not quizzes. |
| 64 | **Masking-tape recall with right/wrong tracking** | FX | M | 3 | Tape hides/reveals but records nothing. |
| 65 | **Flashcards from a lasso selection** | GN | M | 3 | AI cards are generated from page text; needs #13. |

### 1.10 Organisation and library

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 66 | **Smart folders / saved filters** (tag + date + source) | AN | M | 3 | — |
| 67 | **Library multi-select + batch move/export/delete** | GN, NB, NS | M | 3 | Actions are per notebook. |
| 68 | **List view** (not only grid) | NB, NS, GN | S | 2 | `LibraryView` builds a `LazyVGrid` only (`LibraryView.swift:834`). |
| 69 | **Content views** (all photos / all recordings / all bookmarks) | NS | M | 2 | — |
| 70 | **Workspaces** (separate environments above folders) | GN (2026) | L | 1 | Out of scope for personal use. |

### 1.11 Sync, backup, export

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 71 | **Any sync between iPad and Mac** | GN, NB, NS, MS, Saber | L | 5 | `Packages/SyncKit/Sources/SyncKit/SyncKit.swift` is a 4-line hello-world; the library is a local folder (`AppModel.defaultLibraryRoot`). The status file confirms no remote and no Drive work beyond a plan. |
| 72 | **Auto-backup to a cloud folder** (Drive/Dropbox/OneDrive/WebDAV, native or PDF) | GN, NB, NS | L | 5 | No backup code path at all. Community research ranks data safety as a top-three switch reason. |
| 73 | **Export the whole library / batch PDF** | GN, NS | M | 4 | Only the open notebook exports (`NotebookView` export menu). |
| 74 | **Notebook password lock** | GN, NS, NB (folders) | M | 3 | `PasswordProtector`, `ManifestEncryption`, `KeychainKeyStore` exist in HistoryKit but no app code calls them (only PDF *import* passwords are handled). |
| 75 | **Export to RTF / Word / Markdown for a notebook** | NB (RTF), MS (Word) | M | 2 | PDF/PNG only; `TextDocKit` has markdown export for text documents, unwired to notebooks. |
| 76 | **Library lives in a user-chosen folder / iCloud Drive** | Noteful, Saber | L | 2 | Fixed local root. Relevant mainly as the cheap substitute for #71. |

### 1.12 Settings and gestures

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 77 | **Palm rejection strength** (Low/Med/High) | GN, CN | M | 3 | Only the finger-draws toggle exists (`SettingsView.swift:100`). |
| 78 | **Keep iPad awake while reading** | NB, Noteful | S | 3 | No `isIdleTimerDisabled` anywhere. |
| 79 | **Hover preview of the stroke and eraser footprint** | GN, NB, AN | M | 3 | No `UIPencilHoverPose` use. |
| 80 | **Pencil haptics on snap / tool change, with off switch** | NB, AN | S | 2 | — |
| 81 | **Squeeze radial/arc menu at the nib** | CN, NB | M | 2 | Double-tap can open the colour palette (`EditorToolState.handlePencilDoubleTap`); squeeze has no custom UI. |
| 82 | **Left-handed layout mirroring** | NS, MS, RM | M | 2 | Controls are placed for right-handed use. |
| 83 | **Toolbar dock to any edge** | GN, NB, NS | M | 2 | Toolbar editor reorders/hides tools; the bar is fixed to the bottom. |
| 84 | **Choose the undo gesture** (2-finger tap vs 3-finger swipe) | NB | S | 2 | Both gestures are on/off toggles, not a choice. |
| 85 | **Tap anywhere to start typing** | NB | S | 2 | Text needs the Text Box command. |
| 86 | **Writing-style calibration** (posture picker) | MS, NS | M | 2 | — |

### 1.13 Accessibility

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 87 | **Respect Reduce Motion** | platform norm | S | 3 | No `accessibilityReduceMotion` check; several `withAnimation` transitions run regardless. |
| 88 | **Increase Contrast / differentiate without colour** | platform norm | M | 3 | Colour is the only signal for tool selection and layer state in places. |
| 89 | **Dynamic Type for chrome** | platform norm | M | 3 | 69 accessibility labels exist, one `@ScaledMetric`; most controls use fixed point sizes and a 52 pt toolbar. |
| 90 | **Spoken feedback / read a note aloud** | NB (TTS) | M | 2 | — |
| 91 | **Larger UI targets / UI zoom** | platform norm | M | 2 | Minimum 44 pt is mostly honoured; dense toolbar rows in split view are not. |

### 1.14 Mac companion

| # | Feature | Has it | Effort | Impact | Note |
|---|---|---|---|---|---|
| 92 | **Ink editing on the Mac** | GN, NB, NS (limited) | L | 4 | macOS page area is a rendered image (`macPageImage`, `NotebookView.swift:1006`); `EditorToolbar` is `#if os(iOS)`, so there is no tool selection, no drawing, no lasso on Mac. |
| 93 | **Mac menu commands and full shortcuts** | GN, NS | M | 3 | Header has Library/Read Only/Pages/Insert/More; no `.commands`, no tool keys, no page navigation keys. |
| 94 | **Mac window/tab restore and multi-window** | GN, NB | S | 2 | Single window per app scene. |
| 95 | **Search and study on Mac** | NB, GN | S | 3 | Library and notebooks exist; `NoteAIPanel`/`StudyReviewView` are shared but audio and capture are iPad-first. |

---

## 2. PARTIAL features — present, but short of the competitor version

| # | Feature | Where in code | What is missing vs the competitor |
|---|---|---|---|
| 1 | **Layers** | `NoteApp/Notebook/LayersPanel.swift`, `NotebookSession.addLayer/renameLayer/toggleLayerVisibility/toggleLayerLock/deleteLayer/moveLayer` | Layer count is unbounded and layers can be locked/reordered — *better* than Goodnotes' fixed 5. Missing: layer opacity, duplicate layer, "export visible layers only" toggle, and moving an existing selection between layers (needs #13). |
| 2 | **Eraser** | `EditorToolState.EraserMode`, `EditorToolbar.EraserSettingsPopover` | Stroke/pixel + 4 widths + highlighter-only + auto-deselect. Missing erase-by-type for pencil/tape/shapes (NS has all four), "auto" size that matches the stroke, and a visible erase filter as an allow-list (GN's model). Help text already promises "filter" but only one filter exists. |
| 3 | **Shapes** | `InkKit/HoldToShape.swift`, `ShapeRecognizer.swift`, `NoteCore/PageElement.shape` | Hold-to-shape covers line/rect/triangle/ellipse, and elements resize/rotate. Missing arrow/polygon/star, fill UI, dashed outline, snap guides to other shapes, and "draw and hold then keep dragging to scale" (GN/NB). |
| 4 | **Tape** | `PageElement.tape`, `InkKit/PageElementRenderer.swift:406`, `NotebookView.swift:1232` | 3 colours, write-on, finger reveal. Missing patterns, width/straight modes, "erase tape only", and a hide-all/show-all switch. Tape is inert in exported PDFs (same as GN). |
| 5 | **Ruler** | `NotebookView.swift:710` (`isRulerActive`), `PencilCanvasView` | PencilKit ruler: drag, rotate, straight strokes. Missing units, angle measurement, "stamp line", and a visible scale (MS, NB, GN all ship at least one of these). |
| 6 | **Zoom View** | `NoteApp/Notebook/ZoomWindowView.swift`, `InkKit/ZoomBand.swift` | Has magnification 1.5–5×, resizable band, auto-advance, settings. Missing: a visible zoom % readout, and a confirmation that the lasso/eraser work inside the band (the band is a viewport canvas; tool parity is untested on device). GN users cite both as the top missing bits. |
| 7 | **Audio** | `NotebookAudio.swift`, `AudioRecordingsView.swift` | Record/play/delete per notebook, elapsed timer, clean clip store. Missing everything that makes audio a study tool: stroke anchoring (#45), transcript (#46), speed/boost (#47), edit (#48). |
| 8 | **Search** | `Packages/SearchKit`, `NoteApp/Search/*` | Stronger than most: phrase/OR/-term syntax, source and last-edited filters, page marks, pencil query pad, index rebuild. Missing tag filter, saved searches, index progress, per-notebook language. |
| 9 | **AI** | `Packages/AIKit`, `NoteApp/AI/NoteAIPanel.swift` | On-device summary, flashcards and grounded Q&A with a deterministic offline fallback; cards save into a study set. Missing multi-turn chat, library scope, handwriting input, maths, translation. |
| 10 | **Study** | `Packages/StudyKit`, `NoteApp/Study/*` | Sets, CSV import/export, SM-2 scheduler, Smart Learn review, grades Again/Hard/Good/Easy. Missing APKG, quizzes, timer, and cards from ink selections. |
| 11 | **Tags** | `AppModel.tags(for:)`, `setTags`, `LibraryView` alert | Notebook-level, comma-separated, no tag view. NS and ZN support page-level tags plus a tag browser; AN has smart folders. |
| 12 | **Bookmarks / outline** | `PageBookmarks.swift`, `PageOutline.swift`, `OutlinePanel.swift` | Page titles + boolean bookmarks + PDF outline export. Missing bookmark names, colours and a "bookmarked only" filter (NS, GN). |
| 13 | **Version history** | `Packages/HistoryKit`, `Notebook/VersionHistoryView.swift` | Local per-page snapshots with restore and merge semantics — good. Missing: whole-notebook restore, prune policy UI, and any off-device copy (NB's 7/30/90-day cloud history). |
| 14 | **Templates** | `PageTemplates.swift`, `PageTemplatePicker.swift` | 22 designed templates across Basics/Planning/Creative, per-page change, default for new notebooks. Missing custom import, covers-on-template, and line-density/opacity sliders (PB). |
| 15 | **Toolbar** | `EditorToolbar.swift`, `ToolbarLayout.swift`, `ToolbarEditorView.swift` | Customisable, overflow-aware, favourite pens, per-tool palettes, Read Only in More. Missing docking to other edges, second-tap-to-options on every accessory, and a "reset to default" discoverability pass. |
| 16 | **Gestures** | `PencilCanvasView` (`drawsWithFinger`, undo taps, double-tap action), `SettingsView` | Finger-draws toggle, 2/3-finger undo/redo, Pencil double-tap mapping. Missing configurable gesture *choice*, 3-finger swipe, 4-finger focus, squeeze menu, hover. |
| 17 | **Mac** | `NotebookView.macHeader`, `macPageImage` | Builds and reads/searches/annotates via insert menus, but the page is a static image. Effectively a viewer + page manager. |
| 18 | **Text** | `NotebookSession.addTextElement/updateTextElement`, `PageElementViews` | Font, size, colour, alignment, z-order. Missing bullets/checklists, headings, links, TTS, per-box paper (NB). |
| 19 | **Export** | `PDFExport.swift`, `PDFExportOptionsSheet.swift` | Page range, template on/off, flattened vs editable annotations, bookmarks→outline, PNG. Missing batch/library export, RTF/Word/Markdown, and a "transparent background" toggle (NS). |
| 20 | **Accessibility** | 69 `accessibilityLabel`s across `NoteApp/` | Consistent labels on custom controls, VoiceOver actions for swatch reordering. Missing the system-level passes (motion, contrast, type) and a canvas alternative for non-visual use. |

---

## 3. Half-built code (things that exist but are not finished or not wired)

| # | What | Evidence | State |
|---|---|---|---|
| 1 | **SyncKit is a placeholder** | `Packages/SyncKit/Sources/SyncKit/SyncKit.swift` — 4 lines, `hello()` printing "Hello, world!"; `Tests/SyncKitTests/SyncKitTests.swift` asserts nothing | Empty package. No model, no transport, no conflict rule. |
| 2 | **Audio stroke anchoring is modelled, unused** | `Packages/AudioKit/Sources/AudioKit/AudioAnchor.swift` (offset/clamp/clock-jump maths + 96 lines of tests); `NotebookAudio` never calls it | The hard clock reasoning is done; the replay UI and seek are absent. |
| 3 | **Transcription stack is built, unused** | `SpeechAnalyzerTranscriber.swift` (180 lines), `Transcript.swift`, `TranscriptSegment.swift`, `SpeechTranscriber.swift`; no `Transcript` reference in `NoteApp/` | Transcription can run but has no surface, no storage in the notebook, no link to clips. |
| 4 | **Password/encryption stack is built, unused** | `HistoryKit/PasswordProtector.swift`, `ManifestEncryption.swift`, `KeychainKeyStore.swift`, `LockPolicy.swift`; no app reference except PDF import password | Notebook lock is one wiring job away, but nothing calls it. |
| 5 | **`PageBookmarks` and `PageOutline` are `UserDefaults`-only** | Both classes write JSON to `UserDefaults.standard` | Not in the notebook folder, not versioned, not exported (except as PDF outline), lost on a library move. Contradicts the project's "files are the source of truth" rule for metadata. |
| 6 | **Study CSV only; store is local** | `StudySetCSV.swift` has no APKG parser; `StudySetStore` writes under the app library | No Anki interop, no sync with the notebook (a card cannot link back to the page it came from). |
| 7 | **AI is one-shot** | `AIService.respond` / `stream`, `NoteAIPanel` state is per-sheet | No conversation history, no library context, no retry/undo of inserted text beyond a single "added block" note. |
| 8 | **Boards glue lives only in a scratch worktree** | `.memory/progress/status.md` ("Glue only there: board passes new toolbar params…") | `BoardEditorView` and `EditorToolbar` parameter mismatch is patched in the `ipad-combined` snapshot, not on a branch. |
| 9 | **Toolbar help text promises a filter that does not exist** | `EditorToolbar.swift:307` "tap again for size, filter and Auto-Deselect" vs popover with one highlighter filter | Small doc/UI drift; either build the allow-list or fix the string. |
| 10 | **PDF forms and widgets are explicitly dropped** | `PageElementRenderer.swift:177`, `PDFImportConversion.swift:67` | Documented limitation, not a bug — but it means "PDF annotation" is ink-only. |
| 11 | **Two different "elements" concepts** | `PageElementViews.PageElementsSheet` (objects on a page) vs the competitor meaning (reusable sticker library) | Naming will mislead the next implementer; there is no library. |
| 12 | **`inkCapture` / `InkCapture` cross-page replay** | `ContinuousPagesView.swift:46-47, 84-96` | Works for a first stroke on a loading page, but is a patch around "one live canvas"; it cannot become cross-page writing without a real multi-page canvas. |
| 13 | **Ruler is a boolean with no options** | `NotebookView.swift:175, 710` | No units, no angle, no stamp — the state exists only to pass to PencilKit. |
| 14 | **Study review has no session statistics** | `StudyReviewView` | Grades are stored per card; no streaks, retention, or "exam in N days". |
| 15 | **`AppSettings` has no migration or reset** | `NoteApp/Settings/AppSettings.swift` | Keys accumulate; no schema version, no "reset settings". Low risk, real debt. |

---

## 4. Top 15 by impact ÷ effort

| Rank | Feature | Area | Effort | Impact | Why this rank |
|---|---|---|---|---|---|
| 1 | **Ink smoothing / stabilisation** | Ink | S | 4 | One filter before stroke commit, per tool; fixes the "my handwriting looks bad" complaint that drives everything else. |
| 2 | **Lasso restyle + duplicate** | Editing | M | 5 | Needs a selection model (`didChangeSelection`, stroke mutation), but it unlocks the most-requested edit and is the base for #3 (handwriting→text), #15 (copy/paste), #17 (elements) and #65 (cards from ink). |
| 3 | **Handwriting → text for a selection** | AI/Editing | M | 5 | Recogniser already exists; the work is the selection bridge and an insert-as-text path. |
| 4 | **Stroke-anchored audio replay** | Audio | M | 5 | All the clock maths and clip store exist; needs timestamps on strokes (already stored), a replay renderer and seek-on-tap. |
| 5 | **Custom page templates (PDF/PNG import)** | Pages | M | 5 | Data model already supports arbitrary page backgrounds; the work is import, naming, storage and a picker section. |
| 6 | **Dashed/dotted strokes** | Ink | S | 3 | A field on `InkTool` plus a renderer branch; also makes underlines and tables credible. |
| 7 | **Extend the selective eraser** (pencil-only, tape-only, shape-aware) | Ink | S | 3 | Stroke provenance is already stored per tool (`PageItemKind.of`). |
| 8 | **Highlighter straight line + eyedropper** | Ink | S | 3 | Two small affordances with daily payoff; both exist as patterns elsewhere in the app. |
| 9 | **Copy/paste + drag a selection between pages/notebooks** | Editing | M | 4 | Follows #2; removes the "redraw it on the next page" tax. |
| 10 | **PDF text selection → highlight/strikeout/copy** | PDF | M | 4 | Requires a text-layer hit test but no new data model; the single biggest PDF-reader gap. |
| 11 | **Palm rejection strength + keep iPad awake** | Settings | M | 3 | Two support-ticket features; the second is a one-line `isIdleTimerDisabled`. |
| 12 | **Page tags + a tag/smart-folder filter** | Library | M | 3 | Tags already exist at notebook level; page tags and a saved query make search scale. |
| 13 | **Scribble-to-erase with an off switch** | Ink | M | 4 | Pen-native delete; the off switch is mandatory (GN's vanishing-letters lesson). |
| 14 | **Focus mode (4-finger) + clean presentation output** | Pages | S/M | 3 | Focus is cheap; presentation is the same UI-hiding work with an external-screen rule. |
| 15 | **Sync or auto-backup to a user-chosen folder** | Trust | L | 5 | The only item here that protects against total loss. Ranked last because it is L, not because it matters least — the community research puts data safety in the top three switch reasons. |

**Deferred on purpose:** Mac ink editing (#92, L/4 — the Mac is a viewer today), handwriting restyle (#55, L/3), maths/LaTeX (#57, L/3), layer opacity, workspaces, marketplace, collaboration. None fits a personal-use app before the list above.

### Top 3 to build first

1. **Ink smoothing** — smallest change with the widest daily effect; it also gives the stroke pipeline a place to hang pressure/velocity curves later.
2. **Lasso restyle + duplicate, then handwriting→text on the same selection model** — one architectural job (selection inspection and stroke mutation) buys three headline features and unblocks flashcards-from-ink.
3. **Stroke-anchored audio replay** — the data and clock logic are already tested in `AudioKit`; wiring it turns the app's existing recorder into the one feature users say they cannot leave Notability for.

---

## Sources

Everything below was opened this session.

**Product / UX research (in-repo, used for every competitor claim)**

1. `research_notes/iPad note app feature plan/competitor_features.md` — Goodnotes/Notability/alternatives inventory, table stakes vs differentiators (§Q1–Q6). Compiled 12 Nov 2026.
2. `research_notes/competitors/goodnotes/SETTINGS-AND-GESTURES.md` — Goodnotes support-centre teardown: settings, gestures, tool micro-behaviours, 144 help articles.
3. `research_notes/competitors/notability/FEATURES.md` — Notability 16.13.5 teardown: audio, Learn, templates, PDF outlines, settings.
4. `research_notes/competitors/noteshelf/FEATURES.md` — Noteshelf 3.8.1.2 teardown: eraser sub-modes, tape, zoom box, tags, backup.
5. `research_notes/competitors/others/SURVEY.md` — MyScript Notes, Flexcil, CollaNote, ZoomNotes, Notewise, Penbook, OneNote, Apple Notes/Freeform, Samsung Notes, reMarkable.
6. `research_notes/competitors/community/POWER-USERS.md` — Reddit/YouTube synthesis: "Most-loved advanced features", "Top complaints & requests", "Ranked ideas for NOTEAPP".
7. `research_notes/freeform/FREEFORM-RESEARCH.md`, `BOARD-CODE-AUDIT.md`, `WHITEBOARD-PLAN.md` — whiteboard/scene evidence used for board and scene rows.

**Code (each DONE/PARTIAL claim cites one of these)**

8. `NoteApp/Notebook/NotebookView.swift` — tool wiring, insert/More menus, macOS page image, laser/tape overlays, export entry points.
9. `NoteApp/Notebook/EditorToolbar.swift`, `EditorToolState.swift`, `PenPresets.swift`, `FavoritePens.swift`, `ColorPalettePopover.swift` — tools, palettes, eraser popover, zoom button, shortcuts.
10. `NoteApp/Notebook/NotebookSession.swift`, `LayersPanel.swift`, `PageOutline.swift`, `PageBookmarks.swift`, `PageTemplates.swift`, `PageTemplatePicker.swift`, `ZoomWindowView.swift`, `ContinuousPagesView.swift`.
11. `NoteApp/Import/PDFImporter.swift`, `PDFImportFlow.swift`; `NoteApp/Export/PDFExport.swift`, `PDFExportOptionsSheet.swift`.
12. `NoteApp/Search/*`, `Packages/SearchKit/Sources/SearchKit/*` — index, query syntax, recogniser, match locator.
13. `NoteApp/AI/NoteAIPanel.swift`, `Packages/AIKit/Sources/AIKit/*` — provider selection, prompts, flashcards, citations.
14. `NoteApp/Study/*`, `Packages/StudyKit/Sources/StudyKit/*` — sets, CSV, scheduler, Smart Learn.
15. `NoteApp/Audio/*`, `Packages/AudioKit/Sources/AudioKit/*` — recorder, clip store, playback, `AudioAnchor`, transcriber.
16. `NoteApp/AppModel.swift`, `Library/LibraryView.swift`, `LibraryCovers.swift`, `NotebookCoverStyle.swift` — folders, tags, sort, trash, tabs, split, covers.
17. `NoteApp/Settings/AppSettings.swift`, `SettingsView.swift` — every preference the app exposes.
18. `Packages/InkKit/Sources/InkKit/*` — `InkTool`, `PencilCanvasView`, `HoldToShape`, `ShapeRecognizer`, `TemplateRenderer`, `PageElementRenderer`, `VectorPDFExport`, `ZoomBand`.
19. `Packages/NoteCore/Sources/NoteCore/Model/*`, `Store/*` — page, element, layer, folder, manifest, store layout.
20. `Packages/HistoryKit/Sources/HistoryKit/*` — snapshots, indexing, encryption, key store, lock policy.
21. `Packages/BoardKit/Sources/BoardKit/*`, `NoteApp/Boards/*` — boards, items, connectors, camera.
22. `Packages/TextDocKit/Sources/TextDocKit/*`, `NoteApp/TextDocs/*` — block documents and markdown.
23. `Packages/SyncKit/Sources/SyncKit/SyncKit.swift` — the placeholder, quoted verbatim.
24. `.memory/context/project.md`, `.memory/progress/status.md` — branch state, known gaps, the board-glue note.

## Unverified

- **Whether the Zoom View band supports lasso and the eraser identically to the page.** The code passes a shared controller and viewport, but I did not run the app; treat tool parity in the band as unconfirmed.
- **Whether PencilKit's `.fountainPen` on iOS 27 already responds to barrel roll.** The app has no roll handling, but the platform may provide some; the NB/GN "nib angle + lock" gap is about *explicit control*, not necessarily zero roll response.
- **Exact Goodnotes/Notability tier gating** of some features (Layers, presentation, selectable eraser) — the in-repo research itself flags this as unresolved in the vendor plan tables.
- **Whether Notability's exported PDFs embed an OCR layer** — flagged as a snippet only in `POWER-USERS.md`.
- **Mac ink input without a Pencil.** `macPageImage` is a static render today; whether a future PencilKit-on-macOS path would accept mouse/trackpad drawing was not tested.
- **LiquidText and Noteful** feature details: LiquidText appears only via a Reddit quote, and Noteful's site timed out during the original research, so rows citing them are weak evidence.
