#!/usr/bin/env python3
"""Regenerate OKF index, log, viz.html for .memory/ bundle."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEMORY = ROOT / ".memory"
OKF_HOME = Path(os.environ.get("OKF_HOME", "/Users/panda/Data/knowledge-catalog/okf"))

SKIP_DIRS = {"_legacy", "archive", ".viz-staging"}
SKIP_FILES = {
    "index.md",
    "log.md",
    "session-journal.jsonl",
    "PROGRESS.md",
    "CONTEXT.md",
    "INDEX.md",
    "DECISIONS.md",
    "unsummarized.md",
}
RESERVED = {"index.md", "log.md"}
FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
NAV_START = "<!-- harness-links:autogen -->"
NAV_END = "<!-- /harness-links:autogen -->"
BASE_SPINE_IDS = (
    "context/project",
    "progress/status",
    "meta/router",
    "meta/sre-routing",
    "meta/lazy-code",
    "failures/log",
)

DEBT_SKIP_DIRS = {
    ".git",
    "node_modules",
    ".venv",
    ".memory",
    "graphify-out",
    "dist",
    "build",
    "assets",
}
PONYTAIL_RE = re.compile(r"(?:#|//|--|<!--)\s*ponytail:(.*)")

ADR_NUM_RE = re.compile(r"ADR-(\d+)", re.I)


def discover_domain_spine() -> tuple[str, ...]:
    """Optional .memory/domains/*.md topic routers (project-specific)."""
    domains = MEMORY / "domains"
    if not domains.is_dir():
        return ()
    return tuple(
        f"domains/{md.stem}"
        for md in sorted(domains.glob("*.md"))
        if md.name != "index.md" and not md.name.endswith(".bak")
    )


def spine_ids() -> tuple[str, ...]:
    return BASE_SPINE_IDS + discover_domain_spine()


def has_domains() -> bool:
    return bool(discover_domain_spine()) or (MEMORY / "domains" / "index.md").exists()


def parse_frontmatter(text: str) -> tuple[dict[str, str | list[str]], str]:
    m = FM_RE.match(text)
    if not m:
        return {}, text
    fm: dict[str, str | list[str]] = {}
    body = text[m.end() :]
    current_list_key: str | None = None
    for line in m.group(1).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- "):
            if current_list_key:
                if not isinstance(fm[current_list_key], list):
                    fm[current_list_key] = []
                fm[current_list_key].append(stripped[2:].strip())  # type: ignore[index]
            continue
        if ":" in stripped:
            key, _, val = stripped.partition(":")
            key, val = key.strip(), val.strip().strip('"')
            current_list_key = key
            if val == "":
                fm[key] = []
            else:
                fm[key] = val
    return fm, body


def iter_concepts() -> list[tuple[Path, dict[str, str | list[str]], str]]:
    concepts: list[tuple[Path, dict[str, str | list[str]], str]] = []
    for md in sorted(MEMORY.rglob("*.md")):
        rel_parts = md.relative_to(MEMORY).parts
        if any(p in SKIP_DIRS for p in rel_parts):
            continue
        if md.name.endswith(".bak"):
            continue
        if md.name in SKIP_FILES or md.name in RESERVED:
            continue
        if any(p.startswith(".") for p in rel_parts):
            continue
        text = md.read_text(encoding="utf-8")
        fm, body = parse_frontmatter(text)
        if not fm.get("type"):
            print(f"WARN: missing type frontmatter: {md.relative_to(MEMORY)}", file=sys.stderr)
        concepts.append((md, fm, body))
    return concepts


def concept_id(path: Path) -> str:
    return str(path.relative_to(MEMORY).with_suffix("")).replace("\\", "/")


def serialize_concept(fm: dict, body: str) -> str:
    lines = ["---"]
    for key, val in fm.items():
        if isinstance(val, list):
            if val:
                lines.append(f"{key}:")
                for item in val:
                    lines.append(f"  - {item}")
            else:
                lines.append(f"{key}: []")
        else:
            escaped = str(val).replace('"', '\\"')
            if any(c in escaped for c in ":{}[]#&*!|>'\"%@`"):
                lines.append(f'{key}: "{escaped}"')
            else:
                lines.append(f"{key}: {escaped}")
    lines.append("---")
    return "\n".join(lines) + "\n\n" + body.strip() + "\n"


def relative_md_link(from_path: Path, to_id: str) -> str:
    to_path = MEMORY / f"{to_id}.md"
    rel = os.path.relpath(to_path, from_path.parent)
    return rel.replace("\\", "/")


def wire_graph_links(concepts: list[tuple[Path, dict, str]]) -> None:
    """Inject markdown cross-links so OKF viz.html draws a connected graph."""
    valid = [(p, fm, b) for p, fm, b in concepts if fm.get("type")]
    ids: dict[str, tuple[Path, dict]] = {concept_id(p): (p, fm) for p, fm, _ in valid}
    spines = spine_ids()

    for path, fm, body in valid:
        cid = concept_id(path)
        targets: set[str] = set()

        if cid == "meta/router":
            targets = set(ids.keys()) - {cid}
        else:
            for spine in spines:
                if spine != cid and spine in ids:
                    targets.add(spine)

            for other_id, (other_path, _) in ids.items():
                if other_id == cid:
                    continue
                if other_path.parent == path.parent:
                    targets.add(other_id)

            if cid.startswith("decisions/"):
                for other_id in ids:
                    if other_id.startswith("decisions/") and other_id != cid:
                        targets.add(other_id)

            if cid.startswith("domains/"):
                for other_id in ids:
                    if other_id.startswith("decisions/"):
                        targets.add(other_id)

            if cid.startswith("features/"):
                for other_id in ids:
                    if other_id.startswith("features/") and other_id != cid:
                        targets.add(other_id)

            for key in ("depends_on", "blocks"):
                val = fm.get(key, [])
                if isinstance(val, str):
                    val = [val.strip()] if val.strip() and val.strip() != "[]" else []
                for dep in val or []:
                    dep_id = str(dep).replace(".md", "").strip()
                    if dep_id in ids:
                        targets.add(dep_id)

        nav_lines = ["## Graph links", ""]
        for tid in sorted(targets):
            title = str(ids[tid][1].get("title") or tid.split("/")[-1])
            nav_lines.append(f"- [{title}]({relative_md_link(path, tid)})")
        nav_lines.append("")
        nav_block = f"{NAV_START}\n" + "\n".join(nav_lines) + NAV_END

        if NAV_START in body:
            body = re.sub(
                re.escape(NAV_START) + r"[\s\S]*?" + re.escape(NAV_END) + r"\n?",
                "",
                body,
            )
        body = body.rstrip() + "\n\n" + nav_block + "\n"
        path.write_text(serialize_concept(fm, body), encoding="utf-8")


def _debt_no_trigger(rest: str) -> bool:
    return "," not in rest.strip()


def harvest_ponytail_debt() -> Path:
    """Scan repo for `ponytail:` comments; write `.memory/meta/debt.md`."""
    meta = MEMORY / "meta"
    meta.mkdir(parents=True, exist_ok=True)
    dest = meta / "debt.md"
    rows: list[tuple[str, int, str, bool]] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in DEBT_SKIP_DIRS]
        for name in filenames:
            if name == "SKILL.md":
                continue
            rel = Path(dirpath, name).relative_to(ROOT).as_posix()
            if rel.startswith(".cursor/hooks/"):
                continue
            path = Path(dirpath) / name
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for i, line in enumerate(text.splitlines(), 1):
                m = PONYTAIL_RE.search(line)
                if not m:
                    continue
                rest = m.group(1).strip().rstrip("-->").strip()
                rel = path.relative_to(ROOT).as_posix()
                rows.append((rel, i, rest, _debt_no_trigger(rest)))
    rows.sort()
    n = len(rows)
    no_trig = sum(1 for r in rows if r[3])
    lines = [
        "---",
        "type: Debt Ledger",
        "title: Ponytail Debt",
        "description: Harvested `ponytail:` shortcuts — ceiling and upgrade path",
        "tags:",
        "  - ponytail",
        "  - debt",
        f"timestamp: \"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\"",
        "---",
        "",
        "# Ponytail Debt",
        "",
        "Regenerated by `harness-sync.py`. Do not edit by hand.",
        "",
    ]
    if n == 0:
        lines.append("Clean ledger.")
    else:
        for rel, lineno, rest, flagged in rows:
            tag = " `no-trigger`" if flagged else ""
            lines.append(f"- `{rel}:L{lineno}` — {rest}{tag}")
        lines.extend(["", f"{n} markers, {no_trig} no-trigger."])
    dest.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return dest


def _self_check() -> int:
    assert _debt_no_trigger("global lock")
    assert not _debt_no_trigger("global lock, per-account locks if throughput matters")
    sample = "// " + "ponytail: O(n2) scan, index if n>1k"
    m = PONYTAIL_RE.search(sample)
    assert m is not None and "O(n2)" in m.group(1)
    body = strip_for_inject(
        "---\ntype: x\n---\n\n# Progress\nhello\n\n"
        f"{NAV_START}\nlinks\n{NAV_END}\n"
    )
    assert body == "# Progress\nhello"
    print("self-check ok")
    return 0


def cleanup_stray_files() -> None:
    legacy = MEMORY / "_legacy"
    try:
        legacy.mkdir(parents=True, exist_ok=True)
    except OSError:
        legacy = None
    # Case-insensitive FS (macOS): INDEX.md == index.md — never archive the real index.
    real_index = (MEMORY / "index.md").resolve()
    for name in ("PROGRESS.md", "CONTEXT.md", "INDEX.md"):
        stray = MEMORY / name
        if not stray.exists():
            continue
        try:
            if stray.resolve() == real_index:
                continue
        except OSError:
            pass
        try:
            if legacy is not None:
                shutil.move(str(stray), str(legacy / f"{name}.stray"))
            else:
                stray.unlink()
        except OSError:
            # ponytail: macOS may lock .memory/_legacy; delete stray in place
            try:
                stray.unlink()
            except OSError:
                pass
    for bak in MEMORY.rglob("*.bak"):
        if "_legacy" in bak.parts:
            continue
        try:
            bak.unlink()
        except OSError:
            pass


def prepare_viz_staging() -> Path:
    staging = MEMORY / ".viz-staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    for path, fm, _ in iter_concepts():
        if not fm.get("type"):
            continue
        rel = path.relative_to(MEMORY)
        dest = staging / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
    return staging


def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return (len(text) + 3) // 4


def strip_for_inject(text: str) -> str:
    """Same body inject-context.js sends: no frontmatter, no autogen nav."""
    _, body = parse_frontmatter(text)
    if NAV_START in body:
        body = re.sub(
            re.escape(NAV_START) + r"[\s\S]*?" + re.escape(NAV_END),
            "",
            body,
        )
    return body.strip()


def estimate_inject_tokens() -> int:
    for candidate in (MEMORY / "progress" / "status.md", MEMORY / "PROGRESS.md"):
        if candidate.exists():
            return estimate_tokens(strip_for_inject(candidate.read_text(encoding="utf-8")))
    return 0


def build_dir_index(entries: list[tuple[str, str, str, str]]) -> str:
    grouped: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    for typ, title, link, desc in entries:
        grouped[typ or "Other"].append((title, link, desc))
    sections: list[str] = []
    for typ in sorted(grouped):
        lines = [f"# {typ}", ""]
        for title, link, desc in sorted(grouped[typ], key=lambda e: e[0].lower()):
            suffix = f" - {desc}" if desc else ""
            lines.append(f"* [{title}]({link}){suffix}")
        sections.append("\n".join(lines))
    return "\n\n".join(sections) + "\n"


def extract_adr_number(title: str, filename: str) -> int | None:
    for text in (title, filename):
        m = ADR_NUM_RE.search(text)
        if m:
            return int(m.group(1))
    return None


def regenerate_decisions_index(concepts: list[tuple[Path, dict, str]]) -> None:
    active: list[tuple[int, str, str, str]] = []
    for path, fm, _ in concepts:
        rel = path.relative_to(MEMORY)
        if rel.parent.name != "decisions" or rel.name == "index.md":
            continue
        title = str(fm.get("title") or rel.stem)
        num = extract_adr_number(title, rel.name)
        if num is None:
            # Non-ADR decisions still list, sorted after numbered ones
            num = 10_000
        desc = str(fm.get("description") or "")
        active.append((num, title, rel.name, desc))

    lines = ["# Architectural Decisions", "", "> Auto-generated by /harness-sync. Sorted by ADR number.", ""]
    for num, title, link, desc in sorted(active, key=lambda e: (e[0], e[1].lower())):
        suffix = f" - {desc}" if desc else ""
        lines.append(f"* [{title}]({link}){suffix}")

    archive_dir = MEMORY / "decisions" / "archive"
    if archive_dir.is_dir():
        archived: list[tuple[int, str, str]] = []
        for md in sorted(archive_dir.glob("*.md")):
            text = md.read_text(encoding="utf-8")
            fm, _ = parse_frontmatter(text)
            title = str(fm.get("title") or md.stem)
            num = extract_adr_number(title, md.name) or 9999
            archived.append((num, title, f"archive/{md.name}"))
        if archived:
            lines.extend(["", "## Archived", ""])
            for num, title, link in sorted(archived, key=lambda e: e[0]):
                lines.append(f"* [{title}]({link})")

    (MEMORY / "decisions" / "index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def regenerate_indexes(concepts: list[tuple[Path, dict, str]]) -> None:
    regenerate_decisions_index(concepts)
    by_dir: dict[Path, list[tuple[str, str, str, str]]] = defaultdict(list)
    for path, fm, _ in concepts:
        rel = path.relative_to(MEMORY)
        if rel.parts[0] == "decisions" and rel.parent == Path("decisions"):
            continue  # decisions/index handled above
        title = str(fm.get("title") or rel.stem)
        desc = str(fm.get("description") or "")
        typ = str(fm.get("type") or "")
        link = rel.name
        by_dir[path.parent].append((typ, title, link, desc))

    for directory in sorted(by_dir, key=lambda p: len(p.relative_to(MEMORY).parts), reverse=True):
        entries = by_dir[directory]
        index_path = directory / "index.md"
        index_path.write_text(build_dir_index(entries), encoding="utf-8")

    features: list[tuple[str, str, str, str, str, str]] = []
    for path, fm, _ in concepts:
        rel_id = str(path.relative_to(MEMORY).with_suffix("")).replace("\\", "/")
        if not rel_id.startswith("features/") or "/archive/" in rel_id:
            continue
        depends = fm.get("depends_on", "")
        blocks = fm.get("blocks", "")
        if isinstance(depends, list):
            depends = ", ".join(depends)
        if isinstance(blocks, list):
            blocks = ", ".join(blocks)
        features.append(
            (
                str(fm.get("title") or path.stem),
                rel_id + ".md",
                str(fm.get("status") or ""),
                str(fm.get("priority") or ""),
                str(depends),
                str(blocks),
            )
        )

    est_tokens = estimate_inject_tokens()
    budget_ok = est_tokens < 500

    entry_points = [
        "* [Project Context](context/project.md) - stack, phase, key paths",
        "* [Session Progress](progress/status.md) - done / in-progress / next",
    ]
    if has_domains():
        entry_points.append(
            "* [Domain Maps](domains/index.md) - topic routers (read before all ADRs)"
        )
    entry_points.extend(
        [
            "* [Decision Index](decisions/index.md) - architectural choices",
            "* [Feature Index](features/index.md) - modular feature specs",
            "* [Failure Log](failures/log.md) - SRE failed hypotheses",
            "* [Memory Authority](meta/memory-authority.md) - challenge before overriding project truth",
            "* [SRE Routing](meta/sre-routing.md) - sre-architect path map",
            "* [Lazy Code Ladder](meta/lazy-code.md) - ponytail 7-rung write path",
            "* [Companion Skills](meta/companion-skills.md) - optional grilling + done-gate",
            "* [Ponytail Debt](meta/debt.md) - harvested `ponytail:` markers",
            "* [Graph View](viz.html) - interactive concept browser",
        ]
    )

    lines = [
        "# Knowledge Harness Index",
        "",
        "> Auto-generated by /harness-sync. Read this first.",
        "",
        "## Entry Points",
        "",
        *entry_points,
        "",
        "## Active Features",
        "",
        "| Feature | Status | Priority | Depends on | Blocks |",
        "|---------|--------|----------|------------|--------|",
    ]
    active_rows = 0
    for title, link, status, priority, depends, blocks in sorted(features, key=lambda x: x[0].lower()):
        if status.lower() not in ("in-progress", "planned"):
            continue
        lines.append(f"| [{title}]({link}) | {status} | {priority} | {depends} | {blocks} |")
        active_rows += 1
    if active_rows == 0:
        lines.append("| *(none yet)* | | | | |")

    lines.extend(
        [
            "",
            "## Token Budget",
            "",
            f"- Estimated injection size: ~{est_tokens} tokens",
            "- Budget: <500 tokens",
            f"- Status: {'✅ Under budget' if budget_ok else '⚠️ Over budget — run /memory-compact'}",
            "",
        ]
    )
    (MEMORY / "index.md").write_text("\n".join(lines), encoding="utf-8")


def append_log(changed: int) -> None:
    log_path = MEMORY / "log.md"
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry = f"- {ts} | harness-sync | regenerated index ({changed} concepts)\n"
    try:
        if log_path.exists():
            content = log_path.read_text(encoding="utf-8")
            if not content.startswith("# Update Log"):
                content = "# Update Log\n\n" + content
            content += entry
        else:
            content = "# Update Log\n\n" + entry
        log_path.write_text(content, encoding="utf-8")
    except OSError:
        # ponytail: log.md may be TCC-locked; sync still succeeds without append
        pass


def run_visualize() -> bool:
    venv_python = OKF_HOME / ".venv" / "bin" / "python"
    python = venv_python if venv_python.exists() else Path(sys.executable)
    staging = prepare_viz_staging()
    cmd = [
        str(python),
        "-m",
        "reference_agent",
        "visualize",
        "--bundle",
        str(staging),
        "--out",
        str(MEMORY / "viz.html"),
        "--name",
        "Knowledge Harness",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT), timeout=120)
        if result.returncode != 0:
            print(result.stderr or result.stdout, file=sys.stderr)
            return False
        print(result.stderr.strip() or f"Wrote {MEMORY / 'viz.html'}")
        return True
    except FileNotFoundError:
        print("WARN: OKF visualize skipped — set OKF_HOME to knowledge-catalog/okf", file=sys.stderr)
        return False


def run_graphify_update(skip: bool) -> bool:
    if skip:
        return False
    graph_json = ROOT / "graphify-out" / "graph.json"
    if not graph_json.exists():
        return False
    py_file = ROOT / "graphify-out" / ".graphify_python"
    python = py_file.read_text(encoding="utf-8").strip() if py_file.exists() else "python3"
    try:
        subprocess.run(
            [python, "-m", "graphify", "update", str(ROOT)],
            capture_output=True,
            text=True,
            timeout=300,
            cwd=str(ROOT),
        )
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync OKF .memory/ bundle")
    parser.add_argument("--skip-viz", action="store_true")
    parser.add_argument("--skip-graphify", action="store_true")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()

    if args.self_check:
        return _self_check()

    if not MEMORY.exists():
        print("ERROR: .memory/ not found", file=sys.stderr)
        return 1

    harvest_ponytail_debt()
    concepts = iter_concepts()
    cleanup_stray_files()
    wire_graph_links(concepts)
    concepts = iter_concepts()
    regenerate_indexes(concepts)
    append_log(len(concepts))

    viz_ok = False
    if not args.skip_viz:
        viz_ok = run_visualize()

    graph_ok = run_graphify_update(args.skip_graphify)

    print(f"Indexed {len(concepts)} concept(s)")
    print(f"  index.md → {MEMORY / 'index.md'}")
    print(f"  viz.html → {'OK' if viz_ok else 'skipped'}")
    print(f"  graphify → {'updated' if graph_ok else 'skipped'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
