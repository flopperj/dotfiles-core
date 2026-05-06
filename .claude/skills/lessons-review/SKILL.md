---
name: lessons-review
description: "Surface all lessons.md entries across every project in one place so cross-project patterns are visible. Use when the user types /lessons-review, asks 'what have I learned across projects', 'show me my lessons', 'are there patterns across my projects', or wants to promote a recurring lesson to system-wide guidance."
user-invocable: true
---

# Lessons Review — Cross-Project Pattern Surfacing

Read every `~/.claude/tasks/<project>/lessons.md`, group entries by project, and present them so the user can spot patterns that recur across projects. When a pattern is real, the user can promote it to `~/.claude/_shared/cross-project-lessons.md` — a curated, durable layer that survives individual project memory.

## When to Use

- The user types `/lessons-review`.
- The user asks: "what have I learned across projects?", "show me my lessons", "are there patterns across my projects?", or any cross-project retrospective question.
- A scheduled job wants to surface accumulated lessons periodically (e.g., monthly).
- The user remembers learning something about a tool but doesn't recall which project.

## What This Skill Is Not

- Not an automatic pattern miner. With small N (a few projects, a few entries each), automatic similarity detection is mostly noise. The user is a far better pattern detector than a heuristic at this scale. The skill *surfaces*; the user *recognizes*.
- Not an auto-promoter. Promotions to `~/.claude/_shared/cross-project-lessons.md` happen only on explicit user approval. Anything written to `_shared/` is loaded into every future agent context, so the bar is high.
- Not a lessons editor. Per-project edits go in the per-project `lessons.md`. This skill reads, indexes, and offers promotion — it does not rewrite the per-project files.

## Workflow

### Step 1: Discover all lessons.md files

```bash
find ~/.claude/tasks -name 'lessons.md' -type f 2>/dev/null
```

Each path encodes the project: `~/.claude/tasks/<project>/lessons.md`.

If no files are found:

```
No lessons.md files exist yet under ~/.claude/tasks/.

Lessons are written by agents (and you) when corrections happen during a
session. The Signs format lives at ~/.claude/_shared/lessons-signs-format.md.

Start a project pipeline (Cyrus, ticket-pickup, ticket-swarm) and after
your first correction, a lesson will appear.
```

Stop. There's nothing to review.

### Step 2: Read and parse

Read every file. Each lesson follows the Signs format defined in `~/.claude/_shared/lessons-signs-format.md`:

```
### YYYY-MM-DD — <one-line summary>

- **Trigger:** ...
- **Do:** ...
- **Why:** ...
```

If a file deviates from the Signs format (e.g., free-form prose left over from older sessions), include it in the output but flag it: *"⚠ this entry is not in Signs format — consider re-shaping at next correction"*. Do not rewrite it unilaterally.

### Step 3: Render the cross-project view

Output structure:

```
# Lessons Review

Found N lessons across M projects.

## By Project

### <project-1> (k lessons)

- YYYY-MM-DD — <summary>
  Trigger: <first 80 chars>...
- ...

### <project-2> (k lessons)

...

## Cross-project recurrence (visual scan)

Group lessons by topic affinity — files touched, tools mentioned, or trigger
keywords (e.g., "husky", "node version", "migration", "pre-push", "CI",
"flag"). Use loose grouping; the goal is to make patterns visible to the
user, not to be definitive.

If no obvious cross-project pattern exists, say so:

> No obvious cross-project pattern visible. Lessons appear project-specific
> right now. Re-run after more sessions accumulate.

## Already-promoted patterns

If `~/.claude/_shared/cross-project-lessons.md` exists, list its entries here
verbatim under "Currently promoted". Confirms they are still loaded into
agent contexts.
```

### Step 4: Offer promotion (only if a pattern exists)

If — and only if — the user names a pattern they want promoted, or if the cross-project view obviously shows the same Trigger/Do recurring across ≥2 projects, offer promotion:

```
The following pattern recurs across <project-1> and <project-2>:

  Trigger: <merged trigger>
  Do:      <merged action>
  Why:     <merged root cause>

Promote to ~/.claude/_shared/cross-project-lessons.md? This file is loaded
into every agent context, so the bar is high.

  -> y  = Promote (append to cross-project-lessons.md)
  -> n  = Not yet
  -> e  = Edit the merged entry first
```

**Rules for promotion:**

1. **Only the user approves.** Never write to `~/.claude/_shared/cross-project-lessons.md` without explicit "yes."
2. **Append, never overwrite.** New promotions go to the end of the file, dated.
3. **Preserve the Signs format.** Even when merging two project entries, the result is one Trigger / Do / Why entry, not a free-form paragraph.
4. **Cite source projects.** Add a `**Source:** <project-1>, <project-2>` line under Why so future readers know where the pattern came from.
5. **Do not modify the source `lessons.md` files.** The per-project lesson stays where it was; promotion adds a curated layer above, not a deletion of the source.
6. **Cap promotions.** If `cross-project-lessons.md` exceeds 30 entries or 200 lines, prompt the user to retire stale ones rather than continuing to grow. The file is loaded into every agent context — size matters.

### Step 5: If `cross-project-lessons.md` does not exist yet

On first promotion, create the file with this header:

```markdown
# Cross-Project Lessons

Curated patterns that recur across multiple projects. Each entry is in the
Signs format (see ~/.claude/_shared/lessons-signs-format.md).

This file is loaded into every agent context. Promotion is gated by user
approval via /lessons-review. Direct edits are allowed but should be rare —
the discipline of cross-project recurrence is what gives entries their
weight.

---

```

Then append the first entry below the `---`.

## Failure Modes

| Scenario | Behavior |
|---|---|
| `~/.claude/tasks/` does not exist | Step 1 reports cleanly, no error. |
| Some `lessons.md` files are empty | Treated as zero entries for that project. |
| Some entries are malformed | Surface with ⚠ flag; never rewrite. |
| User asks for promotion but no clear pattern exists | Decline politely: "I don't see enough recurrence across projects to promote with confidence yet." |
| Promotion fails (write error to `_shared/`) | Surface the error verbatim. Do not retry or guess. |

## Why This Design (Not Auto-Promotion)

Earlier proposals had this skill auto-detect similar lessons via string similarity and promote them on a quarterly schedule. That design has two problems with current data:

1. **Sample size is too small.** Auto-detection with 2-3 projects produces noise, not signal. The user reading two columns is faster and more accurate.
2. **Promotion writes to `_shared/`, which is loaded into every future agent prompt.** A bad promotion contaminates every future session. The cost of a false-positive promotion is high enough that explicit human approval is the right gate even when N grows.

If the user later wants automatic surfacing of recurrent patterns (rather than promotion — *surfacing* is safe), the skill can be extended with a `--auto-detect` mode that flags likely recurrences. That extension stays *non-promoting* — the human gate is structural, not transitional.

## Responsibility Boundaries

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
<!-- EXTRA_ROWS: lessons-review -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Lessons Review** | Surface all per-project lessons in one view; gate promotion to cross-project-lessons.md on user approval | Auto-promote, modify per-project lessons, rewrite malformed entries, write to role-guards or AGENTS.md |
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->
