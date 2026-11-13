# Local-first sync, backup, versioning and data durability

Scope: how NOTEAPP (iPad + Mac companion, personal use, no backend) should get notes from device to device, survive crashes and corruption, and let the user go back in time. Read against the current code: `Packages/NoteCore` (per-page `.page` files, tombstones), `Packages/HistoryKit` (local snapshots), `Packages/SyncKit` (empty), `NoteApp/AppModel.swift`, `research_notes/iPad note app feature plan/google_drive_sync.md`, `technical_architecture.md`.

Evidence tags below: **strong** = peer-reviewed or first-party normative docs; **moderate** = research prototype, vendor design docs, first-party API reference describing behaviour; **weak** = vendor marketing, secondary reporting.

---

## Key findings

1. **Local-first defines the local copy as primary, not a cache; sync is a background reconciliation.** Seven ideals: no spinners, not trapped on one device, network optional, collaboration, longevity, security/privacy, ownership. — **moderate** (position paper, Onward! 2019, plus the long-form essay) — [1]

2. **Longevity requires boring, openly specified formats, not a proprietary container.** "Some file formats (such as plain text, JPEG, and PDF) are so ubiquitous that they will probably be readable for centuries"; the US Library of Congress "recommends XML, JSON, or SQLite as archival formats for datasets". — **moderate** (essay quoting LoC practice) — [1]

3. **Dumb file sync produces conflicted copies that users cannot reconcile.** The essay shows a Dropbox "conflicted copy" and Evernote's "conflicting changes" notebook, noting "there is nothing to support the user in resolving the situation — not even a facility to compare the different versions of a note". — **moderate** (survey, not measured) — [1]

4. **A CRDT gives convergence without a server, with no lost updates, and merges on the client.** A JSON CRDT with formal semantics supports nested lists/maps, insert/delete/assign, "performs all merging client-side and does not depend on ordering guarantees from the network". — **strong** (IEEE TPDS, formal) — [21]

5. **However, automatic merge is necessary but not sufficient.** In the Upwelling prototype, merging concurrently edited words yields artefacts like "frostysoft"; the authors distinguish *syntactic* conflicts (detectable) from *semantic* conflicts (require human review) and deliberately invest in review UI instead of cleverer merge policy. — **moderate** (research prototype + interviews) — [2]

6. **Version history UX that works: always-on capture, group changes into reviewable units, linearise the history.** Upwelling records every edit without a "track changes" switch, lets a draft (= commit) group related edits, keeps a stack of merged layers, and rebases all other drafts onto the stack so conflicts surface *before* merge. — **moderate** — [2]

7. **Tombstone garbage collection is the direct enemy of "undo across sessions".** Yjs garbage-collects deleted content by default; `doc.gc = false` is required "to be able to restore old content". Yjs also warns that reusing a client ID across sessions "might get permanently corrupted". — **moderate** (official docs) — [19]

8. **CRDT merge engines are transport-agnostic: "if you can transfer bytes, you can sync documents".** Automerge keeps the whole change history locally, compresses it columnar, and exposes old versions/branches. — **weak–moderate** (vendor docs) — [17][18]

9. **Apple offers exactly three iCloud storage services — key-value, document storage, CloudKit — and only the first two remove explicit synchronisation.** "The core idea behind key-value and document storage is to eliminate explicit synchronization between devices… your app never interacts directly with iCloud servers." CloudKit instead makes record fetch/save the app's job. — **strong** (first-party guide) — [7]

10. **iCloud's own conflict model is per-file, and it is not a merge.** For cloud files "there is usually only one version of the file at any given time", but when two computers save at once, "one file is chosen as the current version and any other versions are tagged as being in conflict"; `isConflict` marks the losers, and conflicts "should be resolved as soon as possible". — **strong** — [3][4]

11. **Any access to iCloud/other-provider files must be coordinated, and presenters are a background liability.** `NSFileCoordinator` is per-operation; presenters are notified only for changes made *through* a coordinator; an active presenter while backgrounded can get the app killed "in order to prevent deadlock". — **strong** — [5][6]

12. **CloudKit, by contrast, hands you the three records needed for a real merge.** On `serverRecordChanged` the error carries the client record, the server record and the original; you must merge into the server record and re-save, and records are capped at 1 MB (assets excluded). — **strong** — [8][9]

13. **Peer-to-peer (Multipeer) is a foreground-only transport.** It needs `NSLocalNetworkUsageDescription` and Bonjour service declarations, and "if the app moves into the background, the framework stops advertising and browsing and disconnects any open sessions". — **strong** — [10]

14. **Atomic single-file writes are cheap and necessary but not sufficient for multi-file invariants.** `Data.write(.atomic)` writes an auxiliary file and replaces the original; yet a study of 11 real systems found 60 crash-consistency vulnerabilities because correctness depended on filesystem-specific persistence properties (fsync/rename ordering). — **strong** — [12][14]

15. **Silent corruption is common, correlated, and invisible without checksums.** 400,000+ checksum mismatches over 41 months in production fleets; nearline disks an order of magnitude worse; mismatches cluster in time and space on the same disk and across disks in a system. — **strong** (large-scale field study) — [15]

16. **PDF/A is the archival answer for appearance-only copies, and it is a family of ISO standards, not one format.** ISO 19005; PDF/A-3 allows arbitrary embedded files; PDF/A-4 (based on PDF 2.0) was still under development at the last LoC update. Purpose: preserve static visual appearance "independent of the tools and systems used for creating, storing or rendering". — **strong** — [16]

17. **Handoff carries an activity, not data.** `NSUserActivity` "encapsulates the state of an activity"; the system ships that activity object to the person's other devices so the app can replicate it. — **moderate** — [13]

---

## Recommended architecture (one concrete design)

**Name:** "NOTEAPP Sync = local-first, per-page files, merged as a stroke-set CRDT, transported by iCloud Drive, with an offline LAN path."

The design deliberately reuses what the codebase already has: one file per page (small conflict blast radius), SHA-256 content-addressed assets (already immutable and deduplicating — `LibraryStore.addAsset`), stroke/element UUIDs plus tombstone sets (`Page.deletedStrokeIDs`, `deletedElementIDs`), and `HistoryKit` local snapshots.

### Why this transport, not the alternatives

| Option | Verdict for NOTEAPP |
|---|---|
| **iCloud Drive ubiquity container** | **Chosen.** No OAuth, no quota logic, no server code; the OS transfers bytes and retries in the background [7]; per-file conflict versions exist and are readable/removable via `NSFileVersion` [3][4]; per-page files mean only edited pages move. Costs: Apple-only, per-file (not transactional), conflicts arrive as *whole page versions* that the app must merge. |
| CloudKit | Rejected for v1. Real merge inputs on conflict [9], but the store would have to become records under a 1 MB cap with assets as separate transfers [8], and the app owns all fetch/save scheduling — a rewrite of `LibraryStore` plus a second data model. Only worth it if live multi-user sharing appears. |
| Google Drive | Rejected. Existing research: no ETag/If-Match conditional write, no server push usable by a client-only app, OAuth verification overhead; whole market ships one-way backup only — see `google_drive_sync.md` §1, §5, §10. |
| Multipeer / LAN only | Not primary: disconnects when backgrounded [10], no third copy. Kept as the "no iCloud, same room" fast path (Phase 4). |

### Wire format on disk (inside the ubiquity container)

```
NOTEAPP/
  library.json                      # libraryID, schemaVersion, epoch  (last writer wins)
  devices/<deviceID>.json           # lastSeenAt, seenEpoch, appVersion
  folders.json                      # folder tree, LWW by (epoch, deviceID)
  notebooks/<nbID>/notebook.json    # title, pageOrder, scrollMode, epoch, deletedAt
  notebooks/<nbID>/pages/<pageID>.page
  notebooks/<nbID>/assets/<sha256>.<ext>
  trash/<nbID>.json                 # {deletedAt, byDevice, epoch}
  journal/<deviceID>/<seq>.jsonl    # optional append-only audit/repair log
```

Rules:

- **Page is the merge unit.** Two versions of `pages/<pageID>.page` merge as: union of strokes by `id`, union of elements by `id`, union of tombstones, *tombstone wins over insert*, and a deterministic order — keep the surviving list order, append unseen strokes sorted by `(createdAt, id)` (both fields already exist: `StrokeRecord.createdAt`, `PageElement.updatedAt`). This is exactly the set-CRDT the Drive research recommended as v2, and it needs no library.
- **Do not merge at per-stroke LWW.** The genuinely concurrent same-stroke cases are erase-vs-erase and erase-vs-move; a tombstone set handles both with no clocks [21][1].
- **Conflict source is `NSFileVersion`, not polling.** When iCloud reports conflict versions for a page (via presenter/coordinator callbacks or a metadata query [5][11]), load each, `merge`, write the merged page, then `removeOtherVersionsOfItem` so the conflict does not recur [3][4]. Nothing is ever deleted to "resolve" a conflict.
- **Deletes are files, not absence.** `trash/<nbID>.json` plus a monotonically increasing `epoch` acknowledged in `devices/<deviceID>.json`; an offline device that still holds the notebook cannot resurrect it after acknowledging the epoch.
- **Never write across files as one logical operation.** `savePage` currently writes the page then the manifest; a crash between them is recoverable because `loadNotebook` already reports orphans/missing page ids. Keep that, and add a page hash to the manifest so a half-uploaded page is detectable.
- **History stays local and never syncs** (`VersionHistoryStore` is a sibling of the library, not inside the container). That is right: history is per-device, cheap to regenerate, and syncing it would multiply the conflict surface.

### What merge cannot fix, and must be surfaced instead

Set-union merge is correct for ink (append-mostly), but wrong silently for *semantic* edits: a page reordered on both devices, a PDF background swapped on one and annotated on the other, a notebook retitled twice. Upwelling's lesson is to show the divergence rather than pretend it merged [2]. So every merge produces a **merge receipt** (device, time, strokes added, strokes tombstoned, elements moved) and the page shows a small "merged" badge with a diff preview and one-tap restore from `HistoryKit`.

### Phased steps

**Phase 0 — durability before sync (target: 2–3 days).**
`savePage` → hash + verify (decode what was written), append an intent record to `journal/`, fsync the file *and* the directory, then write the manifest. On load, a page that fails decode/hash is quarantined (moved to `cache/corrupt/`) and offered for restore from history instead of failing the notebook. This is the cheapest item with the largest downside removed [14][15].

**Phase 1 — backup you can restore (3–5 days).**
"Back up now" → one `.noteappbackup` archive: `library.json`, folders, every `notebook.json`, every `.page`, assets, a `manifest.sha256`, plus a PDF/A render per notebook. Restore imports into an empty library and verifies every hash. No merge, no cloud account. This alone satisfies Goodnotes/Notability-class backup (existing research §9) and is a prerequisite for trusting Phase 2.

**Phase 2 — one-way mirror into iCloud Drive (1 week).**
`SyncKit` gains a transport protocol + `ICloudDriveTransport` writing content-addressed page blobs and a `head.json` per notebook. Read-only on the second device: "this library is a mirror of iPad". Proves the container plumbing, `NSFileCoordinator` correctness and the device registry without any merge risk.

**Phase 3 — two-way merge between iPad and Mac (1–2 weeks).**
Turn on writes on both devices; add the page merge, conflict-version adoption, epoch-based deletes, and the merge receipt UI. Ship behind a switch; log every merge with inputs so a bad merge can be replayed offline. Expect this to be the phase where the bugs are.

**Phase 4 — LAN fast path and continuity (optional, 1 week).**
Multipeer/Bonjour "sync with nearby Mac" reusing Phase 3's merge core for the case where iCloud is unavailable or slow; `NSUserActivity` so a notebook open on iPad offers "continue on Mac" (it hands over the *position in a notebook*, not the bytes) [10][13].

**Phase 5 — archival and durability monitoring (ongoing).**
PDF/A-2b export for appearance, native JSON bundle for fidelity, nightly scrub of a sampled 1% of pages (hash compare), and a "data health" panel showing: last verified backup, last sync per device, number of unresolved conflicts, count of quarantined files. Local-first only pays off if the user can see it working [1][15][16].

---

## What this means for NOTEAPP

- **Already ahead of most apps:** per-page files, SHA-256 content-addressed assets, stroke UUIDs with tombstone sets, atomic single-file writes, local version history with a retention policy, and a manifest/page reconciliation that reports orphans instead of dropping them. That is the hard half of a sync-ready format.
- **The missing half is invariants, not features:** nothing verifies a written page, nothing detects bit rot, nothing records "which device last wrote this", and deletes have no cross-device meaning yet.
- **Do not adopt Automerge/Yjs for pages.** The document is append-mostly ink with existing UUIDs; a set-CRDT is a few hundred lines and keeps the file debuggable JSON. Automerge's costs (opaque binary, history growth, Rust build) buy live collaboration the app does not need [17][18][19].
- **Do not adopt CloudKit yet.** It is the better *server* story, but it is a data-model rewrite, and the personal-use case does not need record-level sharing [8][9].
- **The differentiator is the conflict UX, not the transport.** Nobody in the ink market does two-way sync over a third-party drive (existing research §9); if NOTEAPP shows a readable "these two versions merged, here is what changed, undo" receipt, it is ahead of Goodnotes' iCloud sync on the thing users actually fear.

---

## Feature ideas (table)

| # | Idea | Evidence | NEW/EXTENDS/DONE | Where in code | Effort | Impact |
|---|---|---|---|---|---|---|
| 1 | Verify-after-write: re-decode + SHA-256 each page after saving; record hash in `notebook.json` | [14][15] | EXTENDS | `LibraryStore.writePageFile`, `savePage` | S | 5 |
| 2 | Append-only save journal (`journal/<device>/<seq>.jsonl`) written before each mutation, replayed on open to repair torn multi-file states | [14] | NEW | `NoteCore/Store`, `LibraryStore` | M | 5 |
| 3 | Quarantine + guided restore: undecodable page moved aside, notebook opens, banner offers `HistoryKit` restore | [1][15] | EXTENDS | `LibraryStore.loadPage`, `VersionHistoryView` | S | 5 |
| 4 | "Back up now" archive: one `.noteappbackup` (JSON + assets + `manifest.sha256`) with verified restore into an empty library | [1][16] | NEW | `NoteApp/Export`, `LibraryStore` | M | 5 |
| 5 | PDF/A-2b archival export alongside the existing PDF/PNG export | [16] | EXTENDS | `NoteApp/Export/PDFExport.swift` | M | 3 |
| 6 | Native open-format bundle export/import (per-notebook JSON + assets + schema version) | [1] | NEW | `NoteCore/Format`, `LibraryStore` | M | 4 |
| 7 | `SyncKit`: transport protocol + content-addressed object store + `head.json` pointer per notebook | [1][17] | NEW | `Packages/SyncKit` (empty) | M | 5 |
| 8 | iCloud Drive (ubiquity container) transport using `NSFileCoordinator`/`NSFilePresenter`, presenters only while foreground | [5][6][7] | NEW | `SyncKit`, app entitlements | L | 5 |
| 9 | Per-page set-CRDT merge: union strokes/elements by UUID, tombstones win, order by `(createdAt,id)` | [21][1] | EXTENDS | `Page`, `PageOperations.swift` | L | 5 |
| 10 | Conflict-version adoption: read `NSFileVersion` conflict copies for a page, merge, write merged file, remove losers | [3][4] | NEW | `SyncKit` | M | 5 |
| 11 | Device registry + delete epochs so an offline device cannot resurrect a trashed notebook | [1] | EXTENDS | `LibraryStore.deleteNotebook/restoreNotebook`, `library.json` | M | 4 |
| 12 | Merge receipt + per-page diff preview ("3 strokes added, 1 erased on Mac") with one-tap undo | [2][1] | NEW | `SyncKit` + `VersionHistoryView` | M | 5 |
| 13 | Page timeline with scrub preview (Time Machine-like) instead of a plain list of timestamps | [2] | EXTENDS | `NoteApp/Notebook/VersionHistoryView.swift` | M | 4 |
| 14 | "Undo across sessions": persistent per-page undo backed by `HistoryKit` snapshots, not just restore | [2][19] | EXTENDS | `HistoryKit`, `NotebookSession` | M | 4 |
| 15 | Smarter autosnapshot: before any destructive op (clear page, delete items, PDF import replace) plus idle-interval, kept by `SnapshotPolicy` | [2] | EXTENDS | `SnapshotPolicy`, `NotebookSession` | S | 4 |
| 16 | Sync status surface: per-device last-sync, pending count, unresolved conflicts, quarantined files; never silent failure | [1][2] | NEW | `NoteApp/Library` settings | S | 4 |
| 17 | Data-health panel: last verified backup, sampled scrub result, "3 copies?" indicator | [15][1] | NEW | `NoteApp`, `HistoryKit` | M | 4 |
| 18 | LAN pairing sync (Multipeer + Bonjour) reusing the merge core, explicit "sync with nearby Mac" | [10] | NEW | `SyncKit` | L | 3 |
| 19 | Handoff "continue reading on Mac" via `NSUserActivity` (activity, not data) | [13] | NEW | `NoteApp/Notebook` | S | 2 |

---

## Sources

1. Kleppmann, M., Wiggins, A., van Hardenberg, P., McGranaghan, M. (2019). *Local-first software: you own your data, in spite of the cloud.* Onward! 2019, ACM SIGPLAN, pp. 154–178. DOI [10.1145/3359591.3359737](https://doi.org/10.1145/3359591.3359737). Full essay read at <https://www.inkandswitch.com/essay/local-first/> (the `/local-first/` URL redirects here); abstract/metadata cross-checked via Semantic Scholar.
2. McKelvey, K. R., Jenson, S., Wagner, E., Cook, B., Kleppmann, M. (2023). *Upwelling: Combining real-time collaboration with version control for writers.* Ink & Switch. <https://www.inkandswitch.com/upwelling/>
3. Apple. *NSFileVersion.* <https://developer.apple.com/documentation/foundation/nsfileversion>
4. Apple. *NSFileVersion.isConflict.* <https://developer.apple.com/documentation/foundation/nsfileversion/isconflict>
5. Apple. *NSFileCoordinator.* <https://developer.apple.com/documentation/foundation/nsfilecoordinator>
6. Apple. *NSFilePresenter.* <https://developer.apple.com/documentation/foundation/nsfilepresenter>
7. Apple. *iCloud Design Guide — About Incorporating iCloud into Your App* (archived). <https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/Introduction.html> and *iCloud Fundamentals (Key-Value and Document Storage)*, <https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html>
8. Apple. *CloudKit.* <https://developer.apple.com/documentation/cloudkit> and *CKRecord* (1 MB record limit, assets). <https://developer.apple.com/documentation/cloudkit/ckrecord>
9. Apple. *CKError.Code.serverRecordChanged.* <https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged>
10. Apple. *Multipeer Connectivity.* <https://developer.apple.com/documentation/multipeerconnectivity>
11. Apple. *NSMetadataQuery.* <https://developer.apple.com/documentation/foundation/nsmetadataquery>; *FileManager.url(forUbiquityContainerIdentifier:)*, <https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)>
12. Apple. *NSData.WritingOptions.atomic.* <https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic>
13. Apple. *NSUserActivity.* <https://developer.apple.com/documentation/foundation/nsuseractivity>
14. Pillai, T. S., Chidambaram, V., Alagappan, R., Al-Kiswany, S., Arpaci-Dusseau, A. C., Arpaci-Dusseau, R. H. (2014). *All File Systems Are Not Created Equal: On the Complexity of Crafting Crash-Consistent Applications.* OSDI '14, USENIX. <https://www.usenix.org/conference/osdi14/technical-sessions/presentation/pillai>
15. Bairavasundaram, L. N., Goodson, G. R., Schroeder, B., Arpaci-Dusseau, A. C., Arpaci-Dusseau, R. H. (2008). *An Analysis of Data Corruption in the Storage Stack.* FAST '08, USENIX. <https://www.usenix.org/legacy/events/fast08/tech/full_papers/bairavasundaram/bairavasundaram_html/index.html>
16. Library of Congress. *PDF/A Family, PDF for Long-term Preservation* (fdd000318, last significant update 2024-05-08). <https://www.loc.gov/preservation/digital/formats/fdd/fdd000318.shtml>
17. Automerge project. *Automerge — version control for your data* (product/engineering overview). <https://automerge.org/>
18. Automerge project. *Welcome to Automerge* (docs: offline, merge, history, network-agnostic). <https://automerge.org/docs/hello>
19. Yjs docs. *Y.Doc* (`doc.gc`, per-session `clientID`, splitting YDocs for history/undo). <https://docs.yjs.dev/api/y.doc>
20. Yjs docs. *Document Updates* (commutative/associative/idempotent updates, state vectors, "doesn't garbage-collect deleted content"). <https://docs.yjs.dev/api/document-updates>
21. Kleppmann, M., Beresford, A. R. (2017). *A Conflict-Free Replicated JSON Datatype.* IEEE Transactions on Parallel and Distributed Systems 28(10). DOI [10.1109/TPDS.2017.2697382](https://doi.org/10.1109/TPDS.2017.2697382). Abstract read via Semantic Scholar; open PDF: <https://arxiv.org/abs/1608.03960>
22. Internal: `research_notes/iPad note app feature plan/google_drive_sync.md` (Drive API limits, Joplin/remotely-save designs, Goodnotes/Notability one-way backup, background `URLSession` constraints). Read this session; used as secondary evidence, not re-verified.
23. Internal: `research_notes/iPad note app feature plan/technical_architecture.md` (iOS 27 PencilKit stroke IDs, Goodnotes' CRDT use).

---

## Unverified

- **iCloud Drive conflict-version behaviour in practice** (how often conflict copies appear, latency, whether a whole-directory rename is atomic). Apple documents the *existence* of conflict versions [3][4] but I found no source quantifying frequency or timing, and no source on whether a File Provider (Dropbox/Drive local folder) produces the same conflict versions.
- **Whether `NSFileVersion` conflict versions survive if the app never resolves them.** Apple says they "should be resolved as soon as possible so that the corresponding files can be removed from the cloud" [3]; the retention/deletion policy is not documented anywhere I read.
- **`NSMetadataQuery` as a change feed for a ubiquity container**: which keys (`NSMetadataUbiquitousItemDownloadingStatusKey`, `…IsUploadedKey`) reliably indicate "remote content changed" is not verified in this pass.
- **CloudKit private-database quota and asset limits** for a large ink library (existing research flagged this too) — not re-verified.
- **Multipeer peer-count limit** (commonly cited as 8) — no first-party number read this session.
- **Automerge document growth** for a page with ~10k strokes, and whether automerge-swift compacts automatically — no benchmark read; treat any size claim as unsourced.
- **Dynamo-style version vectors**: I did not read the Dynamo paper this session (Semantic Scholar returned no abstract), so causality-tracking beyond `(timestamp, deviceID)` is asserted only as a design option, not as evidenced practice.
- **Whether iCloud device backups already cover the `Documents/Library` tree** well enough to count as a second copy — Apple's backup documentation was not opened; do not claim coverage either way.

---

## Top 3 to build first

1. **Verify-after-write + save journal + quarantine/restore (ideas 1–3).** Everything else multiplies the number of ways a page can be lost; this is two to three days of work, it removes the worst failure mode (a page that silently fails to decode months later), and it is the precondition for trusting any sync engine. It also uses `HistoryKit`, which already exists and already prunes sensibly.
2. **"Back up now" archive with verified restore (idea 4), then PDF/A as a second output (idea 5).** A backup you have never restored is a rumour: the value is in the restore path and the hash manifest, not the zip. This gets NOTEAPP to the market-standard backup bar (one-way, native + PDF) in under a week, with zero cloud dependencies and zero conflict risk.
3. **`SyncKit` object store + iCloud Drive one-way mirror (ideas 7–8), then page merge and conflict adoption (9–10).** The format is already sync-shaped — per-page files, content-addressed assets, UUIDs, tombstones — so the work is plumbing and merge, not modelling. Splitting it one-way-then-two-way means the first shippable version cannot corrupt notes, and the merge phase then has a known-good transport and a known-good backup to fall back on.
