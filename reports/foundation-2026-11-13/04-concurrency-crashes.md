# 04 — Crash & Concurrency Sweep

Scope: all of `NoteApp/` and `Packages/*/Sources` (165 files, ~34.7k lines), read-only audit. Date 2026-11-13.

## 0. Headline

**No Critical findings.** The escape hatches this kind of sweep normally finds are almost absent: zero
`try!`, zero `as!`, zero `unowned`, zero `fatalError` outside `init(coder:)` stubs, two force unwraps
(both literal UUIDs, `BoardEditorView.swift:23,25`), one `nonisolated(unsafe)` (`NotebookAudio.swift:14`)
and two `@unchecked Sendable` (`NotebookAudio.swift:12`, `KeychainKeyStore.swift:66`). Indexing of
decoded or user data is consistently guarded (`PageTransform.init(_:):110`, `MarkdownSyntax.swift:34-37`,
`TextBlockEditing.swift:41,195`, `TextDocument.removeBlock(at:):47`).

The app is **already in Swift 6 language mode** (`SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
`SWIFT_APPROACHABLE_CONCURRENCY = YES` — `NoteApp.xcodeproj/project.pbxproj:247-251,291-295`; packages
`swift-tools-version: 6.4` + `ApproachableConcurrency`) and builds (`BUILD-STATUS.md`). What remains is
therefore not *unchecked* concurrency, but the few places where the model was deliberately widened, plus
resource fan-out no type system can see.

## 1. Ranked risks

### High-1 — Unsynchronised closure read across threads: `AudioPlaybackDelegate.onFinish`
`NoteApp/Audio/NotebookAudio.swift:12-33` (declaration `:14`), assigned at `:146`, read on the
AVAudioPlayer callback thread at `:22-24`.

`onFinish` is `nonisolated(unsafe) var`, written on the MainActor before `player.play()` and read from
`audioPlayerDidFinishPlaying` / `audioPlayerDecodeErrorDidOccur` on AVAudioPlayer's thread. Nothing
serialises the two, and Swift 6 cannot check it because the opt-out is on the storage.

Triggers: (a) play a clip, tap it again inside the callback window — `stopPlayback()` (`:158`) clears
`player`/`delegate` while a callback is in flight, then a new clip reassigns `onFinish`; the stale
callback hops to `@MainActor`, invokes the *new* handler, and the new clip stops ~0 s in. (b) The same
window is a real race on a closure reference (concurrent retain/release) → over-release → rare
`EXC_BAD_ACCESS`.
Fix: drop the unsafe storage. Keep `onFinish` `@MainActor` on `NotebookAudio`, have the delegate hold
`weak var owner: NotebookAudio?` and call `Task { @MainActor in owner?.finishPlayback() }`, plus a
playback-generation counter so a late callback cannot stop the current clip.

### High-2 — Unbounded `Task.detached` render fan-out (jetsam)
15 detached sites; no render path shares a limiter (no `TaskGroup`, `OperationQueue` or semaphore in the
tree — verified by grep). Fan-out: `PageThumbnailStrip.swift:182` (per cell), `PageBackground.swift:272`
(base, per page) and `:303` (sharp, up to 3× per pinched page — `quantized()`, `ContinuousPagesView.swift:307`),
`ContinuousPagesView.swift:649`, `LibraryCovers.swift:46,53`, `BoardThumbnail.swift:75`.

Trigger: fling a 421-page scanned-PDF notebook at 2–3× zoom on a 4 GB iPad. Each sharp render is a
1785×2526 (~18 MB) bitmap on top of the page image; the caches (`PageImageCache` 128 MB,
`ThumbnailCache` 64 MB, `PageBackgroundCache`, `LibraryCovers` 48 MB — ~400 MB per
`MemoryPressure.swift:5-8`) only *evict*, they never throttle. Cancellation is forwarded correctly
(`PageThumbnailStrip.swift:186-195`), so most off-screen work is skipped — but renders already holding a
thread finish concurrently. Outcome: jetsam kill (malloc failure), not a Swift-level crash.

Fix: one `actor RenderGate` with `maxInFlight = min(4, activeProcessorCount)`, acquired around the
`PageRenderer.image` calls. `InkKit` has no dependencies, so it belongs there (`PaperAppearance` at
`PageBackground.swift:29` is the common entry).

### Medium-1 — `PDFLinkHandler.lastDocument` is a permanent, never-invalidated retain
`NoteApp/Notebook/PDFLinkHandler.swift:19`, `:95-102`.

A static `(url, PDFDocument)` cache on the MainActor, keyed by URL, with no eviction, no
`invalidate` on notebook close, and no check that the file is unchanged. Two consequences: (a) the last
PDF opened for a link tap stays resident for the rest of the session — for scanned books that is tens
to hundreds of MB that `MemoryPressure.purgeCaches()` does not touch; (b) if the asset is replaced or
the notebook is re-imported at the same path, the stale document answers with the old page count and
old link rectangles, so a link tap jumps to the wrong page.
The design rationale (per-tap `PDFDocument(url:)` costs 0.2–1.1 ms) is sound — `PERFORMANCE-NOTES.md:37`
— so the fix is only lifecycle: expose `PDFLinkHandler.forget()` and call it from `closeTab`
(`AppModel.swift:790`), plus compare `URLResourceValues.contentModificationDate` before reuse.

### Medium-2 — Whole-file `Data(contentsOf:)` on the MainActor when importing an image
`NoteApp/Notebook/NotebookView.swift:476` (inside `fileImporter`'s completion, which is `@MainActor`).

A 48 MP HEIC or a multi-page TIFF is read synchronously on the main actor before `Task { await
session.addImageElement(...) }` hands the bytes on. Not a hang-watchdog crash, but a multi-hundred-ms
`RunLoop` stall on the exact gesture users repeat, and it doubles peak memory (bytes + decoded image).
Fix: move the read into the existing `Task`, `try await Task.detached { try Data(contentsOf: url) }.value`,
keeping the security-scoped access bracketed around the awaited read (use `withTaskCancellationHandler`
or a `defer` inside the task, not the outer `defer`).

### Medium-3 — PDF import materialises the entire file in RAM, twice
`NoteApp/Import/PDFImporter.swift:244` (detached `scan`), `:295-296` (`open` keeps both the
`PDFDocument` and the full `Data`), `:306` (`readData`).

A 1 GB PDF therefore needs the raw bytes plus PDFKit's parse structures before one page is written, and
`stored` then hands the same bytes to `store.addAsset` — a direct path from memory warning to jetsam in
the one action where a kill loses everything (`:160-164` does tear down the half-created notebook).
Fix: copy with `FileManager.copyItem` into the assets directory and open the document from that URL,
unlocking in place, instead of holding `Data`.

### Medium-4 — Last edit batch is dropped silently when autosave fails at close
`NoteApp/Notebook/NotebookSession.swift:900-918` (failure branch restores `pendingPage`), then
`AppModel.swift:805-810` (`closeTab` → `flushPendingSave`) discards the session without re-reporting.

`commitPendingSave` is correct in isolation (ordered chain, atomic writes, retry) but the failure is
only surfaced through `errorMessage` on a model that is about to be deallocated. If the disk is full,
the user sees "could not be saved" once and can then close the tab, losing that batch with no trace.
Fix: return the unsaved page IDs from `flushPendingSave()` and have `closeTab` keep the tab (or write a
recovery draft) when it fails.

### Low (verified, no action required — recorded so they are not re-litigated)

- Justified `@unchecked Sendable`: `SecurityKeychainKeyStore` (`KeychainKeyStore.swift:66,76`) serialises
  every keychain call behind an `NSLock`.
- `MainActor.assumeIsolated` × 3: `MemoryPressure.swift:25` (`.main`-queue observer), `HoldToShape.swift:229,253`
  and `PencilCanvasView.swift:51` (`DispatchQueue.main.async`, `UndoManager` main-thread handler). Correct
  *today*; they trap if that hop ever moves off the main queue. One comment each, no fix.
- PencilKit off the main actor: `BoardThumbnail.swift:89-105` builds a `PKDrawing` and rasterises it in a
  detached task; `PencilKitRecognizer` (`HandwritingRecognizer.swift:29-72`) runs `PKStrokeRecognizer`
  inside `SearchIndex`. Undocumented by Apple but data-only, with no shared recogniser.
- PDFKit off the main actor: `PageElementRenderer.drawPDFPage:136-177` opens its **own** `PDFDocument` per
  call, so it is safe *because* the document is local (`PERFORMANCE-NOTES.md:37` already notes a shared
  one would need a lock). Keep that rule.
- `fatalError("init(coder:)")` ×3 — `ZoomWindowView.swift:365`, `ContinuousPagesView.swift:286,1340`:
  only reachable via nib/storyboard decoding, which this project never does.
- `MemoryPressure.observer` is never removed (`:15,20`) — intentional app-lifetime, idempotent via
  `guard observer == nil`.
- `AppModel.start()` spawns unstructured maintenance (`:155-170`); `retryLoad` (`:166`) resets
  `hasStarted` and can spawn a second `search.indexAll` — duplicate work, never a race.
- Timers: there are none. Every "timer" is a cancellable `Task` + `Task.sleep`
  (`NotebookAudio.swift:194-204`, `HoldToShape.swift:145-155`), cancelled in the matching `stop()`;
  `StrokeHoldObserver` captures `[weak self]`, so an orphan task self-terminates.

## 2. Structural strengths (why there is no Critical)

Critical findings usually live here; do not regress these:

1. **`LibraryStore` is an `actor`** (`Packages/NoteCore/Sources/NoteCore/Store/LibraryStore.swift:10`),
   so `savePage` and `deleteNotebook` cannot interleave. That kills the classic "autosave resurrects a
   trashed notebook" corruption: `savePage` reads the manifest first (`:365`) and throws when the
   directory was moved (`:167`), so a pending write fails cleanly.
2. **Saves are an ordered chain** (`NotebookSession.commitPendingSave:876-918`): each write awaits the
   previous, so an older snapshot cannot land after a newer one; encoding is off the main actor.
3. **All I/O is atomic**: `AtomicFile.write` (temp → `synchronize` → `replaceItemAt`) and
   `LibraryStore.writeAtomically:683`.
4. **Every stateful subsystem is an actor**: `SearchIndex:176`, `VersionHistoryStore:50`, `AIService:4`,
   `AVFoundationAudioRecorder` (rationale `:12`); app state is uniformly `@MainActor @Observable`, with
   no global mutable state beyond the MainActor cache enums.
5. **Background flush is correct**: `RootView.swift:29-53` wraps per-session `flushPendingSave()` in
   `beginBackgroundTask`, so suspension cannot strand ink.

## 3. Swift 6 strict concurrency: already in effect

Nothing to migrate. In force today:

| Layer | Setting | Where |
|---|---|---|
| App target | `SWIFT_VERSION = 6.0` | `project.pbxproj:250,294` |
| App target | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | `:248,292` |
| App target | `SWIFT_APPROACHABLE_CONCURRENCY = YES` | `:247,291` |
| All 10 packages | tools 6.4 ⇒ Swift 6 mode | `Packages/*/Package.swift` |
| All 10 packages | `ApproachableConcurrency` upcoming feature | same |

`SWIFT_STRICT_CONCURRENCY` is absent because the v6 language mode implies it; there is no
`-swift-version 5` override, no `@preconcurrency import`, no `OTHER_SWIFT_FLAGS` suppression.

Remaining work, by value:

1. **Delete the last unsafe escape** (High-1). Afterwards the tree holds zero `nonisolated(unsafe)` and
   one justified `@unchecked Sendable`, which makes an audit rule enforceable.
2. **Add a render gate** (High-2): one small actor in `InkKit`, entered from `PaperAppearance` and
   `PageRenderer` — no call-site churn.
3. **Give `PDFLinkHandler` a lifecycle** (Medium-1): `forget()` on tab close plus an mtime check.
4. **Enforce in CI**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` on both targets and all packages (already
   zero-warning), plus a `scripts/` check failing on `nonisolated(unsafe)`, `@unchecked Sendable`,
   `Task.detached` outside an allowlist, `try!`, `as!` and `fatalError`.
5. **Do not** add `.defaultIsolation(MainActor.self)` to `NoteCore`/`SearchKit`/`HistoryKit`/`SyncKit`:
   they are deliberately nonisolated model layers and it would push MainActor hops into file and index
   code; applying it to `InkKit` alone is optional and low value.

Items 1–4 are about a day; none needs a language-mode change.
