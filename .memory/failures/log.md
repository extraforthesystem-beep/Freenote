---
type: Failure Log
title: Failure Log
description: SRE hypothesis failures — read before retrying a failed approach
tags: [sre, failures, harness]
timestamp: 2026-06-21T00:00:00Z
---

# Failure Log

Append entries when a hypothesis fails verification. Format:

```markdown
## FAIL-XXX: Short title
- **Date:** YYYY-MM-DD
- **Hypothesis:** What you expected to work
- **Result:** Failed / Confirmed / Rejected — what actually happened
- **Lesson:** What to do differently next time
```

Before retrying a fix, search this file for matching keywords.
