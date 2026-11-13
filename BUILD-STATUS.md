# Build status — GoodNotes parity

Written 2026-11-12, after the multi-agent build. Everything below was built in this checkout; none of it is committed.

## Verification

| Check | Result |
|---|---|
| iPad simulator build (`iPad Pro 11-inch (M5)`, iOS 27.2) | `** BUILD SUCCEEDED **` |
| macOS build (`platform=macOS`) | `** BUILD SUCCEEDED **` |
| Package tests | **316 passing, 0 failing** |

| Package | Tests |
|---|---|
| NoteCore | 36 |
| InkKit | 24 |
| SearchKit | 12 |
| SyncKit | 1 |
| StudyKit | 42 |
| AudioKit | 22 |
| BoardKit | 42 |
| TextDocKit | 30 |
| AIKit | 45 |
| HistoryKit | 62 |

The iPad simulator was not driven interactively: its device session was owned by another thread, and this build did not take it over. Drawing, zoom, audio and element gestures still need a hands-on pass.

## Integrated into the running app

### Canvas and page tools

- **Zoom and pan** — the page, elements and ink sit in one `UIScrollView` content view; pinch zoom, two-finger pan, fit and zoom buttons. `NoteApp/Notebook/ZoomablePageView.swift`.
- **Highlighter** — a translucent marker stored with `StrokeTool.isHighlighter`; export and reload render highlights under pen ink. Live drawing during a session still appends on top until the page reloads.
- **Layers panel** — add, rename, reorder, hide, lock and delete layers; new ink goes to the active layer; hiding a layer never deletes its strokes. `LayersPanel.swift`, `AppModel.swift`.
- **Element editing** — a dedicated mode to move, resize, rotate, lock, delete and reorder text boxes, images, shapes and PDF pages. `ElementEditLayer.swift`.
- **Rich text boxes** — bold, italic, underline, alignment and line spacing, stored in `PageElement.textStyle` and rendered by InkKit.
- **Outline and bookmarks** — a flat page outline with custom titles, plus page bookmarks and jump. `OutlinePanel.swift`, `PageOutline.swift`, `PageBookmarks.swift`.
- **PNG and PDF export** — PDF still exports every page; PNG exports the current page at 2×.
- **PDF text search** — SearchKit now indexes PDF page text as well as handwriting and typed text.
- **PDF links** — the working-tree finger-tap handler opens URL and internal page links.
- **Folder colours and icons** — custom appearance stored in the folder tree and shown in the sidebar.
- **Tabs and split view** — the working-tree tab bar and two-pane split are integrated.

### Document types

- **Notebooks** — existing paged notebooks, PDF import, templates, covers and handwriting search.
- **Text documents** — block-based library and editor: headings, paragraphs, lists, quotes, code, checklists and dividers. `NoteApp/TextDocs/`.
- **Whiteboards** — a 3000 × 3000 dot-grid canvas with pen, highlighter, eraser, undo/redo, fit and center, saved as one ink `BoardItem`. `NoteApp/Boards/`.
- **Study sets** — create, import `question,answer` CSV, edit cards, Smart Learn review with SM-2 scheduling, and AI flashcards saved as a study set. `NoteApp/Study/`.

### Capture and assistance

- **Audio** — record from the notebook header, play/stop, delete; recordings are stored as immutable notebook assets with clip metadata. Transcription is engine-ready but not surfaced.
- **Page AI** — summarize the page, generate flashcards, and ask questions grounded in the page text. Uses the on-device `FoundationModelsProvider` when available and a deterministic fallback otherwise. `NoteApp/AI/NoteAIPanel.swift`.
- **Version history** — a local snapshot is recorded after each page save, with a restore panel. History stays outside the synced library. `VersionHistoryView.swift`.

## Engine-ready but not fully surfaced

| Package | What exists | What is missing |
|---|---|---|
| AudioKit | Recording, clip store, stroke-time anchors, `SpeechAnalyzer` transcriber, playback controller | Transcript UI, live summary, stroke-tap replay wiring |
| HistoryKit | Snapshots, retention policy, PBKDF2 + AES-GCM, manifest envelope, lock policy, keychain protocol | Password/lock UI, encrypted page files, Face ID |
| BoardKit | Infinite-camera maths, board items, store, merge, layout | Text/shape/image/connector UI, true infinite growth, undo |
| TextDocKit | Block model, store, Markdown import/export, PDF text layout | Markdown UI, image insertion, PDF renderer |
| AIKit | Summaries, flashcards, ask, rewrite, tone, grammar, math, citations | Rewrite/tone/grammar UI, on-device runtime smoke test |
| StudyKit | Sets, cards, SM-2 scheduler, CSV, smart session | Exam prep, card images UI |
| SyncKit | Placeholder target | Google Drive auth, backup, restore, sync |

## Still missing against GoodNotes

- Lasso cut/copy/paste, resize and cross-page move (PencilKit lasso selection only).
- Shape recognition (hold-to-perfect), ruler, tape, laser pointer.
- Sticky notes, comments, presentation mode.
- Handwriting-to-text, Restyle / Smart Ink.
- Scan/camera import, document flattening, PDF text selection, PDF page insert/delete/reorder.
- Transcription UI, meeting notes, recording summaries.
- Password protection, read-only mode, full app lock.
- True infinite whiteboard; whiteboard text, shapes, images and connectors.
- Custom template import and a template library.
- Mac annotation; the Mac side remains a read-only renderer.
- Google Drive backup and two-way sync.
- The custom Metal ink engine.

## Known limitations and risks

- **Highlighter layering:** stored order is correct and every export/reload is correct, but a highlight drawn in the current session sits above existing ink until the page reloads.
- **Zoom/element gestures:** compile-verified only; no hands-on Pencil pass.
- **Whiteboard:** finite 3000 × 3000 page, ink only, read-only on macOS, and the saved camera is not restored on open.
- **Text documents:** last save wins, no undo, images are read-only, no Markdown UI.
- **Audio:** the real `AVAudioRecorder` path was not run in the simulator; the microphone permission string is present.
- **AI:** Foundation Models generation was not run on a real device; the deterministic fallback is what the build can prove today.
- **History:** snapshots are unencrypted, local only, and pruning currently runs on launch, not after every save.
- **Search:** PDF text extraction happens during indexing on the calling task; a very large PDF can make the first index slow.
- **No commit:** all work is in the working tree.

## Recommended next pass

1. Run the iPad hands-on checks: highlighter layering, pinch zoom, element drag/resize/rotate, layer hide/lock, Pencil palm rejection, audio record/play.
2. Implement lasso actions, shape recognition, ruler and tape; these are the largest remaining daily-use gaps.
3. Surface transcription and the audio stroke-tap replay.
4. Add password protection and read-only mode behind a deliberate security pass.
5. Then Google Drive backup/sync, because the document format now has the v2 fields (element tombstones, text styles, audio assets) that sync must understand.
