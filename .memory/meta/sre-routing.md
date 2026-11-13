---
type: Playbook
title: SRE Memory Routing
description: OKF path mapping for sre-architect skill memory retrieval order
tags:
  - sre
  - routing
  - harness
timestamp: "2026-09-07T00:00:00Z"
---

# SRE Architect — OKF memory order

When the `sre-architect` skill is active, fetch context in this order:

| Step | Old flat path | OKF path |
|------|---------------|----------|
| 1 | INDEX.md | [.memory/index.md](../index.md) |
| 2 | CONTEXT.md | [context/project.md](../context/project.md) |
| 3 | PROGRESS.md | [progress/status.md](../progress/status.md) |
| 4 | SYSTEM-MAP.md | project root `SYSTEM-MAP.md` (if present) |
| 5 | DECISIONS.md | [decisions/](../decisions/index.md) |
| 6 | FEATURES/*.md | [features/](../features/index.md) |
| 7 | FAILURES.md | [failures/log.md](../failures/log.md) |
| 8 | — | [meta/debt.md](debt.md) — `ponytail:` ledger |

**Before writing code:** climb the ladder in [lazy-code.md](lazy-code.md). Rung 2 is `graphify query "<capability>"`.

## Micro-loop

Observe → Predict → Act → Verify. On verify failure, escalate rollback ladder; after attempt 3, append a `FAIL-XXX` entry to [failures/log.md](../failures/log.md).

## Token budget

Session inject target <500 tokens. If [index.md](../index.md) reports over budget, run `/memory-compact` then `/memory-sync`.

## Memory vs code (Memory Authority)

When memory and code disagree: **code wins for runtime**; **memory wins for decided intent** until the user overrides. Report the drift; do not silently rewrite an ADR. Follow [Memory Authority](memory-authority.md).

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Companion Skills](companion-skills.md)
- [Ponytail Debt](debt.md)
- [Lazy Code Ladder](lazy-code.md)
- [Memory Authority](memory-authority.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
