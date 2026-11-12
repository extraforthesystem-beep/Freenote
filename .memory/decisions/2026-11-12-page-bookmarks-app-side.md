---
type: decision
title: Page bookmarks stay app-side
status: accepted
date: 2026-11-12
---

# Page bookmarks stay app-side

## Decision

Page bookmarks are stored in `UserDefaults` keyed by notebook UUID and page UUID (`PageBookmarks`), not in `notebook.json`.

## Why

- Bookmarks are a view preference, not document content; they should not force a page or manifest rewrite.
- `notebook.json` is the document truth that will be synced; adding a per-device list there would create needless merge conflicts.
- Bookmarks can move into the document later if the user wants them on every device; the page IDs are stable.

## Consequence

Bookmarks do not sync through Google Drive and do not survive a restore on another device until they are promoted to document data. A future ADR must record that change.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Lazy Code Ladder](../meta/lazy-code.md)
- [SRE Memory Routing](../meta/sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
