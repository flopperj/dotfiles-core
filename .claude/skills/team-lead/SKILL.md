---
name: team-lead
description: "Domain coordinator for ticket-swarm. Receives a cluster of enriched tickets sharing a domain, detects intra-cluster dependencies, injects domain-specific context, sequences tickets to prevent merge conflicts, and launches pipelines in the correct order. Not user-invocable — only called by ticket-swarm."
user-invocable: false
---

# Team Lead

Coordinate a cluster of tickets within a single domain. Detect dependencies,
inject domain context, sequence properly, and launch pipelines.

This skill is an **internal orchestration component** — it is only called by
`ticket-swarm`, never directly by the user.

---

## Responsibility boundaries

A team lead is a **coordinator**, not a new agent role. It groups, sequences,
and injects context, then delegates to the same pipeline agents.

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
<!-- EXTRA_ROWS: team-lead,ticket-pickup -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Team Lead** | Dependency detection, domain context injection, within-cluster sequencing, pipeline dispatch | Write code, produce plans, perform strategic analysis, review PRs, enrich tickets, classify complexity |
| **Ticket Pickup** | Fetch ticket, enrich with codebase context, classify complexity, route to pipeline | Write code, produce plans, perform strategic analysis, review PRs |
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->

---

## Input contract

The team lead receives from ticket-swarm:

- **Cluster**: A list of enriched tickets (from ticket-pickup Steps 2-4),
  each with:
  - Ticket key, summary, priority, complexity classification
  - `ticket_complexity: simple | medium | complex` per ticket
  - Codebase references (file paths found during enrichment)
  - Jira linked issues (blockers, duplicates, related)
- **Domain tag**: `backend`, `frontend`, `infra`, or `unknown`
- **Execution flags**: `swarm_mode: true`, `execution_mode: autonomous`
- **Parent story key** (optional): If these tickets are sub-tasks of a
  Story, the parent key for Jira comment context

---

## Step 1: Analyze dependencies within the cluster

Examine the enriched ticket data to detect relationships:

### File-level dependencies

Compare codebase references across tickets in the cluster. If two tickets
reference the same file:
- They **must not** run in parallel (merge conflict risk)
- Sequence them: the simpler ticket runs first (fewer changes = easier base
  for the next ticket)
- Mark with: `[sequenced: shared file {path}]`

### Jira link dependencies

Check linked issues between tickets in the cluster:
- **"Blocks" links**: If ticket A blocks ticket B, A must complete first
- **"Relates to" links**: Advisory only — note the relationship but don't
  force sequencing unless files also overlap
- **"Duplicate" links**: Flag to the swarm orchestrator — duplicates should
  not both be implemented

### Logical ordering

For sub-tasks from a Story decomposition, infer logical dependencies even
if files don't overlap:
- Database schema changes before API changes
- API changes before frontend changes
- Shared libraries/interfaces before consumers
- Tests that validate integration after the components they test

### Build the dependency graph

Produce a sequencing plan:

```
Cluster: Backend (4 tickets)

  Wave 1 (parallel):
    PROJ-1003 (Simple) — DB migration, no dependencies
    PROJ-1007 (Simple) — Config change, independent

  Wave 2 (parallel, depends on Wave 1):
    PROJ-1001 (Medium) — API update, depends on PROJ-1003 [shared: app/lib/MC/Billing.php]
    PROJ-1009 (Simple) — Error handler fix, independent

  Wave 3 (sequential, depends on Wave 2):
    PROJ-1002 (Medium) — Service integration, depends on PROJ-1001 [Blocks link]
```

If no dependencies exist, all tickets can run in parallel (single wave).

---

## Step 2: Inject domain context

Based on the domain tag, prepare domain-specific context to pass to each
pipeline. This context supplements the enriched ticket brief.

### Backend domain context

```
Domain: Backend (PHP / Avesta MVC)

Conventions:
- Controllers in app/controllers/, business logic in app/lib/MC/
- Models in app/models/, gRPC via Autolyse in app/lib/Autolyse/
- Tests in tests_phpunit/ using Phake for mocking
- snake_case variables, camelCase methods, PascalCase classes
- No abstract classes — favor composition
- No named arrays for structured data — always use a class
- Alphabetically sort imports, methods, and properties

Validation:
- PHPStan and Phan must pass after changes
- Run devenv test for PHPUnit tests

Security:
- XSS protection for any view/template changes
- CSRF protection for controller actions and Autolyse services
- SQL injection protection for any database queries
```

### Frontend domain context

```
Domain: Frontend (React / TypeScript)

Conventions:
- Components in web/js/src/
- Routes in web/js/src/Main/routes/
- Always use IDS/MCDS design tokens — no hardcoded colors, spacing, or typography
- Check Figma alignment when available
- Invoke the frontend-design skill for any visual changes

Validation:
- ESLint and TypeScript checks must pass
- Jest tests for components
```

### Infra / Cross-Boundary domain context

```
Domain: Infrastructure / Cross-Boundary

Conventions:
- Proto changes go in proto/, never edit app/lib-grpc/ directly
- gRPC code is auto-generated from protos
- Database migrations are Tuesdays only — if a migration is needed, flag prominently
- Feature flags in config/flags.ini, always start at enabled = 0.00
- Observability: traces around entry points, logging context through call chains

Special rules:
- Changes that span backend + frontend must coordinate commit ordering
- Proto changes require regeneration step before dependent code compiles
```

### Unknown domain

No additional context injected. The ticket's own enrichment data is
sufficient.

---

## Swarm context accumulator

The team lead maintains a **shared context object** that accumulates results
across waves. This gives downstream agents awareness of what upstream agents
built, beyond just the files on disk.

**Initialize** the context as empty before Wave 1.

**After each wave completes**, append a brief summary:

```
Wave 1 results:
  PROJ-1003: Created app/lib/MC/Billing/AccountId.php (new value object)
             Modified app/models/Invoice.php (added billing_account_id column)
  PROJ-1007: Modified config/flags.ini (added mc_billing_multi_account flag)
```

**Inject** the accumulated context into each subsequent wave's pipeline
agents alongside the domain context: `"Prior wave context: {accumulated}"`

This context is **ephemeral** — it lives only for the duration of the
swarm run and is not persisted to agent memory. It is included in the
run log for swarm-retro analysis.

**Accumulator size limits:**
- Keep only the last 3 wave summaries in full detail
- For earlier waves: condense to a single line per ticket (key, files changed, pass/fail)
- Max total accumulator size: ~200 lines
- If exceeded: drop the oldest wave details, keeping only the condensed single-line entries

---

## Step 3: Launch pipelines by wave

Execute the sequencing plan from Step 1, wave by wave:

**For each wave:**

1. Launch one pipeline per ticket in the wave. For each ticket, invoke
   `ticket-pickup` with:
   - The enriched ticket brief
   - Domain context from Step 2
   - **Swarm context** from the accumulator (prior wave results)
   - Jira ticket key
   - Branch name (determined by ticket-swarm)
   - `swarm_mode: true`, `execution_mode: autonomous`
   - `ticket_complexity` from the ticket's classification (determines
     whether Cyrus auto-triggers Scout, code auditor, or Ranger on completion)
   - For independent tickets: branch is created by ticket-swarm (via
     `newbranch` or fallback) from the latest default branch
   - For sequenced tickets: the prior ticket's branch as the base
     (instead of the default branch)

2. Wait for all pipelines in the wave to complete.

3. Collect results from each pipeline:
   - Files changed, tests written, coverage metrics
   - Pass/fail status, blockers encountered
   - Reviewer results (Scout or Ranger depending on complexity)

4. **Update the swarm context accumulator** with this wave's results
   (files created/modified, classes/interfaces established).

5. **If any pipeline in the wave fails or reports a blocker:**
   Run smart failure analysis (Step 3.5) before escalating.

6. Report wave completion to ticket-swarm:
   ```
   [Backend Lead] Wave 1 complete: 2/2 succeeded

     PROJ-1001: API update (Medium) — 2 files, 8 tests, coverage 90%, Auditor->Scout: clean
     PROJ-1007: Config change — 1 file, 2 tests, coverage 88%, Scout: clean

   Proceeding to Wave 2...
   ```

7. Proceed to the next wave.

---

## Step 3.5: Smart failure analysis

When a pipeline in a wave reports a blocker, auto-analyze before
escalating to the user. This reduces unnecessary user interruptions.

### Flaky test detection

Check if the failing test meets flaky test criteria:
- The test file was **not modified** by this pipeline (failure in
  pre-existing test code)
- The test name matches known flaky patterns from agent memory
  (`~/.claude/agent-memory/ticket-swarm/classification-heuristics.md`,
  "Known flaky tests" section)
- The failure message suggests timing/network issues (timeout, connection
  refused, intermittent assertion)

If flaky test criteria are met:
- **Auto-retry once** without user intervention
- Log as `[auto-retry: suspected flaky test — {test-name}]`
- If retry succeeds: proceed normally, note in run log
- If retry fails again: escalate as a real failure

### Cross-ticket dependency failure

Check if the error references code from another ticket in the cluster:
- The error message mentions a class, method, or file that another
  ticket in this cluster *created or modified* (from the swarm context
  accumulator)
- The error is a "class not found", "method not found", "undefined
  function", or import failure

If cross-ticket dependency is detected:
- **Auto-resequence**: move the failed ticket to a later wave, after
  the ticket that provides the dependency completes
- Log as `[auto-resequence: dependency on {other-ticket} — {symbol}]`
- Do not count this as a retry — it's a sequencing correction

### Real failure

If neither flaky test nor cross-ticket dependency applies:
- Surface to the user with failure analysis context:
  ```
  {ticket} [BLOCKED] — Test failure (real)
    Failing: {test-class}::{test-method}
    Analysis: Test file was modified by this pipeline. Failure is in new code.
    Not a flaky test. Not a cross-ticket dependency.
    -> retry   = Re-run this ticket's pipeline
    -> context = Provide additional context for Cyrus
    -> skip    = Skip this ticket
    -> abort   = Cancel this ticket
  ```
- Hold downstream waves that depend on this ticket
- Independent waves may proceed

### Recovery logging

All smart recovery actions are included in the cluster report and the
swarm run log for post-mortem analysis by swarm-retro:
```
Smart Recovery Actions:
  PROJ-1003: [auto-retry: suspected flaky test — MC_CampaignTest::testTimeout] (succeeded)
  PROJ-1009: [auto-resequence: dependency on PROJ-1001 — MC_Billing::processRefund] (moved to Wave 3)
```

---

## Step 4: Report cluster completion

When all waves complete (or all remaining tickets are blocked/aborted),
report the cluster summary to ticket-swarm:

```
[Backend Lead] Cluster complete: 4/4 tickets processed

  Succeeded: 3 (PROJ-1003, PROJ-1007, PROJ-1001)
  Blocked:   1 (PROJ-1002 — test failure in integration step)

  Waves executed: 3
  Agents spawned: 4
  Total files changed: 8
  Total tests written: 18
```

ticket-swarm aggregates reports from all team leads into the swarm
progress dashboard.

---

## Dependency edge cases

- **Circular dependencies**: If ticket A depends on B and B depends on A
  (from Jira Blocks links), flag this to ticket-swarm as unresolvable.
  Suggest the user merge the tickets or clarify the dependency direction.
- **Single-ticket clusters**: If the domain has only one ticket, skip
  dependency analysis and wave scheduling. Launch the pipeline directly.
- **All-independent clusters**: If no dependencies are detected, launch
  all tickets in a single wave (maximum parallelism).
- **Branch chaining for sequential tickets**: When ticket B depends on
  ticket A, B's branch should be created from A's completed branch (not
  from the default branch). This ensures B sees A's changes. The team
  lead instructs ticket-pickup to use the appropriate base branch.
- **Pre-existing branches**: Before creating any branch, check if one
  matching the ticket key already exists (`git branch --list "*{key}*"`).
  If found, use it — the user may have pre-created the branch manually.
  For chained tickets, verify the pre-existing branch is based on the
  correct parent (rebase onto A's branch if needed).

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
