---
name: ticket-pickup
description: "Fetch a Jira ticket, enrich it with codebase context, classify its complexity, and route it to the right pipeline depth. Use when the user types /ticket-pickup, starts a prompt with 'Pickup', or asks to 'pick up a ticket', 'grab the next bug', 'work on PROJ-1234', or 'what's my next ticket'. Single-ticket entry point for the agent pipeline."
user-invocable: true
# parity-ignore: work on PROJ-1234
---

# Ticket Pickup

Fetch a single Jira ticket, enrich it with codebase context, classify
complexity, and route to the appropriate pipeline depth.

This skill is the **entry point** for ticket-driven work. It replaces
manually copy-pasting ticket context into prompts.

---

## Responsibility boundaries

Ticket Pickup is an **orchestrator** — it fetches, enriches, classifies, and
routes. It never does any of the downstream agents' jobs.

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
<!-- EXTRA_ROWS: ticket-pickup -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
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

Ticket Pickup supports two execution modes, passed by the caller:

- **`gated`** (default) — present classification to user, wait for approval
  at every pipeline transition. Used when invoked directly by the user.
- **`autonomous`** — present classification to user for batch approval, then
  auto-approve all pipeline transitions except PR creation. Used when invoked
  by `ticket-swarm`.

---

## Step 1: Resolve the ticket

Parse the user's input to determine the ticket:

- **Explicit ticket key** (e.g., `PROJ-1234`) — use directly.
- **Branch name** — extract ticket key from the current git branch
  (pattern: `ABC-1234`). Run `git branch --show-current` if needed.
- **"Pick my next bug"** — query Jira for the user's highest-priority
  assigned bug:
  ```
  searchJiraIssuesUsingJql(
    jql='assignee = currentUser() AND type = Bug AND status in ("To Do", "Open") ORDER BY priority ASC, created ASC',
    maxResults=1
  )
  ```
- **JQL override** — if the user provides a JQL query, execute it and pick
  the first result.

If no ticket can be resolved, ask the user for a ticket key. If no ticket exists yet, offer to create one via `/create-jira-ticket`.

---

## Step 2: Fetch ticket context

Use the Atlassian MCP tools. All Jira operations are best-effort — never
block the pipeline on a Jira failure.

**Primary: Atlassian MCP plugin**
1. Call `getJiraIssue` with the ticket key. Extract:
   - Summary, description, acceptance criteria
   - Comments (especially reproduction steps, stack traces, linked PRs)
   - Status, priority, labels, components
   - Linked issues (blockers, duplicates, related)
   - Attachments (note URLs for reference)

<!-- BEGIN OVERLAY-FRAGMENT: ticket-pickup-jira-fallback -->
<!-- END OVERLAY-FRAGMENT: ticket-pickup-jira-fallback -->

---

## Step 2.5: Detect ticket hierarchy

After fetching the ticket, check if it's a parent ticket (Story or Epic)
with children that should be swarmed instead of processed individually.

1. Check the `issuetype` field from `getJiraIssue`.
2. If type is **Story** or **Epic**:
   - Fetch sub-tasks via JQL:
     ```
     searchJiraIssuesUsingJql(
       jql='parent = {ticket-key}',
       fields=["summary", "description", "status", "priority", "issuetype", "components", "labels"],
       maxResults=50
     )
     ```
   - Also check for linked issues with "is parent of" or "has sub-task"
     link types in the ticket's linked issues.
3. If children exist and at least 2 are in a workable status ("To Do",
   "Open", "Reopened"):
   - **Skip Steps 3-7** (enrichment + classification for a container
     ticket is meaningless)
   - Present the story decomposition gate (below)
4. If no children exist (or all children are already Done/Closed):
   - Treat the Story/Epic as a regular ticket (it may be a standalone
     task mislabeled as a Story)
   - Proceed with normal enrichment and classification at Step 3
   - If the Story needs sub-tickets created, use `/create-jira-ticket`
     which handles story points, Epic assignment, and description templates

### Story decomposition gate

```
Story Detected: PROJ-1000 — Multi-account billing support

  Type: Story | Status: To Do | Priority: P2
  Sub-tickets: 5 found

  #  Ticket      Type      Status   Summary
  1  PROJ-1001   Sub-task  To Do    Add account selector to billing page
  2  PROJ-1002   Sub-task  To Do    Update billing API for multi-account
  3  PROJ-1003   Sub-task  To Do    Add billing_account_id to invoices table
  4  PROJ-1004   Sub-task  To Do    Write migration for existing accounts
  5  PROJ-1005   Sub-task  To Do    Update billing tests for multi-account

  -> swarm     = Swarm all sub-tickets (enrich, classify, parallel pipelines)
  -> swarm 1,2 = Swarm specific sub-tickets
  -> single N  = Pick up a single sub-ticket normally
  -> story     = Treat the Story itself as a single complex ticket
  -> x         = Cancel
```

**In gated mode:** Wait for user input.

**In autonomous mode:** Auto-select `swarm` for all workable sub-tickets.

### Delegating to ticket-swarm

If the user picks `swarm` (or autonomous mode auto-selects it):

1. Launch the `ticket-swarm` skill with:
   - `child_tickets`: the list of selected sub-ticket keys
   - `parent_story_key`: the Story/Epic ticket key
   - `execution_mode`: forward from caller (or default `gated`)
   - `swarm_mode`: forward from caller if present
2. ticket-swarm skips its JQL harvest (Step 1 Source A) and uses the
   provided child tickets directly.
3. Transition the parent Story to "In Progress" if available.
4. Add a comment to the parent Story:
   `🤖 Story decomposed into swarm. Sub-tickets being processed: {list}.`

All Jira operations are best-effort.

---

## Step 3: Enrich with codebase context

Launch an explore subagent to search the codebase for references from the
ticket:

- **Stack traces**: Extract file paths, class names, line numbers from the
  ticket description and comments. Search the codebase to confirm they exist
  and pull surrounding context.
- **Error messages**: Grep for exact error strings to find the origin.
- **Component names**: Search for classes, modules, or services mentioned in
  the ticket.
- **Related PRs**: If the ticket links to merged PRs, fetch the PR diff
  summaries via `gh pr view <number> --json title,body,files`.

Compile the enrichment into a structured brief:

```
Ticket: PROJ-1234 — Campaign preview returns 404
Priority: P1 | Status: To Do | Components: campaigns, preview

Description:
  [Ticket description, trimmed to essentials]

Reproduction:
  [Steps from comments, if available]

Codebase references found:
  - app/controllers/CampaignPreviewController.php (line 142 — route handler)
  - app/lib/MC/Campaign/Preview.php (line 89 — render method)
  - tests_phpunit/MC/Campaign/PreviewTest.php (existing test coverage)

Related:
  - PROJ-1200 (duplicate, closed — previous fix reverted)
  - PR #4521 (merged — original preview implementation)
```

**If `gh` or enrichment fails:** Log the failure, continue with whatever
context was gathered. Partial enrichment is better than no enrichment.
Follow CLAUDE.md error handling defaults.

---

## Step 4: Classify complexity

Evaluate the enriched ticket to determine pipeline depth:

### Simple (Cyrus direct)
All of these must be true:
- Single file or 2-3 closely related files affected
- Clear stack trace or error message pointing to the root cause
- Fix pattern is obvious (null check, off-by-one, typo, missing flag check)
- No architectural implications
- Existing test coverage exists to validate against

### Medium (Optimus -> Cyrus)
Any of these:
- 2-5 files across multiple directories
- Needs a plan but the strategic direction is obvious
- Requires new test files or significant test additions
- Touches a well-understood pattern (controller + service + test)

### Complex (Aristotle -> Optimus -> Cyrus)
Any of these:
- Root cause is unclear or debatable
- Multiple possible fix strategies with different trade-offs
- Architectural implications (changes how systems interact)
- Race conditions, concurrency issues, or timing-dependent bugs
- Cross-service or cross-system boundaries
- Previous fix attempts failed (linked duplicate/reverted tickets)

---

## Step 5: Present and gate

Show the enriched ticket with classification:

```
Ticket Pickup: PROJ-1234

  Summary:    Campaign preview returns 404
  Priority:   P1
  Complexity: Medium
  Pipeline:   Optimus -> Cyrus (2-3 files, needs a plan)

  Codebase context:
    - CampaignPreviewController.php:142 — route handler
    - MC/Campaign/Preview.php:89 — render method
    - PreviewTest.php — existing coverage

  Enrichment:
    - Previous fix (PR #4521) was reverted in PROJ-1200
    - Stack trace points to null $campaign in render()

  -> g  = Go — launch the pipeline as classified
  -> s  = Simplify — I think this is simpler, route to Cyrus directly
  -> e  = Escalate — this is more complex, route through Aristotle
  -> c  = Add context (provide additional information)
  -> x  = Cancel
```

**In gated mode:** Wait for user input.

**In autonomous mode:** Log the classification and auto-select `g` unless
the complexity is ambiguous (e.g., borderline Simple/Medium). If ambiguous,
escalate one level rather than risk under-routing.

### Metrics emit (after classification)

After the classification gate resolves (user choice or autonomous auto-select),
emit a `ticket_classified` event. See the `metrics-emit` library skill for
format and emit instructions.

Data to capture:
- `classification`: the final classification (Simple/Medium/Complex)
- `pipeline`: the pipeline path (cyrus / optimus-cyrus / aristotle-optimus-cyrus)
- `enrichment_sources`: which sources produced enrichment (e.g. ["jira", "codebase", "gh"])
- `override`: null if no override, "simplified" if user chose `s`, "escalated" if user chose `e`

If emit fails, log and continue. Never block the pipeline on metrics.

---

## Step 5.5: Ensure branch exists

Before launching the pipeline, ensure the working branch is set up. This
step handles branch creation automatically so the user never needs to
manually create a feature branch.

1. **Check current branch**: `git branch --show-current`
2. **Detect if already on a matching branch**: If the current branch name
   contains the ticket key (e.g., branch `PROJ-1234-fix-npe` matches
   ticket `PROJ-1234`), use it as-is. Skip branch creation.
3. **Check for a pre-existing branch**: Run
   `git branch --list "*{ticket-key}*"`. If a matching branch exists
   but is not currently checked out, check it out and pull latest.
4. **Create a new branch** if no matching branch exists:
   - Determine the branch name: `{ticket-key}-{slug}` (e.g.,
     `PROJ-1234-fix-campaign-preview`). Slugify from the ticket summary.
   - Use the `newbranch` shell alias if available (from `.aliases.local`):
     `newbranch {ticket-key}-{slug}`. This handles default branch
     detection (queries `origin/HEAD`, supports any branch name), checkout,
     `git pull origin`, and new branch creation in one command.
   - **Fallback** if `newbranch` is not available (non-dotfiles
     environment): detect the default branch manually via
     `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
     (fall back to `main` then `master` via `git show-ref`), then:
     `git checkout {default} && git pull origin {default} && git checkout -b {ticket-key}-{slug}`

**In swarm mode:** Skip this step — ticket-swarm handles branch creation
before dispatching to ticket-pickup.

---

## Step 6: Launch pipeline

Based on classification and user choice:

**Simple -> Cyrus direct:**
Launch the `cyrus-tdd-engineer` skill. Pass:
- The enriched ticket brief (from Step 3)
- Jira ticket key for commit messages
- Execution mode (from caller or default `gated`)
- `swarm_mode` flag if invoked by ticket-swarm

**Medium -> Optimus -> Cyrus:**
Launch the `optimus-planner` skill. Pass:
- The enriched ticket brief as the problem statement
- Jira ticket key
- Execution mode
- `swarm_mode` flag if applicable

The Optimus skill handles its own gate and Cyrus handoff.

**Complex -> Aristotle -> Optimus -> Cyrus:**
Launch the `aristotle-deconstructor` skill. Pass:
- The enriched ticket brief as the problem to deconstruct
- Jira ticket key
- Execution mode
- `swarm_mode` flag if applicable

The Aristotle skill handles its own gates and downstream handoffs.

**CI fix loop:** When Jenkins MCP is configured, Cyrus includes an autonomous CI failure diagnosis and fix loop after pushing code. Default behavior: Cyrus reports "Pushed. CI running" and stops; the fix loop triggers on the next interaction that reveals a failure. In swarm mode (`swarm_mode: true`), Cyrus polls Jenkins via `mcp__jenkins-mcp__check_build` and enters the fix loop automatically if the build fails (up to 3 iterations). See the Cyrus agent definition for details and guardrails.

### Metrics emit (after pipeline completes)

When the downstream pipeline (Cyrus / Optimus+Cyrus / Aristotle+Optimus+Cyrus)
returns, emit a `pipeline_complete` event before proceeding to Step 7.

Data to capture:
- `classification`, `pipeline`: same as the ticket_classified event
- `duration_seconds`: wall-clock seconds from pipeline launch to return
- `tests_passed`: true/false from Cyrus's report
- `coverage_percent`: coverage number from Cyrus's report (null if not reported)
- `ci_fix_attempts`: number of CI fix iterations (0 if none)
- `first_pass`: true if pipeline completed with 0 retries and 0 CI fix attempts
- `files_changed`: count of files modified

If emit fails, log and continue.

**IMPORTANT:** Immediately after launching the pipeline, proceed to
Step 7 (Jira transition). Do not skip it.

---

## Step 7: Jira status transition (MANDATORY)

You **MUST** transition the ticket to "In Progress" **IMMEDIATELY** after
launching the pipeline. Do not defer this. Do not skip it.

1. Call `getTransitionsForJiraIssue` to find the "In Progress" transition ID.
2. Call `transitionJiraIssue` with the transition ID.
3. Add a comment: `🤖 Picked up by agent pipeline. Complexity: {classification}. Pipeline: {pipeline}.`

**Verify:** Confirm the transition succeeded by checking the response.
If it fails (no valid transition, Jira unavailable), log the failure
but do not block the pipeline.

This step is **not optional**. The user expects ticket status to reflect
pipeline activity in real time.

---

## Gate rules

- **Ticket Pickup never writes code.** It fetches, enriches, classifies, and
  routes. The downstream skill handles everything else.
- **Classification is a recommendation.** The user can override at the gate.
- **Autonomous mode still gates on ambiguous classification.** When in doubt,
  escalate complexity one level.
- **Each downstream pipeline runs as a subagent** to keep context clean.
- **NEVER skip Jira transitions.** They happen at pipeline launch, not later.
  The user expects real-time status updates.
- **Fallback gracefully.** If Jira is unavailable, if codebase search finds
  nothing, if enrichment is thin — still present what you have and let the
  user decide.

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
