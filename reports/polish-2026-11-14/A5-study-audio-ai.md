# A5 — study, audio and AI audit

Read 2026-11-14. Read-only audit: no build, no test, no source edit.

Files read (line counts):

| File | Lines |
|---|---|
| `NoteApp/Audio/NotebookAudio.swift` | 638 |
| `NoteApp/AI/NoteAIPanel.swift` | 560 |
| `NoteApp/Study/StudyReviewView.swift` | 429 |
| `NoteApp/Study/StudyModel.swift` | 423 |
| `NoteApp/Study/StudySetEditorView.swift` | 286 |
| `NoteApp/Study/StudyLibraryView.swift` | 283 |
| `NoteApp/Audio/AudioRecordingsView.swift` | 249 |
| `NoteApp/Study/NotebookStudySheet.swift` | 241 |
| `NoteApp/Audio/ClipTranscriptView.swift` | 149 |
| `NoteApp/Study/LeechRewriteSheet.swift` | 148 |
| `NoteApp/Audio/NowPlayingBar.swift` | 125 |
| `NoteApp/Study/TapeStudyControls.swift` | 82 |
| `NoteApp/Audio/ReplayInk.swift` | 49 |
| Context only (not reported on): `Packages/AudioKit/Sources/AudioKit/PlaybackController.swift` 87, `ReplayTarget.swift` 97, `AVFoundationAudioRecorder.swift` 143, `AudioClipStore.swift` 169, `SpeechAnalyzerTranscriber.swift` 180; `Packages/StudyKit/Sources/StudyKit/ReviewPass.swift` 304, `FSRSScheduler.swift` 130 of 262; `Packages/SearchKit/Sources/SearchKit/HandwritingRecognizer.swift` 79 of 138, `Packages/AIKit/Sources/AIKit/AIProvider.swift`, `AIService.swift` (signatures) | — |
| Background read: `PERFORMANCE-NOTES.md` (63), `.memory/decisions/2026-11-13-wave4-feature-build.md`, `2026-11-13-phase1-data-durability.md`, `2026-11-12-dark-mode-paper.md` | — |
| Outside-area reads for consumer context only: `NoteApp/Notebook/NotebookView.swift` 1450–1629 (audio replay wiring), `NoteApp/Search/HandwritingSearch.swift` 297–317, `NoteApp/AppColor.swift` 1–60 | — |

## Findings

| ID | Sev | Head | file:line | Quoted line | Why it hurts the user | Proposed fix | Size |
|---|---|---|---|---|---|---|---|
| A5-01 | P1 | 1 — main-thread work | `NoteApp/Audio/NotebookAudio.swift:523` | `self.playheadSeconds = player.currentTime` | The playhead task ticks every 250 ms (`:520`) and each tick also unconditionally assigns `activeStrokeID` at `:538` even when the stroke has not changed. `pageContent` in the notebook reads `activeStrokeID` and rebuilds the page, and `ReplayInk.fading` copies the whole stroke array for every body run (`ReplayInk.swift:17`). So while a recording plays with Follow on, a 2 000-stroke page is re-mapped and handed to `PencilCanvasView` 4×/s — dropped frames and a laggy-looking canvas for the whole listen. | Publish the playhead into a small dedicated `@Observable` (or write `activeStrokeID` only when it differs, like PERF-NOTES #5 does for `page`) and let only the marker/label read it; over the marker, PencilKit re-applies only when `activeStrokeID` really changed. | M |
| A5-02 | P1 | 1 — main-thread work | `NoteApp/Study/NotebookStudySheet.swift:104` | `if cards.isEmpty {` | `body` runs five whole-library scans every time it evaluates: `dueCount` at `:79` and `:87`, `cards` at `:104`, `:108` and `:118`, and each one rebuilds `StudyModel.allStates` (a UUID-string parse for every card in every set, `StudyModel.swift:131-149`) before filtering and sorting. `question` and `answer` are `@State` in this same view (`:24-25`), so **every keystroke** in the two text fields pays all five scans. On a library of a few hundred cards that is per-keystroke lag in "New Card". | Compute the queue once per body run into a local (`let cards = self.cards`) or, better, cache it in `@State` keyed by `study.reviewStates`/`sets` revision, and pass the counts down. | M |
| A5-03 | P2 | 1 — main-thread work | `NoteApp/Study/StudyLibraryView.swift:118` | `if study.totalDueCount > 0 {` | The body reads the library-wide due count twice (here and again through `dueNowSection` at `:138`), and each visible row calls `study.dueCount(for:)` at `:184` — every one of them rebuilds `allStates` over the entire library. Scrolling a large study library therefore does a full-library dictionary rebuild per row that appears, and every grade/delete re-scans everything. | One `allStates` per change; compute per-set due counts in one pass and store them (or memoise `allStates` until `stateRevision` moves). | M |
| A5-04 | P2 | 1 — main-thread work | `NoteApp/Study/TapeStudyControls.swift:14` | `(session.page?.visibleElements ?? []).compactMap { element in` | This floating bar reads `session.page`, which changes on every stroke. PERF-NOTES #5 and #11 removed exactly this dependency from the editor chrome because it re-runs the whole body per stroke; the bar has the same problem, plus `revealedCount` re-filters the tape list on every pass. | Read a derived, stroke-independent value (e.g. a `tapeIDs` list published by `NotebookSession` when tape is added/removed) instead of `session.page`. | S |
| A5-05 | P2 | 1 — main-thread work | `NoteApp/AI/NoteAIPanel.swift:412` | `pageText = await search.noteText(for: page)` | `HandwritingSearch` is `@MainActor` and `noteText` builds a `PKDrawing` from every stroke of the page synchronously (`StrokeCodec.drawing(from:)`, `HandwritingRecognizer.swift:42/56`) before any `await`. Opening the AI panel on a dense page therefore does the stroke→PencilKit bridge on the main thread while the sheet is animating in, and "Check Again" repeats it. | Make `noteText` build the drawing in a detached task (the package already takes `[StrokeRecord]`, which is `Sendable`), or read the page's cached OCR/index text instead of re-recognising. | M |
| A5-06 | P2 | 1 — main-thread work | `NoteApp/AI/NoteAIPanel.swift:439` | `let response = try await ai.respond(` | The request runs in an untracked `Task {}`; dismissing the sheet does not cancel it and there is no Cancel button, so an on-device generation (and the flashcard/ask work behind it) keeps running and burning battery after the user closed the panel. `AIService`/providers honour `Task.checkCancellation`, so the cost is entirely in the app not cancelling. | Keep the `Task` in `@State`, `.onDisappear { task?.cancel() }`, and add a Cancel button to `workingRow` while `isWorking`. | S |
| A5-07 | P2 | 1 — main-thread work | `NoteApp/AI/NoteAIPanel.swift:214` | `ForEach(Array(cards.enumerated()), id: \.offset) { index, card in` | Card identity is the array position, and the "added" bookkeeping is keyed on the same index (`id: "card-\(index)"` at `:229`). Generating flashcards a second time replaces the array under the same ids, so the green "Added to page" checkmark stays on whatever card now sits at that index — the UI says a card was added to the page when a different one was. | Key on `card` content (`id: \.question`) or give `AIFlashcard` an `Identifiable` id; key `addedBlock` on the same value. | S |
| A5-08 | P2 | 1 — main-thread work | `NoteApp/Audio/AudioRecordingsView.swift:18` | `if session.audio.clips.isEmpty {` | `clips` is empty until the `.task` at `:66` finishes `load()` (which first runs crash recovery and may copy several MB of leftover audio), so on a notebook that has recordings the sheet first renders the "No Recordings — Record a lecture…" empty state and then pops the list in. On a notebook with leftover pending files this is visible for a second or more. | Expose `NotebookAudio.isLoading` (a boolean already exists privately) and show a progress row instead of the empty state until the first load completes. | S |
| A5-09 | P2 | 6 — loading / empty / error | `NoteApp/Audio/NotebookAudio.swift:212` | `isBusy = true` | After Stop, the recording row disappears immediately (`isRecording = false` at `:210`) while the clip is read, added to assets and saved; `isBusy` only disables buttons, it shows nothing. Stopping a lecture-length recording leaves a sheet with no row, no spinner and no clip — the user cannot tell whether the audio is being kept. (`finalize` at `:251` also reads the whole file into memory to copy it.) | Show a "Saving recording…" row driven by `isBusy`, and stream the copy with `FileHandle`/`copyItem` instead of `Data(contentsOf:)`. | S |
| A5-10 | P2 | 6 — loading / empty / error | `NoteApp/Audio/NotebookAudio.swift:553` | `func transcribe(_ clip: AudioClip) async {` | Transcription of a long clip shows only an indeterminate `ProgressView` (`ClipTranscriptView.swift:18`), has no Cancel, and is launched from a button `Task` so it keeps running after the transcript sheet is dismissed. The transcriber is cancellation-aware and may even download speech assets first, so the user is watching an unspecified wait with no exit. | Hold the transcription task in `NotebookAudio`, cancel it from a Cancel button in the sheet and from sheet dismissal, and show the clip duration/progress while it runs. | M |
| A5-11 | P2 | 6 — loading / empty / error | `NoteApp/Audio/NotebookAudio.swift:177` | `errorText = error.localizedDescription` | Microphone denial surfaces as the alert "Audio error: Microphone permission was denied." with a single OK. Nothing says the app cannot record without it or how to grant it, so the only record button appears broken. | Detect `AudioKitError.permissionDenied` and show an explanation plus an "Open Settings" button (`UIApplication.openSettingsURLString`). | S |
| A5-12 | P2 | 5 — touch targets | `NoteApp/Audio/NowPlayingBar.swift:24` | `.frame(width: 36, height: 36)` | The now-playing bar's play/pause is 36×36, Stop is 32×32 (`:49`), Follow is `minHeight: 30` (`:85`) and the scrubber is clipped to `height: 20` (`:65`). This bar floats over the page while the user is writing with a Pencil; all four are below the 44 pt iPad target and the 20 pt scrubber is very hard to grab. | 44×44 for both icon buttons, `minHeight: 44` + `.contentShape` for Follow, and give the slider a 44 pt row (visual track unchanged). | S |
| A5-13 | P2 | 5 — touch targets | `NoteApp/Study/TapeStudyControls.swift:49` | `.frame(width: 28, height: 28)` | The bar's close button is 28×28 and the whole bar is `.controlSize(.small)` (`:57`), so "Reveal All" and "Hide All" are roughly 26 pt tall. In tape study the user is tapping this repeatedly to lift tape, one-handed or with a Pencil in the other hand. | 44 pt close target, `.controlSize(.regular)` for the two actions, keep the capsule visual. | S |
| A5-14 | P2 | 5 — touch targets | `NoteApp/Study/StudyLibraryView.swift:256` | `.frame(width: 28, height: 28)` | The error banner's dismiss button is 28×28 and its Retry is `.controlSize(.small)` (`:250`), in a banner that spans the top of the study library and pushes the list down. | 44 pt dismiss target, keep Retry at the default control size. | S |
| A5-15 | P2 | 5 — touch targets | `NoteApp/AI/NoteAIPanel.swift:143` | `.frame(minHeight: 32)` | Six bordered buttons in the AI panel are pinned to a 32 pt height ("Summarize Page", "Flashcards", all four Copy/Add buttons). Where `.controlSize(.large)` is also applied they grow, so the same row of buttons is 32 pt on one surface and ~44 pt on another. | Drop the `minHeight: 32` and use `.controlSize(.large)` consistently for the panel's primary row, or 44 pt minimum. | S |
| A5-16 | P2 | 5 — keyboard | `NoteApp/Study/StudyReviewView.swift:244` | `gradeButton("Again", quality: 1, color: .red, item: item, pass: pass)` | Nothing in `Study/`, `Audio/` or `AI/` declares a keyboard shortcut (`rg keyboardShortcut` → no matches). The Mac companion can only run a review by clicking: click Reveal, click one of four grade buttons, per card, forever. No Space to reveal/advance, no 1–4 to grade, no Escape to leave the pass. | `.keyboardShortcut(.space, modifiers: [])` on Reveal, `.keyboardShortcut("1"..."4", modifiers: [])` on the four grades, `.keyboardShortcut(.cancelAction)` on Done. | S |
| A5-17 | P2 | 4 — motion | `NoteApp/Study/StudyReviewView.swift:251` | `withAnimation(.easeInOut(duration: 0.2)) { revealed = true }` | Reveal animates with `.easeInOut(0.2)` and the matching collapse on grade uses `.easeInOut(0.18)` (`:353`) — the same kind of change with two durations, neither of them on the agreed quick/standard scale, and neither gated on Reduce Motion (no `accessibilityReduceMotion` anywhere in these three folders). The card itself then swaps to the next question with no animation at all while the reveal collapse animates, so the new card appears instantly inside a moving layout. | One shared "quick" (0.18 s) for reveal/collapse, chosen only when `!accessibilityReduceMotion`; animate the card change (opacity or the same quick curve) so the advance and the collapse are one movement. | S |
| A5-18 | P2 | 3 — fixed fonts | `NoteApp/Study/StudyReviewView.swift:145` | `.font(.system(size: 28, weight: .semibold, design: .rounded))` | The review card's question (28), the recalled answer (17, `:189`) and the answer (24, `:208`) are fixed point sizes. The most important text in the app — the thing the user is reading at arm's length on an iPad — ignores Dynamic Type entirely, while everything around it (`caption`, `headline`) scales. | `.font(.system(.largeTitle, design: .rounded, weight: .semibold))` / `.title2` / `.title`, keeping the rounded design. | S |
| A5-19 | P2 | 2 — layout / spacing | `NoteApp/AI/NoteAIPanel.swift:309` | `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))` | Same element, three metrics inside one panel: a result block is radius 12 / padding 16, a flashcard block is radius 10 / padding 12 (`:226`), the title suggestion is radius 10 / padding 12 (`:190`). Across the area the floating surfaces also disagree — now-playing bar 12/8 radius 16, tape bar 14/10 capsule, study error banner 16/10 flat — so "a card of content" and "a floating bar" look like three different apps. | Pick one content-card metric (radius 12, padding 16) and one floating-bar metric (radius 16, padding 12/8); apply them to `A5`'s five surfaces. | M |
| A5-20 | P2 | 2 — layout / spacing | `NoteApp/Audio/AudioRecordingsView.swift:96` | `? "\(elapsedText) recorded so far. Stop when you are done; the audio is saved with this notebook."` | This is the second place that reads `session.audio.elapsed` (also `:125`), and it is read from the sheet's `body` via `emptyState`, so the whole audio sheet — NavigationStack, toolbar, empty state — re-runs 2×/s while recording into a notebook that has no clips yet. PERFORMANCE-NOTES #14 made the rule that only a small recording label may read the timer. | Move the elapsed text into a `RecordingElapsedLabel`-style child view so only that `Text` re-renders. | S |
| A5-21 | P3 | 1 — main-thread work | `NoteApp/Audio/ClipTranscriptView.swift:146` | `let time = audio.playheadSeconds` | Every transcript line that is on screen reads the 4 Hz playhead to decide whether it is the current line, so during playback each visible row re-evaluates four times a second. `List` keeps this bounded to the visible rows, which is why it is not P2, but on a long transcript it is a steady 40 body runs/s. | Compare against a playback position passed down once per tick from a single observer, or move the highlight into an overlay that reads the playhead itself. | S |
| A5-22 | P3 | 1 — main-thread work | `NoteApp/Study/StudyReviewView.swift:333` | `items: study.queue(` | The pass is built synchronously in `.onAppear`, which means `allStates` plus a filter-and-sort of the whole library on the main thread during the sheet's presentation animation. Visible as a beat before the first card on a large library. | Build the queue in a `.task` in the same view (a `ProgressView` is already shown while `pass == nil`) so the sheet animates in unblocked. | S |
| A5-23 | P3 | 6 — loading / empty / error | `NoteApp/Study/StudyModel.swift:322` | `let decoded = try? JSONDecoder().decode(StateFile.self, from: data)` | A corrupt or truncated `review-states.json` is swallowed here: `reviewStates` stays empty, so every card reads as new and the whole library becomes due, with no banner. `lastError` is used for unreadable *set* files (`:48`) but not for this file. This does not contradict the durability ADR (the states are a rebuildable cache); the missing part is telling the user the schedule was rebuilt. | On decode failure set `lastError` to "Review progress could not be read; cards were rescheduled as new." and keep the bad file aside the way `LibraryStore` quarantines. | S |
| A5-24 | P3 | 4 — motion | `NoteApp/Audio/AudioRecordingsView.swift:118` | `.symbolEffect(.variableColor.iterative)` | Two continuously looping symbol effects (recording row `:118`, playing row `:180`) that cannot be turned off under Reduce Motion in this code (no gate anywhere in `Audio/`). Separately, the recording row appears and disappears without animation (`.isRecording` flips at `NotebookAudio.swift:210`). | Gate both effects on `@Environment(\.accessibilityReduceMotion)`, and tint/opacity the row instead; add the shared quick animation to the row's insertion/removal. | S |
| A5-25 | P3 | 7 — accessibility | `NoteApp/Audio/AudioRecordingsView.swift:161` | `.accessibilityLabel(isPlaying ? "Pause playback" : "Play recording")` | Every row's play button is announced as "Play recording", with no clip title or date, so a VoiceOver user paging the list hears the same button N times (the Delete button beside it does include the title, `:212`). | `"Play \(clip.title.isEmpty ? "recording" : clip.title)"`, matching the delete label. | S |
| A5-26 | P3 | 7 — accessibility | `NoteApp/Study/StudyReviewView.swift:350` | `pass = current` | Grading replaces the card content with no announcement, so a VoiceOver user taps "Good" and the question silently changes underneath; focus stays where the grade button was and nothing says a new card is up. | `.accessibilityAnnouncement` (or `AccessibilityNotification.Announcement`) with the new question after a grade, and `.accessibilityFocused` on the new question. | S |
| A5-27 | P3 | 9 — copy | `NoteApp/Audio/ClipTranscriptView.swift:95` | `Label("Transcribe", systemImage: "waveform.badge.magnifyingglass")` | The same action is called four things in two files: "Transcribe" (empty state), "Transcribe again" (toolbar `:43`), "Show transcript"/"Transcribe recording" (list row `AudioRecordingsView.swift:198`), and "Recognise the speech in this recording" (body `:90`). | Use "Transcribe" / "Transcribe again" / "Show transcript" only, and drop "Recognise" from the prose. | S |
| A5-28 | P3 | 9 — copy | `NoteApp/Study/NotebookStudySheet.swift:80` | `Label("Nothing due", systemImage: "checkmark.circle")` | Three wordings for the same empty queue: "Nothing due" here, "No cards in this scope are due right now." (`StudyReviewView.swift:308`), and the button label "Nothing Due" (`StudySetEditorView.swift:138`) which also collides with the *unavailable* state of that button. | One sentence ("Nothing due right now.") for the state, and keep the disabled button label "Review" / "Nothing Due" distinct from it. | S |
| A5-29 | P3 | 5 — keyboard | `NoteApp/AI/NoteAIPanel.swift:379` | `TextField("Ask about this page…", text: $question, axis: .vertical)` | A vertical-axis `TextField` with no `.onSubmit`/`.submitLabel`, so on the Mac companion Return inserts a newline and the only way to ask is to click the arrow button. | `.onSubmit { ask() }` with `.submitLabel(.send)` (or `.keyboardShortcut(.return, modifiers: .command)` on the button) while keeping Shift-Return for a newline. | S |
| A5-30 | P3 | 6 — loading / empty / error | `NoteApp/AI/NoteAIPanel.swift:484` | `answer = response.text` | The panel keeps one answer: asking a second question overwrites the first answer and its citations with no history, no "previous answer" and no notice. Unlike everything else in the notebook, the AI conversation is not kept anywhere, so a follow-up destroys the text the user may still be reading. | Keep an ordered `[(question, answer)]` and append, or block a new question until the previous answer is copied ("Ask again will replace this answer"). | S |
| A5-31 | P3 | 9 — copy | `NoteApp/Audio/AudioRecordingsView.swift:41` | `.navigationTitle("Audio")` | The sheet is titled "Audio", its empty state says "No Recordings", its row says "Recording", the clip titles say "Recording 1", the toolbar button says "Start recording", and the notebook entry that opens it is a microphone. Five names for one thing. | Title the sheet "Recordings" and use "recording" everywhere for one item. | S |
| A5-32 | P3 | 4 — motion | `NoteApp/Study/TapeStudyControls.swift:71` | `private func revealAll() {` | "Reveal All" toggles tape one element at a time in a loop with no animation, so a page with twelve pieces of tape reveals as a stutter of individual state changes rather than one movement; "Hide All" does the same in reverse. | Wrap the loop in one `withAnimation` (the shared standard curve, gated on Reduce Motion) and set the revealed set in one mutation. | S |

## Off-scale layout values (head 2)

Scale used: spacing 2, 4, 8, 12, 16, 20, 24, 32; radius 4, 8, 10, 12, 16, 20. Only literals off the scale are listed. `minHeight`/`frame` touch targets are covered by the head-5 rows, not here.

### `NoteApp/AI/NoteAIPanel.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `spacing: 10` | 7 | 8 | low |
| `spacing: 22` (panel section gap) | 1 | 24 | low |
| `spacing: 6` (citations stack) | 1 | 8 | low |
| `padding(14)` (ask bar) | 1 | 12 or 16 | low |
| `cornerRadius: 10` (cards) | 2 | 12, to match the result block | low |

### `NoteApp/Study/StudyReviewView.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `spacing: 10` (bottom bars) | 2 | 12 | low |
| `spacing: 22` (card column) | 1 | 24 | low |
| `spacing: 6` (progress header) | 1 | 8 | low |
| `padding(.vertical, 14)` (Reveal Answer) | 1 | 12 | low |
| `padding(.vertical, 10)` (grade buttons) | 1 | 12 | low |

### `NoteApp/Study/StudyLibraryView.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `spacing: 14` (row) | 1 | 12 | low |
| `spacing: 3` (row title/subtitle) | 1 | 4 | none |
| `padding(.vertical, 6)` (row) | 1 | 4 | low |
| `padding(.vertical, 10)` (banner) | 1 | 8 or 12 | low |

### `NoteApp/Study/NotebookStudySheet.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `padding(.vertical, 5)` (card row) | 1 | 4 | none |

### `NoteApp/Study/StudySetEditorView.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `padding(.vertical, 6)` (card row) | 1 | 4 or 8 | low |

### `NoteApp/Study/TapeStudyControls.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `spacing: 1` (title/count) | 1 | 2 | none |
| `padding(.horizontal, 14)` | 1 | 12 or 16 | low |
| `padding(.vertical, 10)` | 1 | 8 or 12 | low |

### `NoteApp/Audio/AudioRecordingsView.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `spacing: 14` (row) | 2 | 12 | low |
| `spacing: 3` (row title/subtitle) | 2 | 4 | none |

### `NoteApp/Audio/NowPlayingBar.swift`

| value | count | proposed token | risk |
|---|---|---|---|
| `spacing: 10` (bar) | 1 | 8 or 12 | low |
| `spacing: 1` (title/time) | 1 | 2 | none |

Files with no off-scale padding/spacing/radius literals: `NotebookAudio.swift`, `ReplayInk.swift`, `ClipTranscriptView.swift` (`spacing 12`, `minHeight 32`), `StudyModel.swift`, `LeechRewriteSheet.swift` (a `Form`).

### Same element, different metrics

| Element | Where | Metrics in use |
|---|---|---|
| Content card on a material | AI result block `NoteAIPanel.swift:308-309` | radius 12, padding 16 |
| Content card on a material | AI flashcard / title suggestion `NoteAIPanel.swift:225-226`, `:189-190` | radius 10, padding 12 |
| Rounded action tile | Grade button `StudyReviewView.swift:294` | radius 10, padding v10 |
| Floating bar over the page | Now-playing bar `NowPlayingBar.swift:68-70` | radius 16, padding h12/v8 |
| Floating bar over the page | Tape bar `TapeStudyControls.swift:58-60` | capsule, padding h14/v10 |
| Inline banner | Study error banner `StudyLibraryView.swift:262-265` | flat, padding h16/v10 |
| Primary button height | Study review Reveal `:253-257` | headline + v14 ≈ 52 pt |
| Primary button height | Study set "Review N Due" `StudySetEditorView.swift:141-145` | minHeight 44 + `.large` |
| Primary button height | AI "Summarize Page" `NoteAIPanel.swift:142-145` | minHeight 32, default control size |
| Primary button height | Audio empty state `AudioRecordingsView.swift:103-110` | minHeight 32 + `.large` |

## Fixed font sizes (head 3)

| file:line | N | Styles | Text or glyph |
|---|---|---|---|
| `NoteApp/Study/StudyReviewView.swift:145` | 28 (semibold, rounded) | review card question | **Text** — should follow a text style (`.largeTitle`/`.title`) and Dynamic Type |
| `NoteApp/Study/StudyReviewView.swift:189` | 17 (rounded) | the user's typed recall, echoed | **Text** — should be `.body` |
| `NoteApp/Study/StudyReviewView.swift:208` | 24 (regular, rounded) | review card answer | **Text** — should be `.title2` |
| `NoteApp/Audio/NowPlayingBar.swift:23` | 14 (semibold) | play/pause glyph | Glyph — may stay fixed |
| `NoteApp/Audio/NowPlayingBar.swift:48` | 13 (semibold) | close (×) glyph | Glyph — may stay fixed |
| `NoteApp/Audio/NowPlayingBar.swift:80` | 12 (semibold) | Follow eye glyph | Glyph — may stay fixed (label text beside it is `.caption`) |
| `NoteApp/Audio/AudioRecordingsView.swift:152` | 16 (semibold) | row play/pause glyph | Glyph — may stay fixed |

## Animations (head 4)

| file:line | Kind / curve | Animates |
|---|---|---|
| `NoteApp/Study/StudyReviewView.swift:251` | `withAnimation(.easeInOut(duration: 0.2))` | revealing the answer (`revealed = true`) |
| `NoteApp/Study/StudyReviewView.swift:353` | `withAnimation(.easeInOut(duration: 0.18))` | collapsing the reveal when a grade advances the card |
| `NoteApp/Audio/AudioRecordingsView.swift:118` | `.symbolEffect(.variableColor.iterative)` | recording waveform, loops for the whole recording |
| `NoteApp/Audio/AudioRecordingsView.swift:180` | `.symbolEffect(.variableColor.iterative)` | playing waveform, loops for the whole clip |
| — | none | card advance itself (`StudyReviewView.swift:350`): new question/answer appear with no animation while the reveal collapses |
| — | none | pass progress bar and "N reviewed / N left" (`StudyReviewView.swift:116-125`) |
| — | none | AI results appearing (`NoteAIPanel.swift:442`, `:461`, `:484`): the summary/answer/cards pop into the scroll view |
| — | none | recording row appearing/disappearing (`AudioRecordingsView.swift:22-26`) |
| — | none | "Reveal All"/"Hide All" tape (`TapeStudyControls.swift:71-81`) |
| — | none | error banner appearing (`StudyLibraryView.swift:24-26`) |

Inconsistency: 0.2 s vs 0.18 s for the two halves of the same reveal, neither the agreed 0.18 quick nor 0.25 standard; no `accessibilityReduceMotion` in `Study/`, `Audio/` or `AI/`, so every one of the above (and both looping symbol effects) plays regardless of the Reduce Motion setting.

## Not checked

- **Device frame cost.** A5-01 and A5-02 are reasoned from the code paths (4 Hz × whole-page stroke copy; five library scans per keystroke), not measured on the base iPad; the numbers in "Why it hurts" are counts of passes, not milliseconds. A measurement would need the release build and Instruments described in PERFORMANCE-NOTES.
- **`PencilCanvasView`'s diffing cost** for the new `[StrokeRecord]` it receives each playhead tick is outside this area (I read only the call site, `NotebookView.swift:1517-1600`), so A5-01's frame cost is inferred from that consumer, not from the canvas itself.
- **`StrokeCodec.drawing(from:)` timing** (A5-05) was not measured; the synchronous-on-main claim rests on the call being made from a `@MainActor` method with no `await` before it (`HandwritingSearch.swift:297-317`, `HandwritingRecognizer.swift:42/56`).
- **Dark mode**: checked line by line across the three folders; colours are semantic (`AppColor`/system/accent/material) except `.white` on a coloured tag (`StudyLibraryView.swift:194`), the marker's white ring on paper (`ReplayInk.swift:42`) and the grade-button tints, all of which sit on paper or on their own fill. Nothing reported; I did not verify the faded-ink appearance on Dark Paper, because the inverting render lives in InkKit outside this area.
- **AIKit streaming**: `AIProvider.stream` exists and honours cancellation, but the panel only uses `respond`, so there is no per-token relayout to audit here; I did not read `FoundationModelsProvider` beyond its signatures.
- **Audio session edge cases** (interruption mid-playback, route changes) were read in `NotebookAudio` but not exercised; only the interruption-during-recording path is visible in code.
- **`StudySetCSV` import** and `StudyKit`'s store were read only as far as needed to judge whether the app awaits them off the main actor.
- **VoiceOver order** through the review pass was reasoned from the view tree, not heard on a device.
- `NoteApp/Study/StudyModel.swift` lines 300–423 and `StudyReviewView` were read in full; `Packages/AudioKit/.../AudioClipStore.swift` only around `list/save/delete`.
