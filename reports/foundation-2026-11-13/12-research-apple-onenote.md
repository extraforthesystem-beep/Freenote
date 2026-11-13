# 12 — Competitor re-research: Apple Notes, Freeform, OneNote (Nov 2026)

Scope: Apple Notes (iPadOS 27), Apple Freeform (iPadOS 27), OneNote for iPad in late 2026; which Apple frameworks now replace parts of our custom stack; where the three are beatable. Pages read **2026-11-13**. Confidence: **[Apple]** docs/guide, **[WWDC]** session/sample, **[Review]** hands-on, **UNCONFIRMED** unverified.

Supersedes `research_notes/freeform/FREEFORM-RESEARCH.md`, `WHITEBOARD-PLAN.md` and the Apple/OneNote sections of `competitors/others/SURVEY.md` where they conflict. The two changes that matter: **iPadOS 27 opened handwriting recognition to third parties**, and **PaperKit became a readable/writable canvas model**.

---

## 1. Feature table vs us

"Us" = current tree per `BUILD-STATUS.md`.

### Ink, handwriting, math

| Capability | Apple Notes 27 | Freeform 27 | OneNote iPad | Us | Read |
|---|---|---|---|---|---|
| On-device recognition | System-wide, 29 languages, Spotlight-indexable by any PencilKit app **[WWDC]** | Yes, search covers handwriting **[Apple]** | Search yes; ink→text **no** **[MS]** | Custom SearchKit index | Apple now hands us the engine |
| Handwriting → text | Smart Selection, copy/paste as text **[Apple]** | Copy as text **[Apple]** | **Unsupported on iPad**; Ink to Text is Windows-only **[MS]** | Lasso, no convert | Clearest win over OneNote |
| Refine / straighten | Refine, Straighten, animated Auto-refine **[Apple]**, **[Review]** | Hold-still smoothing, Snap to Shapes **[Apple]** | No (Samsung has Align) | HoldToShape only | Table stakes |
| Math | Math Notes: write `=`, inline solve; Insert vs Suggest; 2D/3D graphs **[Apple]** | Math Results modes **[Review]** | Ink to Math, narrow | None | No public math API — ours to build |
| Pencil Pro extras | Squeeze, double-tap, barrel roll, hover **[Apple]** | System defaults | Draw with Touch, stylus orientation **[MS]** | Partial; no hover preview | Cheap gap |

### Canvas, objects, AI

| Capability | Apple Notes | Freeform | OneNote | Us | Read |
|---|---|---|---|---|---|
| Canvas | Fixed page | Infinite, expands with content; dot grid only, no lines/squares **[Apple]**, **[Review]** | Every page is an expandable canvas **[MS]** | Pages; board = 3000×3000, one ink blob | Our board is a sketch pad |
| Zoom | Fit width | 10–400 %, pinch **[Review]** | Free | Page zoom + Zoom Window | Cap is a known complaint |
| Objects | Text, ink, tables, attachments | Sticky, shape, text, table, image, video, scan, link, file, connector **[Apple]** | Text boxes anywhere, images, ink, tables, audio **[MS]** | Sticky/text/shape/image planned | Structural gap: objects over ink |
| Connectors | — | Yes, snap + auto-next-node **[Apple]** | — | No | Needed to diagram |
| Scenes | — | Named camera views: reorder, present, export, shared **[Apple]** | — | Page bookmarks only | Best value/effort on boards |
| Links | Section links, `>>` note links, dividers **[Apple]**, **[Review]** | Board→Notes one-way, via PDF **[Review]** | Notebook/section/page tree | Page/bookmark links | Cross-doc links are ours to own |
| Audio | Record, live transcript, tap-word-to-seek, **AI summary** **[Apple]** | — | Page audio | Record/play; transcription engine-ready | ~1 day of UI |
| AI | Writing Tools, summaries, Image Wand, Siri AI **[Apple]** | Image Playground, on-canvas generation (paid tier) **[Review]** | Copilot Notebooks on iPad since Jul 2026; **ink not documented** **[Review]** | Page AI: summary, cards, Q&A | We beat OneNote on ink-grounded AI |
| Study | — | — | Tags only | SM-2 sets, CSV import, AI cards | Our moat |
| Price | Free | **Inside Apple Creator Studio**; premium AI gated **[Apple]**, **[Review]** | Free + Copilot licence **[Review]** | Personal | "No subscription" is ours to say |

---

## 2. Apple APIs to build on

Rule from `.memory/meta/lazy-code.md`: delete custom code when Apple ships the same thing.

### 2.1 PaperKit — board *and* text-doc canvas

`PaperMarkup` + `PaperMarkupViewController` give ink plus shapes, images, text boxes, links and loupes, with `MarkupEditViewController` (iOS) / `MarkupToolbarViewController` (macOS) **[Apple]**. Apple confirms PaperKit powers Notes markup, Preview, and **Freeform on macOS** **[WWDC26-372]**. iPadOS 27 opens the model: `subelements` is a read/write `MarkupOrderedSet`, `allowedInteractions` locks template elements, `MarkupAdornment` adds non-persisted overlays that track zoom/scroll, and each Pencil stroke is a markup element **[WWDC26-372]**.

**Replaces:** `ElementEditLayer`, element hit-testing/z-order/resize chrome, shape insertion, image cards, most element drawing in `VectorPageRenderer`. **Gives free:** `scrollConfiguration`, `zoomRange`, `contentVisibleFrame`, `setContentVisibleFrame(_:animated:)` — our zoom-to-fit and zoom-to-scene primitive **[Apple]**.

Caveat: `PaperMarkup(bounds:)` is a finite rect over a scroll view, so "infinite" stays large-bounds illusion — the same trick as our 3000 pt board, done by Apple. Keep our camera model and store the visible frame. iOS 26+, UIKit VCs in SwiftUI, and it owns its tool picker: plan a hybrid (PaperKit canvas, our `EditorToolState` pens).

### 2.2 `PKStrokeRecognizer`

New in 27 for iOS/iPadOS/macOS/visionOS: Swift **actor**, on-device, offline, 29 languages, works on **any** canvas via Bézier conversion **[WWDC26-203]**. Surface: `updateDrawing`, `recognizedText`, `indexableContent` (Spotlight-ready), `search(_:)` returning bounds, `recognitionVersion`, `supportedLanguages` **[WWDC26-203]**, **[Apple]**.

**Replaces:** our recogniser and the stroke→text half of `SearchKit`. Keep `SearchQuery`, filters and page-mark UI as consumers; feed `indexableContent` to Core Spotlight. Bounds make highlight overlays and VoiceOver reading of ink nearly free — the session calls that out **[WWDC26-203]**. Note: Simulator recognizes Latin scripts only.

### 2.3 PencilKit model access

Also new in 27: lossless `PKStrokePath` ↔ Bézier, stable `Identifiable` stroke IDs that survive undo and remote edits, controllable selection, wet-ink render groups, and slicing (programmatic erase that splits a stroke; substroke extraction by range) **[WWDC26-203]**. **Replaces:** our codec bridge, hand-rolled stroke splitting, and index-based identity. Adopt stable IDs before board/sync work.

### 2.4 Foundation Models (2026)

Rebuilt on-device model with image attachments; **Private Cloud Compute** (32K context, no API keys); a `LanguageModel` protocol for Apple, local MLX/CoreAI or partner models; built-in `OCRTool`, `BarcodeReaderTool`, `SpotlightSearchTool` (local RAG); **Dynamic Profiles** (swap model/tools/instructions inside one session); **Evaluations** framework; `fm` CLI and Python SDK **[WWDC26-241]**, **[Apple]**.

**Replaces:** our provider fallback ladder and prompt/JSON plumbing in AIKit. One session per feature, reasoning level per step; `SpotlightSearchTool` removes our embeddings store; `OCRTool` removes a Vision pipeline for scans; Evaluations gives a number for card/summary quality. Still absent: **no public handwritten-math API** — Math Notes lives in Notes/Calculator only, so §2.5 stays ours.

### 2.5 Speech, and our math route

`SpeechAnalyzer` (26) with `SpeechTranscriber` / `DictationTranscriber` replaces `SFSpeechRecognizer`; 27 adds `CaptureInputSequenceProvider`, `AssetInputSequenceProvider`, `AnalyzerInputConverter` **[Apple]**, **[WWDC25-277]**. Results are time-aligned to the audio, which is exactly word-level "tap a word to hear it".

**Replaces:** our `AudioKit` transcription seam and any alignment code. Transcript → Foundation Models summary mirrors Notes' Summary button.

Math: `PKStrokeRecognizer.recognizedText()` on a math region → Foundation Models structured generation with a grammar; `=` as trigger; copy Notes' red (unsolvable) / blue (ambiguous) dot feedback **[Apple]**.

---

## 3. Pain points to beat

1. **Freeform performance.** Large boards lag while panning/zooming; reviewers report overheating and battery drain on new hardware **[Review]**, **[Review]**. We control the render path (`InkRenderViewport`), so cull off-screen objects and rasterise static layers. Target 500 objects + 20k strokes at 60 fps.
2. **400 % zoom, two backgrounds.** "Not impressive", and still no lined or squared option **[Review]**. Ship 800 % and lines/squares/dots as paper.
3. **Freeform is partly subscription now** — it sits under "Subscribe to Apple Creator Studio" in Apple's own guide **[Apple]**, **[Review]**. Ours: local, no account, no subscription.
4. **Collaboration is distrusted** — missed changes, missing items on collaborators' boards, unusable lag **[Review]**. We are personal-only: win with trustworthy history, real undo, lossless export.
5. **Flat organisation** — no tags, folders only in 27, and putting a note on a board needs a PDF export **[Review]**. Our library already has tags, folders, search: make "insert notebook page / text doc / study set as a live card" a board object.
6. **OneNote iPad has no ink→text, and Copilot doesn't document reading ink** **[MS]**, **[Review]**. `PKStrokeRecognizer` gives us the first for free; an ink-aware page AI beats Copilot on the same page.
7. **Apple Notes can't be a canvas; links are one-way.** Section links exist **[Apple]**, but no canvas, objects, scenes or study loop. Board + text docs + study sets in one library is a shape none of the three ship.
8. **Scenes are the missing navigation layer.** Reviewers call them the best tool for big boards **[Review]**. Adding a scene strip (save/restore `contentVisibleFrame`, name, thumbnail) is small and highly visible.

---

## 4. Plan changes

- **Board**: build on `PaperMarkupViewController`, not a hand-rolled item layer; keep our camera and add scenes. Re-check the 3000 pt world against a large `PaperMarkup` bounds.
- **Search**: `PKStrokeRecognizer` instead of our recogniser; keep the query layer; index to Spotlight.
- **AIKit**: one session with Dynamic Profiles; `SpotlightSearchTool` for library RAG; `OCRTool` for scans; an Evaluations target.
- **AudioKit**: `SpeechAnalyzer` + time-indexed `SpeechTranscriber`; transcript + Summary in the header.
- **Do not build**: collaboration, undo plumbing, a board ink engine, an embeddings store. **Study stays** — none of the three compete.

---

## 5. Sources

**Apple guides (iPadOS 27):** Freeform draw https://support.apple.com/guide/ipad/draw-or-handwrite-ipadf825a0bd/ipados · scenes https://support.apple.com/guide/ipad/navigate-and-present-scenes-ipad9c7aadac/ipados · settings/grid/guides https://support.apple.com/guide/ipad/change-freeform-settings-ipadcb84e16e/27/ipados/27 · insert media https://support.apple.com/guide/ipad/add-images-scans-links-and-other-files-ipada82c9eff/ipados · Creator Studio https://support.apple.com/guide/ipad/ipadc82420c67/ipados · Notes handwriting https://support.apple.com/guide/ipad/add-drawings-and-handwriting-ipada87a6078/ipados · Notes audio https://support.apple.com/guide/ipad/record-and-transcribe-audio-ipadd0bde806/ipados · Notes links https://support.apple.com/en-mide/guide/ipad/ipad03a11b57/ipados · Math Notes https://support.apple.com/guide/ipad/solve-math-with-math-notes-ipadeb38d0f8/ipados · feature availability https://www.apple.com/ios/feature-availability

**Apple developer:** iPadOS 27 https://developer.apple.com/ipados/whats-new · PaperKit https://developer.apple.com/documentation/paperkit · PaperKit integration https://developer.apple.com/documentation/paperkit/getting-started-with-paperkit · `PaperMarkupViewController` https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller · PencilKit recognition sample https://developer.apple.com/documentation/pencilkit/building-a-handwriting-recognition-experience-with-pencilkit · Foundation Models https://developer.apple.com/foundation-models-framework · SpeechAnalyzer https://developer.apple.com/documentation/speech/speechanalyzer · SpeechTranscriber presets https://developer.apple.com/documentation/speech/speechtranscriber/preset

**WWDC:** 26-203 https://developer.apple.com/videos/play/wwdc2026/203 (transcript https://nonstrict.eu/wwdcindex/wwdc2026/203/) · 26-372 https://developer.apple.com/videos/play/wwdc2026/372 (notes https://wwdc.ai/2026/372) · 26-241 https://developer.apple.com/videos/play/wwdc2026/241 · 25-285 https://developer.apple.com/videos/play/wwdc2025/285 · 25-277 https://developer.apple.com/videos/play/wwdc2025/277

**Microsoft:** handwritten notes https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/take-handwritten-notes-in-onenote · ink gestures https://support.microsoft.com/en-us/onenote/onenote-help-and-learning/ink-faster-with-gestures-for-creating-shapes-deleting-ink-and-more · iPad drawing modes https://support.microsoft.com/en-us/onenote/onenote-for-ipad-or-iphone-help-and-learning/select-a-drawing-mode-in-onenote-for-ipad-or-iphone · Goodnotes vs OneNote https://www.goodnotes.com/blog/goodnotes-vs-onenote · Copilot scope https://templacity.com/onenote/copilot-in-onenote

**Reviews:** Freeform in iPadOS 26 https://beingpaperless.com/apple-freeform-in-ipados-26-review/ · Freeform full review https://beingpaperless.com/apple-freeform-everything-you-need-to-know · Smart Script https://www.macstories.net/stories/ipados-18s-smart-script-a-promising-start-but-dont-toss-your-keyboard-out-yet/ · Notes in iOS 27 https://9to5mac.com/2026/09/28/heres-everything-new-for-apple-notes-in-ios-27 · section links https://www.macobserver.com/tips/round-ups/how-to-link-to-section-of-note-ios-27-notes/ · handwriting API opened https://www.heise.de/en/news/iPadOS-27-Apple-opens-handwriting-recognition-for-third-party-apps-11349267.html · OneNote iPad ink-to-text https://macmyths.com/how-to-use-handwriting-and-ocr-features-of-onenote-in-ipad

**Gaps:** Freeform's preset zoom values and any iPadOS 27 presentation timing are UNCONFIRMED; OneNote's iPad Copilot-with-ink behaviour is undocumented in both directions; no public handwritten-math API found in any 2026 source.
