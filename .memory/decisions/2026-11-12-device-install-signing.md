---
type: decision
title: Physical iPad installs use the personal team and automatic signing
status: accepted
updated: 2026-11-12
---

# ADR: Physical iPad installs use the personal team and automatic signing

- **Status:** accepted
- **Date:** 2026-11-12
- **Extends:** [[2026-11-12-goodnotes-parity-build]]

## Context

The build had only ever run in the iPad simulator. The user asked to install it on a real iPad. The project had an empty `DEVELOPMENT_TEAM`, and the Mac had one imported Apple Development certificate whose private key asks for a keychain password nobody knows.

## Decisions

1. **Target device:** iPad (9th generation), `iPad12,1`, iPadOS 27.2.1, UDID `00008030-000A1D412EE3C02E`. Developer Mode is on.
2. **Team:** personal team `CQ65B26KFJ` (`Apple Development: granth0530@gmail.com (FP6586C7M3)`). `DEVELOPMENT_TEAM` is set in both build configurations; signing stays automatic. The app has no entitlements, so a free team is enough.
3. **Build:** `xcodebuild -project NoteApp.xcodeproj -scheme NoteApp -configuration Debug -destination 'id=00008030-000A1D412EE3C02E' -derivedDataPath build/device -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`. The flag pair is what creates/refreshes the iOS Team Provisioning Profile and registers the device.
4. **Install:** `xcrun devicectl device install app --device <udid> build/device/Build/Products/Debug-iphoneos/NoteApp.app`.
5. **The old imported certificate is not required.** If `codesign` fails with `errSecInternalComponent`, create a fresh Apple Development certificate from Xcode → Settings → Accounts → Manage Certificates (the account is signed in) rather than recovering the old key's password.

## Consequences

- Device builds live in `build/device`, separate from the simulator's DerivedData.
- Free-team profiles expire after 7 days; re-running the build with `-allowProvisioningUpdates` refreshes them.
- Full Pencil/gesture checklist still has to be walked on the device; installation alone is not a verification.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Advanced search uses Apple's ink engine; query syntax lives in SearchKit](2026-11-12-advanced-search.md)
- [Dark mode keeps white paper unless Dark Paper is on](2026-11-12-dark-mode-paper.md)
- [GoodNotes parity build and page format v2](2026-11-12-goodnotes-parity-build.md)
- [Page saves go through one ordered write queue](2026-11-12-ordered-page-writes.md)
- [Page bookmarks stay app-side](2026-11-12-page-bookmarks-app-side.md)
- [Page operations are pure NoteCore functions; app settings live in UserDefaults](2026-11-12-page-operations-and-settings.md)
- [One live canvas per notebook; other pages are cached images](2026-11-12-page-scroll-live-canvas.md)
- [PDF export is vector; import rewrites only when it must](2026-11-12-pdf-vector-export-and-import.md)
- [Sticky notes and tape are page elements; search hits carry source and snippet](2026-11-12-sticky-tape-and-search-hits.md)
- [A finger drag on a board object is decided at touch-down, before ink](2026-11-13-board-finger-drag-vs-ink.md)
- [Boards open full screen on iPad; the Mac keeps a sheet](2026-11-13-board-full-screen.md)
- [Editor toolbar is customisable and only the colours scroll](2026-11-13-customisable-toolbar.md)
- [Page thumbnails live in a side panel; Undo and Redo leave the default toolbar](2026-11-13-pages-side-panel.md)
- [Live ink renders at its own zoom through a counter-scaled host](2026-11-13-sharp-ink-zoom.md)
- [Wave 4 lands eight research-backed feature sets on foundation-base](2026-11-13-wave4-feature-build.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
