# Storage & Data Integrity Audit

Scope: `NoteCore`, `SyncKit`, `HistoryKit`, `AppModel.swift`, `NotebookSession.swift`, plus the ordered-writes ADR. Read-only; every claim is traced to code.

**What is already right.** The ADR's ordered write queue exists (`NotebookSession.swift:881-919`); `LibraryStore` is an actor, so manifest read-modify-write is serialised in-process (`LibraryStore.swift:365-373`); page-before-manifest ordering is consistent; scanning skips unreadable manifests (`:653-669`); HistoryKit writes atomically with fsync (`AtomicFile.swift:22-49`). The failures below sit *around* that core.

---

## 1. Findings

### CRITICAL

**C1 — One corrupt `folders.json` makes the library look empty.**
`AppModel.reload()` assigns the tree *before* scanning notebooks (`AppModel.swift:187-193`), and both live in one `do`/`catch` (`:194-196`). `loadFolderTree()` propagates a decode failure (`LibraryStore.swift:495-499` → `LibraryCodecs.swift:20-22`). So a damaged tree throws at line 187 and `notebooks = listing.manifests` (`:190`) never runs.
*User-visible:* every notebook is still on disk, but the grid is empty at launch — indistinguishable from total data loss. Worse, `FolderTree.init(from:)` throws on a single malformed UUID in `notebookFolder`, `tags` or `favourites` (`Folder.swift:77-84, 90-96, 103-110`), so one bad entry costs the whole tree.
*Fix:* load tree and notebooks in separate `do` blocks; on tree failure fall back to `FolderTree()` plus a notice ("Folders could not be read; notebooks are unaffected"). Have `FolderTree.init(from:)` skip malformed entries instead of throwing. Never let the grid's data depend on the tree's decode.

**C2 — Corrupt `library.json` bricks the app with no repair path.**
`open()` decodes it and throws (`LibraryStore.swift:71-73`); `AppModel.start()` turns that into `loadError` with a retry button (`:169-173`) that re-runs the identical decode (`:178-183`). Nothing else is consulted, though the file holds only `schemaVersion` + `deviceID` (`LibraryInfo.swift:4-12`), and nothing reads `deviceID`.
*User-visible:* a permanent "library cannot be opened" screen; the only exit is reinstalling, which deletes every notebook.
*Fix:* treat a decode failure as "first run": move the bad file to `library.json.damaged-<timestamp>`, mint a new `deviceID`, continue. Never gate opening on this file.

### HIGH

**H1 — A failed save silently loses a page's ink on navigation.**
`loadPage` calls `await commitPendingSave()` and ignores whether it succeeded (`NotebookSession.swift:236`); `commitPendingSave` only puts the page back if no newer one is queued (`:913`). `pendingPage` is a single slot (`:64`), so the first edit on the next page overwrites the retry copy. The error message is also cleared by the new page's own save. The ADR names this gap (`ordered-page-writes.md:27`) but it was never closed.
*User-visible:* a transient I/O error or full disk silently discards minutes of writing; the user sees one toast, then nothing.
*Fix:* `pendingPages: [UUID: Page]`, drained in order and retried; make `loadPage` await a successful flush or refuse navigation with a blocking "not saved" banner. Never overwrite an unsaved entry.

**H2 — Permanently deleted notebooks keep their full ink history forever.**
`VersionHistoryStore.deleteNotebook` exists (`VersionHistoryStore.swift:262-281`) and is called **only from tests** (`VersionHistoryStoreTests.swift:236-237`). `AppModel.purge` (`:585-593`) and `emptyTrash` (`:596-607`) never call it, so `Documents/History/<notebook-id>/*.snapshot` (root at `AppModel.swift:125-128`) survives purge and trash expiry forever.
*User-visible:* storage grows without bound, and a "deleted" notebook stays readable on disk — bad for an app people delete notes in on purpose. `prune` only caps total bytes at 200 MB (`SnapshotPolicy.swift:25`) and is best-effort (`AppModel.swift:160`).
*Fix:* call `history.deleteNotebook` from `purge`, `emptyTrash` and `purgeExpiredTrash`, and sweep history directories with no matching notebook.

**H3 — Deleted pages can come back after a crash.**
`deletePage` rewrites the manifest first, then removes the file (`LibraryStore.swift:376-389`), while `loadNotebook` re-appends every page file not in `pageOrder` (`:128-130`). A crash or failed `removeItem` in that window *resurrects* the deleted page, and `AppModel.open` then alerts "Some pages needed attention" every launch (`:748-753`).
*Fix:* add `deletedPageIDs` tombstones to `NotebookManifest`, filter orphans through them, and sweep old tombstones — which also ends the alert-on-every-open noise.

**H4 — Orphan pages break page reordering permanently.**
The reconciliation in `loadNotebook` is in-memory only ("A load never rewrites the manifest", `:121, 130`). `moveCurrentPage` sends that reconciled order straight to `reorderPages` (`NotebookSession.swift:384-390`), whose guard demands an exact count match against the on-disk manifest (`LibraryStore.swift:393-397`). After any crash between `writePageFile` and the manifest write in `addPage`/`savePage` (`:349-354`, `:367-372`), every move throws → "The page could not be moved."
*Note:* `insertPages` accidentally heals this by calling `reloadManifest()` first (`NotebookSession.swift:344-352`) — which proves the fix.
*Fix:* let `reorderPages` accept a superset (append unknown ids), and persist the reconciliation once on open.

**H5 — Deleting an open notebook races its own save.**
`AppModel.delete` moves the folder to trash (`:565`) and only then calls `closeTab` (`:567`), whose flush runs in an unawaited `Task` (`:805-815`). `savePage` starts with `loadManifest` (`LibraryStore.swift:366`), which now throws `notFound`, so the queued ink is dropped.
*Fix:* `await active.flushPendingSave()` before the move, and close the tab synchronously. Note `addAsset` (`:461-471`) is the only write that does not load the manifest first, so it can recreate `notebooks/<id>/assets/` after a delete — a permanently unreadable "notebook" no trash UI can remove.

**H6 — No fsync anywhere in the library store.**
`writeAtomically` uses `Data.write(options:.atomic)` (`LibraryStore.swift:683-690`): atomic against `kill -9`, but with no `synchronize()` and no directory sync — unlike `HistoryKit/AtomicFile.swift:35-42`, which does exactly this and could be reused. Since `savePage` rewrites `notebook.json` on every stroke save (`:371-372`), the window is hit constantly: on power loss or kernel panic the newest page or manifest can be zero-length or stale.

### MEDIUM

- **M1 — `schemaVersion` is decorative.** `SchemaVersion.current = 1` (`SchemaVersion.swift:8`), `VersionGate` only rejects *newer* files (`JSONCoding.swift:115`), and decoding uses required keys: `Page.init(from:)` (`Page.swift:83-91`), `FolderTree.Wire` (`Folder.swift:60-66`), `LibraryInfo` (synthesised). Adding one field later turns **every existing file** into `corruptFile`; there is no migration path.
- **M2 — `Zlib.decompress` can allocate 512 MB** (`JSONCoding.swift:30, 69-97`). A corrupt page header drives the doubling loop to the cap → jetsam instead of a clean error.
- **M3 — Assets are never garbage-collected.** `addAsset` is content-addressed (`LibraryStore.swift:461-471`), but nothing removes a blob when its element or page is deleted (`NotebookSession.swift:664-670`, `LibraryStore.swift:376-389`), so replaced images and PDF pages leak until purge.
- **M4 — `duplicateNotebook` silently drops pages it cannot read** (`LibraryStore.swift:294`, `try? ... else { continue }`) → a quietly incomplete copy.
- **M5 — Folder depth is display-only.** `maxFolderDepth = 12` gates rendering and menus (`AppModel.swift:341-358`), but `createFolder` has no check (`LibraryStore.swift:505-514`).
- **M6 — Trash housekeeping aborts on the first error and only handles directories** (`LibraryStore.swift:239-269`): one locked file stalls all purging, and stray files never go. A failed `markDeleted` (`:187-195`) falls back to folder creation date, purging a re-deleted notebook early.
- **M7 — Cache and history sit in `Documents` with no backup exclusion** (`AppModel.swift:426`, `:125-128`), so regenerable covers and every ink snapshot go to iCloud backup.

### LOW

- `reloadManifest` swallows errors with `try?` and leaves a stale manifest (`NotebookSession.swift:1034`), so later reorder/insert fail misleadingly; `recordSnapshot` likewise swallows failures (`:960-967`).
- `insertPages` reports "could not be added" even when the page files are on disk and visible (`:356-361`).
- Folder cycles *are* handled correctly (`LibraryStore.swift:544-555`, `AppModel.swift:316-326`).

---

## 2. Structural weaknesses that block advanced features

1. **Page = one sealed blob.** Every stroke rewrites the whole page as JSON + deflate (`PageCodec.swift:5-19`), so save cost is O(page), not O(edit). That blocks live collaboration, incremental sync, per-stroke undo and large pages; a per-page append-only op log fixes all four.
2. **No commit boundary.** Page file + manifest are two writes ordered by convention, and recovery is a heuristic that cannot tell "crash before the manifest write" from "the user deleted this page" — the ambiguity behind H3 and H4.
3. **SyncKit is a stub.** `SyncKit.swift:1-5` prints "Hello, world"; no `NSFileCoordinator`, no ubiquity container, and `deviceID` — documented "for later sync bookkeeping" (`LibraryInfo.swift:6`) — is read by nothing. Sync is not partially built; it is absent, with no per-object version vectors to build on. `deletedStrokeIDs`/`deletedElementIDs` are a start, but no manifest- or notebook-level tombstones exist.
4. **Directory-as-database.** Every launch decodes every `notebook.json` (`LibraryStore.swift:653-669`) and every metadata edit rewrites a whole manifest (`:141-161`). Fine at hundreds of notebooks; far below a "10 000 notes" feature.
5. **History is copy-based and unlinked.** Snapshots are full page copies keyed by page id (`VersionHistoryStore.swift:9-29`), not tied to the edit that produced them, so restore is destructive-by-design and whole-notebook undo has nothing to build on.
6. **Two roots, no owner.** `Documents/Library` and `Documents/History` are created in different places (`AppModel.swift:125-128` vs `LibraryStore.swift:64-77`), so delete flows forget one (H2) and backup exclusion cannot be applied centrally.

## 3. Recommended foundation changes, in priority order

1. **Never lose ink.** `pendingPages: [UUID: Page]`; block navigation while unsaved; keep the error visible until resolved. (H1)
2. **Make the library survivable.** Independent loads for `folders.json` and `library.json`; degrade to defaults instead of empty or bricked. (C1, C2)
3. **One atomic writer.** Move `HistoryKit/AtomicFile` into NoteCore for pages, manifests, folders and assets. (H6)
4. **Manifest tombstones + one-shot reconciliation.** Persist `deletedPageIDs` and the reconciled `pageOrder` on open; let `reorderPages` accept new ids. (H3, H4)
5. **Deletion actually deletes.** `history.deleteNotebook` on purge/empty-trash, asset sweep on open, `addAsset` manifest guard, flush before delete. (H2, H5, M3)
6. **Real schema versioning.** Bump on shape change, `decodeIfPresent` for added fields, version-keyed migrations, and quarantine bad files instead of surfacing `corruptFile`. (M1, M2)
7. **Then sync, on the right substrate.** Per-notebook op log + tombstones first; iCloud/`NSFileCoordinator` or CloudKit second.
