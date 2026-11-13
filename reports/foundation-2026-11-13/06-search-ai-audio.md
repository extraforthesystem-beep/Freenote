# Search, AI & Audio Audit

Scope: `Packages/SearchKit`, `NoteApp/Search/*`, `Packages/AIKit` + `NoteApp/AI/*`, `Packages/AudioKit` + `NoteApp/Audio/*`. Read-only; every claim traced to code. ADRs: `2026-11-12-advanced-search.md`, `2026-11-12-sticky-tape-and-search-hits.md`.

**Already right.** The index is incremental at the recognition level (`SearchIndex.swift:336-351`) and persisted atomically — temp file + `replaceItemAt` (`:290-306`); clip metadata likewise (`AudioClipStore.swift:88-96`). Recognition is off-main: `PencilKitRecognizer` is non-isolated async (`HandwritingRecognizer.swift:27,46,57`), so `StrokeCodec.drawing` runs off-main (SE-0338). Writes batch through a deferral counter (`:272-288`) that a cancelled pass still closes (`HandwritingSearch.swift:88-93`). **No API key exists anywhere**: local providers only, no network client, so key storage cannot leak.

## 1. Findings

### CRITICAL

**C1 — A recording lives in `tmp` until stop; a crash loses all of it.**
`startRecording()` writes to `temporaryDirectory/"<uuid>.m4a"` (`NotebookAudio.swift:75-79`) and only moves bytes into the library on stop (`:98-116`); nothing sweeps orphans at launch, and clip metadata is written last (`:106-114`).
*Impact:* a 45-minute lecture dies with the app; iOS also purges `tmp/` under pressure. Silent and unrecoverable.
*Fix:* record into `<notebook>/audio/`, write metadata at stop, sweep unclaimed `.m4a` files at launch into recovered clips.

**C2 — The index is never updated while a notebook is open.**
Index work exists in four places only: launch (`AppModel.swift:166`), notebook close (`:811`), PDF import (`:525`), page delete (`:735`). `index(notebook:)` serves the close path only (`HandwritingSearch.swift:100-124`).
*Impact:* the in-notebook panel (`NotebookSearchPanel.swift:257` → `HandwritingSearch.swift:143-153`) searches the stalest notebook in the library. Write "photosynthesis", search it, get "No Matches".
*Fix:* call `index.update(page:…)` from the page-commit path, debounced ~2 s and coalesced; drain that queue before searching the open notebook.

### HIGH

**H1 — Every persist rewrites the whole index file; a rebuild is quadratic.**
`write()` encodes and replaces the entire record array per flush (`SearchIndex.swift:290-306`); deferral only turns N writes into N/25 (`HandwritingSearch.swift:97`), so a 10k-page rebuild rewrites a ~20 MB file ~400 times.
*Impact:* ~6–8 GB written for one Rebuild (`SettingsView.swift:183`).
*Fix:* one file per page, or SQLite FTS5 — O(1) writes, incremental delete, real ranking.

**H2 — Every launch re-reads every page and hashes every stroke to prove nothing changed.**
`indexAll` loops all pages, `store.loadPage` decodes each (`HandwritingSearch.swift:64-78`), and `contentHash` JSON-encodes the full `strokes` array and SHA-256s it (`SearchIndex.swift:658-669`, at `:336`).
*Impact:* launch cost scales with total ink bytes forever — hundreds of MB decoded and hashed per cold start — to learn "no change".
*Fix:* persist a cheap stamp (page mtime/size or manifest `updatedAt`); fingerprint only when it moves.

**H3 — Search is a linear scan whose miss path folds every word, on the index actor.**
Per segment and term, `search` falls back to `enumerateSubstrings(.byWords)` over the whole text when the exact substring misses (`SearchIndex.swift:421-430, 502-527`). It is synchronous on the actor, so it serialises against indexing.
*Impact:* at 10k pages with one typo, every segment takes the slow path; the UI blocks and a rebuild stalls per keystroke. No inverted index, no result cap.
*Fix:* FTS5 or a postings dictionary, prefix expansion, `LIMIT 200`.

**H4 — No timeout and no cancellation path for AI requests.**
`AIService.respond` checks cancellation around the call but sets no deadline (`AIService.swift:35-46`); the provider awaits `session.respond` unbounded (`FoundationModelsProvider.swift:220-225`). The panel fires un-retained `Task {}`s (`NoteAIPanel.swift:306-367`) with no handle and no Cancel.
*Impact:* a slow or `.modelNotReady` model leaves "Thinking on device…" with all controls disabled; dismissing does not stop the work.
*Fix:* race the provider against a 30 s deadline mapped to `AIError`; keep the task in `@State`, cancel on disappear.

**H5 — No audio-session interruption or route-change handling.**
The recorder activates `.playAndRecord` (`AVFoundationAudioRecorder.swift:61-71`) and never observes `interruptionNotification` or `routeChangeNotification` — no observer exists in `Packages/AudioKit` or `NoteApp`. `NotebookAudio` only polls `recorder.elapsedSeconds` (`:194-205`), which freezes.
*Impact:* a call or Siri stops capture while the UI shows "Recording…" and a frozen timer; the gap surfaces on playback.
*Fix:* observe interruptions, publish an interrupted state, stop the clock, resume on `.shouldResume` or say recording stopped.

**H6 — Stopping materialises the whole recording as `Data`.**
`stopRecording` reads the file with `Data(contentsOf:)` then hands the bytes to `store.addAsset` (`NotebookAudio.swift:102-105`), which copies again.
*Impact:* 30–60 MB peak for a lecture — a jetsam candidate exactly when the recording is finally safe.
*Fix:* move the file into the asset directory; stream rather than buffer.

### MEDIUM

**M1 — A corrupt index disables search until the user finds Rebuild.** `load()` empties records, keeps `loaded = false` and throws (`SearchIndex.swift:236-244`); `ensureLoaded` then re-throws every call, `update()` fails every page, and `search` swallows it with `try?` (`:423`). The ADR calls it a rebuildable cache, so failing closed is backwards. *Fix:* quarantine the file, start empty, rebuild automatically.

**M2 — No relevance ranking, despite the field suggesting one.** `matchedTermCount` is `query.groups.count` for every hit (`SearchIndex.swift:446`) — a constant, since `excerpt` requires all groups (`:475-484`) — so the first sort key is dead and the tie-break is a random UUID (`:456-457`). The UI re-sorts by group size and page (`LibraryView.swift:669-673`, `NotebookSearchPanel.swift:230`), hiding it; but no exact-over-tolerant, recency, or source weight exists to build on. *Fix:* score exact > phrase > tolerant, weight source, decay by recency.

**M3 — The AI panel re-runs recognition instead of reading the index.** `loadTextIfNeeded` calls `search.noteText` (`NoteAIPanel.swift:281-288` → `HandwritingSearch.swift:197-217`), rebuilding a `PKDrawing` for a page the index already holds text for (`SearchIndex.swift:45-64`). *Fix:* read the record's segments, recognise only when absent.

**M4 — A 12k-character cap against a 4k-token context, no chunking.** `AIService.swift:18` allows 12,000 UTF-16 units; the fallback context is 4,096 tokens (`FoundationModelsProvider.swift:13`). Oversize input yields a bare "too long" alert (`AIModels.swift:178-179`); `.notebook` scope has no map-reduce path. *Fix:* derive the cap from `contextSize`; chunk and reduce.

**M5 — The highlight overlay re-recognises after every stroke pause.** Its `.task(id:)` keys on the full stroke-ID list (`PencilSearchPad.swift:238-252`), so a 600 ms pause runs `inkBounds` over the whole page per term (`HandwritingRecognizer.swift:46-54,70-78`). *Fix:* skip while writing, scope to dirty strokes, cap terms.

**M6 — The corpus is resident, and indexing pings observation per page.** `records` holds every page's text for the process lifetime (`SearchIndex.swift:202`), and `indexedPages += 1` on the `@MainActor` (`HandwritingSearch.swift:79`) re-renders the banner per page (`LibraryView.swift:710`). *Fix:* throttle progress to ~4 Hz; keep the corpus in SQLite.

### LOW

- **L1** `search` has no cancellation check in its loop; a superseded scan runs to completion.
- **L2** `SearchIndex.isFresh` (`:315-319`) has no call sites — dead API.
- **L3** If `clipStore.save` fails after `addAsset`, the temp is deleted but the asset is orphaned (`NotebookAudio.swift:113-123`).
- **L4** Playback never deactivates the audio session (`NotebookAudio.swift:126-173`).
- **L5** `Packages/AudioKit` shadows the well-known third-party module of that name.
- **L6** The anchor is read after `record()` returns (`AVFoundationAudioRecorder.swift:89-105`), making `startedAt` late by the activation latency — harmless only because nothing consumes it.
- **L7** `NotebookView.onDisappear` stops recording (`NotebookView.swift:255-263`), so switching to the library silently ends the take.

## 2. Architecture limits

1. **No incremental write path and no query index.** One JSON blob, full rewrite per flush, and a linear scan with word enumeration are one decision: text search treated as a small cache. At 10k pages it fails on writes (H1), launch (H2) and latency (H3); FTS5 replaces all three and supplies ranking.
2. **The editor and the index are not connected.** The save queue knows which page changed and that the write succeeded; nothing forwards it. C2 is a missing wire between systems that already expose the right hooks.
3. **Handwriting is one lossy string per page** — no word bounds, confidence, or stroke mapping — so ink hit-testing is recomputed live through Apple's engine on every stroke.
4. **Audio is a disconnected side channel.** `AudioAnchor` has zero call sites in `NoteApp`; `AudioClip` stores no page or stroke reference (`AudioClip.swift:1-6`); `seek(to:)` (`:189-192`) is not wired to stroke selection, so "tap a stroke, hear that moment" does not exist. `SpeechAnalyzerTranscriber` is tested but never called: recordings are neither transcribed nor searchable, and `PageTextSource` has no audio case (`SearchIndex.swift:8-11`).
5. **AI is local-only and the fallback is a template engine.** `AIService()` wires both providers (`AppModel.swift:74`, `AIService.swift:15-19`), so without Apple Intelligence every action silently routes to `DeterministicProvider`, presented in the same register as a model answer (`NoteAIPanel.swift:92`) and with no escape from the 4k context.
6. **Index and clip metadata are per-device.** The index sits in the local cache dir (`HandwritingSearch.swift:33-37`); clip JSON in the notebook's private `audio/`. Whether SyncKit carries audio assets or rebuilds indexes is **UNVERIFIED** here.

## 3. Prioritized foundation changes

1. **P0 — Record into the asset directory with crash recovery** (C1): one move, one launch sweep; removes the only unrecoverable failure in scope.
2. **P0 — Wire page-save → `index.update`** (C2), debounced and coalesced, so search means "what I just wrote".
3. **P1 — Move the index to SQLite FTS5** (H1, H2, H3, M2, M6): per-page rows, replace-in-place writes, `MATCH` with `bm25()`. Keep `SearchQuery` parsing and `SearchHit`'s shape, so the UI does not change.
4. **P1 — Bound every AI call** (H4), read page text from the index first (M3), size the cap from `contextSize` with chunking (M4).
5. **P1 — Handle interruptions in the recorder** (H5, L7); stop buffering media as `Data` (H6).
6. **P2 — Self-healing index** (M1): quarantine and rebuild rather than failing closed forever.
7. **P2 — Real ranking** (M2): exact > phrase > tolerant, recency decay, source weight; keep notebook grouping.
8. **P2 — Finish the audio features the model assumes**: page/stroke anchors, `AudioAnchor.offset(for:)` for tap-to-seek, transcription indexed as a fourth source. Three well-built pieces have no consumer.

**UNVERIFIED:** SyncKit's handling of index and audio assets; H1–H3 timings on a 10k-page library (inferred from code shape, not measured); whether `.modelNotReady` can hang on this OS build (the missing deadline is verified, the hang is not).
