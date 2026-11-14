# A3 — library and app shell audit

Read-only audit of the library, settings, backup, import and export surfaces. No build, no test, no edit outside this file.

Files read:

| File | Lines |
|---|---|
| `NoteApp/RootView.swift` | 84 |
| `NoteApp/NoteAppApp.swift` | 10 |
| `NoteApp/AppModel.swift` | 948 |
| `NoteApp/AppColor.swift` | 137 |
| `NoteApp/MemoryPressure.swift` | 37 |
| `NoteApp/Library/LibraryView.swift` | 1537 |
| `NoteApp/Library/LibraryCovers.swift` | 144 |
| `NoteApp/Library/LibraryTags.swift` | 72 |
| `NoteApp/Library/ContinueRail.swift` | 91 |
| `NoteApp/Library/PageRecents.swift` | 63 |
| `NoteApp/Library/NotebookCoverStyle.swift` | 159 |
| `NoteApp/Library/PagePreviewThumbnail.swift` | 92 |
| `NoteApp/Library/PageOverviewGrid.swift` | 134 |
| `NoteApp/Library/PinnedPagesList.swift` | 127 |
| `NoteApp/Library/PageHistoryControls.swift` | 54 |
| `NoteApp/Settings/AppSettings.swift` | 188 |
| `NoteApp/Settings/SettingsView.swift` | 281 |
| `NoteApp/Backup/BackupView.swift` | 325 |
| `NoteApp/Backup/BackupFilePickers.swift` | 92 |
| `NoteApp/Import/ImageSizeReader.swift` | 15 |
| `NoteApp/Import/PDFImportFlow.swift` | 371 |
| `NoteApp/Import/PDFImporter.swift` | 432 |
| `NoteApp/Export/PDFExport.swift` | 282 |
| `NoteApp/Export/PDFExportOptionsSheet.swift` | 108 |

Total: 24 files, 5 784 lines. Read against `PERFORMANCE-NOTES.md` and the four decision records named in the brief (page operations/settings, PDF vector export/import, dark paper, phase-1 durability). No code in these files contradicts those decisions.

## Findings

| ID | Sev | Head | file:line | Quoted line | Why it hurts the user | Proposed fix | Size |
|---|---|---|---|---|---|---|---|
| A3-01 | P1 | 1 | `NoteApp/AppModel.swift:170` | `await boards.load()` | `isLoading` is only cleared at line 189, so the first library frame waits for `reload()`, `templates.load()` (a synchronous `Data(contentsOf:)` on the main actor), the trash purge, the history sweep, and then StudyKit, TextKit and BoardKit loading **every one of their documents, in series**. On a library with boards, study sets and text documents this is launch time spent on three screens the user did not open, and `RootView` can only show "Opening library…" while it happens (the perf notes budget 400 ms to first frame). | Show the library as soon as `reload()` returns (`isLoading = false` right after line 164); move `templates.load`, `study.load`, `textDocs.load`, `boards.load` and the two sweeps into one `Task` that runs after the first frame (and `async let` them together), each guarded so its badges arrive late rather than blocking. | M |
| A3-02 | P1 | 1 | `NoteApp/AppModel.swift:214` | `let listing = try await store.scanNotebooks()` | Every `reload()` lists `notebooks/` and `trash/` and reads + JSON-decodes **every** `notebook.json` (`LibraryStore.scan`), then replaces `notebooks` and `trashedNotebooks` wholesale. With 200 notebooks that is ~200 file reads and decodes plus two directory listings. It is called by 23 sites in `AppModel`, and 18 of them are single-notebook or single-folder edits (table below), so starring a notebook, renaming it or dragging it into a folder pays the whole scan and re-renders the whole grid before the star appears. | Replace the 18 in-place calls (table below); keep a full `reload()` only for launch, retry and backup restore. Consider `Listing` returning a per-notebook `updatedAt` diff so `notebooks` is only replaced when a value actually changed. | L |
| A3-03 | P1 | 1 | `NoteApp/Backup/BackupView.swift:312` | `backups = BackupArchive.summaries(in: directory)` | Runs from `.task` (line 59) on the main actor, and `BackupArchive.summaries` walks **every regular file of every backup** (`regularFiles(in:)` + `byteCount(of:)`) to total the size. Five backups of 2 000 pages each is ~10 000 `stat` calls before the Backup sheet can draw, and the same call runs again after each backup, verify and delete. | Make the summary list async: enumerate + stat in a `Task.detached`, publish when done, and show a "Reading backups…" row meanwhile. Persist `fileCount`/`byteCount` in the backup manifest at write time so the list never stats the payload. | M |
| A3-04 | P1 | 1 | `NoteApp/Library/LibraryView.swift:858` | `ForEach(groups) { group in` | Search results are a plain `ScrollView` + `VStack` + `ForEach` (line 836), and each group contains one nested `ForEach(sourceHits)` of 150×92 cards inside a **non-lazy** `HStack` (line 958) in a horizontal `ScrollView` (line 956). A broad query ("a") over 200 notebooks builds every group, every chip and every nested scroll view in one body pass — hundreds of views, their highlights and their backgrounds, with none of the lazy containers that the grid correctly uses. | `LazyVStack` for the groups and `LazyHStack` for the chips; cap the visible chips per source (e.g. 20) behind a "+N more" row. | S |
| A3-05 | P1 | 6 | `NoteApp/AppModel.swift:810` | `if let existing = tabs.first(where: { $0.notebookID == notebook.id }) {` | This is the only guard against a double open, and it runs **after** two awaited disk round trips (`markOpened` at 805, `loadNotebook` at 831). The grid stays on screen until `isShowingLibrary = false` at 844, so a second tap during that window (exactly what a user does when a tap appears to do nothing) passes the check before the first tap has appended its tab, and both continue to `tabs.append(newSession)` at 842. Two sessions then hold the same notebook, both save the same page, and the later write wins. | Flip a synchronous `openingNotebookID` (or set `isShowingLibrary = false`) before the first `await`, and re-check `tabs` after every await before appending; show the card in a pressed/loading state until the session exists. | S |
| A3-06 | P2 | 1 | `NoteApp/Library/LibraryCovers.swift:84` | `guard let data, let image = InkImage(data: data) else { return nil }` | `LibraryCovers` is `@MainActor`, so the PNG → `InkImage` step for every cover runs on the main actor while the grid scrolls; the expensive render is off-main (line 53) but the decode and its first draw are not. The shared task (line 43) also never checks cancellation, so a fling through 200 cards keeps rendering and writing covers for cells that are long gone. With the 48 MB memory limit only ~13 covers fit, so every pass through a large library decodes again. | Return `Data` from the detached task and decode there (`Task.detached`), or keep an `InkImage` built off-main; add `if Task.isCancelled { … }` between load, render and write, and check `Task.isCancelled` in the card's `loadCover` before assigning. | M |
| A3-07 | P2 | 1 | `NoteApp/Library/LibraryView.swift:631` | `let visibleNotebooks = model.visibleNotebooks.filter { matchesActiveTags($0.id) }` | Recomputed on **every** body run of the detail column (each keystroke in the search field, each sort change, each selection). `visibleNotebooks` filters and sorts the whole array (two sorts for `.recents`), and `matchesActiveTags` re-parses the query per notebook because it calls `activeTagKeys` (line 438) inside the filter — 200 `TagQuery` parses and 200 `Set` builds per pass. The sidebar adds its own per-pass work: `folderNodes` re-filters and re-sorts every folder at every level (line 342) and each `folderRow` calls `model.notebookCount(inFolder:)` (line 358), which re-walks the folder tree and re-filters all notebook→folder entries. At 200 notebooks and 30 folders this is a few milliseconds per keystroke on a base iPad, spent before the user's character is drawn. | Hoist the tag key set out of the filter, cache `visibleNotebooks` in a `@State` updated on `notebooks`/`selectedLocation`/`sortOrder`/query changes, and compute folder counts once per tree pass instead of per row. | M |
| A3-08 | P2 | 1 | `NoteApp/Library/LibraryView.swift:809` | `guard let index = notebook.pageOrder.firstIndex(of: hit.pageID) else { return nil }` | Grouping runs `firstIndex` over the notebook's whole `pageOrder` for every hit. An imported 1 000-page book returning 300 hits costs 300 × 1 000 = 300 000 comparisons on the main actor each time `search.hits` changes (line 102), and the group also rebuilds `Set(hits.map(\.pageID))` from `pageCount` on every read. | Build one `[UUID: Int]` page-index map per notebook before the `compactMap`, and store `pageCount` in the group instead of recomputing it in a computed property. | S |
| A3-09 | P2 | 1 | `NoteApp/AppModel.swift:219` | `bookmarks.prepare(notebookIDs: notebooks.map(\.id))` | The first `reload()` of every launch synchronously reads, decodes and (for old libraries) migrates one `bookmarks.json` **per notebook**, on the main actor, inside the launch path (`PageBookmarks` is `@MainActor` and `bookmarks(for:)` does `Data(contentsOf:)`). 200 notebooks is 200 file reads before the first frame, and any notebook whose cache entry was dropped pays it again. | Load bookmark files in a detached task into a plain dictionary and hand it to the main actor, or read them lazily per visible card after the first frame. | M |
| A3-10 | P2 | 1 | `NoteApp/Library/LibraryView.swift:1354` | `.task(id: notebook.id) {` | The search-result cover reloads only when the notebook id changes, while the sibling `NotebookCard` keys on `coverTaskID` including `updatedAt` (line 1421). After editing a notebook, its cover in search results keeps showing the image loaded the first time the view appeared (or a blank gradient if it appeared before the first page existed). | Key on `notebook.updatedAt` like `NotebookCard`, or use `LibraryCovers.cached(notebook:)` in the body with the key recomputed from the manifest. | S |
| A3-11 | P2 | 2 | `NoteApp/Library/LibraryView.swift:980` | `.padding(14)` | 23 of the 49 literal layout values in this file are off the token scale (7 padding, 12 stack spacings, 4 radii). They are all within 1–3 pt of a token, so fixing them is nearly invisible but keeps the library from drifting: `22` (grid VStack) → 24, `14` (search group card, trash row, list spacing) → 16, `10`/`9`/`7`/`6`/`5`/`3` → the nearest token. Full per-file table below. | Map to the scale as listed in the table (all low-risk); after the mapping, replace the literals with the shared spacing/radius tokens. | M |
| A3-12 | P2 | 2 | `NoteApp/Library/LibraryView.swift:1039` | `.padding(.horizontal, 9)` | The same element — a tag chip — is built with three different metrics in one file: the active-filter bar uses `9 / 3` (lines 1039–1040), the notebook card uses `7 / 2` (lines 1504–1505), and both use different fonts (`.caption.weight(.medium)` vs `.caption2`). A chip that moves from the filter bar to a card visibly changes size. | One `TagChip` view: `8 / 2` padding, `.caption2`, capsule background; use it in both places. | S |
| A3-13 | P2 | 4 | `NoteApp/Library/LibraryView.swift:1007` | `ForEach(visibleNotebooks, id: \.id) { notebook in` | There is **no animation anywhere in this area**: a search for `withAnimation`, `.animation(` and `.transition(` over all 24 files returns zero matches. Creating a notebook, deleting to the trash, moving a card between folders, re-sorting, changing the tag filter and replacing the search results all swap or reorder the array instantly, so cells jump and disappear without any transition while every other part of the app animates. The intended motion tokens (quick 0.18 s / standard 0.25 s / emphasized spring, off under Reduce Motion) have nothing to apply to. | Wrap the grid's data changes in the shared standard animation (`withAnimation(.noteStandard)`) and give inserted/removed cards a small scale+opacity transition, gated on `\.accessibilityReduceMotion`; animate the sort menu's order change with the same curve. | M |
| A3-14 | P2 | 5 | `NoteApp/Library/PageHistoryControls.swift:47` | `.frame(width: 36, height: 36)` | The two page-history chevrons are 36×36 pt (the capsule is 36 pt tall), under the 44×44 pt iPad minimum, and they sit in a floating capsule near the page edge where a mis-tap scrolls or inks instead. | 44×44 hit area (`.frame(minWidth: 44, minHeight: 44)` with the 13 pt glyph inside), or `.contentShape` expanded to 44 pt while keeping the capsule visual size. | S |
| A3-15 | P2 | 5 | `NoteApp/Library/LibraryView.swift:321` | `return button.keyboardShortcut(",", modifiers: .command)` | ⌘, is registered **only** under `#if os(iOS)`, and `NoteAppApp` has no `Settings` scene (only a `WindowGroup`), so on the Mac the standard Settings shortcut does nothing. Import is also shortcut-less: "Import PDF…" in the New menu (line 726) has no `.keyboardShortcut`, and there is no shortcut for New Folder. | Add a `Settings` scene (or give the gear button ⌘, on macOS too) and `.keyboardShortcut("i", modifiers: [.command, .shift])` for Import PDF / ⌘⇧N for New Folder. | S |
| A3-16 | P2 | 6 | `NoteApp/Import/PDFImportFlow.swift:183` | `.disabled(flow.isWorking)` | A PDF import cannot be stopped: Cancel is disabled while reading or importing, `interactiveDismissDisabled` (line 186) blocks the swipe, and `PDFImporter.scan` (loop at 284) and the page-write loop (172) contain no `Task.isCancelled` check. Importing a 1 000-page scan is minutes of work the user can only wait out, with a sheet that swallows every tap. | Keep Cancel enabled during `.importing`, hold the task, cancel it on dismiss, and add `try Task.checkCancellation()` in both loops; treat cancellation as "N of M pages added" (the existing `partialInsert` message already covers it). | M |
| A3-17 | P2 | 6 | `NoteApp/Backup/BackupView.swift:51` | `.overlay {` | Back Up, Restore, Verify and Verify All Pages all show the same indeterminate spinner with no page/file count and no cancel button; `verifyPages` can read every page in the library (line 284 loop) with no feedback beyond the spinner, and the only way out is to wait or force-quit. Every other long operation in the app (PDF import, PDF export) already has determinate progress and cancellation. | Reuse the `PDFExportProgress` pattern: a `(done, total)` callback per notebook/page, a determinate `ProgressView` with "Verifying page 312 of 1 040", and a Cancel button that cancels the task between items. | M |
| A3-18 | P2 | 6 | `NoteApp/AppModel.swift:509` | `ThumbnailCache.invalidate(notebookID: notebook.id, pageID: pageID)` | "Regenerate Thumbnails" deletes the covers folder on disk and invalidates page thumbnails, but never calls `LibraryCovers.removeAllFromMemory()`, and the cards' `.task(id: coverTaskID)` ids do not change, so every library cover keeps showing the image it had before. The row reports "Done" while the most visible thumbnails in the app were not regenerated. | Call `LibraryCovers.removeAllFromMemory()` and bump a `coverGeneration` value included in `coverTaskID` (or call `reload()` after clearing), and mention covers in the row's progress. | S |
| A3-19 | P2 | 6 | `NoteApp/Backup/BackupView.swift:131` | `pendingDelete = offsets.compactMap { backups.indices.contains($0) ? backups[$0] : nil }.first` | A multi-row `onDelete` keeps only the first offset and confirms/deletes one backup; the other selected backups stay, so the user believes they deleted several and they are still on disk. | Keep `[BackupArchive.Summary]` and delete all confirmed, or disable multi-select editing and use one swipe per row. | S |
| A3-20 | P2 | 6 | `NoteApp/Backup/BackupView.swift:304` | `try FileManager.default.removeItem(at: backup.url)` | Deleting a backup removes a folder with thousands of page and asset files synchronously on the main actor (the call is inside the view, not a task). The sheet freezes for as long as the filesystem takes, with no spinner because `isWorking` is never set for delete. | `Task.detached` for the removal, set `isWorking` around it, and report failure through the existing alert. | S |
| A3-21 | P2 | 9 | `NoteApp/Library/LibraryView.swift:161` | `.alert("Empty Recently Deleted?", isPresented: $showsEmptyTrashAlert) {` | One place is named three ways: the sidebar row is "Recently Deleted" (line 291), the toolbar button and alert action are "Empty Trash" (lines 693, 163), the alert title is "Empty Recently Deleted?", and a row's destructive action is "Delete" (line 1199), "Delete Permanently" (context menu, line 1207) and "Delete permanently?" (alert title, line 150). The user has to decide whether "Empty Trash" and "Delete Permanently" are the same operation. | Pick "Recently Deleted" for the place and "Delete Permanently" for the action everywhere; the toolbar button becomes "Empty Recently Deleted", the alert title "Empty Recently Deleted?" with button "Delete Permanently". | S |
| A3-22 | P2 | 9 | `NoteApp/Backup/BackupView.swift:75` | `"Backup failed",` | The one error alert is titled "Backup failed" but is also raised by Restore (line 238), Verify (line 264), Verify All Pages (line 289) and Delete (line 307). A failed restore of a corrupt archive tells the user "Backup failed", which reads as if their existing backup was damaged. | Title the alert from the operation ("Restore failed", "Verification failed", "Delete failed"), or use a neutral "Backup & Restore failed" with the operation in the message. | S |
| A3-23 | P3 | 2 | `NoteApp/Library/PageOverviewGrid.swift:73` | `.padding(.vertical, 3)` | 11 further off-scale literals live outside `LibraryView`: the page-number badge (`7 / 3`), the cover picker's checkmark inset (7) and grid spacing (18), ContinueRail's stack spacings (10, 5), the backup spinner's 28, and the import sheet's `spacing: 10`. Individually invisible; together they make the second-tier screens drift from the library. Part of the per-file table below. | Map each to the nearest token (see table). | S |
| A3-24 | P3 | 2 | `NoteApp/Library/LibraryView.swift:1004` | `columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 20)],` | The same element — a document/page tile in an adaptive grid — uses three different metrics: library cards 170–230 with grid spacing 20/24 and 14 pt corners (line 1471), page overview 148–210 with 16/20 and 8 pt corners (`PageOverviewGrid.swift:15`, 20), cover picker 120–180 with 16/18 and 10 pt corners (`NotebookCoverStyle.swift:69`, 74, 105). Switching between these screens changes tile size, gutter and corner radius. | One shared tile metric set (e.g. 150–220 min/max, gutter 16, spacing 20, radius 12) applied to all three grids. | M |
| A3-25 | P3 | 5 | `NoteApp/Library/ContinueRail.swift:55` | `Button {` | A Continue tile is a notebook page like a grid card, but long-press does nothing: no Open, Rename, Tags, Cover, Move or Delete menu, whereas `NotebookCard` has all of them (line 1017). The search-result notebook rows (line 846) have the same gap. | Attach the card menu (a trimmed version without Cover) to Continue tiles and search-result rows. | S |
| A3-26 | P3 | 5 | `NoteApp/Backup/BackupView.swift:168` | `Button("Verify") { verifyBackup(backup) }` | Verify and Export are `.font(.caption)` bordered buttons inside a form row, roughly 28–30 pt tall — under 44 pt on iPad and easy to hit the wrong one while aiming for the row. | `.controlSize(.regular)` with `.frame(minHeight: 44)` (or move them into the row's context menu with a single chevron). | S |
| A3-27 | P3 | 5 | `NoteApp/Library/LibraryView.swift:713` | `Button("Close All Tabs", systemImage: "xmark.circle", role: .destructive) {` | The Open Tabs menu lists each tab as an activate button and offers only "Close All Tabs": there is no way to close one tab from the library, and no ⌘W equivalent. | Add a per-tab close (swipe in the menu, or a small xmark button in each menu row) and a `Close Tab` command with ⌘W. | S |
| A3-28 | P3 | 6 | `NoteApp/Backup/BackupView.swift:146` | `Text("Restore a backup from the iPad.")` | On the Mac the Restore section is a dead end: a sentence with no button, while the same sheet's Back Up section works. A Mac user who needs to restore has no path from the app. | Use `fileImporter(forOpeningContentTypes: [.folder])` on macOS and run the same `BackupArchive.restore` path. | M |
| A3-29 | P3 | 7 | `NoteApp/Library/LibraryView.swift:389` | `.foregroundStyle(showsPinnedPages ? Color.accentColor : Color.primary)` | The Pinned Pages row and the tag rows (line 407) signal selection by colour only, and neither is a `List` selection tag, so VoiceOver announces "Pinned Pages, 3" with no selected state and a colour-blind user sees only a tint change. (The bookmark/tag icons do swap fill, which partly covers sighted users.) | Add `.accessibilityAddTraits(isSelected ? .isSelected : [])` (and `.accessibilityValue("Selected")`), and keep the filled-symbol change as the non-colour cue. | S |
| A3-30 | P3 | 7 | `NoteApp/Library/LibraryView.swift:1422` | `.accessibilityLabel(Text("\(notebook.title), \(pageCountText), \(dateText)"))` | The card's explicit label replaces all children, so "Open", the favourite star and up to three tags are never announced; a VoiceOver user cannot tell which notebook is already open or starred from the grid. | Append the state to the label: `…, open, favourite, tags: work, uni`. | S |
| A3-31 | P3 | 7 | `NoteApp/Backup/BackupView.swift:53` | `ProgressView()` | The busy overlay is an unlabelled spinner with no status text; VoiceOver announces a bare "progress indicator" for a backup that may run for minutes in a modal overlay. | `.accessibilityLabel("Backing up")` (operation-specific) plus `.accessibilityAddTraits(.updatesFrequently)`, or a status text inside the overlay. | S |
| A3-32 | P3 | 9 | `NoteApp/Import/PDFImportFlow.swift:56` | `isInsert ? "Insert PDF Pages" : "Import PDF"` | The sheet is titled "Insert PDF Pages" when inserting, but its confirm button says "Import Page(s)" (line 360) and the failure message says "the pages could not be added". Three verbs for one action. | Use "Insert" for the title, button and errors when `isInsert`, "Import" otherwise. | S |
| A3-33 | P3 | 6 | `NoteApp/Settings/SettingsView.swift:184` | `Toggle("Index Handwritten Notes", isOn: $handwritingRecognition)` | The toggle only stops future indexing (`HandwritingSearch.indexAll`/`index` guard on the setting); nothing clears the existing index or withdraws the Spotlight entries published while it was on, and `HandwritingSearch.search` has no guard, so handwriting hits keep appearing after the footer promises "Notebooks will be searchable when enabled". | On change: when off, `await search.updateSpotlight(enabled: false)` and reset/disable handwriting results (with a confirmation that the index will be discarded); when on, offer the existing rebuild. | S |
| A3-34 | P3 | 6 | `NoteApp/AppModel.swift:599` | `try? await store.setFolder(folderID, forNotebook: result.manifest.id)` | Importing a PDF while a folder is selected files it there, but the failure is swallowed: the notebook opens in All Notebooks and the user is never told it was not filed. `createNotebook` surfaces the same failure through its catch. | Replace `try?` with `do/catch` that sets a notice ("Imported, but could not move it into <folder>"), or file it before the reload and let the existing error path report. | S |

## `reload()` call sites

`AppModel.reload()` is `@MainActor` and does two independent loads: `loadFolderTreeRecovering()` (one `folders.json` decode) and `scanNotebooks()` + `scanTrash()` (a directory list and a `notebook.json` read + decode per notebook, for both the library and the trash), then `pageRecents.prune`, `bookmarks.prepare` (line 219), the unreadable-count notice and `takeRecoveryNotices`. 23 `await reload()` call sites in `AppModel` plus one in `BackupView`.

| Call site | User action | Store call and what it returns | Could update memory in place? |
|---|---|---|---|
| `AppModel.swift:164` | App launch | `store.open()` → `LibraryInfo`; first full scan | No — this is the one call that must scan |
| `AppModel.swift:512` | Settings → Regenerate Thumbnails | no store call (cover folder wipe + thumbnail invalidation) | Not needed at all; drop it |
| `AppModel.swift:525` | Tags alert → Save | `store.setTags` → `Void`; the cleaned array is local | Yes: `folderTree.tags[id] = cleaned` |
| `AppModel.swift:553` | New Notebook | `store.createNotebook` → `NotebookManifest`; `store.addPage` → `Page` | Yes: append the returned manifest with the new page id and `Date()` for `updatedAt` |
| `AppModel.swift:571` | Failed create cleanup | delete/purge → `Void` | Yes: remove the id |
| `AppModel.swift:605` | Import PDF as new notebook | `PDFImporter.importPDF` → `PDFImportResult` carrying a freshly loaded `manifest` (with `pageOrder`) | Yes: append `result.manifest` |
| `AppModel.swift:617` | Rename notebook | `store.renameNotebook` → `Void`; caller holds the manifest | Yes: `notebooks[i].title = trimmed` |
| `AppModel.swift:636` | Duplicate | `duplicateNotebook` → the copy's `NotebookManifest`; `setFolder` → `Void`; `toggleFavourite` → `Bool`; `setTags` → `Void` | Yes: append the copy and set its folder/favourite/tags in `folderTree` from the values already computed |
| `AppModel.swift:659` | Delete to Recently Deleted | `store.deleteNotebook` → `Void` | Yes: move the manifest to `trashedNotebooks` and stamp `deletedAt = Date()` |
| `AppModel.swift:668` | Restore from trash | `store.restoreNotebook` → `Void` | Yes: move it back and clear `deletedAt` |
| `AppModel.swift:680` | Delete permanently | `store.purgeNotebook` → `Void` | Yes: remove from `trashedNotebooks` |
| `AppModel.swift:695` | Empty Recently Deleted | `store.emptyTrash` → `Int` (count removed) | Yes: `trashedNotebooks.removeAll()` |
| `AppModel.swift:704` | Pick a cover | `store.setCover` → `Void`; caller holds `name` | Yes: `notebooks[i].coverName = name` |
| `AppModel.swift:713` | Add/remove favourite | `store.toggleFavourite` → `Bool` (the new state) | Yes: insert/remove in `folderTree.favourites` |
| `AppModel.swift:722` | Move to folder | `store.setFolder` → `Void`; caller holds `folderID` | Yes: `folderTree.notebookFolder[id] = folderID`, or remove for Root |
| `AppModel.swift:743` | New folder | `store.createFolder` → `Folder` | Yes: append to `folderTree.folders` |
| `AppModel.swift:754` | Rename folder | `store.renameFolder` → `Void`; caller holds `Folder` | Yes: mutate the name |
| `AppModel.swift:771` | Folder colour / icon | `store.setFolderAppearance` → `Void`; caller holds both values | Yes: mutate colour/icon |
| `AppModel.swift:780` | Move folder | `store.moveFolder` → `Void`; caller holds `parentID` | Yes: mutate `parentID` |
| `AppModel.swift:792` | Delete folder (children move up) | `store.deleteFolder` → `Void`; the reparenting rule is the store's | Partly: `loadFolderTreeRecovering()` alone (one `folders.json` decode) refreshes the tree; rescanning every notebook is unnecessary |
| `AppModel.swift:876` | Show library | none — only the active session may have saved | `store.loadManifest(active.id)` (one `notebook.json`) or copy `active.manifest` in place |
| `AppModel.swift:922` | Close one tab | none | Copy `closing.manifest` in place; the session already holds the saved `pageOrder`/`updatedAt` |
| `AppModel.swift:946` | Close all tabs | none | Same, per tab |
| `NoteApp/Backup/BackupView.swift:232` | Restore a backup | `BackupArchive.restore` → `RestoreSummary` with `restoredNotebookIDs` | Partly: load only the restored manifests; a full scan is defensible because a restore can add many notebooks |

Views that re-render when `notebooks` is replaced wholesale (all read it, directly or through a computed property): `LibraryView.sidebar` (the All Notebooks badge, `tagSummaries`, and every folder row's `notebookCount`), the whole detail column (`visibleNotebooks` → grid or an empty state; `trashList` on the other array), every visible `NotebookCard` (it re-evaluates `coverTaskID` and calls `LibraryCovers.cached`), `ContinueRail.items`, `PinnedPagesList.pins`, and `SearchNotebookCover`. Replacing `trashedNotebooks` re-renders the sidebar's trash badge and the trash list. Replacing `folderTree` re-renders the sidebar, folder badges and the folder/favourites filters.

## Off-scale layout values, per file

Scale used: spacing/padding 2, 4, 8, 12, 16, 20, 24, 32; corner radius 4, 8, 10, 12, 16, 20.

`NoteApp/Library/LibraryView.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 3 (padding) | 1 | 4 | low |
| 7 (padding) | 1 | 8 | low |
| 9 (padding) | 1 | 8 | low |
| 10 (padding) | 2 | 8 or 12 | low |
| 14 (padding) | 1 | 16 | low |
| 18 (padding) | 1 | 16 or 20 | low |
| 3 (spacing) | 1 | 4 | low |
| 6 (spacing) | 3 | 8 | low |
| 10 (spacing) | 5 | 8 or 12 | low |
| 14 (spacing) | 2 | 16 | low |
| 22 (spacing) | 1 | 24 | low |
| 5 (radius) | 2 | 4 | low |
| 14 (radius) | 2 | 12 or 16 | low |

`NoteApp/Library/PageOverviewGrid.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 7 (padding) | 1 | 8 | low |
| 3 (padding) | 1 | 4 | low |
| 6 (spacing) | 1 | 8 | low |

`NoteApp/Library/ContinueRail.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 10 (spacing) | 1 | 12 | low |
| 5 (spacing) | 1 | 4 | low |

`NoteApp/Library/NotebookCoverStyle.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 7 (padding) | 1 | 8 | low |
| 18 (spacing) | 1 | 16 or 20 | low |

`NoteApp/Backup/BackupView.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 28 (padding) | 1 | 24 or 32 | low |

`NoteApp/Import/PDFImportFlow.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 10 (spacing) | 2 | 12 | low |

`NoteApp/Library/PageHistoryControls.swift`

| Value | Count | Proposed token | Risk |
|---|---|---|---|
| 0 (spacing) | 1 | 0 (deliberate divider gap) | none |

No off-scale literal padding, spacing or radius in `RootView.swift`, `NoteAppApp.swift`, `AppModel.swift`, `AppColor.swift`, `MemoryPressure.swift`, `LibraryTags.swift`, `PageRecents.swift`, `PagePreviewThumbnail.swift`, `PinnedPagesList.swift`, `AppSettings.swift`, `SettingsView.swift`, `BackupFilePickers.swift`, `ImageSizeReader.swift`, `PDFImporter.swift`, `PDFExport.swift`, `PDFExportOptionsSheet.swift`.

## Fixed font sizes

| file:line | Size | What it styles | Text or glyph |
|---|---|---|---|
| `NoteApp/Library/PageHistoryControls.swift:46` | 13, semibold | the Back/Forward chevrons in the history capsule | glyph — may stay fixed (but the 36 pt target around it is a finding, A3-14) |
| `NoteApp/Library/LibraryView.swift:1436` | `symbolSize * 1.8` (`@ScaledMetric` base 22, relative to `.title2`) | the cover-style SF Symbol on a library card | glyph — may stay fixed; already scaled |
| `NoteApp/Library/LibraryView.swift:1452`, `:1461` | `symbolSize` (base 22, `.title2`) | the "preview unavailable" and loading glyphs on a card | glyph — may stay fixed; already scaled |

No `.font(.system(size:))` styles text anywhere in this area; all text uses text styles.

## Motion

`rg 'withAnimation|\.animation\(|\.transition\(|\.contentTransition|\.symbolEffect|\.matchedGeometry|\.spring|\.easeIn|\.easeOut|\.linear|\.bouncy|\.smooth|\.snappy|ReduceMotion'` over the 24 files returns **no matches**. Nothing in this area animates, so nothing has a curve to compare — and nothing honours Reduce Motion because there is nothing to reduce. Changes that jump with no animation:

| Change | Site | Animation |
|---|---|---|
| Create notebook, grid gains a card | `LibraryView.swift:1007` (ForEach over `visibleNotebooks`) | none |
| Delete to trash / restore / purge, card leaves or enters | `LibraryView.swift:1007`, `:1181` | none |
| Move a card between folders, or a folder in the tree | `LibraryView.swift:360` (`contextMenu`), `:1007` | none |
| Sort order change, every card reorders | `LibraryView.swift:742` (`Picker` bound to `$model.sortOrder`) | none |
| Tag filter / search results swap the whole grid | `LibraryView.swift:631`, `:858` | none |
| Pinned Pages and tag rows swap the detail column | `LibraryView.swift:377`, `:398`, `:593` | none |
| Trash row removed after purge | `LibraryView.swift:1181` | none |
| Backup list row removed after delete | `BackupView.swift:127` | none |

## Not checked

- **Dark mode (head 8): no findings.** Chrome colour in this area goes through `AppColor` (`groupedBackground`, `paper`, `pageAnnotation`, `swatchOutline`) or system semantics (`.separator`, `.secondary`, `.thinMaterial`, `.regularMaterial`). The hard-coded RGB values are the eight `NotebookCoverStyle` gradients and the card overlays drawn *on* those gradients, which the dark-mode decision keeps light by design ("Covers and whiteboards stay light"). I did not audit the editor, page caches or PDF rendering, where the dark-paper rules actually apply.
- **VoiceOver sweep is static, not run.** A3-29/30/31 come from reading labels and traits; I could not run VoiceOver or Dynamic Type to see how card labels, badges and the 150×92 hit chips reflow at accessibility sizes.
- **No measurement.** No build, no Instruments, no simulator. The per-body costs in A3-07/A3-08 and the launch cost in A3-01 are reasoned from the code and the item counts (200 notebooks, 30 folders, 1 000-page PDF), not timed; the perf notes' 400 ms launch budget and 2–3× base-iPad factor are the only numbers used.
- **Store internals outside the assigned files** (`LibraryStore`, `BackupArchive`, `HandwritingSearch`, `PageBookmarks`, `ThrottleCache`/`ThumbnailCache`, `PageRenderer`) were read only to describe what the calls in my files return or cost; no findings are filed against them.
- **`LibraryStore.scan`'s own JSON decoder cost** is not broken down (200 × `ManifestCodec.decode`); the finding is about call frequency, not the decode constant.
- **Export destination flows** (`fileExporter` in the editor) are outside this area, so export cannot be checked end to end here; `PDFExportOptionsSheet` and `NotebookExporter` themselves were read in full and have progress, cancellation checks and off-main rendering.
- **`PDFExportOptionsSheet` range validation** (From > To) is not reported: `PDFExportOptions.pageIndices` normalises with min/max, so a reversed range exports the pages between rather than failing.
- **`BackupFilePickers`** is a thin `UIDocumentPickerViewController` wrapper; its delegate callbacks are correct and it has no UI of its own, so it yielded no findings.
