# Competitor research — Notability vs Noteshelf 3 (late 2026)

Baseline: `research_notes/competitors/{notability,noteshelf}/FEATURES.md`. This adds the 2026 delta and the foundation each hard feature needs in **our** code (`NoteApp/`, `Packages/`).

Versions: **Notability 16.13.5** (2026-11-09, 4.76★ / 458,779 US ratings) [N1]; **Noteshelf 3 8.1.2** (2026-11-11, 4.54★ / 7,261 US ratings) [S3].

---

## 1. Feature table

| Feature | Notability | Noteshelf 3 | Us |
|---|---|---|---|
| Audio recording | Yes, multiple clips per note [N3] | Yes, page-attached clip [S10] | **Yes** (`Audio/NotebookAudio.swift`) |
| Replay audio by touching ink/text | Yes — "Note Replay", tap anything [N3] | **No**, audio is page-level only [S11] | **Partial** — per-point stroke times + `AudioAnchor`; no tap-to-seek UI |
| Live transcription | Plus/Pro; live transcripts Pro [N4][N5] | Yes, iOS 26+, with key points [S2][S11] | **Partial** — `SpeechAnalyzerTranscriber` exists, no UI |
| Clip trim/split/merge, speed, voice boost | Yes, 0.7–2×, Voice Boost [N3] | Speed only [S10] | **Partial** — play/seek only |
| Learn / quiz mode | Summary, quizzes, flashcards; Practice/Memorize/Test [N5] | No quiz engine [S9] | **Yes (lite)** — summary, ask, AI flashcards |
| Spaced repetition | Ratings + Anki import [N5] | No | **Yes** (`StudyKit` SRS scheduler) |
| Handwriting → text | Per selection [N6] | Lasso → convert [S1] | **Yes** (PencilKit recognition + index) |
| Math → LaTeX | Yes, MyScript, editable LaTeX [N6] | **No** — top user request [S21] | **No** |
| Handwriting → graph | Yes [N7] | No | **No** |
| Infinite canvas | **No** dedicated canvas [N22] | **No**; "Add Space" enlarges one page [S3] | **Yes** — BoardKit freeform board (branch) |
| Multi-note split | In-app, horizontal/vertical [N8] | No in-app split; OS windows only [S13] | **Yes** (`NotebookView` tabs + split) |
| Layers | No (front/back only) | **No** (front/back only) [S14] | **Yes** (`LayersPanel`) |
| Pen engine | Pressure/tilt, stabilization 0–1 (default 0.3) [N12][N11][N20] | 4 nibs, 0.1 mm slider [S1][S11] | **Yes** — custom renderer, `InkRenderViewport` |
| Stabilization | Per-tool + global default [N11][N20] | Not documented | **Partial** — planned |
| Calligraphy nib + barrel roll | Yes, nib angle, roll, lock [N-features] | No | **No** |
| Shape recognition | Hold → shape, snap guides, stroke/fill/ink fill [N14] | Hold to convert, editable, fills (2026) [S16] | **Yes** (`HoldToShape`); no guides/fill UI |
| Smart highlighter (snaps to text) | Yes, PDF + typed text [N15] | No | **No** |
| Tape / study cover | Yes, 12 sizes, 9 patterns | Yes, tape + patterns [S11] | **No** |
| Zoom view with auto-advance | Yes, target box, auto-wrap [N-features] | Zoom box, resizable [S15] | **Yes** (`ZoomWindowView`) |
| Gallery / community content | Yes — publish, browse, download [N9] | Template Store + editorial "Discover" [S5] | **No** |
| Templates | 20,000+, planners [N2] | 200+ store, custom PDF/PNG paper [S5][S6] | **Yes** — 3 categories, custom paper |
| Tags | **No** (folders only) | Page + notebook tags [S18] | **Partial** — folders only |
| Subjects / dividers | Retired in v15 [N10] | Categories + unlimited sub-groups [S17] | **Partial** — folders, depth 12 |
| AI assistant | Chat, Smart Notes, action items, YouTube→note [N2][N5] | ChatGPT: summarise/explain/translate, ink output [S9] | **Yes** — on-device FoundationModels + fallback (`AIKit`) |
| Handwriting search | Global/in-note, per-note language [N6] | Yes, 65 languages [S3] | **Yes** (`SearchKit`, Pencil query pad) |
| PDF import / annotate / outline | Yes, add space, outlines | Yes, blank pages, outlines [S1] | **Yes** (`PDFImporter`, `OutlinePanel`) |
| Export | PDF, NTB, JPEG, PNG [N19] | Image/PDF/.noteshelf, page toggles [S11] | **Yes** — vector/editable PDF + PNG |
| Version history | 7/30/90 days by plan [N2] | Trash restore only [S3] | **Yes** (`HistoryKit` snapshots) |
| Sync | iCloud or Notability Cloud, 4 platforms [N2][N19] | iCloud + Drive (Android) [S19] | **No** (`SyncKit` empty) |
| 3rd-party backup | One-way, PDF option [N16] | One-way, PDF, WiFi-only, Evernote [S19] | **No** |
| Lock | Folder only, no per-note | Per-notebook password + biometrics | **Yes** (`HistoryKit` lock) |
| Pencil Pro squeeze | Yes — erase, last tool, palette, arc menu [N13] | Not documented (double-tap only) [S11] | **Partial** — tap wired, no squeeze/haptics |
| Performance on large libraries | Sync blocks library, text-box lag [N27][N24] | Open lag; raster ink blurs when scaled [S11][S12] | **Ahead** — tiles, off-main raster, memory pressure |

---

## 2. Their technically advanced features and the foundation each needs

**2.1 Stroke-aligned audio replay.** Notability timestamps ink written during playback and seeks on tap of any word, sketch or photo [N3]; it still warns about 1-hour recording splits and gates transcription by plan [N3][N2]. Foundation: per-point times in the stroke model, a monotonic anchor that survives clock changes, ink hit-testing → offset, and a fast seek path. We already have `createdAt` + per-point offsets and `AudioAnchor` (monotonic, clock-jump repair). Missing: tap/lasso hit-test on the live canvas, seek, and a "now playing" ink highlight. Cheapest credible win: Noteshelf cannot do it by design [S11].

**2.2 Live transcription.** Needs a streaming recogniser with volatile/final segments, locale assets, and segment times on the same timebase as ink. We have `SpeechTranscriber`/`SpeechAnalyzerTranscriber` in `AudioKit`, unsurfaced. Missing: per-clip transcript store, segment→stroke search coupling, editing UI. Notability's is plan-gated [N2]; ours would be free and offline.

**2.3 Learn / quiz generation.** Notability extracts text (handwriting, PDF, audio), calls an LLM, returns summary/quiz/flashcards/action items; it requires 250–20,000 words, accepts one note only, and cannot export quizzes into a note [N5]. Foundation: extraction (we have `SearchKit` indexing), a structured schema (question, options, answer, source span), session state, grading, persistence into a study set. `AIKit` + `StudyKit` cover most of it. Their limits are the opening: multi-note scope, exportable cards.

**2.4 Math → LaTeX.** Two hard parts: segment handwriting into symbols with 2-D layout (superscripts, fractions, matrices), then recognise to LaTeX. Notability licenses MyScript and preserves colour, with editable source [N6]. Foundation: math OCR model or SDK, LaTeX renderer producing a vector element, round-trip editing. Most expensive item (weeks + licensing); demand is proven — Noteshelf lacks it and users ask [S21].

**2.5 Handwriting → graph.** Cheap once 2.4 exists: parse `f(x)`, plot in CoreGraphics, insert as vector element; two functions, ranges, intersections [N7].

**2.6 Infinite canvas.** Not a page-size hack: camera transform, on-demand endless background/grid, spatial index for hit-testing and culling, ink sharp across a huge zoom range. We have `BoardKit` (camera, layout, items, merge, store) and InkKit's zoom-invariant viewport; missing is ink *on* the board plus links between board regions and pages. Neither competitor has this [N22][S3].

**2.7 Multi-note split.** Notability does it in-app with orientation and a private second note while presenting [N8]; Noteshelf only opens OS windows, duplicating app state [S13]. Foundation: two live sessions, **per-pane tool state** (today one `EditorToolState`), per-pane undo, and a memory budget that degrades the background pane. Tabs/split exist; per-pane state and throttling are the work.

**2.8 Pen engine depth.** Notability's feel is stacked details: pressure/tilt, width steps, per-tool stabilization with a global default, dashed/dotted, calligraphy nib angle with Pencil Pro roll, hover preview, haptics [N12][N11][N13][N20]. Foundation: our rasteriser (have it), a One-Euro-style input filter, per-tool parameter storage. Barrel roll is awkward: PencilKit exposes roll-aware marker/fountain inks at `PKContentVersion.version3`; a fully custom pen needs roll from a non-PencilKit canvas. Ship stabilization + nib presets first; accept system ink for roll.

**2.9 Smart highlighter.** Requires *text-line geometry*, not pixels: PDFKit selection rects per word, TextKit 2 line fragments for typed text. Foundation: a per-background text-geometry provider plus a highlighter type that renders under glyphs and drags word-by-word [N15]. Medium effort, high polish, no Noteshelf equivalent.

**2.10 Tape, zoom auto-advance, gallery.** Tape = element with pattern, mask, and "hidden in export" flag — easy on our element model, and turns any note into a flashcard. Zoom auto-advance needs band geometry and wrap rules (we have `ZoomBand`). A gallery needs signed template bundles, a catalog and moderation; Notability's is a network-effect moat [N9], so ship a local template pack instead.

**2.11 Sync is the real gap.** A safe design: files stay the source of truth; add a per-page op log with stable stroke IDs and tombstones; sync the log (CKSyncEngine or Drive); never block the library on network. Until then, position as "local-first, versioned, exportable" — stronger than cloud-first apps that hide notes behind a spinner.

---

## 3. Pain points we can beat

1. **Sync-shaped data loss.** Sync/data loss is the top complaint across 11 note apps, present in 11/11, ~6.7× other categories; "notes permanently lost" in 10/11 [N25]. Notability users report sync erasing journal entries twice [N23]; Ginger Labs' KB treats an empty library as an account mismatch [N19]. Noteshelf users migrated 200 notebooks one at a time, backups silently failing [S22][S21]. Beat it by architecture: local files, snapshots, exportable native+PDF backup, no login before writing.

2. **Subscription and AI-paywall fatigue.** Notability's 2021 switch is still the wound; the Anki-import launch drew "monster trying to meet the needs of investors" [N26]. Classic returned in July 2026 at $39.99/$49.99, Starter capped at 5 notes [N18] — a partial retreat that validates the complaint. Noteshelf charges once but made NS3 a new paid app, stranding NS2 users [S21]. We are personal-use, on-device: no subscription, no AI meter, no account.

3. **Audio is the category's most neglected feature.** Noteshelf's audio "hasn't improved at all", is page-level and cannot replay from ink [S11][S12]. Notability's is good but plan-gated with a 1-hour split warning [N3][N2]. Beat both: stroke-level replay, segmented files for unlimited length, free offline transcripts, trim/merge.

4. **Raster ink.** Noteshelf renders raster ink, so scaled handwriting blurs [S11][S12]. We already re-render at seen zoom — a visible 8× win.

5. **Lag in big notebooks.** Notability: library frozen 30+ minutes during sync, text-box lag after 15.4.4, Android eraser/undo lag [N27][N24]. Noteshelf: "please fix open lag" [S21]. Answer with measured cold-open and stroke latency.

6. **No layers, no infinite canvas.** Both only do bring-to-front/send-to-back [S14]; neither has a whiteboard. We have both — "diagram on a board, notes on a page, linked" is unreachable for them without re-architecting.

7. **Migration and lock-in.** NS2→NS3 lost handwriting search on migrated pages and removed features users relied on [S21]; Notability retired Subjects/Dividers in v15 [N10] and has no per-note password. Our answer: documented open format (JSON+zlib pages), vector PDF export, no feature removals.

8. **AI that cannot leave the note.** Learn needs 250+ words, one note, and cannot export a quiz [N5]; Noteshelf sends selections to the ChatGPT API [S9][S12]. Beat it with grounded on-device retrieval, multi-note scope, and cards in a library the user owns — closing the loop: record → annotate → cards → SRS review → jump to the exact page and audio offset.

**Copy:** math conversion, tape patterns, smart highlighter, template distribution, left-handed presets, unlimited sub-groups, per-notebook scroll, PDF backup, calligraphy nib. **Skip:** cloud-first sync, AI metering, chat-with-library as a headline.

---

## Sources

**Notability** — [N1] apps.apple.com/us/app/notability-ai-notes-pdf/id360593530 · itunes.apple.com/lookup?id=360593530 · [N2] notability.com/pricing/compare · [N3] support.gingerlabs.com/en-us/articles/16300122-recording-and-playing-audio · [N4] …/16300075-audio-transcripts · [N5] …/16300046-notability-learn · [N6] …/16300114-handwriting-and-math-conversion · [N7] …/17737566-graphs · [N8] …/16300213-multi-note-and-note-switcher · [N9] …/16300109-notability-gallery-overview · [N10] …/16300129-subjects-and-dividers-version-15-and-below · [N11] …/18321210-ink-smoothing · [N12] …/16300204-writing-with-apple-pencil · [N13] …/16300052-squeeze-gestures-with-apple-pencil-pro · [N14] …/16300159-creating-and-styling-perfect-shapes · [N15] …/16300200-highlighter · [N16] …/16300117-auto-backup-third-party-backup-guide · [N18] blog.notability.com/post/you-asked-we-listened-classic-is-back · [N19] support.gingerlabs.com/en-us/articles/16810282-notes-missing-after-signing-in-to-your-notability-account and blog.notability.com/post/one-notebook-for-every-meeting-on-your-calendar · [N20] blog.notability.com/post/hey-siri-find-my-notes-in-notability · [N22] goodnotes.com/blog/goodnotes-vs-notability · [N23] reddit.com/r/notabilityapp/comments/1rg5hme/very_frustrated_user · [N24] reddit.com/r/notabilityapp/comments/1rxdf46/notability_lagging_issues_after_update_1544 · [N25] reddit.com/r/AppIdeas/comments/1vh6cj4/notetaking_app_existing_apps_have_same_unfixed · [N26] reddit.com/r/notabilityapp/comments/1ucpfxd/dear_notability_staff_please_read_this · [N27] justuseapp.com/en/app/360593530/notability/reviews

**Noteshelf 3** — [S1] noteshelf.net/new/features · [S2] noteshelf.net/new/noteshelf-ai · [S3] apps.apple.com/us/app/noteshelf-3/id6458735203 (+ lookup id 6458735203) · [S5] noteshelf-support.fluidtouch.biz/hc/en-us/articles/22808638737689--v8-0-2-Introducing-The-All-New-Template-Store · [S6] …/4408484586009-How-to-Create-Custom-pages-Covers · [S9] …/21713907764505-Introducing-AI-for-Noteshelf-3 · [S10] …/1500001623222-How-to-create-and-manage-Audio-Recordings-in-Noteshelf-iOS · [S11] paperlike.com/blogs/paperlikers-insights/noteshelf-review · [S12] beingpaperless.com/noteshelf-3-for-the-ipad-complete-review · [S13] …/21885120773529-How-to-view-two-notebooks-side-by-side · [S14] …/18783688583321-Layers-Send-to-back-Bring-to-front · [S15] …/4414988800025-Where-is-the-Zoom-Mode-icon-in-v8-6 · [S16] …/22746403936793--v8-0-4-All-new-Draw-Straight-Lines-Editable-Shapes · [S17] …/360046855313-How-to-Categorize-Shelves-in-Noteshelf · [S18] …/22809060465561-How-to-Create-Manage-Tags · [S19] …/19504346634393-How-to-enable-Auto-back-up-in-Noteshelf-iOS · [S20] …/4402353351321-New-Presentation-Mode-in-Noteshelf-iOS · [S21] justuseapp.com/en/app/6458735203/noteshelf-3-digital-notes/reviews · [S22] play.google.com/store/apps/details?id=com.fluidtouch.noteshelf3 · [S23] reddit.com/r/GoodNotes/comments/16t1v2y/any_opinions_on_noteshelf_3_noteful_kilonote_or
