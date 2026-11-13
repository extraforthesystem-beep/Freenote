---
type: Meta
title: Memory Authority
description: Project memory is source of truth — challenge before override; topic recall on demand
tags:
  - meta
  - harness
  - authority
timestamp: "2026-09-16T00:00:00Z"
---

# Memory Authority

`.memory/` is **project truth** (decisions, features, architecture). Session chat recall is a different layer. Existing ADR files are mechanically append-only (session-start snapshot + restore). Policy still requires a challenge before architecture-bend.

## Truth tiers

| Tier | Paths | Behavior |
|------|--------|----------|
| **Hard truth** | `.memory/decisions/**`; feature **body/contract** under `.memory/features/**`; stack/phase/architecture in `context/project.md` | On **conflict, override, remove, or architecture-bend**: stop and challenge. Never edit old ADRs — append a new file. Non-conflicting new ADR (user already decided in-session): write, then summarize. |
| **Soft ops** | `progress/status.md`; feature frontmatter-only `status`/`priority`; session-end hook progress | Sync without challenge ceremony. |
| **Runtime** | Code | Code is what runs. Memory is what was decided. On drift: report + ask; do not silently rewrite the ADR or ignore the bug. |

## Challenge shape

**Default (short):**

> Conflicts `<path>` — keep / update / remove / add?

**Architecture bend:** first load the related picture (below), then challenge.

Do **not** ask before every progress write or every non-conflicting ADR append.

## Topic recall (on demand)

When a topic comes up (or before a hard-truth change that might bend architecture):

1. Read `.memory/domains/<topic>.md` if present (or `domains/index.md`)
2. Keyword-search `.memory/decisions/`, `.memory/features/`, `.memory/failures/`
3. Load only the hits needed for the bigger picture — stay lean

Do **not** expand session-start inject beyond progress (budget `<500` tokens).

## Agent workflow

1. Topic recall if the task touches known domains or old decisions
2. Classify soft vs hard vs runtime
3. Soft → act; hard conflict/bend → challenge; runtime drift → report + ask
4. After work → `/memory-sync`

## Honest limit

Existing ADRs: hook restores in-place edits to the session-start snapshot. New ADR files are allowed. Agents can still ignore the *challenge* step on new writes; pushback remains correct until the user overrides.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Companion Skills](companion-skills.md)
- [Ponytail Debt](debt.md)
- [Lazy Code Ladder](lazy-code.md)
- [SRE Memory Routing](sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
