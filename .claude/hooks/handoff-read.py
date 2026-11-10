#!/usr/bin/env python3
"""Handoff read-half: auto-surface open handoff on session start.

Wired via SessionStart hook in ~/.claude/settings.json. Resolves project +
branch from git, looks up the handoff artifact, evaluates predicates within
bounds (per the handoff SKILL.md Section H), and prints the Section I
surface block to stdout. Claude Code captures stdout as session context.

Exits 0 silently on: not in a git repo, detached HEAD, or no handoff file.
Malformed frontmatter prints a one-line warning to stdout and exits 0.
The frontmatter is parsed in-process, so no third-party module is required.
Every git call and predicate shares one time budget that stays under the
5-second SessionStart hook timeout.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

PREDICATE_TIMEOUT_SECONDS = 2
GIT_TIMEOUT_SECONDS = 2
HOOK_BUDGET_SECONDS = 4.0
TASKS_ROOT = Path.home() / ".claude" / "tasks"
_DEADLINE = time.monotonic() + HOOK_BUDGET_SECONDS


def _budget(cap):
    return min(cap, _DEADLINE - time.monotonic())


def read_hook_input() -> dict:
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, OSError):
        return {}


class FrontmatterError(ValueError):
    pass


def _git(args, cwd):
    """stdout (stripped) on success; None on non-zero exit, timeout, spent budget or missing git."""
    timeout = _budget(GIT_TIMEOUT_SECONDS)
    if timeout <= 0:
        return None
    try:
        result = subprocess.run(
            ["git", *args], cwd=cwd, capture_output=True, text=True,
            timeout=timeout,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def resolve_project(cwd):
    """(project, legacy_project): legacy_project is the worktree folder name
    when cwd is a linked worktree, else None."""
    toplevel = _git(["rev-parse", "--show-toplevel"], cwd)
    if not toplevel:
        return None
    folder = Path(toplevel).name
    git_dir = _git(["rev-parse", "--path-format=absolute", "--git-dir"], cwd)
    common = _git(["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd)
    if not git_dir or not common or git_dir == common:
        return folder, None
    # A submodule's common dir sits under the superproject's .git/modules, so
    # its checkout is reached through core.worktree, not the parent directory.
    config = str(Path(common) / "config")
    core_worktree = _git(["config", "--file", config, "--get", "core.worktree"], cwd)
    if core_worktree:
        return (Path(common) / core_worktree).resolve().name, folder
    if _git(["config", "--file", config, "--bool", "--get", "core.bare"], cwd) == "true":
        name = Path(common).name
        return (name[:-4] if name.endswith(".git") and len(name) > 4 else name), folder
    return Path(common).parent.name, folder


def resolve_git_context(cwd: str):
    resolved = resolve_project(cwd)
    branch = _git(["branch", "--show-current"], cwd)
    if resolved is None or not branch:
        return None
    project, legacy = resolved
    return project, branch.replace("/", "-"), legacy


def working_tree_state(cwd):
    status = _git(["status", "--porcelain"], cwd)
    if status is None:
        return None
    uncommitted = sum(1 for ln in status.splitlines() if ln.strip())
    ahead = _git(["rev-list", "--count", "@{u}..HEAD"], cwd)
    unpushed = f"{ahead} unpushed commit(s)" if ahead and ahead.isdigit() else "no upstream"
    return f"{uncommitted} uncommitted file(s); {unpushed}"


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
    timeout = _budget(PREDICATE_TIMEOUT_SECONDS)
    if timeout <= 0:
        return "cannot-evaluate", "hook time budget spent"
    try:
        result = subprocess.run(
            argv, cwd=cwd, capture_output=True, text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        if timeout < PREDICATE_TIMEOUT_SECONDS:
            return "cannot-evaluate", "hook time budget spent"
        return "cannot-evaluate", f"timeout after {PREDICATE_TIMEOUT_SECONDS}s"
    except (FileNotFoundError, OSError) as exc:
        return "cannot-evaluate", f"exec error: {exc}"
    if result.returncode == 0:
        return "holds", ""
    if result.returncode == 1:
        return "fails", "anchor moved or pattern no longer matches"
    return "cannot-evaluate", f"grep exit {result.returncode}: {result.stderr.strip()[:80]}"


_KEY_RE = re.compile(r"^([A-Za-z0-9_.\-]+):(?:\s+(.*)|\s*)$")
_BLOCK_HEADERS = ("|", ">", "|-", ">-")


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _skippable(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith("#")


def _scalar(raw: str, lineno: int):
    text = raw.strip()
    if text in ("", "null", "~"):
        return None
    if text == "true":
        return True
    if text == "false":
        return False
    if text[0] in "[{&*":
        raise FrontmatterError(f"line {lineno}: unsupported flow collection or anchor")
    if text[0] == '"':
        if len(text) < 2 or text[-1] != '"':
            raise FrontmatterError(f"line {lineno}: unterminated double-quoted string")
        return re.sub(r'\\([\\"n])', lambda m: "\n" if m.group(1) == "n" else m.group(1), text[1:-1])
    if text[0] == "'":
        if len(text) < 2 or text[-1] != "'":
            raise FrontmatterError(f"line {lineno}: unterminated single-quoted string")
        return text[1:-1].replace("''", "'")
    return text


def _block_scalar(lines, i, header, parent_indent):
    """Collect a block scalar whose body is indented deeper than parent_indent."""
    body = []
    block_indent = None
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            body.append("")
            i += 1
            continue
        indent = _indent_of(line)
        if indent <= parent_indent:
            break
        if block_indent is None:
            block_indent = indent
        if indent < block_indent:
            break
        body.append(line[block_indent:])
        i += 1
    while body and body[-1] == "":
        body.pop()
    sep = "\n" if header.startswith("|") else " "
    text = sep.join(body)
    if not header.endswith("-") and body:
        text += "\n"
    return text, i


def _parse_pair(lines, i, rest, column):
    """Value for `key: rest` found on lines[i]; returns (value, next_index)."""
    rest = rest.strip()
    if rest in _BLOCK_HEADERS:
        return _block_scalar(lines, i + 1, rest, column)
    return _scalar(rest, i + 1), i + 1


def _check_indent(line: str, lineno: int) -> None:
    if "\t" in line[: len(line) - len(line.lstrip())]:
        raise FrontmatterError(f"line {lineno}: tab indentation is not supported")


def _parse_sequence(lines, i):
    dash_indent = _indent_of(lines[i])
    items = []
    while i < len(lines):
        line = lines[i]
        if _skippable(line):
            i += 1
            continue
        _check_indent(line, i + 1)
        indent = _indent_of(line)
        stripped = line.strip()
        if indent != dash_indent or not (stripped.startswith("- ") or stripped == "-"):
            break
        content = line[indent + 1:]
        body = content.lstrip(" ")
        key_col = indent + 1 + (len(content) - len(body))
        if not body:
            raise FrontmatterError(f"line {i + 1}: empty sequence item")
        match = _KEY_RE.match(body)
        if not match:
            items.append(_scalar(body, i + 1))
            i += 1
            continue
        item = {}
        value, i = _parse_pair(lines, i, match.group(2) or "", key_col)
        item[match.group(1)] = value
        while i < len(lines):
            nxt = lines[i]
            if _skippable(nxt):
                i += 1
                continue
            _check_indent(nxt, i + 1)
            if _indent_of(nxt) <= dash_indent:
                break
            pair = _KEY_RE.match(nxt.strip())
            if not pair:
                raise FrontmatterError(f"line {i + 1}: expected `key: value` inside a list item")
            value, i = _parse_pair(lines, i, pair.group(2) or "", _indent_of(nxt))
            item[pair.group(1)] = value
        items.append(item)
    return items, i


def parse_frontmatter(text: str) -> dict:
    """Parse the block-style YAML subset the handoff skill writes.

    Supported: top-level `key: scalar`, `key:` + block sequence of scalars or
    of mappings (`- key: value` with deeper-indented continuation keys),
    block scalars (`|`, `>`, `|-`, `>-`) at either level, quoted scalars,
    null/~/empty, true/false, `#` comment lines. Flow collections
    (`[a, b]`, `{a: b}`), anchors and multi-document files raise
    FrontmatterError, which the caller reports as malformed.
    """
    lines = text.splitlines()
    result = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if _skippable(line):
            i += 1
            continue
        _check_indent(line, i + 1)
        if _indent_of(line) != 0:
            raise FrontmatterError(f"line {i + 1}: unexpected indentation")
        match = _KEY_RE.match(line)
        if not match:
            raise FrontmatterError(f"line {i + 1}: expected `key: value`")
        key, rest = match.group(1), (match.group(2) or "").strip()
        if rest == "":
            j = i + 1
            while j < len(lines) and _skippable(lines[j]):
                j += 1
            if j < len(lines) and (lines[j].strip().startswith("- ") or lines[j].strip() == "-"):
                result[key], i = _parse_sequence(lines, j)
            else:
                result[key], i = None, i + 1
            continue
        result[key], i = _parse_pair(lines, i, rest, 0)
    return result


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
        return parse_frontmatter(parts[1])
    except FrontmatterError as exc:
        print(f"Handoff file at {path} is malformed; skipping. Inspect manually. ({exc})")
        return None


def _first_line(text: str) -> str:
    text = str(text or "").strip()
    return text.splitlines()[0] if text else ""


def _render_refs(refs):
    lines = ["  Refs:"]
    for ref in refs:
        if isinstance(ref, dict):
            kind, value = ref.get("kind") or "ref", ref.get("value")
        else:
            kind, value = "ref", ref
        if value is None:
            continue
        lines.append(f"    [{kind}] {value}")
    lines.append("")
    return lines


def _render_in_flight(items):
    lines = ["  In flight at handoff (restart to resume):"]
    for item in items:
        if not isinstance(item, dict):
            item = {"what": item}
        state = "left running" if item.get("stopped") is False else "stopped"
        head = f"    {item.get('what') or '(unnamed)'} — {state}"
        if item.get("cwd"):
            head += f"; cwd {item['cwd']}"
        lines.append(head)
        if item.get("restart"):
            lines.append(f"      restart: {item['restart']}")
        brief = _first_line(item.get("brief"))
        if brief:
            lines.append(f"      brief: {brief} (full brief in the handoff file)")
    lines.append("")
    return lines


def format_surface_block(data, holds, shifts, cannot, path, tree_state):
    task_key = data.get("task_key", "?")
    written = data.get("written", "?")
    intent = (data.get("intent") or "").strip() or "(none)"
    goal = (data.get("goal") or "").strip()
    lines = [
        f"Open handoff detected for {task_key} (written {written}).",
    ]
    if tree_state is not None:
        lines.append(f"  Working tree: {tree_state}")
    lines += ["", "  Immediate next intent:"]
    lines += [f"    {ln}" for ln in intent.splitlines()]
    lines += ["", "  Active goal:"]
    if goal:
        lines += [f"    {ln}" for ln in goal.splitlines()]
    else:
        lines.append("    (omitted; recoverable from PR/ticket)")
    lines.append("")
    if data.get("refs"):
        lines += _render_refs(data["refs"])
    if data.get("in_flight"):
        lines += _render_in_flight(data["in_flight"])
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
    project, task_key, legacy = ctx
    handoff_path = TASKS_ROOT / project / "handoff" / f"{task_key}.md"
    if not handoff_path.is_file():
        legacy_path = TASKS_ROOT / legacy / "handoff" / f"{task_key}.md" if legacy else None
        if legacy_path is not None and legacy_path.is_file():
            print(
                f'Handoff for {task_key} found under legacy project key "{legacy}" '
                f"at {legacy_path}; move it to {handoff_path} to surface it here."
            )
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
    tree_state = working_tree_state(cwd)
    if tree_state is None:
        print("[handoff-read] working tree state unavailable", file=sys.stderr)
    print(format_surface_block(data, holds, shifts, cannot, handoff_path, tree_state))
    return 0


if __name__ == "__main__":
    sys.exit(main())
