---
name: swarm-retro
description: "Analyze completed swarm runs for misclassifications, blocker patterns, and improvement opportunities. Use when the user types /swarm-retro, starts a prompt with 'Retro', or asks to 'analyze my last swarm', 'review swarm results', 'what went wrong in the swarm', or 'improve swarm accuracy'. Reads run logs from ~/.claude/tasks/<project>/swarm-runs/, identifies patterns, and promotes stable learnings to agent memory."
user-invocable: true
---

# Swarm Retro

Analyze completed swarm runs to find misclassifications, recurring blockers,
and patterns worth learning from. Bridge raw run logs to durable patterns
in agent memory.

---

## Responsibility boundaries

Swarm Retro is an **analyst** — it reads logs, identifies patterns, and
proposes improvements. It never modifies code, tickets, or PRs.

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
<!-- EXTRA_ROWS: swarm-retro -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Swarm Retro** | Analyze run logs, detect misclassifications, propose heuristic updates, promote patterns to agent memory | Write code, modify tickets, create PRs, launch pipelines, perform reviews |
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->

---

## Step 1: Locate run logs

Check for swarm run logs in `~/.claude/tasks/<project>/swarm-runs/`
(see CLAUDE.md § Task Artifact Location for how to resolve `<project>`):

- If the user specifies a run ID (e.g., "Retro, analyze run 2026-04-10-001"),
  read that specific log file.
- If the user says "last swarm" or "my latest run", find the most recent
  `.md` file in `~/.claude/tasks/<project>/swarm-runs/` by timestamp.
- If no run logs exist, inform the user:
  ```
  No swarm run logs found in ~/.claude/tasks/<project>/swarm-runs/.
  Run a ticket-swarm first — it writes a structured log at completion.
  ```

Read the full run log. The expected format is:

```markdown
# Swarm Run: {timestamp}-{run-id}

## Config
- Source: JQL harvest | child_tickets ({parent-key})
- Tickets: N
- Domains: Backend (N), Frontend (N), Infra (N)

## Tickets
| Key | Classification | Pipeline | Domain | Reviewer | Status | Duration | Retries |
|-----|---------------|----------|--------|----------|--------|----------|---------|
| ... | ... | ... | ... | ... | ... | ... | ... |

## Blockers
- {ticket}: {description} (retry N: {outcome})

## Sequencing
- {domain}: {sequence description}

## Smart Recovery Actions
- {ticket}: {action taken} (outcome: {result})

## Summary
- Launched: N | Completed: N | Blocked: N
- PRs: N | Time: Nm | Agents: N
```

---

## Step 2: Analyze the run

Evaluate the run log across six dimensions:

### 2a. Misclassification detection

Compare the initial classification against the actual outcome:

- **Under-classified** (should have been escalated):
  - Ticket classified Simple but blocked or required retries
  - Ticket classified Medium but Cyrus hit architectural blockers
  - Signs: retries > 0, status = BLOCKED, duration >> average for that tier

- **Over-classified** (wasted resources):
  - Ticket classified Complex but completed quickly with no issues
  - Best-of-N where both attempts produced nearly identical results
  - Signs: duration << average for Complex, Ranger found 0 issues, both
    attempts had same files changed

Present findings:
```
Misclassifications detected: 2

  PROJ-1003 (classified: Simple, actual: Medium)
    Evidence: Blocked on test failure, needed retry. 4m duration (avg Simple: 1.5m).
    Suggestion: Tickets touching MC/Billing should default to Medium.

  PROJ-1015 (classified: Complex, actual: Medium)
    Evidence: Completed in 5m (avg Complex: 11m). Ranger found 0 issues.
    Both best-of-N attempts identical. Aristotle analysis was unnecessary.
    Suggestion: Single-file race condition fixes may not need Aristotle.
```

### 2b. Blocker pattern analysis

Examine all blockers and retries:

- **Flaky tests**: Failures in tests not modified by the pipeline that
  succeeded on retry. Track test names for agent memory.
- **Real failures**: Failures in modified code — these are genuine bugs
  the pipeline produced. Track which complexity tiers produce them.
- **Dependency failures**: Failures caused by missing output from another
  ticket. Track whether the team lead's sequencing caught it or missed it.
- **Environment failures**: Timeouts, MCP failures, resource exhaustion.

### 2c. Retry effectiveness

For each retry:
- Did the retry succeed? (If yes, likely flaky test or transient issue)
- Did the retry fail identically? (Suggests a real code issue)
- Was the retry preceded by auto-resequencing? (Team lead's smart recovery)

### 2d. Team lead accuracy

- Were dependency sequences correct? Any merge conflicts despite sequencing?
- Were there missed dependencies (auto-resequenced during execution)?
- Were any tickets in the wrong domain cluster?

### 2e. Reviewer signal quality

- Did Scout/Ranger catch real issues or was every review clean?
- For complex tickets: did Ranger identify issues that Scout likely
  would have missed? (Justifies the Opus cost)
- Were there reviewer false positives that delayed PR creation?
- For medium tickets: did the code auditor route to the right reviewer?
  (Under-routing: auditor sent to Scout but Scout found blockers that
  Ranger confirmed. Over-routing: auditor sent to Ranger but Ranger
  found 0 issues.)

### 2f. Timing analysis

- Which pipeline stages were bottlenecks? (Aristotle, Optimus, Cyrus, review)
- Average duration per complexity tier
- Total wall-clock time vs sum of individual durations (parallelism efficiency)

### 2g. Quantitative trend analysis

If `~/.claude/tasks/<project>/metrics.jsonl` exists and contains events,
compute the following from ALL events in the file (not just the current run):

**First-pass rate trend:**
- Filter `pipeline_complete` events. Group by ISO week.
- For each week: count where `first_pass == true` / total. Report as percentage.
- Show last 4 weeks (or as many as exist). Highlight direction: improving / stable / declining.

**Duration percentiles by classification:**
- Filter `pipeline_complete` events. Group by `data.classification`.
- Compute P50 and P90 duration_seconds for each classification tier.
- Compare against the current run's durations: flag outliers (> P90).

**Classification accuracy:**
- Join `ticket_classified` and `pipeline_complete` events by `ticket` field.
- A classification is "accurate" if the ticket completed without rework,
  blocker, or escalation override.
- Report: accurate / total, with the most common misclassification pattern.

**Swarm-level trends:**
- Filter `swarm_complete` events. Show last 3-5 runs.
- Track: tickets_total, first_pass_rate, duration trend.

Present as a compact trend table in the retro summary (Step 3):

```
Quantitative trends (from metrics.jsonl, N events):

  First-pass rate (last 4 weeks):
    Week 15: 75% (3/4)  Week 16: 80% (4/5)  Week 17: 100% (2/2)  Week 18: —

  Duration P50/P90 by tier:
    Simple:  45s / 120s    (this run: 52s — normal)
    Medium:  240s / 480s   (this run: 610s — above P90 ⚠️)
    Complex: 600s / 1200s  (no data this run)

  Classification accuracy: 85% (17/20 accurate)
    Most common miss: Simple → needed retry (3 cases)
```

**Graceful degradation:**
- If metrics.jsonl does not exist: skip this section silently. Don't report
  its absence — the qualitative analysis from Steps 2a-2f is sufficient.
- If metrics.jsonl exists but has < 5 events: show raw counts only, skip
  percentiles and trends (too little data for meaningful statistics).
- If a field is missing from an event (e.g. old events before an emit hook
  was added): skip that event for that computation, don't fail.

---

## Step 3: Present retro summary

Show the structured analysis to the user:

```
Swarm Retro: {run-id}

  Run stats: {N} tickets, {N} completed, {N} blocked, {time}

  Misclassifications: {N}
    [list with evidence and suggestions]

  Blocker patterns: {N} blockers across {N} tickets
    - Flaky tests: {N} (auto-retried: {N} succeeded)
    - Real failures: {N}
    - Dependency misses: {N} (auto-resequenced: {N})

  Team lead accuracy: {assessment}
    [list any missed dependencies or wrong domain assignments]

  Reviewer signal: {assessment}
    - Scout reviews: {N} clean, {N} with issues
    - Ranger reviews: {N} clean, {N} with issues
    - Ranger justified: {yes/no — did it find things Scout wouldn't?}
    - Auditor routing: {N} medium tickets audited
      - Routed to Scout: {N}, Routed to Ranger: {N}
      - Routing justified: {yes/no — did code complexity match the route?}

  Timing:
    - Fastest: {ticket} ({time}, {complexity})
    - Slowest: {ticket} ({time}, {complexity})
    - Bottleneck stage: {stage}
    - Parallelism efficiency: {wall-clock} / {sum of durations} = {ratio}

  Quantitative trends: {present if metrics.jsonl has data, absent otherwise}
    [trend table from Step 2g]
```

---

## Step 4: Propose heuristic updates

Based on the analysis, propose concrete updates to ticket-pickup's
classification logic:

```
Proposed heuristic updates:

  1. [CLASSIFICATION] Tickets mentioning "RefundProcessor" or touching
     app/lib/MC/Billing/ should default to Medium (not Simple).
     Evidence: 2 of 3 Simple tickets in this area blocked.

  2. [CLASSIFICATION] Single-file fixes for known race conditions can
     stay Medium (skip Aristotle) if the fix pattern is well-established.
     Evidence: PROJ-1015 over-classified, both best-of-N identical.

  3. [FLAKY TEST] MC_CampaignTest::testPreviewTimeout is flaky.
     Evidence: Failed on first attempt, succeeded on retry. No code changes.
     Action: Add to known flaky test list in agent memory.

  -> approve all = Save all proposed updates to agent memory
  -> approve 1,3 = Save specific updates (comma-separated)
  -> edit N      = Modify a proposal before saving
  -> x           = Discard (no memory updates)
```

Wait for user approval before writing to agent memory.

---

## Step 5: Promote to agent memory (if approved)

For approved heuristic updates, write to
`~/.claude/agent-memory/ticket-swarm/classification-heuristics.md`:

```markdown
# Classification Heuristics (learned from swarm retros)

## Component-based overrides
- Tickets touching app/lib/MC/Billing/ → default Medium (learned: 2026-04-10)

## Known flaky tests
- MC_CampaignTest::testPreviewTimeout (learned: 2026-04-10)

## Complexity calibration
- Single-file race condition fixes with known patterns → Medium not Complex (learned: 2026-04-10)
```

If the file already exists, merge new heuristics with existing ones.
Remove any heuristics the user explicitly asks to forget.

Ticket-pickup and team-lead should check this file (if it exists) during
their classification and failure analysis steps.

---

## Plan Archive Analysis (optional)

If `~/.claude/tasks/<project>/plans/archive/` contains plans:

1. Scan archived plans and filter to those with `status: completed` in
   frontmatter (skip `abandoned` plans which have no execution notes).
2. Read the Execution Notes sections from recent completed plans.
3. Look for patterns:
   - Steps that frequently hit blockers (indicates planning gaps)
   - Sections that were consistently skipped (indicates over-templating)
   - Deviations from plan (indicates estimation issues)
4. Propose improvements to Optimus's planning methodology if patterns
   are strong enough (3+ occurrences).
5. With user approval, update `~/.claude/agent-memory/optimus-planner/`
   with the findings.

---

## Gate rules

- **Read-only analysis.** Swarm Retro never modifies code, tickets, or PRs.
- **User approves memory updates.** Heuristic promotions to agent memory
  require explicit approval.
- **Evidence-based proposals.** Every proposed heuristic must cite specific
  tickets and outcomes from the run log.
- **No run log = no retro.** If no logs exist, direct the user to run a
  swarm first.

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
