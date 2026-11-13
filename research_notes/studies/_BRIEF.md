# Research brief (shared by every research agent)

NOTEAPP is a personal handwritten-notes app for iPad (+ Mac companion), Swift 6 / SwiftUI / PencilKit / PDFKit, iOS 27. Personal use only, no App Store.

Read first (skim, do not dump): `.memory/context/project.md`, `.memory/progress/status.md`.
Existing packages: `Packages/NoteCore` (model/store), `InkKit` (ink, render, shapes, PDF), `SearchKit` (handwriting index, query), `SyncKit` (empty), `AudioKit`, `StudyKit`, `AIKit`, `BoardKit` (whiteboard), `HistoryKit`, `TextDocKit`. App code in `NoteApp/`.
Competitor feature research already exists in `research_notes/competitors/` and `research_notes/iPad note app feature plan/` — do not redo it; cite it if relevant.

## Rules

- Research only. Do NOT edit any file outside `research_notes/studies/`. Do NOT commit, branch, or run builds.
- Every claim from a study needs a real source you actually opened this session: title, authors, year, venue, and a working URL or DOI. If you could not open it, put it under "Unverified" — never invent a citation, author, sample size or effect size.
- Prefer peer-reviewed papers (CHI, UIST, CSCW, Psych Science, Educational Psych Review, etc.), meta-analyses and replications over blogs. Note when a famous finding failed to replicate.
- Check what the codebase already does before proposing (grep/read narrowly; pipe through head). Mark each idea: NEW / EXTENDS <file or package> / ALREADY DONE.
- Be concise. No filler.

## Output format (one Markdown file, path given in your task)

```
# <Topic>
## Key findings (each: finding — evidence strength — source ref)
## What this means for NOTEAPP
## Feature ideas (table)
| # | Idea | Evidence | NEW/EXTENDS/DONE | Where in code | Effort S/M/L | Impact 1-5 |
## Sources (numbered, full citation + URL/DOI)
## Unverified
```

Aim for 8–20 ranked feature ideas. Finish with a one-paragraph "Top 3 to build first" with reasons.
