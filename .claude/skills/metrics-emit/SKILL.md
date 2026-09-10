---
name: metrics-emit
description: "Library skill defining the metrics event schema and emit conventions. Not user-invocable. Referenced by pipeline skills that emit structured metrics to ~/.claude/tasks/<project>/metrics.jsonl."
user-invocable: false
---

# Metrics Emit — Library Skill

This is a **library skill** — not user-invocable. Pipeline skills (ticket-pickup,
ticket-swarm, cyrus-tdd-engineer) reference this skill for the canonical event
format, emit instructions, and hard rules.

---

## Metrics file location

```
~/.claude/tasks/<project>/metrics.jsonl
```

`<project>` is the `basename` of the git repo root (per CLAUDE.md § Task Artifact
Location). `emit-metric.sh` resolves this automatically.

**Known limitation (v1):** POSIX append is atomic for small writes, but concurrent
parallel agents emitting simultaneously can interleave lines. This is accepted for
v1 (single-user local tooling) — do not attempt line-level locking. If `jq -s`
fails to parse a line in the file, skip that line in analysis.

---

## How to emit

Pipe a JSON object to `emit-metric.sh`:

```bash
echo '{
  "event_type": "ticket_classified",
  "agent": "ticket-pickup",
  "project": "'"$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"'",
  "ticket": "PROJ-1234",
  "data": { ... }
}' | bash ~/.claude/evals/scripts/emit-metric.sh
```

`timestamp` is optional — the script injects it if absent. Always emit via the
script rather than appending directly, so timestamp injection and path resolution
are centralised.

---

## Event type catalog

### `ticket_classified`

Emitted by **ticket-pickup** after the classification gate resolves.

```json
{
  "timestamp": "2026-04-21T10:00:00Z",
  "event_type": "ticket_classified",
  "agent": "ticket-pickup",
  "project": "my-repo",
  "ticket": "PROJ-1234",
  "data": {
    "classification": "Medium",
    "pipeline": "optimus-cyrus",
    "enrichment_sources": ["jira", "codebase", "gh"],
    "override": null
  }
}
```

`override` values: `null` (no change), `"simplified"` (user chose `s`),
`"escalated"` (user chose `e`).

---

### `pipeline_complete`

Emitted by **ticket-pickup** (orchestration duration) and **cyrus-tdd-engineer**
(implementation duration). Both emit this type — the `agent` field distinguishes
them. Swarm-retro can use either depending on the question being answered.

```json
{
  "timestamp": "2026-04-21T10:15:00Z",
  "event_type": "pipeline_complete",
  "agent": "cyrus-tdd-engineer",
  "project": "my-repo",
  "ticket": "PROJ-1234",
  "data": {
    "classification": "Medium",
    "pipeline": "optimus-cyrus",
    "duration_seconds": 840,
    "tests_passed": true,
    "coverage_percent": 87.5,
    "ci_fix_attempts": 0,
    "first_pass": true,
    "files_changed": 3,
    "outcome": "implemented"
  }
}
```

**Terminal outcomes.** `outcome` is one of:

- `implemented` (default when absent) — the pipeline produced code and a
  branch; `tests_passed` and `first_pass` are booleans.
- `advisory` — the pipeline ended deliberately with no code change because the
  correct answer was not a code change: Aristotle's Phase 0 "wrong tool"
  verdict, or a Move that explicitly states no code changes are needed. This
  is a **success**, not a blocker. Emit `tests_passed: null`,
  `first_pass: null`, `ci_fix_attempts: 0`, `files_changed: 0`, and put the
  one-line verdict in `advisory_reason`. Consumers exclude advisory events
  from the first-pass denominator and count them separately.

A pipeline that stopped because something went wrong (test failure, blocker,
truncation) is neither — it does not emit `pipeline_complete` at all; the
swarm records it as blocked.

**Required data fields:** `first_pass` and `classification` must always be
present (`first_pass` is `null` only when `outcome` is `advisory`). `first_pass` is derived as `tests_passed && ci_fix_attempts == 0`
unless the emitter has better information (e.g. a retry that predates CI).
`classification` is `null` on direct invocations (no ticket-pickup in the
chain) — emit the key with `null`, don't omit it. Consumers (agent-stats)
derive `first_pass` from `tests_passed`/`ci_fix_attempts` for legacy events
that lack the field, but new emitters must not rely on that fallback.

---

### `agent_truncated`

Emitted by **pipeline skills** (aristotle-deconstructor, optimus-planner, cyrus-tdd-engineer, scout-reviewer, ranger-reviewer) when a reasoning subagent's final response is missing the `<<task-complete>>` sentinel — i.e. suspected `maxTurns` truncation. See `~/.claude/_shared/agent-turn-cap-warning.md` for the detection rule and halt/skip behavior.

```json
{
  "timestamp": "2026-05-27T10:00:00Z",
  "event_type": "agent_truncated",
  "agent": "cyrus-tdd-engineer",
  "project": "my-repo",
  "ticket": "PROJ-1234",
  "data": {
    "max_turns": 100,
    "detection": "missing_completion_sentinel",
    "context": "swarm",
    "parent_skill": "ticket-swarm"
  }
}
```

`context` values: `swarm` (called from ticket-swarm), `pipeline` (called from a non-swarm skill chain), `standalone` (called directly without a parent skill). `parent_skill` is optional.

---

### `swarm_complete`

Emitted by **ticket-swarm** after the run log is written.

```json
{
  "timestamp": "2026-04-21T11:00:00Z",
  "event_type": "swarm_complete",
  "agent": "ticket-swarm",
  "project": "my-repo",
  "run_id": "2026-04-21-001",
  "data": {
    "tickets_total": 5,
    "completed": 4,
    "advisory": 0,
    "blocked": 1,
    "prs_created": 4,
    "duration_seconds": 3600,
    "first_pass_rate": 0.75,
    "agents_spawned": 11
  }
}
```

`completed` counts tickets that produced a PR. `advisory` counts tickets whose
pipeline ended with a correct no-code answer (see `pipeline_complete` →
`outcome: advisory`). `first_pass_rate` is (completed on first attempt) /
(`tickets_total` − `advisory`), so an advisory outcome neither helps nor
hurts the rate. `completed + advisory + blocked == tickets_total`.

---

### `multi_repo_split`

Emitted by **ticket-pickup** (Step 3.5) on BOTH paths of multi-repo detection —
after the gate resolves and on notice-only detection. Uses `ticket` (the parent
key), not `run_id` — the split is a per-ticket fact. Named consumers: agent-stats
(counts split by `mode` and `gate_choice`) and swarm-retro's quantitative step.

```json
{
  "timestamp": "2026-08-25T10:00:00Z",
  "event_type": "multi_repo_split",
  "agent": "ticket-pickup",
  "project": "my-repo",
  "ticket": "PROJ-1234",
  "data": {
    "mode": "gate",
    "repos_detected": ["my-repo", "other-repo", "legacy-api"],
    "repos_resolved": ["my-repo", "other-repo"],
    "repos_unresolved": ["legacy-api"],
    "gate_choice": "split",
    "subtask_keys": ["PROJ-1235", "PROJ-1236"],
    "proposed_order": ["other-repo", "my-repo"],
    "final_order": ["other-repo", "my-repo"]
  }
}
```

`mode` values: `gate` (resolution evidence existed, the split gate was shown),
`notice` (signals detected but no registry / no resolution evidence /
corroboration-only — the false-positive denominator). `gate_choice` values:
`split`, `reorder`, `only`, `single`, `cancel`, or `null` — null iff `mode` is
`notice`, and `subtask_keys` / `final_order` are empty arrays then. Gate menu
mapping: the `order N,M` keypress maps to `gate_choice: "reorder"`; `x` maps
to `"cancel"`. On `cancel`/`only`/`single` emit `final_order` equal to
`proposed_order` (no reorder happened) — `final_order` differs from
`proposed_order` only on `reorder`.

---

## Hard rules

### Fail open — never block a pipeline on metrics

If `emit-metric.sh` is missing, if `jq` is absent, if the disk is full, if
permissions deny the write — log the failure to stderr and **continue**. Metrics
are best-effort instrumentation. A pipeline blocked on a metric emit is a worse
outcome than missing a data point.

```bash
echo '{...}' | bash ~/.claude/evals/scripts/emit-metric.sh || true
```

The `|| true` is the minimum safeguard. Skills may also wrap in a subshell:

```bash
(echo '{...}' | bash ~/.claude/evals/scripts/emit-metric.sh) 2>/dev/null || true
```

### No preemptive instrumentation

Only add emit hooks to a skill when there is a **named consumer** that will read
the data. Writing data nobody reads violates Truth #6 (complexity justified only
when simpler approaches are proven insufficient). The v1 consumer is swarm-retro's
quantitative analysis step (Step 2g). Other skills (scout, ranger, code-auditor,
pr-create-from-commits) are not instrumented until a specific quantitative question
requires their data.

---

## `jq` dependency note

`emit-metric.sh` works without `jq` by skipping validation and using bash
parameter expansion for best-effort timestamp injection. Full validation
(required field checks, JSON structure verification) requires `jq`.

Install: `brew install jq` (macOS) or `apt install jq` (Linux).

Without `jq`, malformed JSON can be appended to `metrics.jsonl`. The file is
best-effort — swarm-retro's Step 2g skips unparseable lines gracefully.

---

## Disable mechanism (briefing nudge)

To silence the session-start `/briefing` nudge permanently:

```bash
touch ~/.cursor/.no-briefing-nudge
```

To re-enable:

```bash
rm ~/.cursor/.no-briefing-nudge
```

The cooldown sentinel (`~/.cursor/.last-briefing-ts`) resets automatically when it
becomes 4+ hours stale — no manual intervention needed.

---

## Schema reference

Full JSON Schema: `~/.claude/evals/schemas/metrics-event.schema.json`

The `event_type` enum is deliberately minimal for v1. Future emit points
(`review_complete`, `pr_created`, `eval_run`) extend it when they ship with a
named consumer.
