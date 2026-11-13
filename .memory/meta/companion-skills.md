---
type: Meta
title: Companion Skills
description: Optional external skills the harness routes to — grilling and verification-before-completion. Not vendored.
tags:
  - meta
  - companions
  - skills
timestamp: "2026-09-16T16:45:00Z"
---

# Companion skills (external)

The harness routes. Publishers own the `SKILL.md` files. `kh install` does not copy them.

Install once per machine:

```bash
npx skills add mattpocock/skills --skill grilling -g -y -a cursor -a claude-code -a opencode -a antigravity
npx skills add obra/superpowers --skill verification-before-completion -g -y -a cursor -a claude-code -a opencode -a antigravity
```

Then `npx knowledge-harness install -g -y` so Antigravity links those skills into `~/.gemini/config/Skills/` and writes `~/.gemini/config/GEMINI.md`. `npx skills add -a antigravity` alone does not.

Do not install `grill-me` (stub that only calls `grilling`). Do not install `using-superpowers` (always-invoke; fights the token budget).

If a skill is missing, say so and continue the harness workflow. Do not vendor a copy into `.agents/skills/`.

## When

| Trigger | Skill | Fits the harness because |
|---------|-------|--------------------------|
| Product or architecture fork the human owns | `grilling` | Memory Authority is keep/update/remove/add *after* the choice. Grilling is the interview *before* the write. Look up facts. Wait on decisions. |
| About to say done, fixed, or passing, or about to `/memory-sync` after a code change | `verification-before-completion` | Fresh command in this turn. Evidence before the progress write. |

## Not these

pstack, gstack, `unslop`, `just-scrape`, and kitchen-sink skill packs stay out. Prose stays caveman. Code stays ponytail.

<!-- harness-links:autogen -->
## Graph links

- [NOTEAPP project context](../context/project.md)
- [Ponytail Debt](debt.md)
- [Lazy Code Ladder](lazy-code.md)
- [Memory Authority](memory-authority.md)
- [SRE Memory Routing](sre-routing.md)
- [NOTEAPP status](../progress/status.md)
<!-- /harness-links:autogen -->
