# 14 — Technical research: ink engine, stroke formats, sync, tiling, recognition, packaging

As of 13 November 2026. Scope: what the state of the art is, what the leaders actually ship, and what our foundation should do given that we are on PencilKit, JSON+zlib page files, one live canvas per notebook, and an empty `SyncKit`.

**Bottom line.** Stay on PencilKit. The four reasons to write a custom ink engine (brush textures, pressure curves, partial-erase control, stroke identity) were each narrowed by iOS 27, and the leaders' engines cost years and teams. The real foundation work is not the renderer: it is (1) a stroke record lean enough to sync, (2) a per-page merge rule that treats ink as a set of strokes, (3) a tile cache that survives deep zoom, and (4) a bundle format that a file-sync transport can diff. All four are cheap now and expensive to retrofit.

---

## 1. Custom ink engine vs PencilKit

**Options.** (a) PencilKit as the live surface, our own model underneath. (b) PencilKit replaced by a Metal renderer fed by raw `UITouch` coalesced + predicted touches. (c) Hybrid: PencilKit for the wet stroke, our renderer for committed strokes at high zoom.

**Trade-offs.** PencilKit gives system latency, palm rejection, Pencil Pro squeeze/barrel-roll/hover, eight ink types, undo, and now recognition — for free, and it improves with the OS. Its ceiling is control: no custom brush textures, no pressure curve editing, no per-stroke identity until iOS 27, no layers. A custom engine buys pen feel and vector fidelity at the cost of a renderer, a stroke model, an eraser with masks, selection, undo, and every OS regression becoming yours. Apple's own guidance for closing the gap is predicted touches (`touchesPredicted`) plus a ProMotion-aware render loop, which is what a custom engine has to implement anyway.

**What the leaders use.** Goodnotes runs a custom engine "built on low-level graphics APIs: Metal on iOS and WebGL on the web", keeping >60 fps, with 1.47M lines of shared Swift across platforms — a decade of work. Notability stores every stroke as an editable Bézier object, which is what lets it restyle, resize and let two people edit different strokes on one page. Smaller challengers market the engine as the product: Noteful's "InfiniteStroke", Endless Paper's "Fractile" at 120 fps with millions of strokes on screen. Concepts is a vector–raster hybrid on an infinite canvas.

**Recommendation.** Keep PencilKit, and keep the `InkKit` boundary strict: `PencilCanvasView` may expose only page-space strokes, never a `PKDrawing` to the app layer. Do not start an engine. Revisit only if pen feel becomes the reason someone chooses the app, and even then build it as a second `InkEngine` implementation behind the existing protocol, not a rewrite. iOS 27 already removes three of the four historical reasons: controllable wet-ink `renderGroupID`, programmatic erase with masks, and stable stroke identity.

---

## 2. Stroke data formats and compression

**Options.** (a) Opaque `PKDrawing.dataRepresentation`. (b) Our `StrokeRecord` with full PencilKit point fidelity, JSON + zlib. (c) Quantised, delta-encoded binary, optionally Bézier control points only. (d) Interchange formats (ISF, WILL, InkML) for export.

**Trade-offs.** (a) is smallest and exact but opaque, undocumented, and unusable for search, merge, or a Mac renderer. (b) is debuggable and lossless-ish — our codec stores 12 doubles per point (x, y, time, width, height, opacity, force, azimuth, altitude, secondaryScale, threshold, lateralJitter) plus transform, seed and mask — but JSON repeats keys and prints full-precision decimals. Our largest simulator page is 68 KB compressed, so this is not yet a problem at page granularity. It becomes one when a page is a sync unit, when we keep history, or when pages carry thousands of strokes. Industry practice: Microsoft ISF delta-encodes and compresses coordinates per stroke; WILL is an interchange format, not a storage format; Goodnotes keeps protobuf indexes plus per-note binary blobs; Notability keeps per-stroke Bézier objects in a zip + plist.

**Recommendation.** Keep JSON+zlib for now — it is the reason the format is inspectable and testable — but cap the growth now:
1. **Quantise** positions to 1/64 pt and widths/opacity/force to 8 bits; drop `threshold`/`lateralJitter` when equal to their defaults.
2. **Split geometry from attributes**: one shared tool/colour per stroke, points as flat arrays, not objects with keys.
3. **Store committed pages as Bézier**: iOS 27 converts `PKStrokePath` ⇄ Bézier losslessly for control points, so archived pages can shrink several-fold and still reconstruct exactly for editing.
4. Switch zlib to ZSTD via `Compression` if measurements justify it, and only after 1–3.

Do not adopt ISF/WILL as storage. Add them (or SVG) only as export targets.

---

## 3. Local-first sync: CloudKit vs file sync vs CRDT

**Options.**
- **CloudKit + `CKSyncEngine`**: record-level database sync, change tags, `serverRecordChanged` conflicts, persisted state serialisation, retry/rate-limit handling.
- **iCloud Drive (ubiquity container)**: whole-file sync, `NSFileCoordinator`, conflicts surfaced as `NSFileVersion` siblings ("abc 2.txt").
- **CRDT document** (Automerge / Loro / Yjs) on top of either transport.
- **Own log/merge over a simple transport** (Drive, WebDAV, S3).

**Trade-offs.** CloudKit is the only Apple option that gives per-record conflict detection and error reporting; NotePlan moved to it precisely because iCloud Drive "doesn't give control over the sync", reports no errors, and stalls until Files is opened. Its hard limits: 1 MB per record and per upload batch, so a page or a stroke run must be chunked, and deletions carry no conflict check. iCloud Drive is trivial to reason about (files are the truth) but resolves conflicts by duplicating files, and a whole-page file means a whole page is the conflict unit. CRDTs solve concurrent merge properly: Automerge 3 cut memory >10× (700 MB → 1.3 MB for Moby Dick), Loro leads synthetic benchmarks but its Swift bindings are still labelled experimental, and Yjs has the largest ecosystem. Goodnotes states it does conflict resolution "using Conflict-Free Replicated Data Types" — so stroke-level merging is what a mature product converges on.

**Recommendation.** Do not adopt a general CRDT library for ink. A page is a grow-only set of strokes keyed by stable ID plus a tombstone set plus last-writer-wins per-stroke attributes; that is a few hundred lines, it is deterministic, and it merges exactly the conflicts that matter (two devices adding strokes, one erasing). Put it in `SyncKit` as `PageMerge` with property tests, independent of transport. Then:
- **Transport A (chosen later):** `CKSyncEngine`, one record per page chunk ≤ 256 KB, plus a manifest record per notebook; merge stroke sets on `serverRecordChanged` instead of overwriting.
- **Transport B (Drive):** keep page files, use per-notebook monotonic log files (`ops/<seq>.json`) so a lost race costs one op batch, not a page.
- Never resolve a page conflict with whole-page last-writer-wins; that is how notes get lost, which is the top complaint about the incumbents.

---

## 4. Tiled rendering for deep zoom and infinite canvas

**Options.** (a) Re-render all strokes every frame (what a vector canvas does). (b) Raster cache per page at a few fixed scales. (c) Tile pyramid: fixed world grid, per-tile raster cache plus per-tile vector index, re-rendered on demand. (d) GPU analytic coverage (sparse strips / vello-style) — correct at any zoom, heavy to build.

**Trade-offs.** (a) is O(strokes) per frame and dies at a few thousand strokes. (b) is what we have: inactive pages are cached images capped at 3× and the live canvas re-renders at the seen zoom. It is cheap and looks right, but a 3× cap blurs past 3× and every tile invalidates on any stroke edit. (c) bounds work by screen area, makes zoom quality independent of stroke count, and gives a natural place to hang dirty-rect invalidation. Its cost is cache management and the "single huge stroke covers every tile" case. (d) is what Concepts-class engines reach for; it is a multi-quarter project and unnecessary for a page-bounded notebook.

**Recommendation.** Keep (b) for notebook pages — the sharp-ink viewport already solves the quality problem — but formalise it as a **tile cache keyed by (page, scale bucket, tile index)** with an LRU budget and per-tile dirty tracking, so a stroke only invalidates the tiles it crosses. For whiteboards (`BoardKit`), where the canvas is unbounded, adopt (c) properly: 512-pt world tiles, a spatial index from tile → stroke IDs, raster cache per tile per scale, and culling by tile before drawing. Do not build (d).

---

## 5. On-device handwriting recognition

**Options.** `PKStrokeRecognizer` (iOS 27), Vision text recognition on a rendered image, Google ML Kit Digital Ink, MyScript iink SDK, in-house model.

**Trade-offs.** `PKStrokeRecognizer` is a Swift actor, runs an on-device model, exposes `recognizedText()`, `indexableContent` (multiple candidates — better for search), `search(_:)` with match bounds, `supportedLanguages` (29 in iOS 27), and `recognizerVersion` for re-indexing; Simulator recognition is Latin-only. Vision works on pixels, so it needs a rasterised page, loses stroke bounds and costs a render. ML Kit is fully offline on iOS, covers 300+ languages and shapes/emoji, but takes only `(x, y, t)` points, adds a Google dependency and binary weight. MyScript is the accuracy leader for math/diagram parsing, licensed commercially with quote-based pricing. Building a model is a non-starter at our scale: Goodnotes spent three years with a ten-person ML team to reach 12 languages at >95%.

**Recommendation.** We already made this call correctly — `SearchKit` uses `PKStrokeRecognizer` and stores `recognitionVersion`. Finish the loop: re-index when the version changes, treat `indexableContent` (not `recognizedText`) as the search corpus, and keep a per-page "recognition unavailable" state for Simulator/non-Latin. Add ML Kit only if a non-Latin language becomes a real requirement; add MyScript only if handwriting-to-math becomes a product feature, and price it as a dependency rather than building it.

---

## 6. Document package formats

**Options.** (a) One bundle per notebook: `notebook.json` + `pages/*.page` + `assets/` (current). (b) One SQLite file per notebook. (c) One monolithic library database. (d) Zip container per notebook.

**Trade-offs.** (a) is diffable, per-file syncable, individually recoverable, and a corrupt page costs one page. Its weaknesses are write amplification (rewriting a page rewrites all its strokes) and no query layer. (b) gives atomic transactions, incremental page-level writes (SQLite only rewrites changed pages), FTS5 for search, and single-file portability — but a single-file document is hostile to file-level sync: every save changes the file, so the transport always sees a conflict. (c) is worst for sync and for partial damage. (d) is (a) with a container, which defeats the point of per-file sync.

**What the leaders use.** Goodnotes ships a package: `index.notes.pb`, `index.search.pb`, per-note blobs under `notes/<uuid>`, attachments, thumbnail. Notability ships a zip of plists plus a per-note payload. Apple Notes uses SQLite internally with its own export boundary. Obsidian is plain files and wins on ownership.

**Recommendation.** Keep (a) as the truth: one bundle per notebook, one file per page, assets content-addressed by hash so imports are uploaded once. Add a **rebuildable SQLite sidecar per notebook** (`index.sqlite`) for FTS, page metadata and stroke→page lookup — never truth, deleted and rebuilt freely. If page-write amplification becomes measurable (large pages, autosave every few seconds), move stroke payloads into the notebook's SQLite and keep `.page` export/import, but only with the merge rule from §3 already in place, because that migration changes the sync unit.

---

## What this changes in the foundation

| Area | Now | Change |
|---|---|---|
| Ink engine | PencilKit, custom zoom host | No change; enforce the `InkEngine` boundary |
| Stroke format | JSON + zlib, 12 doubles/pt | Quantise, flatten, Bézier archive; measure first |
| Sync | `SyncKit` empty | `PageMerge` (stroke set + tombstones + LWW), transport-agnostic |
| Rendering | Cached page images ≤3× | Tile cache keyed by scale bucket; tiles for boards |
| Recognition | `PKStrokeRecognizer` in SearchKit | Re-index on `recognizerVersion`; index `indexableContent` |
| Packaging | Per-notebook bundle | Add rebuildable SQLite sidecar; content-addressed assets |

## Sources

**Apple**
- Minimizing latency with predicted touches: https://developer.apple.com/documentation/uikit/minimizing-latency-with-predicted-touches
- ProMotion / frame rates: https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- `CKSyncEngine`: https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5 · WWDC23-10188: https://developer.apple.com/videos/play/wwdc2023/10188/
- CloudKit sample: https://github.com/apple/sample-cloudkit-sync-engine
- iCloud version conflicts (TN2336): https://developer.apple.com/library/archive/technotes/tn2336/_index.html
- `CATiledLayer`: https://developer.apple.com/documentation/quartzcore/catiledlayer
- WWDC26-203 Read between the strokes with PencilKit: https://developer.apple.com/videos/play/wwdc2026/203 (notes: https://wwdc.ai/2026/203)
- WWDC26-372 Unwrap PaperKit: https://developer.apple.com/videos/play/wwdc2026/372 (notes: https://wwdc.ai/2026/372)
- WWDC24-10214 Squeeze the most out of Apple Pencil: https://developer.apple.com/videos/play/wwdc2024/10214/

**Leaders and practice**
- Goodnotes on Swift/Wasm (Metal + WebGL engine, CRDT sync, 1.47M shared lines): https://www.swift.org/blog/bringing-goodnotes-to-web-with-swift/
- Goodnotes handwriting recognition (3 years, 10-person team): https://www.goodnotes.com/blog/machine-learning-engineer-handwriting-recognition
- Notability Calligraphy pen (per-stroke Bézier, concurrent stroke editing): https://blog.notability.com/post/meet-the-calligraphy-fountain-pen-and-the-engineer-who-built-it
- Endless Paper (Fractile engine, 120 fps, millions of strokes): https://www.endlesspaper.app/
- Noteful InfiniteStroke: https://apps.apple.com/fi/app/noteful-notes-pdf-markup/id1587904334
- PencilKit customisation limits: https://medium.com/@wesleymatlock/customizing-pencilkit-going-past-apples-tool-picker-b82eca7bfbe2

**Formats and compression**
- ISF specification (delta + compressed coords): https://www.loc.gov/preservation/digital/formats/digformatspecs/InkSerializedFormat(ISF)Specification.pdf
- WILL data format: https://cdn.wacom.com/u/marketplace/ink-sdk/will/170801_will_data_format_spec.pdf
- Goodnotes package layout: https://reverseengineering.stackexchange.com/questions/25731/how-are-strokes-stored-in-the-goodnotes-file-format
- Notability format teardown: https://jvns.ca/blog/2018/03/31/reverse-engineering-notability-format/
- SQLite as an application file format: https://www.sqlite.org/appfileformat.html

**Sync**
- NotePlan, CloudKit vs iCloud Drive: https://help.noteplan.co/article/16-what-is-the-difference-between-cloudkit-vs-icloud-drive
- Christian Selig, CKSyncEngine Q&A (1 MB records/batches, conflicts, state): https://christianselig.com/2026/01/cksyncengine/
- Automerge 3.0: https://automerge.org/blog/automerge-3/
- `automerge-swift`: https://github.com/automerge/automerge-swift
- `loro-swift` (experimental): https://github.com/loro-dev/loro-swift
- CRDT benchmarks: https://loro.dev/docs/performance

**Rendering**
- Tile-based rendering (sparse strips, cost model): https://infinitecanvas.cc/guide/lesson-035

**Recognition**
- PKStrokeRecognizer: https://developer.apple.com/documentation/pencilkit/pkstrokerecognizer
- ML Kit Digital Ink Recognition: https://developers.google.com/ml-kit/vision/digital-ink-recognition
- MyScript SDK: https://www.myscript.com/sdk/ · pricing: https://www.myscript.com/pricing/

## Known gaps

- We did not find a public statement of Goodnotes' tile or LOD strategy; the tiling recommendation is inferred from their engine description, not observed.
- `PKStrokeRecognizer` accuracy outside Latin, and its per-page latency at high stroke counts, are unmeasured here; only the 29-language and Simulator-Latin limits are documented.
- MyScript SDK pricing is quote-only; no public per-seat figure exists.
- CRDT-for-ink has no shipped public reference implementation besides Goodnotes' own; our `PageMerge` proposal is a design, not a validated library.
