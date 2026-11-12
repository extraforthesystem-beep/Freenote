# Building reliable two-way Google Drive sync for a native SwiftUI iPad + macOS handwritten-notes app

Scope note: all Google documentation below was fetched on 2026-11-12. Google's Drive API quota page carries a **May 1, 2026** change notice, so numbers there apply to Cloud projects created on/after that date.

---

## 1. Drive API v3 primitives relevant to sync (uploads, downloads, changes feed, notifications, metadata, preconditions)

### Takeaway
Drive v3 gives you everything needed for a *file-granular* sync engine (resumable upload, byte-range download, a cursor-based change feed, per-file monotonic `version`, MD5/SHA checksums, private `appProperties`), but it gives you **no transactions, no documented ETag/If-Match conditional write, and no usable server push for a client-only app**. Atomicity and conflict safety must be designed on top.

### Cited Findings

**Uploads**
- Three upload types: `uploadType=media` (simple, ≤5 MB, no metadata), `uploadType=multipart` (≤5 MB, metadata + data in one request), `uploadType=resumable` (>5 MB, or "when there's a high chance of network interruption, such as when creating a file from a mobile app") — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- Resumable session: `POST .../upload/drive/v3/files?uploadType=resumable` returns a `Location` session URI; the files resource is returned only after the data upload completes; "A resumable session URI expires after one week" — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- Chunked resumable uploads must use chunk sizes in multiples of 256 KB (final chunk excepted); `308 Resume Incomplete` = keep going, `404` on status query = session expired, restart from zero — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- For **any 4xx (including 403) during a resumable upload, Google says restart the upload** with a new session URI; for 5xx, resume; for 403 rate-limit, retry; sessions also expire after one week of inactivity — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- Max upload size via `files.update`: **5,120 GB** — [Drive: files.update reference](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)
- Pre-generated file IDs make uploads idempotent: "You can safely retry uploads with pre-generated IDs if there's an indeterminate server error or timeout. If the file action is successful, subsequent retries return a `409 Conflict` … and duplicate files aren't created." Pre-generated IDs don't work for Workspace-type conversions — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads). **This is the closest thing Drive offers to an atomic create.**

**Downloads**
- `files.get` with `alt=media` downloads blob content; `revisions.get` with `alt=media` downloads an older revision — [Drive: Download and export files](https://developers.google.com/workspace/drive/api/guides/manage-downloads)
- Partial download is supported via the HTTP `Range` header, e.g. `Range: bytes=500-999`; **not** supported for Workspace-document export — [Drive: Download and export files](https://developers.google.com/workspace/drive/api/guides/manage-downloads)
- Older blob revisions can only be downloaded if they are marked "Keep Forever" (`keepRevisionForever`, capped at 200 pinned revisions per file) — [Drive: Download and export files](https://developers.google.com/workspace/drive/api/guides/manage-downloads); [Drive: files.update](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)
- Workspace-document export is capped at 10 MB — [Drive: Download and export files](https://developers.google.com/workspace/drive/api/guides/manage-downloads)

**Changes feed (the incremental-sync cursor)**
- `changes.getStartPageToken` returns a token for "the current state of the account"; store it and pass it as the initial `pageToken` to `changes.list` — [Drive: Track changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)
- `changes.list` returns entries in chronological order; if the response has `nextPageToken`, keep paging; otherwise store `newStartPageToken` for the next poll — [Drive: Track changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)
- `includeRemoved` and `restrictToMyDrive` control whether removed/shared items appear — [Drive: Track changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)
- `changes.watch` exists but "Notifications don't contain details about the changes. Instead, they indicate that new changes are available," so you still poll `changes.list` — [Drive: Track changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)

**Push notifications — why a client-only app cannot use them**
- Push requires "an HTTPS server that handles the API notification messages", and the `address` "must use HTTPS" with a valid, non-self-signed certificate and matching hostname — [Drive: Push notifications](https://developers.google.com/workspace/drive/api/guides/push)
- Channel max lifetime: **86,400 s (1 day) for `files`**, **604,800 s (1 week) for `changes`**; default 3,600 s if unspecified; "there's no automatic way to renew a notification channel" — you must re-`watch` with a new channel id — [Drive: Push notifications](https://developers.google.com/workspace/drive/api/guides/push)
- Notification bodies are empty (`Content-Length: 0`); headers only (`X-Goog-Resource-State`: `sync|add|remove|update|trash|untrash|change`) — [Drive: Push notifications](https://developers.google.com/workspace/drive/api/guides/push)
- `changes.watch` and `files.watch` **do** consume quota; delivered notifications do not — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)

**Metadata you can build sync on**
- `md5Checksum` — "The MD5 checksum for the content of the file. This is only applicable to files with binary content" (i.e. not Workspace docs) — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- `sha1Checksum`, `sha256Checksum` also exist, populated "for files with content stored in Google Drive" — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- `headRevisionId` — "The ID of the file's head revision. This is currently only available for files with binary content" — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- `version` — "A monotonically increasing version number for the file. This reflects every change made to the file on the server, even those not visible to the user." **This is your best cheap "did the remote change?" signal.** — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- `modifiedTime` (settable; also updates `modifiedByMeTime`), `createdTime`, `size`, `quotaBytesUsed` — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- `appProperties` — "arbitrary key-value pairs which are private to the requesting app… can only be retrieved using an authenticated request"; null values clear an entry on update/copy — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files). `properties` is the world-visible equivalent — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- Files may have **exactly one parent**; multiple parents are no longer supported — use shortcuts — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- `capabilities.canDownload`, `canEdit`, `canModifyContent`, `canReadRevisions` should be checked before assuming write access — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)

**Revisions / preconditions**
- `files.update` has **no documented `If-Match`/ETag parameter**; its query parameters are `addParents`, `removeParents`, `keepRevisionForever`, `ocrLanguage`, `supportsAllDrives`, `uploadType`, `useContentAsIndexableText`, `includePermissionsForView`, `includeLabels` — [Drive: files.update reference](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)
- The File resource schema has **no `etag` field** (unlike Drive v2 and most REST APIs); it exposes `version` and `headRevisionId` instead — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- Revision history is deletion-prone: only "Keep Forever" revisions are individually downloadable, max 200 per file — [Drive: files.update](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)

### Inferences
- **There is no compare-and-swap on Drive v3 files.** A read-`version`-then-`PATCH` sequence has a TOCTOU window. Any design that overwrites a shared file must therefore either (a) accept last-writer-wins at file granularity, (b) never overwrite (write new immutable objects, then publish a pointer), or (c) use a lock file plus clock skew tolerance (Joplin's approach, §5).
- `version` + `md5Checksum` + `headRevisionId` together are sufficient to detect *that* a remote file changed and to detect a corrupt/incomplete upload (compare MD5 after download), which re covers the two most common silent-corruption failure modes.
- Because push needs a public HTTPS endpoint, a no-server app must poll. Polling cost is low: `changes.list` is 100 quota units against 325,000 units/min/user (see §3), i.e. thousands of polls per minute are theoretically affordable; the real limiter is battery and the background-execution budget, not quota.
- Using pre-generated IDs for every object create converts "did my upload land?" from an ambiguous retry into a 409-vs-200 answer. This is the cheapest correctness win in the whole design.

### Gaps
- Whether Drive v3 silently honours `If-Match` despite not documenting it: **unconfirmed**. The reference lists no such parameter and the resource has no ETag field, but I found no explicit statement that preconditions are rejected.
- How long `changes.list` page tokens remain valid before a client must re-baseline with `getStartPageToken`: **unconfirmed** (not stated on the changes guide I read).
- Whether the `changes` feed, when authorised with `drive.file`, reports only app-visible files: **unconfirmed by documentation**; strongly implied by scope semantics but not stated.

---

## 2. OAuth scopes, verification, CASA, and what a small/personal app can actually ship

### Takeaway
`drive.file` is **non-sensitive**, gives full Drive API surface over files your app creates or the user picks, and needs only basic (brand) verification — it is the correct choice for a notes app that stores user-visible notebooks in the user's own Drive. `drive.appdata` is also non-sensitive but hides files from the user and from the Drive UI. Full `https://www.googleapis.com/auth/drive` is **restricted** and drags in restricted-scope verification plus an annual third-party security assessment. For a personal build, Testing mode works but **every authorisation and refresh token dies after 7 days** and you are capped at 100 test users.

### Cited Findings

**Scope classification (Drive-specific page — the authoritative table)**
- Non-sensitive: `drive.appdata` / `drive.appfolder`, `drive.install`, `drive.file` — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- Sensitive: `drive.apps.readonly` — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- Restricted: `drive`, `drive.readonly`, `drive.activity`, `drive.activity.readonly`, `drive.meet.readonly`, `drive.metadata`, `drive.metadata.readonly`, `drive.scripts` — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- Definition: non-sensitive scopes "only require basic OAuth App Verification"; sensitive need "additional OAuth App Verification"; restricted need restricted-scope verification, and "If you store restricted scope data on servers (or transmit), then you must go through a security assessment" — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- "Whenever possible, use non-sensitive scopes as they grant per-file access and narrow access to specific features" — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)

**What `drive.file` actually means**
- "Create new Drive files, or modify existing files, that you open with an app or that the user shares with an app while using the Google Picker API or the app's file picker." — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- "The `drive.file` scope works with all Drive API REST Resources which means you can use it the same way you use broader OAuth scopes." — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- Google explicitly recommends migrating off `drive` onto `drive.file`, and states "Since `drive.file` is non-sensitive, it allows for a more streamlined verification process" — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- Consequence: `drive.file` cannot enumerate or read arbitrary pre-existing files in the user's Drive — only app-created/picker-granted ones (see Gaps).

**appDataFolder**
- `drive.appdata` is a "non-sensitive scope"; the folder is "automatically created when you attempt to create a file in it"; "only accessible by your app and its contents are hidden from the user and from other Google Drive apps" — [Drive: Application data folder](https://developers.google.com/workspace/drive/api/guides/appdata)
- "The application data folder is deleted when a user uninstalls your app from their My Drive. Users can also delete your app's data folder manually." — [Drive: Application data folder](https://developers.google.com/workspace/drive/api/guides/appdata)
- Constraints: cannot share, cannot move between spaces, **cannot trash** files there — [Drive: Application data folder](https://developers.google.com/workspace/drive/api/guides/appdata)
- List with `spaces=appDataFolder`; create with `parents: ["appDataFolder"]` — [Drive: Application data folder](https://developers.google.com/workspace/drive/api/guides/appdata)

**Verification tiers & exemptions**
- Restricted-scope route requires: permitted application type, brand verification first ("typically takes 2-3 business days"), then data-access review; "the restricted scopes verification process can potentially take several weeks to complete" — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Permitted app types for Drive restricted scopes explicitly include "**Backup and sync**" and "**Productivity and education** … task management, **note-taking**, workgroup communications, and classroom collaboration apps" — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth). A notes app is therefore *eligible* for `drive`, if you want to pay the compliance cost.
- Security assessment: "Every app that requests access to Google users' restricted data and **has the ability to access data from or through a third-party server** must go through a security assessment"; framework is CASA, run by the App Defense Alliance; re-assessment "at least every 12 months after your assessor's Letter of Assessment (LOA) approval date"; adding a new restricted scope may trigger reassessment — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- CASA is "a risk-based, multi-tier assessment approach"; built on OWASP ASVS; there are Assurance Levels (tiering) and a list of Authorized Assessors — [App Defense Alliance: CASA](https://appdefensealliance.dev/casa)
- **Personal-use exemption**: "if you are the only user of your app or if your app is used by only a few users, all of whom are known personally to you… you don't need to submit it for review" — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Verification submission requires a public homepage on a verified domain, a privacy policy on the same domain linked from the consent screen, and (for sensitive/restricted) a demo video on YouTube (unlisted) showing the consent flow and each scope's feature in use in English — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification); [Google Cloud: Manage OAuth app branding](https://support.google.com/cloud/answer/10311615)

**Testing-mode limits (the trap for a personal build)**
- Testing status: "limited to up to **100 test users**"; "Authorizations by a test user will **expire seven days** from the time of consent. If your OAuth client requests an `offline` access type and receives a refresh token, **that token will also expire**." — [Google Cloud: Manage app audience](https://support.google.com/cloud/answer/15549945)
- Sole exception: apps requesting only `userinfo.email`/`userinfo.profile`/`openid` — not applicable once you add any Drive scope — [Google Cloud: Manage app audience](https://support.google.com/cloud/answer/15549945)
- OAuth user cap: "100 new users in total, after the app presents the unverified app screen"; "The user cap applies over the entire lifetime of the project, and it cannot be reset or changed." — [Google Cloud: Manage app audience](https://support.google.com/cloud/answer/15549945)
- Corroborating: Testing "is only available to users you add to the list of test users… a user cap is in effect, and the refresh token lifetime is limited" — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Leaving Testing requires clicking **Publish app**; before publishing sensitive/restricted scopes you get the "unverified app" warning — [Google Cloud: Manage app audience](https://support.google.com/cloud/answer/15549945)
- Brand verification results "are valid for 7 days. If you don't publish within that timeframe… you will have to run the brand verification again." — [Google Cloud: Manage OAuth app branding](https://support.google.com/cloud/answer/10311615)

### Inferences
- **Recommended scope for this app: `https://www.googleapis.com/auth/drive.file`**, with a single app-created folder (e.g. `My Drive/<AppName>/`) as the sync root. It keeps files user-visible and user-manageable (the stated product requirement), stays non-sensitive, and avoids CASA entirely.
- **Do not use Testing mode for the personal build.** The 7-day refresh-token cliff makes long-lived background sync impossible: every week the app would silently go read-only until the user re-consents. Set publishing status to **In production** while requesting only `drive.file` — the "unverified app" warning is shown but the 7-day expiry and 100-user cap are not triggered for approved/non-sensitive scope usage (see Gaps for the one nuance: Google's wording ties the cap to *unapproved sensitive or restricted* scopes).
- `drive.appdata` is a reasonable **secondary** location for machine-only state (device registry, last-seen change tokens, lock files), since it's hidden and auto-deleted on uninstall. Cost: a second non-sensitive scope on the consent screen, and hidden data is unrecoverable-by-user if the app's state corrupts. A single `drive.file` scope with everything inside one visible folder is simpler and more debuggable for v1.
- Adding `drive` (restricted) purely to "see the user's existing Notes folder" buys very little for a large cost: weeks of review, annual CASA, a public privacy policy and demo video. Not justified unless cross-app interop with pre-existing folders becomes a hard requirement.

### Gaps
- **CASA cost**: no price is published on the CASA site I read; cost is quoted per authorised assessor and per tier. **Unconfirmed / no public number.** Budget guidance must come from an assessor quote.
- Exact interaction between "In production" + non-sensitive-only scopes and the 100-user cap: Google's text says the cap applies to "unapproved sensitive or restricted scopes" and that apps presenting the unverified screen get 100 new users. Whether a production app with only `drive.file` is cap-free in practice: **unconfirmed** — verify in Cloud Console's Audience page before shipping.
- Whether `drive.file` can list the *contents of a folder the app created but the user later renamed/moved*: not documented; expected yes (file IDs persist, `parents` changes visible via changes feed) but **unconfirmed**.

---

## 3. Quotas, rate limits, upload caps, backoff, storage

### Takeaway
Per-project and per-user quotas are enormous relative to a notes app (1,000,000 units/min/project; 325,000 units/min/user), and the method costs are small (5–200 units). The biting limits are the **750 GB/day per-user upload cap**, **5 TB per-file max**, and **hard 403/429 responses from backend rate limiting that ignore your quota headroom** — so exponential backoff with jitter is mandatory, not optional.

### Cited Findings
- Quotas: **1,000,000 quota units/min/project**, **325,000 quota units/min/user/project**, **1 TB/day/project egress** — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- A separate daily billing threshold of **400,000,000 quota units/day/project** exists; "You cannot request an increase on this daily threshold limit." Usage under it is unbilled; charges "planned to incur… later in 2026" with ≥90 days' notice — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- Method costs: read 5 units (`files.get` without media, `changes.get`, `about.get`); **list 100 units** (`files.list`, `changes.list`, `changes.watch`, `revisions.list`); edit 50 units (`files.create`, `files.update`, `files.patch`, `files.delete`, `files.copy`); **download 200 units** (`files.get` with `alt=media`, `files.export`); `getStartPageToken` 5 units — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- "Google Workspace users can only upload **750 GB per day** between My Drive and all shared drives; this limit also applies to copies." Reaching it (or uploading a single file >750 GB) blocks further uploads for 24 hours — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- "The maximum file size that users can upload is **5 TB**… The maximum file size that users can copy is 750 GB." — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- Per-account item cap: **500,000,000 items created by an account** (`activeItemCreationLimitExceeded`) — [Drive: Resolve errors](https://developers.google.com/workspace/drive/api/guides/handle-errors)
- Folder caps: **500,000 items directly in one folder**; **100 levels** of nested folders — [Drive: Resolve errors](https://developers.google.com/workspace/drive/api/guides/handle-errors)
- 403 `rateLimitExceeded`/`userRateLimitExceeded` and 429 `rateLimitExceeded` are distinct; "Additional rate limit checks on the Drive backend might also generate a `429`" independent of your quota — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits); [Drive: Resolve errors](https://developers.google.com/workspace/drive/api/guides/handle-errors)
- Recommended backoff: truncated exponential backoff, wait `min((2^n) + random_ms, maximum_backoff)` where `random_ms ≤ 1000` and `maximum_backoff` "is typically 32 or 64 seconds"; recalculate the random component each retry; cap total retries — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- 403 `storageQuotaExceeded` = the *user's* Drive is full (a real, user-facing condition; do not retry) — [Drive: Resolve errors](https://developers.google.com/workspace/drive/api/guides/handle-errors)
- 403 `domainPolicy` = Workspace admin disabled Drive apps; `403 appNotAuthorizedToFile` = app not on the file ACL (fix by Picker/`isAppAuthorized` check) — [Drive: Resolve errors](https://developers.google.com/workspace/drive/api/guides/handle-errors)
- Quota increases are requestable but "Applying for an adjusted quota doesn't guarantee approval" — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)

### Inferences
- A notebook open + edit session costs roughly: 1 metadata read (5) + 1 download (200) + 1 update (50) ≈ 255 units. At 325,000 units/min/user that's >1,000 such cycles per minute — quota is **not** the scaling constraint for a single-user or small-audience app; latency, battery and background time are.
- A "sync every page on every edit" design (hundreds of small files) turns one logical save into hundreds of 50-unit edits and hundreds of 5-unit reads. Still affordable quota-wise, but each request is a round trip: **batch and coalesce**, and prefer per-notebook journals over per-stroke files.
- The 750 GB/day cap is irrelevant for ink but *not* irrelevant once you sync audio + imported PDFs. A 2-hour lecture recording at ~1 MB/min is ~120 MB; a semester of daily recording is tens of GB. Warn users, and never re-upload unchanged large blobs (content-addressing solves this, §5).
- Because 403 can mean five different things, error handling must branch on the JSON `reason`, not the status code. Treat `storageQuotaExceeded`, `insufficientFilePermissions`, `domainPolicy`, `appNotAuthorizedToFile` as terminal-and-explain; only `rateLimitExceeded`/`userRateLimitExceeded`/429/5xx get retried.

### Gaps
- Whether *consumer* (non-Workspace) accounts share the 750 GB/day figure: Google's wording says "Google Workspace users". Consumer behaviour is **unconfirmed**; assume the same order of magnitude.
- Whether per-user quota is enforced per OAuth client or per Google account across all clients: **unconfirmed** (documented as "per user per project").

---

## 4. SDKs on Apple platforms (Sign-In, GTLR, AppAuth, raw URLSession)

### Takeaway
The supported path is **GoogleSignIn-iOS via Swift Package Manager** for auth plus **GTLR (google-api-objectivec-client-for-rest)** for the Drive API — both are first-party, both support iOS **and macOS**, and Sign-In ships a SwiftUI button product. But GTLR is Objective-C, sparsely maintained, and adds a large dependency; **calling the Drive v3 REST API directly with URLSession is entirely viable and probably preferable** for a sync engine that needs fine control over resumable ranges, retries and background sessions.

### Cited Findings
- Google Sign-In: SPM repository `https://github.com/google/GoogleSignIn-iOS`, **version 9.0.0**, product `GoogleSignIn`, plus `GoogleSignInSwift` "for the 'Sign in with Google' button" when using SwiftUI — [Google: Sign-In for iOS/macOS start](https://developers.google.com/identity/sign-in/ios/start)
- CocoaPods alternative: `pod 'GoogleSignIn'` and `pod 'GoogleSignInSwiftSupport'` — [Google: Sign-In for iOS/macOS start](https://developers.google.com/identity/sign-in/ios/start)
- "For iOS and **macOS** apps the OAuth client ID application type must be configured as **iOS**" — i.e. one iOS-type client serves both platforms — [Google: Sign-In for iOS/macOS start](https://developers.google.com/identity/sign-in/ios/start)
- Config requires `GIDClientID` and a reversed-client-ID URL scheme in Info.plist; backend auth is optional (`GIDServerClientID`), and is *not needed* for a no-server app — [Google: Sign-In for iOS/macOS start](https://developers.google.com/identity/sign-in/ios/start)
- macOS Keychain caveat: the app must be Apple-signed, and "For your macOS app to successfully store credentials using Keychain, you will also need to add `$(AppIdentifierPrefix)$(CFBundleIdentifier)` to its keychain access group." — [Google: Sign-In for iOS/macOS start](https://developers.google.com/identity/sign-in/ios/start)
- GTLR: "Written by Google, this library is a flexible and efficient Objective-C framework for accessing JSON APIs… the recommended library for accessing JSON-based Google APIs for **iOS, macOS, tvOS, and watchOS** applications." Layout includes `Sources/GeneratedServices` and `Package.swift` (SPM) plus a podspec — [google-api-objectivec-client-for-rest](https://github.com/google/google-api-objectivec-client-for-rest)
- GTLR is built on `GTM Session Fetcher` and needs separate auth wiring — [google-api-objectivec-client-for-rest](https://github.com/google/google-api-objectivec-client-for-rest)
- Repo health signal: 858 stars, 361 forks, 680 commits, **1 open issue, 1 open PR** at time of reading — [google-api-objectivec-client-for-rest](https://github.com/google/google-api-objectivec-client-for-rest)
- Drive's own docs treat raw HTTP as first-class: every guide gives a `curl` form (`POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable`, `Range: bytes=500-999`, etc.) — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads); [Drive: Download and export files](https://developers.google.com/workspace/drive/api/guides/manage-downloads)

### Inferences
- **Recommended stack: GoogleSignIn (SPM) for OAuth + hand-written `URLSession` client for Drive v3.** Rationale: the sync engine needs explicit control of `Content-Range` chunking, `308` handling, `Range` downloads, per-`reason` retry policy and background-session task identity — all of which fight a generated Obj-C wrapper. The Drive surface you need is ~8 endpoints (`files.create/get/update/delete/list`, `changes.getStartPageToken/list`, `about.get`).
- GTLR is not dead but is effectively in maintenance (1 open issue), and it is Objective-C: bridging headers, `GTLRDriveService`, and no async/await. For a SwiftUI-first codebase that is friction with no payoff.
- AppAuth-iOS is a credible alternative to GoogleSignIn (plain OAuth + PKCE), and avoids Google's UI SDK; it is not required, and I did not verify its current release status — see Gaps.
- Mac Catalyst vs native macOS: Sign-In explicitly covers macOS, and the Drive REST API is platform-agnostic, so nothing in this stack forces Catalyst.

### Gaps
- **AppAuth-iOS** current version, SPM support, and macOS support: **not verified** in this pass.
- Whether GTLR's generated Drive service currently covers `files.download` (the newer LRO download) and Drive v3 `includeLabels`: **unconfirmed**.
- GoogleSignIn 9.0.0's minimum iOS/macOS deployment targets: **not read**.

---

## 5. Sync architecture over a "dumb" cloud drive

### Takeaway
The proven pattern across Joplin, remotely-save and similar tools is: **local DB is the source of truth; the cloud holds immutable, per-item files; a per-item sync-state table records what was uploaded and when; conflicts are resolved by comparing per-item timestamps and writing a *new* "conflicted copy" rather than overwriting.** Drive has no transactions, so atomicity is achieved by (a) immutable objects + a separately-published pointer, or (b) single-file-per-item last-writer-wins with conflict copies. Joplin also demonstrates that a **lock file protocol** is needed to serialise schema upgrades, not to serialise sync.

### Cited Findings

**Joplin's documented design**
- "The Joplin applications are offline first — it means that data is saved locally on the device… each device uploads its notes, notebooks, tags, etc. to the server, and also downloads any notes they do not have, or any recent changes." — [Joplin: Synchronisation](https://joplinapp.org/help/dev/spec/sync/)
- Upload is eager: "Whenever the user makes a change to an item, it is uploaded to the sync target within a few seconds. Uploading items as soon as possible helps limit conflicts." Downloads happen by polling "every few minutes" — [Joplin: Synchronisation](https://joplinapp.org/help/dev/spec/sync/)
- The sync target is abstracted behind a `FileApi` with generic create/update/delete/list file operations; the same `Synchronizer` drives WebDAV, Nextcloud, S3, Joplin Server, Dropbox, OneDrive — [Joplin: Synchronisation](https://joplinapp.org/help/dev/spec/sync/)
- Per-item state lives in a `sync_items` table with `sync_time` ("tells when the item was last synced… used to decide what needs to be synced or not"), plus `sync_disabled` "used in the rare case an item cannot be synced at all — for example if blocked by Dropbox for being 'restricted content'… or is over the limit"; rows are scoped by `sync_target` — [Joplin: Synchronisation](https://joplinapp.org/help/dev/spec/sync/)
- Target-level settings live in a single `info.json` with `{value, updatedTime}` pairs, and "This is used to resolve conflicts when two clients perform the same action on the same property. In this case heuristics decide which value should be kept." — [Joplin: Synchronisation](https://joplinapp.org/help/dev/spec/sync/)
- Locks: two types — **SYNC** (multiple allowed concurrently) and **EXCLUSIVE** (only one, used when upgrading the target). Clients must refresh a lock every X seconds with timeout Y (X < Y); a lock older than Y is ignored; "A client that tries to refresh a lock that has expired should fail"; if your lock expired you must **not** re-acquire — cancel and restart, because another client may have upgraded the target or synced meanwhile — [Joplin: Synchronisation locks](https://joplinapp.org/help/dev/spec/sync_lock/)
- Lock file naming encodes all state in the filename: `<lockType>_<clientType>_<clientId>.json`; "Its content is not used in the lock algorithm since all data can be derived from the filename and file timestamp"; if multiple EXCLUSIVE locks exist, "only the oldest lock amongst the active ones is the valid one. If there are two locks with the same timestamp, the one with lowest client ID is the valid one." — [Joplin: Synchronisation locks](https://joplinapp.org/help/dev/spec/sync_lock/)
- Target schema versioning: if the target version is lower than the client's, sync is refused and the user is prompted to upgrade (`SHOULD_UPGRADE` → `MUST_UPGRADE`, upgrade under EXCLUSIVE lock, then restart) — [Joplin: Synchronisation locks](https://joplinapp.org/help/dev/spec/sync_lock/)

**Obsidian / remotely-save (Drive is a paid tier; the algorithm is published)**
- Supports Google Drive as a **PRO feature**, alongside S3/Dropbox/OneDrive/WebDAV/Box/pCloud — [remotely-save](https://github.com/remotely-save/remotely-save)
- Free tier: "Basic Conflict Detection And Handling"; PRO adds "Advanced Smart Conflict Handling" — "merge small markdown files, or duplicate large markdown files or any-size non-markdown files" — [remotely-save](https://github.com/remotely-save/remotely-save)
- **Auto sync only runs while the host app is open**: "It's technically impossible to auto sync while Obsidian is in background, because the plugin just works in the browser environment provided by Obsidian." — [remotely-save](https://github.com/remotely-save/remotely-save)
- Auto-sync and sync-on-save "would **fail silently**" on error — an explicit anti-pattern to avoid — [remotely-save](https://github.com/remotely-save/remotely-save)
- Mobile perf caveat: "Obsidian API on Mobile has performance issues syncing large files (>= 50 MB)" → skip-large-files setting — [remotely-save](https://github.com/remotely-save/remotely-save)
- Optional E2EE using openssl/rclone crypt format before upload, "but please be aware that the **vault name itself is not encrypted**" — [remotely-save](https://github.com/remotely-save/remotely-save)

**Drive-specific structural facts that shape the design**
- Files have exactly one parent; folders support 500k children and 100 levels — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files); [Drive: Resolve errors](https://developers.google.com/workspace/drive/api/guides/handle-errors)
- Pre-generated IDs give idempotent creates (409 on replay) — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- `appProperties` are private per-app key/value metadata attachable to any file — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)

### Inferences — a concrete design that fits Drive

**Source of truth:** local SQLite (or SwiftData) with tables `objects`, `sync_state`, `devices`, `change_log`. Drive is a replication target, never the primary read path.

**Granularity (recommended):**
```
My Drive/<App>/
  manifest.json                 # schema version, notebook index, epoch
  devices/<deviceID>.json       # heartbeat, last change token, app version
  notebooks/<notebookID>/
      meta.json                 # title, created, cover, page order (ordered list)
      pages/<pageID>.ink        # binary ink doc for one page
      pages/<pageID>.png        # optional thumbnail
      assets/<sha256>.pdf|.m4a|.png   # content-addressed, immutable
  trash/<notebookID>.tombstone.json
```
Rationale: per-page files bound the blast radius of a conflict to a single page (matching how users perceive "the same page edited on two devices"); content-addressed assets mean an imported PDF or a 40-minute recording is uploaded exactly once per device-lifetime and never re-sent on rename.

**Change detection:** store per-file `{fileID, version, md5Checksum, modifiedTime}` in `sync_state`. On sync: run `changes.list` from the stored page token to learn *which* fileIDs changed, then `files.get(fields=id,version,md5Checksum,modifiedTime,size,trashed,appProperties)` for those only. `version` inequality is the cheap "changed" test; `md5Checksum` inequality after download is the integrity test. Avoid `files.list` recursive walks (100 units each, and 500k-children limits make them fragile).

**Upload atomicity without transactions — two workable options:**
1. *Immutable + pointer* (strongest): never PATCH a content file. Write `pages/<pageID>.<contentHash>.ink` (new file, pre-generated ID → idempotent), then PATCH `meta.json` (`version` compare + retry) to point at the new content hash. A crashed upload leaves an orphan blob, never a torn document. Requires the reader to resolve pointers and a GC pass for orphans.
2. *Single-file LWW + conflict copy* (simplest, Joplin-like): PATCH `pages/<pageID>.ink` directly; on a detected concurrent change, download the remote, rename it `pages/<pageID>.conflict-<device>-<timestamp>.ink`, upload yours, and surface the conflict in the UI. No data loss, but the user must reconcile.

**Tombstones:** deletion must be a file, not an absence — write `trash/<id>.tombstone.json` with `{deletedAt, deletedBy, lastKnownVersion}` and only hard-delete after all known devices have acknowledged (each device writes `devices/<id>.json` with a monotonically increasing `seenEpoch`). Otherwise a device that was offline during the delete will happily re-upload the notebook and resurrect it.

**Locks:** adopt Joplin's design but *only* for the migration/schema path. Ordinary sync should be lock-free (multi-writer textbook: immutable objects + last-writer-wins pointer). If you do add a sync lock, follow the "expired lock means abort, not re-acquire" rule — that detail is what prevents the classic two-devices-both-think-they-hold-the-lock corruption.

**Operation log (optional but cheap):** an append-only `notebooks/<id>/oplog/<deviceID>/<seq>.jsonl` gives you (a) an audit trail, (b) a replay path if a page file is corrupted, (c) a migration path to a real CRDT later, since ops can be replayed into an Automerge doc. Cost: unbounded growth; needs compaction into a snapshot.

**What to avoid:** storing one monolithic `.notebook` bundle per notebook and PATCHing it. Every stroke edit then re-uploads the PDFs and audio inside, hitting the 750 GB/day cap and making conflicts total rather than per-page.

### Gaps
- No first-party documentation found for **Xournal++ + Drive**, **DEVONthink**, **1Password's old Dropbox sync**, **Zotero WebDAV**, **Logseq**, **Standard Notes**, **Notesnook**, or **Saber/Nextcloud** internals in this pass — all **unconfirmed**; the report should not attribute specific designs to them without a second research pass.
- Joplin's exact conflict-file naming and "Conflicted copy" UX is referenced in its user docs, which I did not fetch — only the sync/lock specs above are sourced.
- Whether Drive's `changes.list` reports a file whose *content* changed but whose parent/name did not, with `includeRemoved=false` defaults, in the exact shape needed for a delta engine: strongly implied by `manage-changes` ("If the file has changed, the collection provides the current state of each file") but I did not test it.

---

## 6. Conflict resolution for ink documents

### Takeaway
The realistic ladder is: **(1) last-writer-wins per page** (cheap, loses work), **(2) per-page conflict copies** (cheap, never loses work, requires user reconcile — what Joplin/remotely-save do at file level), **(3) per-stroke set-CRDT with stroke UUIDs + tombstones** (automatic merge, moderate engineering, no external dependency), **(4) full CRDT via Automerge** (automatic merge, real library, but you inherit binary doc format, growth and migration concerns). For a two-device personal app, (2) is the correct v1 and (3) is the correct v2.

### Cited Findings
- Joplin resolves *property-level* conflicts with `{value, updatedTime}` timestamps and "heuristics decide which value should be kept" — [Joplin: Synchronisation](https://joplinapp.org/help/dev/spec/sync/)
- remotely-save's free tier offers only "keep newer version or larger version"; PRO adds merging small markdown files or duplicating large/non-markdown files — [remotely-save](https://github.com/remotely-save/remotely-save)
- Automerge is "a Conflict-Free Replicated Data Type (CRDT), which allows concurrent changes on different devices to be merged automatically **without requiring any central server**" — [Automerge Swift docs](https://automerge.org/automerge-swift/documentation/automerge/)
- automerge-swift: SPM, `.package(url: "https://github.com/automerge/automerge-swift.git", from: "0.5.2")`, product `Automerge`, MIT licensed; core rewritten in Rust for cross-platform use; supports **iOS, macOS, and macCatalyst** — [automerge-swift](https://github.com/automerge/automerge-swift); [Swift Forums announcement](https://forums.swift.org/t/introducing-automerge-enable-collaborative-asynchronous-syncing-for-your-data-structures/67985)
- The API is document-centric: `Document()`, `putObject`, `insert`, `delete`, `fork()`, `merge(other:)` — i.e. **you hold an opaque document and merge documents**, which maps cleanly onto "one Automerge file per page/notebook on Drive" — [automerge-swift](https://github.com/automerge/automerge-swift)
- Automerge "always picks a single winner for concurrent edits to the same key or index, but **both values are retained internally**" and can be inspected — [Automerge CRDT concepts](https://cran.r-project.org/web/packages/automerge/vignettes/crdt-concepts.html)
- A reference SwiftUI document-based app (MeetingNotes, iOS + macOS) exists showing Automerge + Automerge Repo in a real app — [automerge-swift](https://github.com/automerge/automerge-swift); [Rhonabwy: Automerge for Swift](https://rhonabwy.com/2023/10/21/automerge-for-swift/)
- No shipped ink app's per-stroke merge granularity was documented in any source I read (Goodnotes and Notability both describe only whole-document backup/sync) — see Gaps.

### Inferences
- **Per-stroke set-CRDT is the sweet spot for ink specifically.** Model a page as a grow-only set of immutable strokes (`strokeID = ULID`), plus a tombstone set of deleted stroke IDs, plus an ordered "stroke order" list resolved by (lamport, deviceID) tiebreak. Merging two page versions is then set union of strokes, set union of tombstones (tombstone wins), and a deterministic order merge. This is ~a few hundred lines, needs no library, serialises to JSON/Protobuf, and — crucially — a *page* is still one file, so it drops straight into the §5 architecture.
- Do **not** merge at "per-stroke last-writer-wins": strokes are append-mostly, and the only genuinely concurrent operation on the *same* stroke is erase-vs-erase or erase-vs-move, both of which a tombstone set handles correctly with no timestamps at all.
- Automerge is the right choice only if you also want live collaboration later. Its costs are real: opaque binary docs (no diff-ability, no partial read), unbounded history growth requiring compaction/snapshotting, and a Rust toolchain in the build. For "iPad + Mac, one user", the set-CRDT gets you the same merge semantics with a debuggable file format.
- **Same page edited offline on both devices** — concrete resolution with the set-CRDT: both devices produce `pages/<pageID>.ink` v1 and v2 from a common v0. Whichever uploads second downloads the other's v1, performs `merge(local, remote)`, and uploads v3. Because merge is commutative/associative/idempotent on sets, the order of the two uploads does not matter, and a third device that only ever sees v3 converges. The only loss mode is a *file-level* overwrite (option 2 in §5), which is precisely why the merge must happen before the PATCH, not after.
- Granularity reality check: Goodnotes and Notability — the two market leaders — do **not** merge at all. Goodnotes' Drive path is a one-way backup and explicitly "does not sync changes across your devices"; Notability's is one-way and "deleting a note in Notability does not delete the backup copy". Genuine two-way ink sync over a third-party drive is therefore a differentiator, not table stakes.

### Gaps
- **Yjs + Swift**: no Swift binding was verified; Yjs is JS-first and would require a JS runtime or a custom port. **Unconfirmed / likely impractical for native Swift** without embedding JavaScriptCore.
- Automerge document **size growth / compaction** characteristics for a page with ~10k strokes: **unconfirmed** (no benchmark read).
- What granularity Goodnotes/Notability use internally for their *own* cloud sync (not the Drive backup): **not documented publicly**.
- Whether any shipped ink app merges strokes individually: no evidence found either way.

---

## 7. iOS/iPadOS and macOS background execution constraints

### Takeaway
iOS gives you exactly one usable mechanism for finishing transfers while suspended: **`URLSession` background sessions**, which run the transfer in a separate process and relaunch your app to deliver results. They support **downloads and uploads from a file**, which is fine for Drive resumable uploads *if* you write the chunk to a temp file first. They do **not** support uploads from memory or streams, and the system rate-limits relaunches. `BGTaskScheduler` is for short opportunistic maintenance, not bulk transfer. macOS has none of these constraints in practice.

### Cited Findings
- "For long-running and nonurgent transfers, you can create tasks that run in the background. These tasks continue to run even when your app is suspended" — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- Configure with `URLSessionConfiguration.background(withIdentifier:)`; set `sessionSendsLaunchEvents = true` (default) to be woken on completion; set `isDiscretionary` for time-insensitive work so the system waits for Wi-Fi/power — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- "If your app is in the background, the system may suspend your app **while the download is performed in another process**"; on completion the system resumes the app and calls `application(_:handleEventsForBackgroundURLSession:completionHandler:)` — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- If the app was terminated, "the system relaunches the app in the background… recreate the background session… using the same session identifier… to allow the system to reassociate the background download task with your session" — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- Hard limitations: the session **must** have a delegate; only HTTP/HTTPS (no custom protocols); redirects are always followed and your redirect delegate is *not* called; "**Only upload tasks from a file are supported (uploads from data instances or a stream fail after the app exits).**" — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- Rate limiter: when the app starts a new background task while backgrounded, "the task doesn't begin until the delay expires. The delay increases each time the system resumes or relaunches your app"; it resets to 0 when the user foregrounds the app. Guidance: "use a small number of background sessions — ideally just one — and use these sessions to start many download tasks at once", and avoid thousands of small tasks — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- Drive explicitly designs for this: resumable uploads are recommended "when your file sizes might vary greatly or when there's a fixed time limit for requests (such as **mobile OS background tasks**)" — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- Resumable session URIs expire after **one week**; resume via empty `PUT` with `Content-Range: bytes */<total>` and a `308` + `Range` response — [Drive: Upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads)

### Inferences
- **Resumable uploads do work with background `URLSession`**, but only in the "single big PUT per chunk from a file" shape: write each 256 KB-multiple chunk to a temp file, hand it to an upload task bound to the background session, and persist the session URI + byte offset in the local DB *before* starting the task. On relaunch, query the session URI for received bytes and continue. The pairing that breaks is "stream the chunk from memory" — that fails after app exit per Apple's own doc.
- Never create one background task per stroke/page. The relaunch rate limiter is the single biggest threat to a per-object design; coalesce into a small number of large transfers (e.g. one zip of changed pages per sync, or one task per notebook).
- Design the sync engine to be **crash-consistent at any suspension point**: every state transition (session URI created, bytes acked, file merged, PATCH applied) must be a committed local DB row. The app can be killed between any two lines.
- Do not rely on `BGTaskScheduler` for the sync itself — it is opportunistic and unbounded-delay by design. Use it only to *nudge* a sync when the app is backgrounded with a foreground-completed transfer queue.
- macOS: `URLSession` background configuration exists but the practical constraint set is different — the app keeps running when the window closes, so a plain `URLSession` + a serial actor queue is sufficient. The macOS-specific gotchas are Keychain access groups (§4) and App Sandbox file access for any Files-app/File-Provider route (§8).

### Gaps
- **`BGTaskScheduler` numeric budgets** (how many seconds `BGAppRefreshTask`/`BGProcessingTask` actually get): Apple publishes no guaranteed number. **Unconfirmed by design** — treat as "tens of seconds, not guaranteed".
- Whether iOS will honour a background `URLSession` **upload** task whose body is produced by an upload-task-from-file created while the app is already suspended: not tested; Apple's docs only describe starting tasks.
- Exact behaviour when the app is suspended *mid*-resumable-upload (server-side session state vs client-side offset drift): **unconfirmed**; the `Range`-on-`308` protocol is the intended recovery path.

---

## 8. Alternative route: Google Drive via the Files app / File Provider / Drive for desktop (no API)

### Takeaway
Storing your `.notebook` documents inside a Drive-synced folder and letting the OS move bytes is attractive (no OAuth, no quota, no verification) but it is the **least reliable option for a document *package* or bundle**: iCloud-style "open in place, coordinate writes" semantics are not what a third-party File Provider or the Drive desktop mount provides, and the well-known failure mode is exactly the package/bundle case. I could not verify current Google Drive File Provider behaviour from a primary source in this pass, so this section is mostly a gap statement plus a design warning.

### Cited Findings
- Apple documents background *downloads* for app-initiated transfers, and separately documents File Provider for presenting remote content to other apps — the File Provider documentation was not read in this pass (see Gaps) — [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- Goodnotes — the largest ink app — explicitly **excludes** this route: its Auto Backup is "available on iOS and iPadOS. It is not currently available in Goodnotes for macOS"; and for iCloud Drive "iCloud Drive doesn't provide the integrations Auto Backup needs" — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Goodnotes also documents the multi-writer hazard of folder-level backup: enabling Auto Backup on a second device "may queue the entire library on device B for upload. The system does not know which documents were already uploaded from another device" — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Goodnotes' Drive destination is constrained: "Auto Backup saves to your base-level Google Drive folder. A custom destination folder is not available at this time." (Dropbox, by contrast, is confined to `/Apps/Goodnotes 6`.) — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Drive's own metadata model treats a "file" as a single blob with one parent — there is no bundle/package concept in the Drive API — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- Drive `capabilities.canDownload` must be checked before download; owner/app-organizer can apply `DownloadRestrictionsMetadata` — [Drive: Download and export files](https://developers.google.com/workspace/drive/api/guides/manage-downloads)

### Inferences
- **Do not ship a package/bundle document format on a third-party synced folder.** The classic failure is partial sync: the OS (or Drive's desktop client) copies some members of the bundle and not others, leaving a document that opens with missing pages — and because Drive has no atomic directory rename, there is no way to publish a bundle atomically. This is a general property of "dumb" drives, and it is why §5 recommends flat directories of independent files with a manifest, not bundles.
- If you want a no-API route for *personal* use, the least-bad shape is: one **flat directory** per notebook, individual files, a `manifest.json`, and treat the Drive folder as a replication target only — the app still owns a local DB and still does its own conflict handling. That is 80% of the work of the API route with none of the observability (no `version`, no `md5Checksum`, no change feed), so it saves little.
- Reasonable compromise if the user insists: ship the API sync as primary and offer **"Export backup to a Drive folder"** (one-way, like every competitor) via the Files app / security-scoped URL. That is honest, low-risk, and matches Goodnotes/Notability behaviour.

### Gaps
- **Google Drive's File Provider extension on iOS/iPadOS**: whether it supports open-in-place, coordinated writes, and directory enumeration for third-party apps; and its known behaviour with `.bundle`/package directories — **not verified from a primary source** in this pass. Widely-reported community problems exist but I did not read a citable page.
- **Google Drive for desktop on macOS**: whether it presents a true local mount (File Stream) vs a synced mirror, and whether it preserves package directories atomically — **unconfirmed**.
- Whether an iOS app can even *hold* a security-scoped bookmark into the Drive File Provider and keep it valid across launches — **unconfirmed**.

---

## 9. How the incumbent ink apps actually use Google Drive

### Takeaway
Uniformly **one-way automatic backup**, never two-way sync. Both market leaders use Drive as a durable export target in a user-chosen (Goodnotes: fixed base-level) folder, in either a native format or PDF, and both explicitly document that changes made in the cloud do **not** flow back. This is strong evidence that two-way sync over Drive is the hard, differentiated part — and that a "backup only" v1 is a legitimate, competitive scope.

### Cited Findings

**Goodnotes**
- "Have your documents automatically uploaded to Google Drive, Dropbox, OneDrive, or WebDAV for safekeeping while you work in Goodnotes." — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- "**Auto Backup is a one-way process.** It does not sync changes across your devices the way iCloud does. Changes you make in the cloud storage do not change your Goodnotes library." — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Not on macOS: "Auto Backup is available on iOS and iPadOS. It is not currently available in Goodnotes for macOS — use iCloud sync to keep documents synced across Apple devices." — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Cadence: "After a successful backup, background Auto Backup usually waits about **12 hours** before running again"; an "Increase Auto Backup frequency" toggle moves it to "about every 1–2 minutes"; manual "Back Up Now" exists — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Warning: "With the default schedule, work since your last successful backup may not be in the cloud yet if the app crashes or the device is lost." — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Formats: **Goodnotes Document** (native, editable, re-importable), **PDF** (flattened, "you can't erase handwriting on the PDF"), or both — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- What triggers upload: create/import document, create folder, recover deleted item, change page content or template, add/remove/reorder pages, rename, move. What does **not**: custom outline edits, favourites, deleting a document or folder — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Privacy claim: "Goodnotes needs Read & Write access to save and update files in your cloud storage. We won't view or modify your other documents and files." — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Separate from backup, Goodnotes' own cross-device sync is **iCloud Sync**, described as "a two-way sync that keeps one version of your documents across devices" — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)

**Notability**
- Third-Party Backup supports Box, Dropbox, Google Drive, OneDrive, WebDAV — [Notability: Backing up notes outside of Notability Cloud](https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud)
- "This is a **one-way backup**, and deleting a note in Notability does not delete the backup copy. Similarly, deleting a backup does not delete the original note in Notability." — [Notability: Backing up notes](https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud)
- Default folder `Notability`, user-relocatable — [Notability: Backing up notes](https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud)
- Formats: **NTB** (native, "best format for backing up and sharing with other Notability users"), **PDF** ("Bookmarks and audio recordings will not be included"), **PDF + Recording** (a .zip with PDF + a folder of .m4a files; "Notability can't open .zip files") — [Notability: Backing up notes](https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud)
- Trigger: "When you enable Third-Party Backup or change its settings, all of your notes are backed up" and "When you edit a note and return to the Library, that note is backed up." — [Notability: Backing up notes](https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud)
- Restore is manual: "Notability can't restore folders from a backup automatically, so they must be remade manually." — [Notability: Backing up notes](https://support.gingerlabs.com/en-us/articles/16300164-backing-up-notes-outside-of-notability-cloud)

**Obsidian (via plugin)**
- Google Drive support is a paid PRO feature of the community plugin `remotely-save`, not a first-party Obsidian feature — [remotely-save](https://github.com/remotely-save/remotely-save)

### Inferences
- The competitive bar is low in one sense (nobody offers two-way Drive sync) and high in another (a two-way implementation inherits every conflict and quota problem that all four vendors chose to avoid). Marketing a **"Backup to Google Drive" as v1, "Two-way sync" as v2** mirrors the entire market and de-risks the launch.
- Notability's "edit → return to Library → upload that note" is a cheap, predictable trigger that a native app can reproduce exactly, and it avoids background-execution complexity entirely. Goodnotes' 12-hour default cadence shows even a well-funded team accepts stale-by-hours for background upload.
- Goodnotes' scope claim ("Read & Write… won't view or modify your other documents") is only *true* if they use `drive.file` — a useful precedent that `drive.file` is sufficient for a shipping, mass-market ink app's Drive backup.
- Audio is the format trap: Notability's plain PDF drops recordings, and its PDF+Recording option produces a zip it cannot re-import. Any app that records audio must define a native container that round-trips, or accept that the Drive copy is not restorable.

### Gaps
- **Noteful** and **Noteshelf** support pages: not read. Whether either offers two-way Drive sync: **unconfirmed**. (Noteshelf is widely described as supporting Google Drive backup; I did not verify.)
- Whether Goodnotes is *also* using `drive.file` vs `drive` scope: inferred from their privacy wording, not verified from an API manifest — **unconfirmed**.

---

## 10. Google Drive vs CloudKit / Dropbox / OneDrive / self-hosted (and hybrid patterns)

### Takeaway
Drive is the **worst-fit of the majors for live sync** and the **best-fit for "the user's own storage, user-visible files, zero server cost"**. It lacks transactions, ETags, server push usable by a client, and package semantics; it has the most onerous verification story of the consumer clouds if you ever leave `drive.file`. If the requirement is "reliable live two-way sync with minimal engineering", **CloudKit wins decisively on Apple platforms**; Drive is a backup/interop target. A hybrid (CloudKit for live sync + Drive for user-visible backup) is the pattern the market actually ships.

### Cited Findings
- Drive exposes no ETag and no conditional-update parameter — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files); [Drive: files.update](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)
- Drive push requires a public HTTPS webhook with a valid CA-signed cert — impossible for a client-only app — [Drive: Push notifications](https://developers.google.com/workspace/drive/api/guides/push)
- Drive's appDataFolder cannot be trashed, shared, or moved between spaces — [Drive: Application data folder](https://developers.google.com/workspace/drive/api/guides/appdata)
- Drive restricted scopes require an annual third-party security assessment (CASA) if data passes through a server — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification); [App Defense Alliance: CASA](https://appdefensealliance.dev/casa)
- Drive charges nothing for standard API use today, but "Exceeding the quota request limits is planned to incur charges… later in 2026" — [Drive: Usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
- Goodnotes ships **both**: iCloud Sync (two-way, Apple-only) *and* Auto Backup to Drive/Dropbox/OneDrive/WebDAV (one-way) — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- Goodnotes FAQ states iCloud Sync is used "if you mainly need protection when a device is lost or damaged", and Auto Backup "when you can't or don't want to use iCloud, or when you need to open documents in cloud storage or on a computer without Goodnotes" — i.e. the two features serve different jobs and coexist — [Goodnotes: Set up Auto Backup](https://support.goodnotes.com/hc/en-us/articles/7352786555279-How-to-Set-Up-Auto-Backup-in-Goodnotes)
- remotely-save's cross-provider abstraction (S3, Dropbox, OneDrive, WebDAV, Drive, Box, pCloud, Yandex, Koofr, Azure Blob) shows the file-level sync algorithm is provider-independent; only the driver differs — [remotely-save](https://github.com/remotely-save/remotely-save)

### Inferences
- **CloudKit** removes: OAuth, verification, quotas, conflict detection (server record changed → `CKRecord` conflict callbacks / `serverRecordChanged` merge), and background-sync plumbing (`NSPersistentCloudKitContainer` does it). It costs you: Apple-only, no user-visible file in a Drive folder, no web/Android access, and CloudKit's own 1 GB/asset limits and per-user private DB quota tied to iCloud storage. For a single-user iPad+Mac app, this is the shortest path to "it just works".
- **Google Drive** buys: user-owned data, files the user can see/open/share in the Drive UI, cross-platform portability, zero marginal cost, and no backend to operate. It costs: you build the sync engine (weeks, not days), you own every conflict and corruption case, and you inherit Google's verification and rate-limit policy.
- **Dropbox** is the closest analogue but slightly friendlier: cursor-based `/delta` and content-hash-based conflict copies are a documented first-class model, and Dropbox's `files/upload` supports a `mode` with `rev`-based conflict handling. I did not re-verify Dropbox's current API docs in this pass (see Gaps), so treat this as directional.
- **OneDrive** with the `App Folder` scope is what remotely-save uses for its free tier — the closest structural analogue to `drive.appdata`, hidden per-app folder — [remotely-save](https://github.com/remotely-save/remotely-save)
- **Self-hosted / Supabase / Firebase**: only worth it if you need server-authoritative merge or multi-user sharing. For "my notes on my two devices", a server is an *extra* availability domain and an extra bill, and the user explicitly does not want one. Nothing in the research shows a server is unavoidable for single-user two-device sync — a lock-free, immutable-object design over Drive is sufficient, given the caveats in §5.
- **Hybrid is the shipping pattern, not a compromise.** Concretely: CloudKit (or `NSPersistentCloudKitContainer`) for continuous two-way sync between the user's own devices, plus a one-way, user-triggered "Back up to Google Drive" producing a native editable file per notebook. This gives the reliability of Apple's stack, the user-visible-portability of Drive, and matches Goodnotes' own product split.

### Gaps
- Current **Dropbox API** semantics (`/files/upload` `mode`, `rev`, `content_hash`, `/delta` cursor, App Folder scope) and **OneDrive** `App Folder`/delta behaviour: **not verified** in this pass; the comparison above leans on general knowledge and should be re-checked.
- **CloudKit** current quotas (per-user private DB asset limits, `CKRecord` 1 MB field limit, `NSPersistentCloudKitContainer` conflict policy): **not verified** here.
- No citable source found for a common "CloudKit for sync + Drive for backup" pattern *outside* Goodnotes' iCloud+Drive split; generalising to third-party indie apps is an inference, not a documented trend.

---

## 11. Security, privacy, and Google policy obligations

### Takeaway
Three concrete obligations: (1) store refresh tokens in the **Keychain** with an access group set correctly for macOS; (2) if you request restricted scopes you must comply with the **Google API Services User Data Policy** including Limited Use, publish a matching privacy policy, and accept annual CASA; (3) optional client-side encryption is *compatible* with the design in §5 (encrypt blobs before upload, keep the key in Keychain) but destroys the "user can open files in Drive" benefit — a real product trade-off, not a technical one.

### Cited Findings
- "Save refresh tokens in secure, long-term storage and continue to use them as long as they remain valid." — [Drive: Choose Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- Google Sign-In on macOS: "Your application must be signed with a certificate issued by Apple… in order to store credentials using Keychain," and you "will also need to add `$(AppIdentifierPrefix)$(CFBundleIdentifier)` to its keychain access group" — [Google: Sign-In for iOS/macOS start](https://developers.google.com/identity/sign-in/ios/start)
- Restricted-scope apps must satisfy "the Additional requirements for specific API scopes" of the Google API Services User Data Policy, or product-specific requirements — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Privacy policy requirements: must be visible to users, hosted on the same domain as the homepage, linked from the OAuth consent screen; "must disclose the manner in which your application accesses, uses, stores, or shares Google user data"; must comply with the User Data Policy and "the **Limited Use requirements** for restricted scopes"; "You must limit your use of Google user data to the practices that your published privacy policy discloses." — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Homepage must be public (not behind login) and clearly about the app; Play Store / Facebook pages "aren't considered valid application home pages" — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Verification requires a demo video (YouTube, unlisted) showing the consent flow in English, the consent screen displaying the app name, the browser address bar containing your client ID, and each scope's feature in action; multiple OAuth clients must each be demonstrated — [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- `appProperties` are private to the app but still stored in Google's cloud and retrievable only with an authenticated request — so they are not a place for secrets, and they are not client-side-encrypted by default — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- Drive supports a **Client Side Encryption (CSE)** model with `clientEncryptionDetails`, `wrappedKey`, `kaclsId`, `aes256GcmChunkSize` — i.e. Google's own CSE is designed around an external Key ACL Service (KACLS), not a purely local key — [Drive: files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
- Precedent for app-level E2EE over a dumb drive: remotely-save encrypts "using openssl / rclone crypt format before being sent to the cloud **if** user specify a password", and warns the vault name itself is not encrypted — [remotely-save](https://github.com/remotely-save/remotely-save)

### Inferences
- With `drive.file` only (recommended), you avoid the restricted-scope obligations entirely — but you still must honour the general Google API Services User Data Policy and you still need a privacy policy on the App Store. The Limited Use section is the operative constraint: don't use Drive data to train models, don't sell it, don't transfer it except as needed to provide the feature.
- **Token storage**: one Keychain item per account (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock` so background refresh works after reboot-before-unlock — *not* `WhenUnlocked` if you want background sync). Store: refresh token, selected account email, granted scope string, and the Drive root folder ID. Access token stays in memory only.
- **Client-side encryption trade-off**: encrypting page/asset blobs before upload keeps Google from reading notes, but then (a) the files in Drive are useless to the user in the Drive UI — killing the main reason to choose Drive, (b) `md5Checksum` becomes a checksum of ciphertext (still fine for integrity, but you lose server-side dedupe), and (c) any key loss is total data loss with no recovery path. If offered, it must be **opt-in, per-vault, with an explicit "we cannot recover this" acknowledgement** — exactly remotely-save's model.
- Google's CSE (`clientEncryptionDetails`) is *not* the right tool here: it requires a KACLS (a server you'd have to run), which contradicts the no-server constraint.
- `appProperties` are excellent for sync bookkeeping (`contentHash`, `deviceID`, `schemaVersion`, `logicalID`) precisely because they're invisible to the user and don't pollute the folder — but they must be treated as plaintext metadata.

### Gaps
- The exact text of the Google API Services User Data Policy's Limited Use section was not read directly in this pass — only Google's summary of it and the requirement to comply. Quote-level citation needed before publishing a privacy policy.
- Whether Google's CSE can be used with a purely local key (no KACLS) for consumer Drive: **unconfirmed**; the resource schema implies KACLS is mandatory.
- App Store review implications of requesting `drive.file` (vs Sign in with Google only): **not researched** — Apple's guidelines on third-party login are a separate question.

---

## Cross-cutting effort/risk summary (for the report writer)

| Decision | Recommendation | Confidence | Main risk |
|---|---|---|---|
| Scope | `drive.file`, single visible app folder | High (documented non-sensitive + full API surface) | Cannot see pre-existing user folders |
| Publishing status | In production, not Testing | High (7-day token expiry documented) | Silent weekly auth failure if left in Testing |
| Transport | `URLSession` + hand-written v3 client | Medium-high (inference) | ~1–2 weeks extra vs GTLR, but far less friction |
| Push | Don't; poll `changes.list` on foreground/launch | High (webhook requires server) | Staleness on the *other* device until it opens |
| Granularity | Per-page files + content-addressed assets + manifest | High (matches Joplin/remotely-save) | Many small requests → background rate limiter |
| Atomicity | Immutable blobs + pointer PATCH, or LWW + conflict copies | High (no CAS exists) | Orphaned blobs need GC |
| Ink merge v1 | Per-page conflict copy | High | User-visible reconcile work |
| Ink merge v2 | Per-stroke set-CRDT with tombstones | Medium (inference, no shipped precedent found) | ~1–2 weeks, needs careful ordering rules |
| Full CRDT | Only if live collaboration is a goal | Medium (Automerge verified for Swift) | Opaque binary, growth, Rust build |
| Background | One background `URLSession`, few large tasks | High (Apple docs) | Relaunch rate limiter; uploads must come from files |
| macOS | Plain `URLSession`; Keychain access group required | High | None significant |
| Files-app route | Backup/export only, never live sync, never bundles | Medium | Unverified File Provider behaviour with packages |
| Product scope | Ship one-way backup first, two-way second | High (whole market does this) | Two-way is the differentiator *and* the risk |
