---
name: agent-stats
description: "Aggregate metrics.jsonl from all projects into a system-level summary of agent pipeline health: first-pass success rate, classification distribution, swarm outcomes, and health flags. Use when the user types /agent-stats, asks 'how is the agent pipeline doing', 'show me agent metrics', 'is Cyrus first-passing?', or wants to evaluate the system rather than a single ticket."
user-invocable: true
---

# Agent Stats — System-Level Pipeline Health

Render a summary of agent pipeline health from `~/.claude/tasks/<project>/metrics.jsonl` files. The aggregation is read-only — no metrics are modified, no events are emitted.

This skill answers questions a staff/principal engineer asks about the *system*, not about a single run:

- What is Cyrus's first-pass success rate?
- How often does Optimus's plan need a CI-fix retry?
- What does the classification distribution look like — am I escalating too often?
- Are swarm runs converging or stalling?

## When to Use

- The user types `/agent-stats`.
- The user asks "how is the agent pipeline doing?", "show me agent metrics", "is Cyrus first-passing?", "what's our first-pass rate?", or any system-level question that single-ticket views cannot answer.
- A briefing or scheduled job wants to surface a weekly health snapshot.

## What It Is Not

- Not a per-ticket view (use `/swarm-retro` for run-level analysis).
- Not a real-time monitor — it reads the on-disk `metrics.jsonl`, which is updated by emitters at pipeline completion.
- Not a writer — it never modifies metrics, never promotes lessons, never opens PRs.

## Workflow

### Step 1: Resolve scope

Parse the user's invocation for filters:

| User says | Args |
|---|---|
| `/agent-stats` (no args) | All projects, last 30 days |
| `/agent-stats --project <name>` | One project, last 30 days |
| `/agent-stats --days 7` | All projects, last 7 days |
| "agent stats for the last week" | All projects, `--days 7` |
| "how is dotfiles doing" | `--project dotfiles`, default 30 days |

If the user names a project that does not match a directory under `~/.claude/tasks/`, run anyway — the script will report "no events in window" cleanly.

### Step 2: Run the aggregator

Invoke the script:

```bash
bash "$(readlink ~/.claude/skills/agent-stats)/../../../scripts/agent-stats.sh" [--project <name>] [--days <N>]
```

The script lives at `scripts/agent-stats.sh` in the dotfiles-core repo, which is not itself symlinked into `~/.claude/` — resolving through this skill's own symlink locates it regardless of where the repo is checked out.

The script's output is plain text designed to be copy-pasted as-is. Do not reformat it. Do not summarize it. Display the raw output.

### Step 3: Add interpretation, only if signal warrants it

After the raw output, add a short interpretation **only when there is something the numbers don't say outright**:

- **If the script raised health flags**: name the most likely cause based on what the user has been working on recently. Example: "First-pass rate dropped — your last 3 swarm runs were on the auth-rewrite branch, which is the most architecturally novel work this month."
- **If sample size is small**: say it once, then stop. Don't editorialize on noisy data.
- **If first-pass rate is high (≥85%) and stable**: a one-liner acknowledging it. Healthy systems deserve a sentence too.

If the numbers speak for themselves, do not add interpretation. The script's output is sufficient.

### Step 4: Suggest one next step (optional)

Only if a flag is actionable, suggest exactly one next command:

| Flag | Suggested next step |
|---|---|
| First-pass rate <60% on Medium tickets | "Type: Retro, analyze my last swarm" — find which classifications are misrouting |
| CI fix attempts > pipeline count | "Type: Cyrus, audit the last 3 failed CI runs" — surface the recurring failure |
| No events in window | "Type: Pickup PROJ-NNNN" — start a pipeline to populate metrics |

Never suggest more than one. The user is reading a dashboard, not running a triage.

## Failure Modes

| Scenario | Behavior |
|---|---|
| `jq` not installed | Script exits 0 with a one-line warning. Surface the warning verbatim. |
| `~/.claude/tasks/` does not exist | Script prints onboarding text. Surface verbatim. |
| Metrics file exists but is empty | Treated as "no events in window". Surface verbatim. |
| Schema drift (events missing required fields) | jq filters skip them silently. The dashboard shows fewer events than were on disk; this is acceptable for a dashboard, not for the schema validator (which is `emit-metric.sh`'s job, not this skill's). |

## Schema Reference

This skill consumes events defined in `~/.claude/evals/schemas/metrics-event.schema.json`. The three event types it reads:

- `pipeline_complete` — emitted by `cyrus-tdd-engineer` and `ticket-pickup`. Contributes to first-pass and CI-fix metrics.
- `ticket_classified` — emitted by `ticket-pickup` after the classification gate. Contributes to classification distribution.
- `swarm_complete` — emitted by `ticket-swarm` at run end. Contributes to swarm outcomes.

If a new event type is added to the schema, this skill will silently ignore it until the script is updated. That is intentional — the dashboard prefers stability over completeness.

## Responsibility Boundaries

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
<!-- EXTRA_ROWS: agent-stats -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Agent Stats** | Aggregate metrics.jsonl files into a read-only summary; surface health flags | Modify metrics, emit events, promote lessons, open PRs, run pipelines |
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->
