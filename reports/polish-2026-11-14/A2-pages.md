# A2 — pages and reading audit

Files read: `NoteApp/Notebook/ContinuousPagesView.swift` (1579), `ZoomablePageView.swift` (222), `PageBackground.swift` (493), `PagesSidePanel.swift` (363), `PageElementViews.swift` (391), `ElementEditLayer.swift` (182), `PageTemplates.swift` (355), `PageTemplatePicker.swift` (342), `PDFLinkHandler.swift` (268), `GoToPageField.swift` (69), `PageBookmarks.swift` (226), `PageOutline.swift` (54), `NoteApp/Search/HandwritingSearch.swift` (365), `HighlightedSnippet.swift` (32), `NotebookFindBar.swift` (455), `PageNumberQuery.swift` (25), `PencilSearchPad.swift` (253). Also read for context (not audited): `PERFORMANCE-NOTES.md`, the six ADRs named in the brief, `NoteApp/AppColor.swift`, `NoteApp/MemoryPressure.swift`, `Packages/InkKit/Sources/InkKit/TemplateRenderer.swift` (entry points only).

## Findings

| ID | Sev | Head | file:line | Quoted line | Why it hurts the user | Proposed fix | Size |
|---|---|---|---|---|---|---|---|
| A2-01 | P1 | Main-thread work | PageBackground.swift:462 | `let rendered = await Task.detached(priority: .utility) {` | `prewarm` is called once per completed page image (`ContinuousPagesView.swift:665`) with no gate: N pages scrolled past start N simultaneous detached 2× PDF/photo draws (77 ms-class on an M1 Max for a scanned page, 2–3× that on the base iPad), and the same key can be drawn twice because the cache is only re-checked after the draw. This breaks the documented "inactive pages render off-main one at a time" rule, and since the page image already drew that PDF page, every scanned page is drawn twice per fling. | Queue prewarm behind the existing serial `renderTask` loop (one at a time), keep single-flight keys, and drop prewarms whose slot has gone. | S |
| A2-02 | P1 | Main-thread work | PageTemplatePicker.swift:314 | `return customTemplates.preview(for: custom)` | The cell body calls a synchronous main-actor render: `CustomTemplateStore.preview` (`PageTemplates.swift:219`) runs `TemplateRenderer.image` → `drawCustom`, which does `CGImageSourceCreateWithURL` + a full-resolution decode + a CGContext page draw, inside a SwiftUI body. Every custom cell hitches on first appearance and again each time a row scrolls in. Built-in previews do the same at `PageTemplatePicker.swift:276` (`TemplateImageCache.preview` renders on a miss). | Render previews in `.task(id:)` off-main into `@State`, the way `PageThumbnailCell` already does, and keep `AppColor.paper` until the image lands. | M |
| A2-03 | P2 | Main-thread work | ContinuousPagesView.swift:323 | `if newOrder != pageOrder {` | `updateUIView` runs on every stroke (the page content is re-rendered per stroke and `activePage` is passed as the whole `Page`), and each run compares the full `pageOrder` array — 1,000 UUIDs on a big notebook — then calls `renderPriority()`, which scans `pageOrder` once per slot (`:922` `pageOrder.firstIndex(of: id)`). Per-stroke cost grows with notebook length. | Compare a revision token instead of the array, and keep a `[UUID: Int]` order map for `renderPriority`. | S |
| A2-04 | P2 | Main-thread work | ContinuousPagesView.swift:626 | `while let self, !self.renderQueue.isEmpty {` | The page-image loop never checks cancellation, and `render` only tests the slot once, before `loadPage` (`:635`). A page that scrolls out of the viewport mid-render still finishes a full paper draw — 77 ms for a scanned page — ahead of the page the user is now looking at. `PERFORMANCE-NOTES.md` #40 claims such renders are "skipped when the slot is gone". | Re-check `slots[pageID] != nil` and `Task.isCancelled` after `loadPage`, before the detached draw, and cancel `renderTask` when the view goes away. | S |
| A2-05 | P2 | Main-thread work | ContinuousPagesView.swift:640 | `guard let loaded = try? await source.store.loadPage(pageID, in: source.notebookID) else { return }` | A page that fails to read (bad JSON, missing file) stays blank paper forever with no message: the failure is swallowed and nothing marks the slot, so it looks like the page was erased. | Report the failure to the session (the pane already has a banner) and mark the slot as failed. | S |
| A2-06 | P2 | Dark mode | HighlightedSnippet.swift:28 | `text[lower..<upper].backgroundColor = Color.orange.opacity(0.28)` | The same search hit is orange in the result list and yellow-with-orange-border on the page (`PencilSearchPad.swift:212`). Two hard-coded colours for one concept, neither from `AppColor`, so the two surfaces drift as the design tokens land. | One `AppColor.searchHit` fill/stroke pair used by both. | S |
| A2-07 | P2 | Keyboard | NotebookFindBar.swift:159 | `iconButton("chevron.up", label: "Previous result") {` | Next/previous result exist only as 28 pt buttons. ⌘F opens the bar (`NotebookView.swift:943`) but there is no ⌘G / ⇧⌘G (or ⌘↓/⌘↑), so on the Mac the result steppers are mouse-only. | `.keyboardShortcut("g", modifiers: .command)` and the shifted variant on the two buttons. | S |
| A2-08 | P2 | Touch targets | NotebookFindBar.swift:194 | `.frame(width: 28, height: 28)` | Clear, previous, next, filter, list and close are all 28×28 in one 44 pt row with 6 pt gaps — seven sub-44 pt controls shoulder to shoulder in the panel's busiest surface. | 44 pt targets (or a 44 pt frame with a 28 pt glyph) and fewer visible controls at 220 pt width. | S |
| A2-09 | P2 | Accessibility | NotebookFindBar.swift:278 | `.accessibilityLabel(pageTitle(result))` | A result row is announced as "Page 12" only. The snippet and the match count — the reason it matched — never reach VoiceOver, so search results are unusable without sight. | Label with page, first snippet and hit count. | S |
| A2-10 | P2 | Main-thread work | NotebookFindBar.swift:309 | `private var pageResults: [PageResult] {` | Rebuilt (group + sort) on every body pass and read five times per pass (`results`, `canStepBack`, `canStepForward`, `selectedIndex`, `step`). The body re-runs per keystroke and, with the panel's Search tab open, per stroke (see A2-12), so a 500-hit notebook pays five grouping passes and five sorts of 500 hits per body evaluation. | Compute once into `@State` when `hits`/sources change. | S |
| A2-11 | P2 | Memory | PageBackground.swift:118 | `let combined = composite(paper: dimmedPaper, ink: invertedInk, pageSize: pageSize, scale: scale)` | On dark paper the sharp render holds five full-page bitmaps at once (paper, dimmed, ink, inverted, composite). At the cache's 4× bucket a 595×842 page is 2380×3368 px, 32 MB each, so one settled zoom can spike ~160 MB transient and the 128 MB cache then holds only four buckets of one page. | Composite the layers in one pass (draw paper, multiply the picture rects, draw inverted ink) instead of five bitmaps, and render only the visible rect at high zoom. | M |
| A2-12 | P2 | Main-thread work | PagesSidePanel.swift:32 | `guard let page = session.page, page.height > 0 else { return 0.707 }` | The panel body subscribes to `session.page`, which changes on every stroke, so the panel — grid plus embedded find bar — re-renders per stroke with the panel open. This is the same class of bug `PERFORMANCE-NOTES.md` #5 and #11 removed from the pane. | Take the aspect ratio from `session.currentPageID` plus a page-size lookup in a child view, never from `page`. | S |
| A2-13 | P2 | Touch targets | PagesSidePanel.swift:72 | `.frame(width: 28, height: 28)` | The panel's only close control is 28×28, in the header that the ADR says is the way out of the panel. | 44 pt hit area around the 15 pt glyph. | S |
| A2-14 | P2 | Motion | PagesSidePanel.swift:95 | `withAnimation(.easeInOut(duration: 0.18)) {` | The panel's scroll to the current page always animates: a one-off curve instead of a shared token, and Reduce Motion is never consulted, so the glide survives for users who asked for no motion. | Shared quick animation, skipped when `accessibilityReduceMotion` is on. | S |
| A2-15 | P2 | Fast-changing ids | PagesSidePanel.swift:147 | `.id(index)` | Cell identity is the index while the cell carries its own `@State image` (`:184`). Insert or delete a page and every cell below keeps showing the previous page's picture until its new render lands — the wrong page under the right number. | `.id(pageID)`, or drop the `.id` and key the state on the page id. | S |
| A2-16 | P2 | Loading states | PageTemplates.swift:207 | `guard let data = try? Data(contentsOf: indexFile),` | A corrupt or unreadable template index silently empties `templates`, so the picker's Custom section shows the "import one of your own" hint as though the user never imported anything. Their templates look deleted. | Surface the read failure in the Custom section with a retry. | S |
| A2-17 | P2 | Memory | PageTemplates.swift:225 | `previews.setObject(image, forKey: key)` | `CustomTemplateStore.previews` sets `totalCostLimit = 32 MB` (`:186`) but stores objects without a cost, so the limit never applies; the cache is also absent from `MemoryPressure.purgeCaches()`, which empties the other five. Decoded template bitmaps accumulate for the session. | Pass `cost:` and add it to `MemoryPressure.purgeCaches()`. | S |
| A2-18 | P2 | Main-thread work | PencilSearchPad.swift:242 | `strokeIDs: strokes.map(\.id),` | The highlight overlay's task id copies and hashes every stroke id, and the page content body runs per stroke — a 2,000-stroke page allocates and hashes 2,000 UUIDs on every stroke while a search highlight is showing. | Key on `session.revision` (or the stroke count and last id). | S |
| A2-19 | P2 | Touch targets | PageElementViews.swift:91 | `.frame(width: 38, height: 32)` | Bold / Italic / Underline in the text composer are 38×32 — the three most-tapped controls in that sheet, below the 44 pt minimum. | 44 pt tall. | S |
| A2-20 | P3 | Keyboard | GoToPageField.swift:35 | `.keyboardType(.numberPad)` | The doc comment promises "pressing Return jumps there", but the iPad number pad has no Return key and `.submitLabel(.go)` never shows, so the Go button is the only way in — a hidden dependency the comment hides. | Allow a keyboard with a return key, or add a keyboard toolbar Done. | S |
| A2-21 | P3 | Main-thread work | HandwritingSearch.swift:273 | `marks += await Task.detached(priority: .userInitiated) {` | PDF text extraction for page marks cannot be cancelled and each page/highlight change starts another, so flipping pages with a search open stacks full PDF extractions. | One latest-wins task keyed by page and query. | S |
| A2-22 | P3 | Copy | NotebookFindBar.swift:216 | `noMatches` | With an empty field the embedded Search tab is blank — no hint of what is searched (handwriting, typed text, PDFs, page numbers). | One line of placeholder copy above the (absent) results. | S |
| A2-23 | P3 | Motion | ContinuousPagesView.swift:1168 | `pager.setContentOffset(target, animated: animated && isNeighbour)` | A thumbnail tap 20 pages away in horizontal mode cuts instantly, while the same tap in vertical mode animates (`:915`). Same gesture, two behaviours. | Animate all programmatic page jumps in horizontal mode too, or none in either. | S |
| A2-24 | P3 | Main-thread work | PageBackground.swift:318 | `let key = baseKey` | The body rebuilds the whole cache key (a string per visible element) plus the `.task(id:)` string on every stroke, because `PaperBackground(page:)` is re-evaluated per stroke. | Compute the key from the element ids/`updatedAt` tuple once per element change. | S |
| A2-25 | P3 | Main-thread work | PageBookmarks.swift:99 | `let folders = (try? FileManager.default.contentsOfDirectory(` | `allBookmarks` lists every notebook folder and decodes each `bookmarks.json` synchronously on the main actor on first read (from `prepare`). | Build it in a detached task and publish. | S |
| A2-26 | P3 | Main-thread work | PageElementViews.swift:128 | `(session.page?.elements ?? []).sorted { $0.zIndex < $1.zIndex }` | The sheet sorts elements on every body pass, and `ElementEditLayer.ordered` (`ElementEditLayer.swift:22`) sorts the same array again for the page. | Sort once. | S |
| A2-27 | P3 | Copy | PageTemplatePicker.swift:203 | `Button("Import PDF or PNG…", systemImage: "plus") {` | The importer accepts `.image` (JPEG, HEIC, …) and `isReadableImage` accepts any decodable image, so the label names two of the accepted formats. | "Import PDF or image…". | S |
| A2-28 | P3 | Main-thread work | PageTemplates.swift:305 | `private func writeTemplateFile(_ data: Data, fileExtension: String) throws -> String {` | The imported template's bytes (a multi-MB PNG) are written on the main actor inside `importTemplate`, right after the off-main read. | Do the write in the same detached task as the read. | S |
| A2-29 | P3 | Copy | PagesSidePanel.swift:76 | `.accessibilityLabel("Hide Panel")` | The panel's close action is "Hide Panel" here, "Close search" in the bar (`NotebookFindBar.swift:180`) and "Hide results" for the list toggle (`:177`) — three verbs on one surface. | One verb for closing the panel, one for closing search. | S |
| A2-30 | P3 | Loading states | PagesSidePanel.swift:210 | `Image(systemName: "exclamationmark.triangle")` | A thumbnail that fails to load is a small tertiary triangle: no text, no retry, no reason. | One-line label plus tap-to-retry. | S |
| A2-31 | P3 | Memory | PDFLinkHandler.swift:26 | `private static var lastDocument: (url: URL, document: PDFDocument)?` | The last parsed PDF is retained for the life of the app after the last link tap, including PDFKit's page caches, on a 4 GB device where 400-page scans are the target case. | Drop it when the notebook closes, or keep a weak/URL-only record. | S |
| A2-32 | P3 | Accessibility | ElementEditLayer.swift:74 | `.onTapGesture {` | An element's own select target has no label or button trait; only the resize handle is labelled (`:94`). VoiceOver reads a stack of unlabelled rectangles over the page. | Label each element by content type plus "element". | S |

## Render sites (unshared `Task.detached` limit)

| file:line | priority | renders | cancellation reaches it | many at once during a fast scroll |
|---|---|---|---|---|
| ContinuousPagesView.swift:649 | .userInitiated | Whole inactive page: paper, strokes, elements, PDF/photo decode | No. The loop (`:626`) never checks; the detached task is only abandoned, never cancelled, after it starts | No — serial queue, but a page that leaves mid-render still finishes (A2-04) and the queue is rebuilt every scroll frame |
| PageBackground.swift:358 | .userInitiated | Base 2× paper for the live page | Partly — checked after the draw (`:369`), never during | Up to 2 (base is awaited before sharp) |
| PageBackground.swift:389 | .userInitiated | Sharp paper at the bucketed zoom (≤4×) | Partly — 150 ms debounce plus a post-draw check; the detached draw itself is unstoppable | A few per pinch bucket; each new settled zoom starts another while the last finishes |
| PageBackground.swift:462 | .utility | 2× paper of a nearby PDF/photo page (`prewarm`) | No — no handler, no check | Yes, unbounded: one per completed page image, plus duplicates for the same key (A2-01) |
| PagesSidePanel.swift:286 | .utility | Thumbnail at 0.3× | Yes — `withTaskCancellationHandler` forwards it (`:295`) and the task checks before drawing | Yes, one per visible cell, but a cell that scrolls away before its turn is skipped (matches PERFORMANCE-NOTES #8) |
| PageTemplates.swift:340 | .userInitiated | PDF first page raster at 1190×1684 on template import | No | No (one import at a time) |
| PageTemplates.swift:246 | .userInitiated | Whole template file bytes on import | No | No |
| HandwritingSearch.swift:273 | .userInitiated | PDF text extraction for match marks | No | Yes — one per page/highlight change (A2-21) |

## Off-scale layout metrics (head 2)

Scale: spacing 2/4/8/12/16/20/24/32, radius 4/8/10/12/16/20.

**PagesSidePanel.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| cornerRadius 7 (page cell, add-page tile, ring) | 4 | 8 | low |
| spacing 10 (LazyVGrid spacing, GridItem spacing) | 2 | 8 or 12 | low |
| spacing 3 (page number under cell) | 1 | 4 | low |
| padding 10 (grid, header horizontal) | 2 | 8 or 12 | low |

**PageElementViews.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| cornerRadius 7 (style button) | 1 | 8 | low |
| spacing 10 (style button row) | 1 | 8 | low |
| padding 12 / spacing 12 / radius 10 / spacing 2 | — | on scale | none |

**ElementEditLayer.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| padding 6 (lock badge inset) | 1 | 4 or 8 | low |
| padding 4 / frame 44 | — | on scale | none |

**PageTemplatePicker.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| spacing 10 (section header→content, size block) | 3 | 8 or 12 | low |
| spacing 22 (section gap) | 1 | 24 | low |
| cornerRadius 14 (applying overlay card) | 1 | 12 or 16 | low |
| padding 7 (selected checkmark) | 1 | 8 | low |
| padding 20/16, spacing 16/12/8, radius 12/8 | — | on scale | none |

**PDFLinkHandler.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| spacing 5 (glyph→text in chip) | 1 | 4 | low |
| frame height 20 (divider), padding 12 | — | on scale | none |

**NotebookFindBar.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| spacing 6 (bar row, result header) | 2 | 8 | low |
| padding vertical 10 (page-number row, result row) | 2 | 8 or 12 | low |
| padding vertical 14 (no-matches) | 1 | 12 or 16 | low |
| padding horizontal 10 (bar) | 1 | 8 or 12 | low |
| cornerRadius 14 (floating card) | 2 | 12 or 16 | low |
| spacing 5 (header glyph) | 1 | 4 | low |

**PencilSearchPad.swift**

| value | count | proposed token | risk |
|---|---|---|---|
| spacing 10 (pad column) | 1 | 12 | low |
| spacing 6 (recognised-text row) | 1 | 8 | low |
| radius 12/4, padding 16 | — | on scale | none |

**ContinuousPagesView.swift, ZoomablePageView.swift, PageBackground.swift, GoToPageField.swift, HighlightedSnippet.swift, PageTemplates.swift, PageBookmarks.swift, PageOutline.swift, HandwritingSearch.swift, PageNumberQuery.swift** — no off-scale layout values. UIKit constants there are on scale (`gap` 16, `fitMargin` 20, `revealMargin` 24); `PageSlotView`'s `shadowRadius = 18` is a shadow, not a radius token. `PageTemplates.swift`'s 18/24/26/30/32/40 are template *line spacings* (paper content), not UI metrics.

Same element, different metrics:

- Rounded page/card surfaces use three radii: 7 (panel page cell and add-page tile), 8 (template preview), 6 (`TapeElementView.cornerRadius`), 10 (sticky note).
- Selected-page ring: 2 pt accent ring in the panel (`PagesSidePanel.swift:222`) vs 2.5 pt accent border on the template preview (`PageTemplatePicker.swift:297`).
- Row insets: find bar rows 12/10 (`NotebookFindBar.swift:271`), page-element rows 12 vertical 2 (`PageElementViews.swift:211`), panel grid padding 10.

## Fixed font sizes (head 3)

| file:line | size | styles | text or glyph |
|---|---|---|---|
| ElementEditLayer.swift:85 | 9, bold | resize-handle arrow | glyph — may stay, though 9 pt is at the edge of legible |
| PageElementViews.swift:90 | 15, semibold | Bold/Italic/Underline buttons | glyph — may stay |
| PageElementViews.swift:297 | `fontSize` (default 15) | sticky-note body text | text, but page-space element content that must not follow Dynamic Type; keep fixed |
| PagesSidePanel.swift:71 | 15, medium | panel close glyph | glyph — may stay |
| PDFLinkHandler.swift:256 | 12, semibold | back/forward chevrons in the link chip | glyph — may stay |

## Motion (head 4)

| file:line | curve | animates |
|---|---|---|
| PagesSidePanel.swift:95 | `easeInOut(0.18)` | panel grid scroll to the current page on page change; no Reduce Motion gate (A2-14) |
| PagesSidePanel.swift:100 | none | same scroll on appear — the first one jumps while every later one glides |
| ContinuousPagesView.swift:418 | UIKit default | `reveal`: scrolls a rect (Zoom View band) into view; no Reduce Motion gate |
| ContinuousPagesView.swift:915 → 783 | UIKit default | vertical page jump after a page change from thumbnails, pill, go-to-page; always animated |
| ContinuousPagesView.swift:1168 | UIKit default, neighbours only | horizontal page jump; a far jump is instant (A2-23) |
| ZoomablePageView.swift:21, 26, 31 | UIKit default | fit / zoom-in / zoom-out (×1.35) |
| — | none anywhere in the area | no `.animation`/`.transition`: the Pages⇄Search tab switch, results appearing, and the image→live-page swap all cut instantly while the panel scroll glides |

Reduce Motion is not consulted anywhere in these files.

## Not checked

- `NotebookView.swift`, `NotebookPane` and the canvas: I inferred that `PagedNotebookView.updateUIView` runs per stroke from `pageArea` reading `session.page` and passing it as `activePage`, but did not read the pane's body to confirm how often SwiftUI re-invokes it.
- No device measurements. Every P1 claim is a code-path argument; the 77 ms / 32 MB figures are from `PERFORMANCE-NOTES.md` and from page-size arithmetic, not from a run.
- `PageRenderer` and the rest of `TemplateRenderer` were not read, so per-preview draw cost in A2-02 is estimated (page-sized vector draw vs image decode).
- `SearchKit`'s `SearchIndex.search` internals (cost, cancellation) were not audited; only the app-side call sites.
- Whether the panel's aspect ratio *should* follow the current page is documented only in a code comment, not an ADR; I do not propose changing the behaviour, only how it is read.
- macOS `#else` branches were read but not exercised.
- The ~25 `Task.detached` sites outside these files were not audited.
- `PageBookmarks`/`PageOutline` have no UI of their own; only their main-actor I/O was checked.
- The `PageImageCache`/`PageBackgroundCache` purge wiring was verified (`MemoryPressure.purgeCaches` empties both), so no finding was raised there.
