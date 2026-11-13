# 08 — Test coverage and build health

Measured 2026-11-13 on macOS 27.2.1 / Xcode 27.2 / Swift 6.4.2, arm64. Each package ran `swift test`
inside `Packages/<name>`, sequentially. No `xcodebuild` was run; the app project was inspected only.

## Results

| Package | Framework | Tests | Pass | Fail | Time | Notes |
|---|---|---|---|---|---|---|
| NoteCore | Swift Testing | 83 | 83 | 0 | 21.8 s | 21.8 s is one randomized page-codec fuzz test |
| InkKit | Swift Testing | 109 | 109 | 0 | 0.3 s | 15 suites; render benchmarks gated behind `NOTEAPP_BENCH` |
| BoardKit | XCTest | 42 | 42 | 0 | 0.2 s | Only package on XCTest; Swift Testing discovers 0 here |
| HistoryKit | Swift Testing | 62 | 62 | 0 | 0.1 s | Real Keychain replaced by a fake |
| TextDocKit | Swift Testing | 49 | 49 | 0 | 0.01 s | |
| StudyKit | Swift Testing | 48 | 48 | 0 | 0.005 s | |
| AIKit | Swift Testing | 45 | 45 | 0 | 0.08 s | FoundationModels tested via injectable fake |
| SearchKit | Swift Testing | 41 | 41 | 0 | 0.07 s | |
| AudioKit | Swift Testing | 22 | 22 | 0 | 0.01 s | Hardware recorders replaced by fakes |
| SyncKit | Swift Testing | 1 | 1 | 0 | 0.001 s | Placeholder only — see below |
| **Total** | | **502** | **502** | **0** | ~22 s | |

**SyncKit has no implementation.** `Sources/SyncKit/SyncKit.swift` is the SwiftPM template
(`public func hello()`); its single test is an empty `example()`. Sync is not untested — it does not exist.

**Stale doc:** `BUILD-STATUS.md` claims "316 passing" with package counts that no longer match (502).

**Harness caveat:** `Packages/InkKit/run-tests.sh` exists because PencilKit's `PKReplicaManager` traps in
`PKDrawing.init(strokes:)` on a second consecutive run without a bundle ID. Plain `swift test` there is not
repeatable; the wrapper clears replica prefs and restarts `cfprefsd`. CI must use it.

## Source files with no tests

| Package | Untested / indirect-only |
|---|---|
| NoteCore | `Store/LibraryLayout.swift` (indirect), `Model/LibraryInfo.swift`, `PageScrollMode.swift`, `PencilDoubleTapAction.swift`; `LibraryStore.saveFolderTree` and `setFolderAppearance` have no direct call |
| InkKit | `PencilCanvasView.swift` (646 lines, `#if os(iOS)`), `HoldToShape.swift` gesture half (`HoldGestureRecognizer`, `PendingShapeReplacement`; `ShapeStrokeBuilder` is tested), `PageElementRenderer.swift` (only through `PageRenderer` suites) |
| SearchKit | `HandwritingRecognizer.swift` (`PencilKitRecognizer`) |
| AudioKit | `AVFoundationAudioRecorder.swift`, `SpeechAnalyzerTranscriber.swift` (device-only) |
| HistoryKit | `AtomicFile.swift` (indirect) |
| TextDocKit | `MarkdownSyntax.swift`, `Support/TextDocJSON.swift`, `TextCaretPosition` (indirect) |
| AIKit | `Internal/TokenEstimator.swift` (no test at any level); arithmetic/flashcard/sentence helpers only via `AIService` |
| BoardKit, StudyKit | none — fully covered |
| SyncKit | entire package is a stub |

**The whole app layer (`NoteApp/`, 61 files, ~19k lines) has zero tests.** `NoteApp.xcodeproj` contains one
`PBXNativeTarget` (`NoteApp`, application), no test or UI-test bundle, no shared test scheme.

## Build health

- **CI:** none. No `.github/`, no `Makefile`, no `*.yml`. `scripts/` holds only `harness-sync.py`.
- **Warnings-as-errors:** none, in app or packages.
- **SwiftLint / swift-format:** absent (no config, no build phase).
- `SWIFT_VERSION = 6.0`, `IPHONEOS_DEPLOYMENT_TARGET = 27.0`; packages declare iOS/macOS 27.0.

## Risk map

Package cores are strong: `PageCodec` fuzzing, trash/restore byte-equality, `HistoryKit` prune and
atomicity, `BoardMerge` commutativity/associativity, PDF-conversion geometry, `SearchIndex` persistence and
freshness. Exposure is the **app-layer glue** composing them, plus iOS-only files macOS tests cannot compile.

- **Persistence glue** — `NotebookSession.commitPendingSave`: 400 ms debounce, `writeChain` ordering,
  failure requeue. App-level; a bug loses ink silently.
- **Stroke merge glue** — `strokesChanged`'s `deletedStrokeIDs` union/subtract and stale-page guard.
- **PDF export** — `NotebookExporter.pdfData`: page selection, editable-vs-flattened ink, cancellation.
- **PDF import** — `PDFImporter`: ranges, scanned-page asset naming/dedupe, password, rollback.
- **Search integration** — `HandwritingSearch` (234 lines): batch deferral, 25-page flush, reindex.
- **iOS-only gestures** — `HoldToShape` timer/replacement/undo.
- **Folder appearance** — `setFolderAppearance` untested at package level.
- **Audio device layer** — permissions, interruption, transcript ranges proven only against fakes.
- **AI prompt budget** — `TokenEstimator` unverified.

## Top 10 missing tests, ranked by risk

| # | Test | Pins this exact behavior |
|---|---|---|
| 1 | `NotebookSession` save coalescing/ordering | Two edits 100 ms apart write once, newest wins; `commitPendingSave` awaits all earlier writes; a failed write keeps the page queued and a newer edit supersedes it; `flushPendingSave` leaves nothing unsaved before a snapshot |
| 2 | `strokesChanged` tombstone math | Erased stroke joins `deletedStrokeIDs`; redrawn stroke leaves it; hidden-layer strokes survive; a report for a stale `pageID` is dropped |
| 3 | `NotebookExporter.pdfData` | `Pages` mode picks the right indices; `.editable` exports only opaque ink as annotations; translucent highlighter is flattened; cancel writes no partial file; a bad page errors with its 1-based number |
| 4 | `PDFImporter.importPDF`/`insertPages` | Selection→PDF index mapping; password retry; each scanned page gets a unique asset and identical scans dedupe; mid-import failure leaves the notebook unchanged; outline maps to page order |
| 5 | `HandwritingSearch.indexAll` | Cancel mid-pass leaves a loadable index; flush every 25 pages; deleting a page/notebook removes its hits; recognizer version bump re-recognises; a replaced index is never written by the stale batch |
| 6 | `LibraryStore.setFolderAppearance` | Colour/icon round-trip via `saveFolderTree`; survives reopen; unknown folder throws without writing |
| 7 | `HoldGestureRecognizer`/`PendingShapeReplacement` (iOS) | Hold ≥ threshold with no movement; only the held stroke is replaced; undo restores the original; cancel leaves the canvas untouched |
| 8 | `NotebookSession.restore` merge | Restored page tombstones ink added after the snapshot; ink deleted since stays deleted; a stale snapshot cannot resurrect strokes |
| 9 | `AVFoundationAudioRecorder` + `SpeechAnalyzerTranscriber` (iOS) | Permission denial yields a typed error and no file; stop finalises duration; segments use half-open ranges through the trailing one |
| 10 | `TokenEstimator` | Estimate grows monotonically; text over budget truncates before the provider call; empty text is zero |

## Minimal CI/test foundation plan

1. **CI:** `.github/workflows/ci.yml` on `macos-26` (Xcode 27). Matrix job per package running `swift test`
   (InkKit via `run-tests.sh`), plus one app build job for the iPad simulator. Cache `Packages/*/.build`.
2. **App test target:** add `NoteAppTests` with `TEST_HOST` and a shared scheme so `xcodebuild test` works.
   Run on the simulator — gesture files are `#if os(iOS)` and never compile on macOS.
3. **Extract, don't just test UI:** move the save chain, tombstone math, exporter, import page-planning and
   search batching into packages so tests 1–5 and 8 run under `swift test`. This is the highest-value step.
4. **Warnings as errors:** enable for package targets first (all build clean today); app after a sweep.
5. **Lint:** `swift-format` check plus a small `.swiftlint.yml` (force casts/tries, empty count); warn for a
   week, then block.
6. **Flake guard:** document the InkKit wrapper; `NOTEAPP_BENCH=1` stays a manual job.
7. **Coverage floor:** `--enable-code-coverage` on packages, no per-package drop below today's baseline.
8. Regenerate `BUILD-STATUS.md` from CI so 316-vs-502 drift cannot recur.

Effort: CI + scheme + test target ≈ 1 day; extracting tests 1–5/8 ≈ 2–3 days; lint and warnings ≈ 0.5 day.
