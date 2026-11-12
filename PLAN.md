# NOTEAPP implementation plan

Written 2026-11-12. Planned Path, no code exists yet. Research behind this plan: `reports/iPad note app feature plan.md` and `research_notes/iPad note app feature plan/`.

Evidence tags used below: `[TESTED]` = checked by a command or a fetch of the vendor's own documentation in this session; `[RESEARCH]` = from the research notes, source page re-fetched during review; `[ASSUMED]` = believed, not checked, and listed as a risk in section 9.

## 1. Goal and locked decisions

A personal handwritten-notes app, iPad first with a Mac companion, built in Xcode with SwiftUI.

| Decision | Value | Source |
|---|---|---|
| Audience | Personal use only, no App Store release | You, 2026-11-12 |
| UI | SwiftUI | You |
| Input | Apple Pencil, palm rejection, multiple pen styles | You |
| Pens | Apple's eight pen styles first, then a custom engine "like Goodnotes" | You |
| Apple features | Handwriting search, math, speech, on-device AI | You |
| Cloud | Google Drive: backup first, then two-way sync | You asked for "Drive backup"; the original brief asked for sync, so both are planned, in that order |
| Mac app | Native macOS target, not the iPad app in compatibility mode | My recommendation, not yet confirmed by you |
| Minimum OS | iPadOS 27, macOS 27 | My recommendation, not yet confirmed |
| Document type | Paged notebooks; infinite canvas deferred | My recommendation, not yet confirmed |

Change from the report: it recommended leaving a custom ink engine as a later decision. You asked for one, so it is now a planned phase (phase 6), and the storage format is designed for it from the start.

## 2. Ground truth checked today

Toolchain on this Mac `[TESTED]`:

- Xcode 27.2, Swift 6.4.2, macOS 27.2.1, iOS SDK 27.2 and macOS SDK 27.2 installed.
- **No simulator runtimes are installed** (`xcrun simctl list runtimes` is empty). Pencil pressure, tilt and palm rejection cannot be tested in a simulator anyway, so a physical iPad is the test device.
- `xcodegen`, `tuist`, `swiftlint`, `swiftformat` are not installed. Nothing in this plan requires them.
- The project folder is empty and is not a git repository.

Apple APIs, checked against Apple's documentation data `[TESTED]`:

| Need | API | Availability | Note |
|---|---|---|---|
| Drawing canvas | `PKCanvasView` | iPadOS 13, Mac Catalyst 13.1. **Not native macOS** | Decides the Mac strategy |
| Palm rejection | `PKCanvasViewDrawingPolicy.pencilOnly` | iPadOS 13 | Free |
| Pen styles | `PKInkingTool.InkType`: pen, pencil, marker, monoline, fountainPen, watercolor, crayon, reed | iPadOS, reed newest | Eight styles |
| Stroke data | `PKDrawing` | iPadOS 13, **macOS 10.15** | Model and `image(from:scale:)` work on native Mac |
| Stroke identity | `PKStroke.id`, `Identifiable`, init with `id`, `mask`, `randomSeed`, `renderGroupID`, `renderState` | current SDK | Enables merge, audio replay, layers |
| Stroke timing | `PKStrokePath.creationDate` (per-point time offsets also expected, `[ASSUMED]`, not re-checked) | iPadOS 14 | Audio replay needs no extra bookkeeping |
| Format bridge | `PKStrokePath.bezierRepresentation`, `init(bezierPath:creationDate:pointProvider:)` | current SDK | Bridge between Apple's strokes and a custom engine |
| Handwriting search | `PKStrokeRecognizer`: `recognizedText(strokeIDs:)`, `indexableContent`, `search(_:fullWordsOnly:caseMatchingOnly:)`, `recognitionVersion` | iPadOS 27, **macOS 27** | Works on Mac without a canvas |
| Shapes, images, text markup | PaperKit: `PaperMarkupViewController`, `PaperMarkup`, `ShapeMarkup`, `ImageMarkup` | iPadOS 26, **macOS 26** | Native Mac annotation path |
| PDF | PDFKit, `PDFViewDelegate.pdfViewWillClick(onLink:with:)` | iPadOS 11, macOS 10.4 | Link handling exists |
| Speech to text | `SpeechAnalyzer` | iPadOS 26, macOS 26 | On-device, public |
| Typed math | `UITextInputTraits.mathExpressionCompletionType` | iPadOS 18, Catalyst 18. Not listed for native macOS | Text fields only |
| **Handwritten math** | **None found.** PencilKit and PaperKit list no math API | n/a | See section 6 |
| On-device model | Foundation Models: `SystemLanguageModel.isAvailable`, `contextSize`, image attachments (`ImageAttachmentContent`) | iPadOS 26, macOS 26 | Route for handwritten math and summaries |

Google `[RESEARCH]`, pages re-fetched in review: `drive.file` scope is non-sensitive; Testing status expires sign-ins and refresh tokens after 7 days; `files.update` documents no conditional-write parameter; push notifications need a public HTTPS server; pre-generated file IDs make uploads retry-safe. Google's native-app OAuth page documents PKCE and a custom URI scheme redirect `[TESTED]`.

## 3. Architecture

### 3.1 Project layout

One Xcode project, one multiplatform SwiftUI app target (iPadOS 27, macOS 27), four local Swift packages. The app target stays thin so that almost all logic is testable with `swift test` on the Mac, with no simulator.

```
NOTEAPP/
  NoteApp.xcodeproj
  NoteApp/                 app target: SwiftUI scenes, platform glue
  Packages/
    NoteCore/              document model, file format, library, merge. No UI, no PencilKit views
    InkKit/                InkEngine protocol, PencilKit engine, later Metal engine
    SearchKit/             recognition, indexing, search
    SyncKit/               Google auth, Drive client, backup, sync engine
```

Dependencies: none in phases 0 to 5 beyond Apple frameworks. Google sign-in uses `ASWebAuthenticationSession` with PKCE first; the GoogleSignIn package is the fallback if spike S2 fails (it would be the only third-party dependency).

### 3.2 The central design choice: who owns the stroke data

- **H1 (chosen, pending spike S1):** the app's own stroke record is the stored truth. A `PKDrawing` is built from it for display and is only a cache.
- **H2 (rival):** Apple's `PKDrawing` blob per page is the stored truth, with a small sidecar file for extra fields.

Strongest case for H2: phases 1 to 5 need nothing more. `PKStroke` already carries an ID and a creation date, merging two versions of a page is a union of `PKDrawing.strokes` by ID, and Apple maintains the format. It is the least code.

Input that breaks H2: a stroke drawn with a custom-engine brush (phase 6) has no `PKInk` type, so it cannot live in a `PKDrawing` blob. The page would then have two stores that must stay in step, and the "open, editable format" goal fails because the blob is opaque.

Discriminating check, run first (spike S1): convert strokes of all eight pen styles to the app's record and back, render both, and compare. If the round trip is lossless, H1 stands. If any pen style loses fidelity, fall back to a hybrid: keep the `PKDrawing` blob for Apple-pen strokes and the app's records for custom strokes, and accept two stores. `[INFERRED from the public PKStroke initialiser taking every stored field]` that the round trip is lossless; not yet tested.

### 3.3 On-disk format

Files are the truth. Everything else (thumbnails, search index, library database) is a cache that can be rebuilt from files. This is what makes Drive sync and restore tractable.

```
Library/
  library.json                     schemaVersion, deviceID
  folders.json                     folder tree, tags, favourites
  notebooks/<notebookID>/
    notebook.json                  title, cover, pageOrder[], schemaVersion, updatedAt
    pages/<pageID>.page            one page: strokes, elements, deleted-stroke IDs
    assets/<sha256>.<ext>          PDFs, images, audio. Immutable, named by content hash
  cache/                           never synced: thumbnails, PKDrawing blobs, index database
```

Stroke record: `id` (UUID), `layerID`, `tool` (engine, ink type, colour, width), `createdAt`, `transform`, `randomSeed`, `mask`, and `points[]` with location, time offset, size, opacity, force, azimuth, altitude. Page file also holds `elements[]` (text box, image, shape, PDF page reference), `deletedStrokeIDs[]`, `template`, `size`.

Encoding: JSON compressed with zlib. `ponytail: JSON+zlib, move to a binary encoding if a 2,000-stroke page loads slower than one frame budget allows on the test iPad.` Readable and debuggable while the format is still changing.

Rules fixed now because they cannot be retrofitted `[RESEARCH]`: every stroke has a stable ID, a timestamp and a layer field from version 1; every file has `schemaVersion`; one file per page; assets are never rewritten.

### 3.4 Canvas and screens

SwiftUI hosts; a UIKit view owns live ink `[RESEARCH]`. A paged UIKit scroll container, wrapped with `UIViewRepresentable`, keeps live canvases for the current page and one either side, and shows cached page images for the rest. UIKit owns the drawing while a stroke is in progress and commits to the model on stroke end; SwiftUI state is never written during a stroke.

`InkEngine` protocol in InkKit: load a page's strokes, report stroke added / erased / transformed, render a page to an image, hit-test for lasso. `PencilKitEngine` implements it in phase 1; `MetalEngine` in phase 6. Nothing outside InkKit imports PencilKit views.

Library: custom browser in a `WindowGroup`, not `DocumentGroup` `[RESEARCH]`. Library metadata cache in SwiftData.

### 3.5 Mac

Native target. Pages render through `PKDrawing.image(from:scale:)`, search runs through `PKStrokeRecognizer`, both available on native macOS `[TESTED]`. Mac scope: read, search, organise, type in text boxes, export, sync. Annotation on Mac through PaperKit is a later sub-phase because PaperKit's data model and the app's stroke record need a bridge `[ASSUMED]`.

## 4. Phases

Each task has a check that must pass before the next phase starts. Checks are relations, not snapshots.

### Phase 0. Setup and spikes

Spikes exist to turn the `[ASSUMED]` items into facts before anything is built on them. Each is throwaway code in `Spikes/`.

| ID | Task | Pass condition |
|---|---|---|
| P0.1 | `git init`, `.gitignore`, first commit, work on a branch | `git status` clean on a non-main branch |
| P0.2 | Create the multiplatform app project in Xcode and the four empty packages | iPad and Mac targets build; `swift test` runs in each package |
| P0.3 | Signing: install on the iPad from Xcode | App launches on the physical iPad |
| S1 | Stroke round trip for all eight pen styles | `decode(encode(stroke)) == stroke` for every field; rendered images of original and round-tripped page match pixel for pixel |
| S2 | Google sign-in with `drive.file` via `ASWebAuthenticationSession` + PKCE on iPad and Mac; create, update, list changes for one file | Refresh token survives app relaunch on both platforms; a file created on iPad is visible to the Mac build |
| S3 | Two devices edit the same page offline, then sync | Both devices end with identical stroke-ID sets containing every stroke drawn on either; no stroke duplicated |
| S4 | PencilKit overlay on a hyperlinked PDF planner | Tapping a link with a finger navigates; writing with the Pencil on the same page still draws |
| S5 | Handwritten math: page region image to the on-device model, ask for the expression and result | Correct transcription on a fixed set of 20 handwritten expressions, score recorded, decision made in section 6 |
| S6 | Render an iPad-drawn page on the Mac | Mac image matches the iPad thumbnail of the same page |

S3 is the prototype the report recommended building first. It decides whether stroke-level merge is real.

### Phase 1. iPad core, local only

| ID | Task | Check |
|---|---|---|
| P1.1 | NoteCore model and file format | Round-trip property test over generated notebooks; unknown `schemaVersion` is refused with a clear error, never half-loaded |
| P1.2 | Library: nested folders, favourites, tags, create / rename / move / delete with a trash | Deleting then restoring leaves the file tree byte-identical |
| P1.3 | Canvas with `PencilKitEngine`, pencil-only policy, eight pen styles, colour, width, saved presets | On device: palm on screen draws nothing; each style draws |
| P1.4 | Eraser (stroke, area), lasso move / resize / copy, including across pages | After any move, stroke count is unchanged and no ID is duplicated (the Goodnotes lasso bug as a test) |
| P1.5 | Undo and redo | N actions then N undos gives the original page file |
| P1.6 | Pages: add, delete, reorder, duplicate, per-page templates, covers | `pageOrder` always lists exactly the page files present |
| P1.7 | Pencil gestures: double-tap, squeeze, hover through the system tool picker | On device |
| P1.8 | Thumbnails and page cache; live canvas window of current page ±1 | Opening a 300-page notebook creates at most three live canvases |
| P1.9 | Autosave: page file written atomically, then `notebook.json` | Killing the app mid-write never leaves an unreadable notebook |
| P1.10 | Tabs, quick switcher, bookmarks, page outline, split view of two notes | Manual |

### Phase 2. Content and search

| ID | Task | Check |
|---|---|---|
| P2.1 | PDF import as a notebook; PDF pages referenced, not copied per page | Importing the same PDF twice stores one asset |
| P2.2 | PDF annotation with the S4 approach; links work | S4 condition holds inside the app |
| P2.3 | Images and text boxes; shape snapping | Elements survive save and reload unchanged |
| P2.4 | Handwriting index: `indexableContent` and `recognitionVersion` per page, recomputed when idle and when the version changes | Editing a page marks only that page stale |
| P2.5 | Search across all notebooks with hit highlighting | Every page whose index contains the term is returned; a hit's rectangle lies inside its page |
| P2.6 | Export: PDF with ink burned in, PNG per page, and the notebook folder as a zip | Exported PDF page count equals notebook page count |

`ponytail: search is a contains-scan over stored page text; move to SQLite FTS5 or Core Spotlight if a search over the whole library takes noticeably long.`

### Phase 3. Google Drive

Sign-in and tokens are an auth change: **I stop for your approval before this phase starts**, and you create the Google Cloud project (OAuth client of type iOS, scope `drive.file`, publishing status "In production", not "Testing").

| ID | Task | Check |
|---|---|---|
| P3.1 | Auth: sign in, refresh, sign out; refresh token in Keychain | Token never appears in logs or files; relaunch stays signed in |
| P3.2 | Drive client over `URLSession`: create with pre-generated ID, resumable upload, download, `changes.list`, back-off on rate-limit errors only | Fake-server tests: a retried create never produces two files |
| P3.3 | **Backup (one way):** mirror the Library tree to `My Drive/NOTEAPP/`, plus a readable PDF per notebook | After backup, every local file's hash equals the Drive copy's `md5Checksum` |
| P3.4 | Restore from Drive onto a clean install | Restored library is byte-identical to the backed-up one |
| P3.5 | Sync state table per file: Drive file ID, `version`, checksum, local hash | Unchanged files cause zero uploads |
| P3.6 | **Two-way sync, step 1:** pull changes on launch and foreground, push on page close; on a page changed on both sides keep both as a conflict copy and show it | No sequence of offline edits on two devices loses a stroke |
| P3.7 | Deletions as marker files, honoured before any upload | A device that was offline during a delete does not resurrect the notebook |
| P3.8 | **Two-way sync, step 2:** stroke-level merge (union of strokes by ID, union of deleted IDs, deleted wins) | Property tests: merge is commutative, associative and idempotent; `merge(a, a) == a` |
| P3.9 | Sync status and errors always visible; no silent failure | Every failed step surfaces a message naming the notebook |

Uploads on iPad come from files on disk and are batched per notebook, because the system throttles apps that start many small background transfers `[RESEARCH]`.

### Phase 4. Mac app

| ID | Task | Check |
|---|---|---|
| P4.1 | Library, notebook reader, page thumbnails | S6 condition holds for every pen style |
| P4.2 | Search with highlighting | Same results as iPad for the same library |
| P4.3 | Text box editing, page and folder organisation, export | Edits made on Mac appear on iPad after sync |
| P4.4 | Sync on Mac (same SyncKit) | S3 condition holds for an iPad and Mac pair |
| P4.5 | Annotation on Mac with PaperKit | Decided after P4.1 to P4.4; needs the bridge noted in 3.5 |

### Phase 5. Apple features

| ID | Task | Check |
|---|---|---|
| P5.1 | Audio recording, tap a stroke to replay from its `creationDate` | Replay position for a stroke equals stroke time minus recording start, within one second |
| P5.2 | On-device transcript with `SpeechAnalyzer`, stored beside the audio asset | Transcript segments carry times inside the recording's duration |
| P5.3 | Typed math in text boxes via `mathExpressionCompletionType` (iPad) | Typing `12*4=` offers `48` |
| P5.4 | Handwritten math, per the S5 decision | See section 6 |
| P5.5 | Page-scoped AI: summarise page, make flashcards from a selection; hidden when `isAvailable` is false | Feature absent, not broken, on an unsupported device |

### Phase 6. Custom ink engine

| ID | Task | Check |
|---|---|---|
| P6.1 | `MetalEngine`: stroke capture with coalesced and predicted touches, smoothing, pressure and tilt | Renders the same stroke records the PencilKit engine renders |
| P6.2 | Custom brushes: adjustable pressure curve, texture, more than Apple's fixed widths | New brush strokes save, sync and reload like any other |
| P6.3 | Layers: per-layer visibility and lock, using the `layerID` already in every stroke | Hiding a layer changes rendering only, never the page file's strokes |
| P6.4 | Search for custom strokes: convert to `PKStrokePath` via the Bézier bridge and feed `PKStrokeRecognizer` | Custom-engine handwriting is found by search |
| P6.5 | Engine switch per notebook, PencilKit stays the default until P6.1 to P6.4 pass on device | Switching engines never rewrites existing strokes |

No published effort figure exists for building an ink engine `[RESEARCH]`; the research's only size signal is Goodnotes reporting 1.47 million lines of shared engine and logic code. This phase is open-ended, so it is last and nothing before it depends on it.

## 5. Invariants and their timing

| Invariant | When it can be false | Design |
|---|---|---|
| `pageOrder` lists exactly the page files present | Between writing a new page file and rewriting `notebook.json`; after a crash in that window | Page file first, then `notebook.json`. On load, a page file not in `pageOrder` is appended, a listed page with no file is shown as missing and flagged. Never silently dropped |
| Local file equals Drive copy | Always false between an edit and the next successful push | Not treated as an invariant. The sync state table records the last agreed version; "dirty" is a normal, visible state |
| Drive update did not overwrite someone else's change | Between reading `version` and writing: Drive has no conditional write `[RESEARCH]` | Merge before upload, re-read `version` after upload, and if it advanced by more than this write, pull and merge again. Stroke merge makes a lost race recoverable; conflict copies cover step 1 |
| Stroke time aligns with audio time | Device clock change during a recording | Store recording start as one absolute timestamp and compute offsets from stroke `creationDate`; test P5.1 bounds the error |
| Search index reflects page content | Between an edit and the idle re-index; after an OS update changes `recognitionVersion` | Index rows carry the page's content hash and the recogniser version; a mismatch means stale and is re-queued |

## 6. Math

What exists `[TESTED]`: typed math completion in text fields on iPad. What does not: any system API for handwritten math in PencilKit or PaperKit. Apple's Math Notes is a feature of Apple's own apps, not something this app can call.

Options for handwritten math:

1. On-device model with an image of the selected ink (Foundation Models, image attachments). Free, private, quality unknown. Spike S5 measures it.
2. A commercial recognition library (MyScript). Production pricing is "contact us" `[RESEARCH]`; out of proportion for a personal app.
3. Defer.

Decision rule: ship option 1 if S5 transcribes the fixed test set well enough that you would use it; otherwise ship typed math only and revisit. I will show you the S5 results before deciding.

## 7. Rejected approaches

| Rejected | Strongest case for it | Input that breaks it |
|---|---|---|
| iPad app on Mac via Catalyst | Same canvas on both platforms, least Mac code | A Mac has no Pencil; you get a drawing canvas driven by a trackpad and iPad conventions for menus and windows, while the observed Mac use is reading and typing |
| `DocumentGroup` per notebook | Free open, save, autosave | A library with nested folders, tags and cross-notebook search is not a set of independently opened documents |
| One file per notebook | Simplest to copy and back up | Any stroke edit re-uploads the notebook's PDFs and audio; a conflict covers the whole notebook |
| A full CRDT library (Automerge) | Proven merge, future live collaboration | One user, two devices: opaque binary files and a Rust build for a merge that set union already provides |
| GoogleSignIn package from the start | Maintained by Google, less auth code | Not needed if S2 passes; kept as the fallback |
| Custom engine first | The pen is the product | Every other feature would wait on an open-ended build; palm rejection, eight pens and search are free today |
| iCloud for live sync, Drive for backup | Likely less sync code | Unverified in research, and you asked for Drive |

## 8. Review of this plan against itself

- **Prior decisions:** no `.memory/`, ADRs or `ponytail:` markers exist in the project. One reversal of the report's recommendation (custom engine), stated in section 1.
- **Report findings carried forward:** all seven open decisions are either locked in section 1 or listed in section 10; the "first prototype is two devices reconciling one page" finding is spike S3; "format before toolbar" is P1.1.
- **Strongest objection found:** the plan makes the app's own stroke record the truth before proving the round trip is lossless. If S1 fails late, phase 1 is built on the wrong store. Answer: S1 is in phase 0 and gates P1.1, with the hybrid fallback already defined.
- **Second objection:** stroke-level merge has no shipped precedent `[RESEARCH]`. Answer: sync ships in two steps, and step 1 (conflict copies) is safe without it.
- **Other attacks tried:** empty notebook, single-page notebook, a page deleted on one device and edited on the other (edit wins as a restored page plus a notice, to be confirmed in S3), first run with an existing Drive folder (treated as restore, never overwritten), sign-out mid-upload, Drive storage full (terminal error, shown, not retried).
- **Numbers:** no time estimates are given because no source for them exists. The 300-page and 2,000-stroke figures are test sizes I chose, not measurements.

## 9. Risks still open

| Risk | Tag | Resolved by |
|---|---|---|
| Stroke round trip loses fidelity for some pen style | `[INFERRED]` lossless | S1 |
| `ASWebAuthenticationSession` + PKCE yields a durable refresh token on both platforms | `[ASSUMED]` | S2 |
| A Google project "In production" with only `drive.file` has no weekly expiry for a personal account | `[RESEARCH]`, flagged unconfirmed there | S2, by leaving the spike signed in for more than 7 days |
| Drawing overlay swallows PDF link taps | `[ASSUMED]` | S4 |
| Handwritten math quality from the on-device model | `[ASSUMED]` | S5 |
| The on-device model is available on your iPad and Mac | `[ASSUMED]` | S5, `isAvailable` |
| PaperKit markup can be bridged to the app's stroke record | `[ASSUMED]` | P4.5 investigation |
| Free Apple ID signing expires after 7 days; a paid developer account lasts a year | `[ASSUMED]`, long-standing Apple policy, not re-checked | P0.3 |
| Background upload behaviour when the app is suspended mid-sync | `[RESEARCH]`, untested | P3.2 on device |

## 10. What I need from you

1. **iPad model and iPadOS version.** The plan requires iPadOS 27, and S5 needs a device that supports Apple's on-device model.
2. **Apple developer account.** Paid, or free Apple ID? It changes how often the app must be reinstalled on the iPad.
3. **Xcode project creation.** Either you create the multiplatform app project once in Xcode (File, New, Project, Multiplatform, App), or you approve installing `xcodegen` so I can generate it.
4. **Confirm or change** the three recommendations in section 1: native Mac app, iPadOS 27 / macOS 27 minimum, pages only for now.
5. **Before phase 3:** create the Google Cloud project and approve the sign-in work.

## 11. Resolution report

```text
🟡 SRE [Tier 2 now, Tier 3 at phase 3 (auth)] | Root Cause: n/a, greenfield plan
Evidence: 16 TESTED (toolchain, the 14 Apple API rows in section 2, Google native-app OAuth page) / 5 RESEARCH Google facts re-fetched in review / 9 ASSUMED, INFERRED or untested RESEARCH items, each mapped to a spike or task in section 9
Recheck: n/a, planning run
Confidence: MEDIUM — the central storage choice (H1) rests on an untested round trip; S1 resolves it before any dependent work
Gate: A ✓ no prior decisions; one reversal of the report stated. B ✓ section 5. C ✓ no ratios used. D ✓ every check is relational. E ✓ section 7. F ✓ section 8. G ✓ section 8, two objections answered. H rung 7 for new code (empty project, nothing to reuse); rungs 4-5 applied: Apple frameworks only, zero third-party dependencies
Ladder: rung 4 (native platform features) | net: 0 lines | ponytail: 2 markers planned (page encoding, search scan)
Fix: n/a
Predict: S1 round trip is lossless → not yet run
T2/3: Impact: none yet | Fail mode: if S1 fails, phase 1 uses the hybrid store in 3.2; if S3 fails, sync stops at conflict copies
Action: PLAN ONLY — no code, nothing staged, project is not yet a git repository
```
