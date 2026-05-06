---
name: ticket-swarm
description: "Batch-process Jira tickets with parallel agent pipelines. Use when the user types /ticket-swarm, starts a prompt with 'Swarm', or asks to 'fix my bugs', 'swarm my tickets', 'batch fix bugs', 'process my bug queue', or 'swarm this story'. Harvests tickets from Jira (or receives child tickets from ticket-pickup), triages in parallel, groups by domain with team leads, spawns isolated pipelines per ticket, and gates on PR creation only."
user-invocable: true
---

# Ticket Swarm

Harvest a batch of Jira tickets, triage them in parallel, group by domain
with team leads, spawn isolated pipelines per ticket, and produce PRs with
minimal human gating.

This skill orchestrates: **Jira -> Ticket Pickup (batch) -> Parallel
Pipelines -> Code Auditor/Scout/Ranger Review -> PR Creation** with two human gates: triage
approval and PR approval.

---

## Responsibility boundaries

Ticket Swarm is a **batch orchestrator**. It composes existing skills — it
never does their jobs.

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
<!-- EXTRA_ROWS: ticket-swarm,ticket-pickup -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Ticket Swarm** | Batch harvest, triage, domain grouping, team-lead dispatch, progress monitoring, PR gating | Write code, produce plans, perform strategic analysis, review PRs, enrich individual tickets |
| **Ticket Pickup** | Fetch ticket, enrich with codebase context, classify complexity, route to pipeline | Write code, produce plans, perform strategic analysis, review PRs |
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->

---

## Execution modes

Ticket Swarm supports two special modes in addition to the standard flow:

- **`dry_run`** — run harvest, triage, and domain grouping but stop before
  launching any pipelines. Presents the full analysis of what *would* happen.
  Triggered by "Swarm, dry-run my bugs" or `dry_run: true`.
- **`mock_tickets`** — when combined with `dry_run: true`, accepts a list of
  mock ticket data instead of querying Jira. Useful for testing classification
  heuristics and domain grouping without MCP dependencies.
  Format: `[{key, summary, type, description, files_hint}, ...]`
  where `files_hint` is a list of file paths that replaces codebase search.

---

## Step 1: Harvest tickets

Ticket Swarm accepts tickets from three sources:

### Source A: Child tickets from ticket-pickup (Story decomposition)

If `child_tickets` is provided by the caller (e.g., ticket-pickup detected
a Story and delegated its sub-tasks), skip JQL harvest entirely. Use the
provided ticket list directly and proceed to Step 2.

The `parent_story_key` is also passed for Jira comment context.

### Source C: Mock tickets (dry-run testing only)

If `mock_tickets` is provided alongside `dry_run: true`, skip all Jira
operations. Use the mock data directly:
- `key` and `summary` populate the triage table
- `type` determines issue type handling
- `description` is used for classification
- `files_hint` replaces codebase search in enrichment (list of file paths
  the ticket is expected to touch)

Proceed to Step 2 with mock data.

### Source B: JQL harvest from Jira (default)

Parse the user's input to build a JQL query:

- **Default** ("Swarm, fix my bugs" or similar): Use
  `assignee = currentUser() AND type in (Bug, Task, Sub-task) AND status in ("To Do", "Open") ORDER BY priority ASC, created ASC`
- **Custom JQL**: If the user provides JQL, use it directly.
- **Project filter**: "Swarm PROJ bugs" ->
  `project = "PROJ" AND assignee = currentUser() AND type in (Bug, Task) AND status in ("To Do", "Open") ORDER BY priority ASC`
- **Priority filter**: "Swarm P1 bugs" ->
  `assignee = currentUser() AND type = Bug AND priority = "Highest" AND status in ("To Do", "Open")`
- **Limit**: Default to 10 tickets max. User can override ("Swarm, fix my
  top 5 bugs").

**Primary: Atlassian MCP plugin** (`plugin-atlassian-atlassian`):
```
searchJiraIssuesUsingJql(
  jql=<constructed_query>,
  fields=["summary", "description", "status", "priority", "components", "labels", "assignee", "issuetype"],
  maxResults=<limit>
)
```

<!-- BEGIN OVERLAY-FRAGMENT: ticket-swarm-jira-fallback -->
<!-- END OVERLAY-FRAGMENT: ticket-swarm-jira-fallback -->

If no tickets are found, inform the user and suggest broadening the query.

If Jira is unavailable, show `⚠️ Jira unavailable — provide ticket keys
manually (comma-separated)` and wait for input.

---

## Step 2: Parallel triage

For each harvested ticket, run the `ticket-pickup` skill's enrichment and
classification steps (Steps 2-4) in parallel using explore subagents.

Launch one explore subagent per ticket (up to 5 concurrent). Each subagent:
1. Fetches full ticket context via `getJiraIssue`
2. Searches the codebase for references (stack traces, error messages, classes)
3. Classifies complexity (Simple / Medium / Complex)

**Subagent failure handling:** If a triage subagent fails or returns
empty, log the failure and continue with remaining tickets. If >50% of
triage agents fail, abort triage and report. Follow CLAUDE.md error
handling defaults.

Aggregate results into a ranked table.

---

## Step 3: Present triage table and gate

Present the batch to the user:

```
Ticket Swarm: N tickets ready

#  Ticket      Priority  Complexity  Summary                        Pipeline
1  PROJ-1001   P1        Simple      NPE in RefundProcessor         Cyrus direct
2  PROJ-998    P2        Medium      Campaign preview 404s          Optimus -> Cyrus
3  PROJ-1015   P1        Complex     Auth token race condition      Aristotle -> Optimus -> Cyrus
4  PROJ-1020   P3        Simple      Typo in error message          Cyrus direct
5  PROJ-1003   P2        Medium      Flag check missing             Optimus -> Cyrus

  -> all  = Launch all pipelines
  -> 1,3  = Launch specific tickets (comma-separated)
  -> r    = Re-triage with additional context
  -> e N  = Escalate ticket N (bump complexity one level)
  -> s N  = Simplify ticket N (drop complexity one level)
  -> x    = Cancel
```

**This is Gate 1** — the user must approve which tickets to swarm. Wait for
explicit input. Do not proceed without approval.

---

## Step 3.5: Group into domains and assign team leads

After the user approves the triage table, group the approved tickets by
domain based on their codebase references from enrichment:

- **Backend**: References in `app/controllers/`, `app/lib/`, `app/models/`,
  `tests_phpunit/`
- **Frontend**: References in `web/js/src/`, `web/css/`, frontend test files
- **Infra/Cross-Boundary**: References span both backend and frontend, or
  touch `proto/`, `config/`, `data/schemas/`, or cross-service boundaries
- **Unknown**: No codebase references found — falls back to Jira component
  field, or groups with the largest existing cluster

If a ticket touches both backend and frontend, it goes to Infra.

Present the grouping:

```
Domain Assignments:

  Backend Lead (3 tickets):
    PROJ-1001 (Simple) -> PROJ-1003 (Medium)  [sequenced: shared file]
    PROJ-1007 (Simple)                         [independent]

  Frontend Lead (2 tickets):
    PROJ-998 (Medium), PROJ-1020 (Simple)      [independent, parallel]

  Infra Lead (1 ticket):
    PROJ-1015 (Complex)                        [best-of-N]
```

**In gated mode:** Show the grouping and let the user adjust (move tickets
between domains, override sequencing).

**In autonomous mode:** Auto-approve the grouping. If domain classification
is ambiguous for a ticket, assign it to Infra (the most cautious domain).

### Cross-domain overlap check

Before dispatching to team leads, scan across all domain clusters for
shared file references:

1. Collect all codebase reference paths from every enriched ticket
2. If any file appears in tickets assigned to different domain clusters:
   - Move the dependent tickets into the same cluster as the ticket that
     owns the primary file (prefer the cluster with more tickets touching it)
   - Or flag the overlap to the user and ask which cluster should own it
3. This prevents parallel team leads from producing conflicting changes
   to the same file

### Launch team leads

Launch one `team-lead` subagent per domain cluster. Each receives:
- The cluster of enriched tickets with their classifications
- The domain tag
- `swarm_mode: true`, `execution_mode: autonomous`
- `parent_story_key` if this swarm originated from a Story decomposition

Team leads handle dependency detection, domain context injection, and
within-cluster sequencing internally. They report progress back to this
orchestrator.

**If a team-lead subagent fails:** Log the failure, mark that domain
cluster as blocked, and continue with other clusters. Surface the
failure to the user.

### Dry-run stop point

If `dry_run: true`, stop here. Do not launch team leads or pipelines.
Instead, present the full analysis:

```
Dry Run Complete: N tickets analyzed

  Domain Assignments:
    Backend Lead (3 tickets):
      PROJ-1001 (Simple) -> PROJ-1003 (Medium)  [sequenced: shared file]
      PROJ-1007 (Simple)                         [independent]
    Frontend Lead (1 ticket):
      PROJ-1020 (Simple)                         [independent]
    Infra Lead (1 ticket):
      PROJ-1015 (Complex, best-of-2)             [Ranger review]

  Estimated pipelines: 6 (5 tickets + 1 best-of-N extra)
  Estimated agents: ~11
  Reviewer breakdown: 2 Scout, 2 Auditor, 2 Ranger

  No pipelines launched. Use "Swarm, fix my bugs" to execute.
```

No Jira transitions, no branches, no code changes. Pure analysis.
Return without proceeding to Step 4.

---

## Step 4: Monitor team-lead pipelines

Team leads manage the actual pipeline dispatch within their clusters.
Ticket Swarm monitors their progress and aggregates results.

For each approved ticket, the team lead spawns an isolated pipeline:

### Branch and worktree setup

Each ticket gets its own branch. Before launching any pipeline:

1. **Determine the branch name**: `{ticket-key}-{slug}` (e.g.,
   `PROJ-1001-fix-refund-npe`). Slugify from the ticket summary.

2. **Check for a pre-existing branch**: Run
   `git branch --list "*{ticket-key}*"`. If a matching branch already
   exists (user pre-created it), use it instead of creating a new one.
   Ensure it is up to date with the default branch.

3. **Create the branch** if no match found. Use the `newbranch` shell
   alias if available (from `.aliases.local`):
   `newbranch {ticket-key}-{slug}`. This handles default branch
   detection (queries `origin/HEAD`, supports any branch name), checkout,
   `git pull origin`, and new branch creation automatically.

   **Fallback** if `newbranch` is not available: detect the default
   branch via `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
   (fall back to `main` then `master` via `git show-ref`), then:
   `git checkout {default} && git pull origin {default} && git checkout -b {ticket-key}-{slug}`

4. If using `best-of-n-runner` subagent type, the worktree isolation is
   handled automatically by the runner. Each attempt still gets its own
   branch suffix (`-attempt-1`, `-attempt-2`).

### Dispatch by complexity

**Simple tickets (Cyrus direct):**
Launch one `cyrus-tdd-engineer` subagent per ticket. Pass:
- The enriched ticket brief
- Jira ticket key
- Branch name
- `swarm_mode: true`
- `execution_mode: autonomous`
- `ticket_complexity: simple`

**Medium tickets (Optimus -> Cyrus):**
Launch one `optimus-planner` subagent per ticket. Pass:
- The enriched ticket brief as the problem statement
- Jira ticket key
- Branch name
- `swarm_mode: true`
- `execution_mode: autonomous`
- `ticket_complexity: medium`

The Optimus skill auto-approves the Cyrus handoff in autonomous mode.
Forwards `ticket_complexity` to Cyrus.

**Complex tickets (Aristotle -> Optimus -> Cyrus):**
Launch using `best-of-n-runner` subagent type with 2 parallel attempts.
Each attempt runs the full `aristotle-deconstructor` pipeline. Pass:
- The enriched ticket brief
- Jira ticket key
- Branch name (each attempt gets a suffix: `-attempt-1`, `-attempt-2`)
- `swarm_mode: true`
- `execution_mode: autonomous`
- `ticket_complexity: complex`

The best attempt is selected based on:
1. All tests pass (hard requirement)
2. Fewer files changed (prefer minimal fix)
3. Higher test coverage
4. Cleaner Ranger review (fewer issues flagged)

**Note:** Complex tickets use Ranger (Opus) for review instead of Scout.
The `ticket_complexity: complex` flag is passed through to Cyrus, which
auto-triggers Ranger on completion. Best-of-N comparison also uses Ranger
to evaluate trade-offs between attempts.

### Parallelism limits

- Launch up to **3 pipelines concurrently** to avoid overwhelming resources.
- Queue remaining tickets and launch as slots free up.
- Simple tickets are fastest — prioritize launching them first to free slots.

**Note:** These concurrency limits are guidelines for the orchestrator,
not hard enforcement. The actual parallelism depends on the Agent/Task
tool's behavior in the current environment. The orchestrator should
respect these as targets and adjust based on observed performance.

---

## Step 4.5: Transition Jira tickets (MANDATORY)

You **MUST** transition each launched ticket to "In Progress" **IMMEDIATELY**
after pipeline launch. Do not defer this to later steps. Do not skip it.

For each ticket:
1. Call `getTransitionsForJiraIssue` to find the "In Progress" transition ID
2. Call `transitionJiraIssue` with the transition ID
3. Add a comment: `🤖 Swarm pipeline launched. Complexity: {classification}. Branch: {branch-name}.`

**Verify:** After all transitions, confirm each ticket's status changed by
checking the response. If a transition fails (no valid transition, Jira
unavailable), log the failure but do not block the pipeline.

This step is **not optional**. The user expects ticket status to reflect
pipeline activity in real time.

---

## Step 5: Monitor and report progress

As team leads report wave completions, maintain a live progress dashboard:

```
Swarm Progress: 3/5 complete

PROJ-1001  [DONE]     PR #482 — Scout: approved, awaiting user review
PROJ-998   [DONE]     PR #483 — Auditor->Scout: 1 issue, awaiting resolution
PROJ-1015  [RUNNING]  Aristotle complete, Optimus planning... (attempt 1/2, Ranger review)
PROJ-1020  [DONE]     PR #484 — Scout: approved, awaiting user review
PROJ-1003  [BLOCKED]  Cyrus hit a test failure — needs input

  -> review N  = Review PR for ticket N
  -> retry N   = Re-run pipeline for ticket N
  -> abort N   = Cancel pipeline for ticket N
  -> status    = Refresh progress
```

### Handling blockers

When a pipeline reports a blocker:
1. Surface the blocker immediately with context (error message, failing test,
   file conflict).
2. Offer options: retry, provide context, skip, or abort.
3. Other pipelines continue independently — a blocker on one ticket does not
   hold the rest.

### Handling best-of-N completion (complex tickets)

When both attempts complete:
1. Run Ranger review on each attempt's branch (complex tickets always use
   Ranger for staff-level analysis).
2. Compare: test results, files changed, Ranger findings, merge readiness.
3. Recommend the better attempt. Present comparison:
   ```
   PROJ-1015: Best-of-2 complete (reviewed by Ranger)

   Attempt 1: 4 files changed, 12 tests, coverage 87%, Ranger: READY, 0 issues
   Attempt 2: 6 files changed, 15 tests, coverage 91%, Ranger: NEEDS CHANGES, 1 issue

   Recommendation: Attempt 1 (fewer changes, clean staff-level review)

     -> 1 = Use attempt 1
     -> 2 = Use attempt 2
     -> x = Discard both
   ```
4. Wait for user choice on complex tickets. This is not auto-approved.

---

## Step 6: PR creation gate

**This is Gate 2** — the final checkpoint before PRs are created.

For each completed pipeline:
1. The appropriate reviewer runs automatically (Scout for simple, code auditor for medium,
   Ranger for complex — triggered by Cyrus completion in autonomous mode).
2. If the reviewer passes (no blocking issues): the ticket is **approved** for PR creation.
3. If the reviewer finds blocking issues: the ticket is **held** for resolution.

**In autonomous mode:** Auto-create draft PRs for all approved tickets (reviewer
passed with no blocking issues). Do NOT wait for user input on approved tickets.
For held tickets (reviewer found blocking issues), surface the issues and wait
for user direction. After all auto-created PRs complete, show the summary:

```
PR creation complete (autonomous): 3 created, 1 held

#  Ticket      Branch                     PR        Status
1  PROJ-1001   PROJ-1001-fix-refund-npe   #201      Draft created
2  PROJ-1020   PROJ-1020-fix-error-typo   #202      Draft created
3  PROJ-1015   PROJ-1015-fix-race-cond    #203      Draft created
4  PROJ-998    PROJ-998-fix-preview-404   —         HELD: 1 blocking issue

Held tickets:
  PROJ-998: Scout found 1 blocking issue — potential SQL injection in query builder
  -> fix 4  = Address reviewer issues and retry
  -> skip 4 = Skip PR creation for this ticket
```

**In gated mode:** Present completed tickets for batch PR approval and wait
for user input before creating any PRs:

```
Ready for PR creation: 3 tickets

#  Ticket      Branch                     Reviewer  Status        Files
1  PROJ-1001   PROJ-1001-fix-refund-npe   Scout     Approved      2
2  PROJ-1020   PROJ-1020-fix-error-typo   Scout     Approved      1
3  PROJ-1015   PROJ-1015-fix-race-cond    Ranger    READY         4
4  PROJ-998    PROJ-998-fix-preview-404   Auditor->Scout     1 minor issue 3

  -> all    = Create PRs for all approved tickets
  -> 1,2,3  = Create PRs for specific tickets (comma-separated)
  -> fix 4  = Address reviewer issues on ticket 4 first
  -> x      = Skip PR creation
```

**MANDATORY: Use `/pr-create-from-commits` for ALL PR creation.**
NEVER use raw `gh pr create`, `gh api`, or manual PR construction.
For each approved ticket, invoke the `/pr-create-from-commits` skill.
PRs are created as **drafts by default**. Only create non-draft PRs if the
user explicitly says "open for review" or "create ready PRs".
The skill handles:
- Draft PR creation (`gh pr create --draft`)
- PR template detection (repo-specific templates)
- Jira status transition
- PR body population from code analysis

Invoke the skill once per ticket. Do not batch — each ticket's PR needs
its own skill invocation with the correct branch checked out.

---

## Step 7: Jira cleanup

After all pipelines complete (or are aborted):

For each ticket with a created PR:
- Transition to "In Review" if available.
- Add comment: `🤖 Fix submitted: PR #{number}. Branch: {branch-name}. Pipeline: {classification}.`

For blocked/aborted tickets:
- Add comment: `🤖 Swarm pipeline did not complete. Reason: {reason}. Manual investigation needed.`
- Leave status unchanged.

---

## Final summary

When the swarm is complete, present a final report:

```
Ticket Swarm Complete

  Launched:   5 tickets
  Completed:  4 (3 PRs created, 1 awaiting review)
  Blocked:    1 (PROJ-1003 — test failure, needs manual fix)

  PRs created:
    - PROJ-1001: PR #482 (approved)
    - PROJ-998:  PR #483 (approved)
    - PROJ-1020: PR #484 (approved)

  Time: ~12 minutes | Agents spawned: 9
```

---

## Step 8: Write run log

After the final summary is presented, write a structured run log to
`~/.claude/tasks/<project>/swarm-runs/{timestamp}-{run-id}.md` for post-mortem
analysis by `/swarm-retro` (see CLAUDE.md § Task Artifact Location for
how to resolve `<project>`).

Create `~/.claude/tasks/<project>/swarm-runs/` if it does not exist.

```markdown
# Swarm Run: {timestamp}-{run-id}

## Config
- Source: JQL harvest | child_tickets ({parent-key}) | mock_tickets
- Tickets: {N}
- Domains: Backend ({N}), Frontend ({N}), Infra ({N})
- Dry run: {yes/no}

## Tickets
| Key | Classification | Pipeline | Domain | Reviewer | Status | Duration | Retries |
|-----|---------------|----------|--------|----------|--------|----------|---------|
| {for each ticket...} |

## Blockers
- {ticket}: {description} (retry {N}: {outcome})

## Smart Recovery Actions
- {ticket}: {action} (outcome: {result})

## Sequencing
- {domain}: {sequence description}

## Summary
- Launched: {N} | Completed: {N} | Blocked: {N}
- PRs: {N} | Time: {duration} | Agents: {N}
```

The run log captures everything the swarm-retro skill needs for analysis.
Dry runs also write a log (with `Dry run: yes` and no pipeline results)
so classification accuracy can be reviewed before committing resources.

### Metrics emit (after run log)

After writing the swarm run log to `~/.claude/tasks/<project>/swarm-runs/`,
emit a `swarm_complete` event. See the `metrics-emit` library skill for
format and emit instructions.

Data to capture:
- `tickets_total`: total tickets in the swarm
- `completed`: tickets that completed successfully
- `blocked`: tickets that hit unresolvable blockers
- `prs_created`: number of draft PRs created
- `duration_seconds`: wall-clock from swarm start to summary
- `first_pass_rate`: (completed on first attempt) / tickets_total
- `agents_spawned`: total subagents launched across all pipelines

If emit fails, log and continue.

---

## Gate rules

- **Two gates only.** Gate 1: triage approval (which tickets to swarm).
  Gate 2: PR creation (which PRs to submit). Everything between auto-chains.
- **Autonomous mode relaxes Gate 2.** When `execution_mode: autonomous`,
  auto-create draft PRs for tickets where the reviewer passed with no
  blocking issues. Only gate on tickets with blocking reviewer findings.
  Always show the summary of what was created after the fact.
- **Best-of-N selection is a third mini-gate** for complex tickets only.
  The user picks which attempt wins.
- **Blockers surface immediately** but don't block other pipelines.
- **Ticket Swarm never writes code.** It orchestrates team leads, which
  orchestrate ticket-pickup, which orchestrates the pipeline agents.
  Composition all the way down.
- **Autonomous mode flows downstream.** Ticket Swarm passes
  `execution_mode: autonomous` and `swarm_mode: true` to all downstream
  skills, which pass them to their downstream agents.
- **NEVER create PRs manually.** Always delegate to
  `/pr-create-from-commits`. No raw `gh pr create`, no `gh api`, no
  manual PR body construction. The skill handles templates, Jira, and
  proper formatting.
- **NEVER skip Jira transitions.** They happen at pipeline launch
  (Step 4.5), not later. The user expects ticket status to reflect
  pipeline activity in real time.
- **Each pipeline runs as a subagent** (or `best-of-n-runner` for complex
  tickets) to keep the main context clean.
- **Jira is always best-effort.** Never block pipeline execution on Jira
  failures — but always attempt the transition.

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
