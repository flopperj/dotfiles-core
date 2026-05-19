#!/usr/bin/env python3
"""Handoff read-half: auto-surface open handoff on session start.

Wired via SessionStart hook in ~/.claude/settings.json. Resolves project +
branch from git, looks up the handoff artifact, evaluates predicates within
bounds (per the handoff SKILL.md Section H), and prints the Section I
surface block to stdout. Claude Code captures stdout as session context.

Exits 0 silently on: not in a git repo, detached HEAD, no handoff file,
or malformed YAML (a stderr warning is emitted in the malformed case).
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

PREDICATE_TIMEOUT_SECONDS = 2
TASKS_ROOT = Path.home() / ".claude" / "tasks"


def read_hook_input() -> dict:
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, OSError):
        return {}


def resolve_git_context(cwd: str):
    try:
        toplevel = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd, capture_output=True, text=True, timeout=2, check=True,
        ).stdout.strip()
        branch = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=cwd, capture_output=True, text=True, timeout=2, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if not toplevel or not branch:
        return None
    return Path(toplevel).name, branch.replace("/", "-")


def evaluate_predicate(kind: str, predicate: str, cwd: str):
    if kind in ("goal-conditional", "untyped"):
        return "cannot-evaluate", f"{kind} — surface to user by design"
    stripped = (predicate or "").strip()
    if not stripped:
        return "cannot-evaluate", "empty predicate"
    if not (stripped.startswith("grep -q ") or stripped.startswith("grep -qF ")):
        return "cannot-evaluate", "predicate not a grep -q invocation; manual check"
    try:
        argv = shlex.split(stripped)
    except ValueError as exc:
        return "cannot-evaluate", f"shlex parse error: {exc}"
    if argv[0] != "grep":
        return "cannot-evaluate", "predicate not a grep invocation"
    try:
        result = subprocess.run(
            argv, cwd=cwd, capture_output=True, text=True,
            timeout=PREDICATE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return "cannot-evaluate", f"timeout after {PREDICATE_TIMEOUT_SECONDS}s"
    except (FileNotFoundError, OSError) as exc:
        return "cannot-evaluate", f"exec error: {exc}"
    if result.returncode == 0:
        return "holds", ""
    if result.returncode == 1:
        return "fails", "anchor moved or pattern no longer matches"
    return "cannot-evaluate", f"grep exit {result.returncode}: {result.stderr.strip()[:80]}"


def parse_handoff(path: Path):
    try:
        content = path.read_text()
    except OSError:
        return None
    if not content.startswith("---"):
        return None
    parts = content.split("---", 2)
    if len(parts) < 3:
        return None
    try:
        import yaml
    except ImportError:
        print(f"[handoff-read] pyyaml not available; cannot parse {path}", file=sys.stderr)
        return None
    try:
        return yaml.safe_load(parts[1]) or {}
    except yaml.YAMLError as exc:
        print(f"[handoff-read] malformed YAML in {path}: {exc}", file=sys.stderr)
        return None


def _first_line(text: str) -> str:
    text = (text or "").strip()
    return text.splitlines()[0] if text else ""


def format_surface_block(data, holds, shifts, cannot, path):
    task_key = data.get("task_key", "?")
    written = data.get("written", "?")
    intent = (data.get("intent") or "").strip() or "(none)"
    goal = (data.get("goal") or "").strip()
    lines = [
        f"Open handoff detected for {task_key} (written {written}).",
        "",
        "  Immediate next intent:",
    ]
    lines += [f"    {ln}" for ln in intent.splitlines()]
    lines += ["", "  Active goal:"]
    if goal:
        lines += [f"    {ln}" for ln in goal.splitlines()]
    else:
        lines.append("    (omitted; recoverable from PR/ticket)")
    lines.append("")
    if holds:
        lines.append("  Holding (these gate this session — do not re-try without a stated reason):")
        for r in holds:
            lines.append(f"    [{r.get('kind','?')}] {_first_line(r.get('claim',''))}")
        lines.append("")
    if shifts:
        lines.append("  Ground may have shifted (you may want to reconsider):")
        for r, note in shifts:
            lines.append(f"    [{r.get('kind','?')}] {_first_line(r.get('claim',''))}")
            lines.append(f"      reason: predicate failed — {note}")
        lines.append("")
    if cannot:
        lines.append("  Cannot evaluate (surface to user):")
        for r, note in cannot:
            lines.append(f"    [{r.get('kind','?')}] {_first_line(r.get('claim',''))}")
            lines.append(f"      reason: cannot-evaluate — {note}")
        lines.append("")
    lines.append(f"  -> Proceeding. To re-examine the handoff later, read {path}")
    return "\n".join(lines)


def main() -> int:
    hook_input = read_hook_input()
    cwd = hook_input.get("cwd") or os.getcwd()
    ctx = resolve_git_context(cwd)
    if ctx is None:
        return 0
    project, task_key = ctx
    handoff_path = TASKS_ROOT / project / "handoff" / f"{task_key}.md"
    if not handoff_path.is_file():
        return 0
    data = parse_handoff(handoff_path)
    if data is None:
        return 0
    holds, shifts, cannot = [], [], []
    for r in (data.get("rejections") or []):
        status, note = evaluate_predicate(r.get("kind", "untyped"), r.get("predicate", ""), cwd)
        if status == "holds":
            holds.append(r)
        elif status == "fails":
            shifts.append((r, note))
        else:
            cannot.append((r, note))
    print(format_surface_block(data, holds, shifts, cannot, handoff_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
