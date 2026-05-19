---
name: handoff
description: "Park the current session for a fresh one — capture the failure trail (typed rejections + next intent) so the next session resumes with full context. Use when the user types /handoff, says 'park this session', wants to 'park work for a fresh session', or asks to 'hand off this task' or 'checkpoint this session'."
user-invocable: true
---

## Overview

Two halves of equal importance. The **write half** (user-invocable) captures the failure trail — typed rejections with re-verification predicates and an immediate next intent — and writes them to a branch-scoped artifact. The **read half** (session-start auto-detect) reads that artifact on the next session for the same branch, evaluates each rejection's predicate, and surfaces the results before any agent dispatch.

Branch name is the universal task key. The artifact survives a context boundary without duplicating signal that `git` already provides.

---

## A. Resolve project and task-key

Resolve `<project>` as:

```
basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

Resolve `<task-key>` as the current branch name:

```
git branch --show-current
```

Slug-safe the branch name by replacing `/` with `-`.

If either git call fails (no git repo), or if the branch is empty or detached HEAD, abort with:

```
Cannot write a handoff: no git branch resolvable. Run from inside a git repo on a named branch.
```

---

## B. Storage path

```
~/.claude/tasks/<project>/handoff/<task-key>.md
```

Create the `handoff/` subdirectory if it does not exist. Permissions inherit from the user umask. One handoff per task-key at any moment.

---

## C. Pre-queue meta-lesson filter

Before any rejection enters the typed queue, apply this filter for each item the user wants to record:

Ask: *"Is there a specific artifact this rejects against, or is this a meta-lesson about how to approach problems in general?"*

- If **meta** — route to `~/.claude/tasks/<project>/lessons.md` using the existing Signs format (`~/.claude/_shared/lessons-signs-format.md`). Do not enqueue in the handoff queue. Show the routing decision to the user so they can override.
- If **specific** — continue to the rejection-collection loop below.

The user sees the routing decision and can override it.

---

## D. Write flow

### Step 1 — Verify git state

Resolve `<project>` and `<task-key>` (Section A). Abort cleanly on failure.

### Step 2 — Check for an existing handoff

Check the target path (Section B). If a file already exists, present three options:

- `append` — add new rejections to the existing list
- `overwrite` — replace the artifact entirely (warn that prior content will be lost)
- `abort` — stop without writing

### Step 3 — Immediate next intent

Prompt for **immediate next intent** — one short statement. Required; do not proceed without it.

### Step 4 — Active goal

Prompt for **active goal** — optional. If the user says "skip" or "trivially recoverable from PR", omit this field from the artifact.

### Step 5 — Rejection-collection loop

For each rejection the user wants to record:

1. Apply the **pre-queue meta-lesson filter** (Section C). If meta → route to `lessons.md`, do not enqueue.
2. Apply the **classification tie-break rule** (Section F): when the rejection cites *selection criteria* as a soft preference ("smaller is preferred"), default to `goal-conditional`. When expressed as a hard invariant ("must not exceed K files"), default to `structural`.
3. Type-tag the rejection as one of: `structural | contractual | empirical-local | empirical-external | goal-conditional | untyped`. The `untyped` kind is the pressure valve when classification genuinely fails; warn if `untyped > 1/3` of the total.
4. Author the `predicate` field per the predicate grammar (Section E). Must be non-empty.
5. Author the `anchor` field (the concrete artifact the predicate checks against — a file path, function signature, dependency name+version, etc.). Must be non-empty.
6. Author the `fallback` field — default: `"drop and surface to user"`.
7. Run the **write-time validator** (Section G): predicate non-empty, kind recognized, anchor non-empty, untyped-fraction check. Warn on findings; do not block.

### Step 6 — Approval gate

Render the proposed handoff artifact in full. Gate on user approval:

- `y` — accept and write
- `e` — edit a field
- `x` — abort without writing

### Step 7 — Atomic write

On approval, write the artifact atomically: write to `<task-key>.md.tmp`, then rename to `<task-key>.md`. This prevents a half-written artifact from being read by a concurrent session.

### Step 8 — Paired obligation (optional)

Offer to create a **paired obligation** that watches the branch/PR for external motion. The user opts in explicitly. If yes, invoke the existing obligations create flow with a sensible default (`gh_query` on the PR if one exists, otherwise a time-based reminder).

### Step 9 — Completion summary and auto-clear

Print:

```
Handoff written: ~/.claude/tasks/<project>/handoff/<task-key>.md (N rejections, intent captured).
```

After the approval gate has succeeded and the artifact (and optional obligation) are written, emit this final directive to the user:

```
Run `/clear` to start a fresh session — the handoff will surface automatically on the next session for this branch.
```

The skill does **not** silently invoke `/clear`. It instructs the user with a single, unambiguous final line. The clear happens only after the approval gate — this is the gate-before-clear safety property.

---

## E. Predicate grammar

Six rejection kinds form a closed enumeration. Each kind has an anchor (what is checked against), a predicate shape (what a writable predicate looks like for that kind), and example predicates.

| # | Kind | Anchor | Predicate shape | Example predicates |
|---|---|---|---|---|
| 1 | **structural** | A type, invariant, or schema declaration at a specific file:line | `"<invariant statement> still holds in <anchor-path>"` | `"grep -q 'final class Foo' src/Foo.php"` ; `"the Bar interface still exposes execute(): void at lib/Bar.ts"` |
| 2 | **contractual** | A function signature, API spec, or interface declaration | `"<signature> unchanged at <anchor>"` | `"grep -qF 'function render(Context $ctx): string' src/Renderer.php"` ; `"the GET /v1/items endpoint still accepts &filter[status] per docs/api.md"` |
| 3 | **empirical-local** | A specific file's behavior at a location (test outcome, observable output, error string) | `"<observable> at <anchor> still <expected>"` | `"grep -q 'throws NullPointerException' tests/RendererTest.php"` ; `"the line 'preview returns null' in CampaignPreviewController.php:142 is still present"` |
| 4 | **empirical-external** | A dependency at a pinned version, or an external service contract | `"<dep> still at version <V>"` or `"<external-system> still <contract>"` | `"grep -q '\"react\": \"18\\.' package.json"` ; `"composer.lock pins guzzlehttp/guzzle to 7.5.x"` |
| 5 | **goal-conditional** | The user's stated goal at write-time | `"user still wants <P>"` | `"user still prefers the smaller blast-radius approach"` ; `"user still wants to avoid touching the legacy Foo subsystem"` |
| 6 | **untyped** | None — the producer could not classify | `"<freeform claim>"` | `"approach X felt wrong but I can't articulate why"` |

**Goal-conditional predicates always evaluate to `cannot-evaluate` automatically** — they exist so the next session asks the user before assuming. Untyped predicates are always surfaced as `cannot-evaluate`.

**Tie-break rule:**

- Selection-criteria rejections expressed as **soft preferences** ("smaller blast radius is preferred", "fewer files is better") → `goal-conditional`.
- Selection-criteria rejections expressed as **hard invariants** ("blast radius must not exceed K files", "no new dependencies allowed") → `structural`.
- When in doubt, prefer `goal-conditional` — it surfaces to the user instead of silently gating.

**Low-information predicate flag:**

A predicate that is trivially always-true (literal `true`, or a tautology) is flagged at write time with `low_info: true` in the rejection's YAML record. The evaluator still runs it, but the read half does not let it gate the session — shown as "noted but not gating" in the surface block.

---

## F. Validator rules

Each rule is a **warning** that surfaces to the user during the write flow, not a blocking error.

1. **Predicate non-empty** — every rejection must have a non-empty `predicate:` field. Empty → warn: *"Rejection {N} has no predicate. It will be marked cannot-evaluate on every read and surfaced unconditionally. Recommend authoring one."*

2. **Kind in closed enumeration** — `kind:` must be one of the six valid values. Unrecognized kind → warn and offer to re-classify. If user insists, force-coerce to `untyped`.

3. **Anchor non-empty** — `anchor:` must be non-empty. Empty → warn: *"Rejection {N} has no anchor. The evaluator has no idea what to check against. Recommend authoring one (e.g., a file path, a function signature, a dependency name+version)."*

4. **Untyped overflow** — if `untyped / total > 1/3`, warn: *"{X} of {Y} rejections are untyped. That's a signal the closed enumeration isn't matching what you're trying to capture. Consider re-classifying."*

5. **Low-information predicate flag** — if a predicate is trivially always-true (e.g., literal `true`, or `"user still wants improvements"`), mark the rejection with an internal `low_info: true` field. The read half shows it as "noted but not gating."

---

## G. Read half — session-start auto-trigger

The read half is **not** user-invocable. It runs at session start (including after `/clear`), before any user message is processed, via the `SessionStart` hook in `~/.claude/settings.json`.

**Trigger:** On every new session, resolve `<project>` and `<task-key>` via the same git convention as the write half (Section A), then check `~/.claude/tasks/<project>/handoff/<task-key>.md`. If present, run the read flow (Section H) and prepend the surfaced result to the first agent response.

**Implementation:** [`.claude/hooks/handoff-read.py`](../../hooks/handoff-read.py), installed by `install.sh` as a symlink at `~/.claude/hooks/handoff-read.py`. The script reads the JSON hook payload from stdin (for `cwd`), executes the read flow, and prints the Section I surface block to stdout — Claude Code captures stdout as session context.

**Required `~/.claude/settings.json` entry.** Overlays may ship this in their `.claude/settings.json.template` for fresh-install convenience, but `lib-mcp-config.sh` only copies the template when `~/.claude/settings.json` does not already exist, so pre-existing installs (including any overlay's main user) must add the block manually:

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "startup|resume|clear",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/hooks/handoff-read.py",
          "timeout": 5
        }
      ]
    }
  ]
}
```

The matcher deliberately omits `compact` — surfacing a handoff mid-task is intrusive. The script no-ops silently when not in a git repo, on detached HEAD, or when no handoff file exists for the current branch.

---

## H. Read flow

### Step 1 — Resolve project and task-key

Use Section A. If either fails (not in a git repo, detached HEAD), **no-op silently**. Detached HEAD is treated the same as no branch.

### Step 2 — Parse the handoff file

Read the handoff file. Parse the YAML frontmatter. If parse fails → surface a warning:

```
Handoff file at <path> is malformed; skipping. Inspect manually.
```

Continue with no gating set.

### Step 3 — Evaluate predicates (bounded)

For each rejection in the frontmatter `rejections:` list, evaluate the predicate with these bounds:

- **Time budget**: 2 seconds per predicate. If exceeded → `cannot-evaluate`.
- **Tool budget**: at most 1 file read, 1 grep, or 1 `gh`/`git` shell call per predicate. If a predicate requires more → `cannot-evaluate`.
- Predicates that require running tests, building, or executing arbitrary code → `cannot-evaluate` immediately.
- `goal-conditional` predicates → always `cannot-evaluate` (surface to user by design).
- `untyped` predicates → always `cannot-evaluate`.

### Step 4 — Partition the rejection list

- `holds` — predicate evaluated true. Added to the gating set for the new session.
- `fails` — predicate evaluated false (the anchor moved). Dropped from the gating set; surfaced as "ground may have shifted."
- `cannot-evaluate` — predicate could not be evaluated within budget, was `goal-conditional`, or was `untyped`. Dropped from the gating set; surfaced to the user.

### Step 5 — Surface block

Print the following before any agent response (Section I for format).

---

## I. Surface block format

```
Open handoff detected for <task-key> (written <timestamp>).

  Immediate next intent:
    <intent>

  Active goal:
    <goal — or "(omitted; recoverable from PR/ticket)">

  Holding (these gate this session — do not re-try without a stated reason):
    [<kind>] <claim>
    [<kind>] <claim>
    ... (N holding)

  Ground may have shifted (you may want to reconsider):
    [<kind>] <claim>
      reason: predicate failed — <one-line evaluator note>
    [<kind>] <claim>
      reason: cannot-evaluate — <one-line: timeout / out-of-budget / untyped>
    ... (M surfaced)

  -> Proceeding. To re-examine the handoff later, read ~/.claude/tasks/<project>/handoff/<task-key>.md
```

---

## J. Lifecycle and cleanup

After the read half runs, the artifact is **not** auto-deleted. It persists across subsequent sessions on the same branch until the user explicitly closes it via `/handoff close`.

### `/handoff close` sub-command

Marks the handoff as resolved by renaming:

```
<task-key>.md  →  <task-key>.md.closed-<timestamp>
```

This preserves the audit trail in the same directory. No new content is authored.

Deletion on branch deletion is **not** automated in v1.

---

## K. Artifact schema

The handoff file is Markdown with YAML frontmatter. The frontmatter holds the machine-readable fields; the Markdown body is reserved for narrative scratch (not consumed by the evaluator).

```yaml
---
task_key: <branch-slug>
project: <project>
written: <ISO 8601 timestamp>
intent: <immediate next intent>
goal: <active goal or null>
rejections:
  - kind: structural
    claim: <claim text>
    anchor: <file path or identifier>
    predicate: <grep -q '...' path/to/file>
    fallback: drop and surface to user
  - kind: goal-conditional
    claim: <claim text>
    anchor: null
    predicate: user still wants <P>
    fallback: drop and surface to user
---

<!-- Narrative scratch — not consumed by the evaluator -->
```
