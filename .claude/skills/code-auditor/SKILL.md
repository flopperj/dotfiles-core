---
name: code-auditor
description: "Complexity-aware review router. Use when the user types /code-auditor, starts a prompt with 'Auditor', or asks to 'review my PR', 'check this PR', 'review my changes', or 'audit this code'. Analyzes code complexity and routes to Scout or Ranger. Also triggered automatically before non-draft PR creation and draft-to-ready promotion."
user-invocable: true
---

# Code Auditor

The user wants a PR or code changes reviewed. The auditor analyzes code
complexity and routes to the right reviewer — Scout (Sonnet, fast) for
simpler changes, Ranger (Opus, deep) for complex ones.

**The auditor is an orchestrator/router, not a reviewer.** It does not
produce review findings itself. It measures complexity and delegates.

**Distinction from Scout/Ranger**: Scout and Ranger can still be invoked
directly ("Scout, review PR #42" or `/scout-reviewer`). The auditor is
the default entry point when the user says "review my PR" without
specifying a reviewer.

---

## Responsibility boundaries

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->

The auditor **analyzes and routes**. It does not:
- Produce review findings or score issues (that's Scout/Ranger)
- Write or suggest code fixes (that's Cyrus)
- Post anything to GitHub (that's Scout/Ranger with user approval)
- Make file edits or run implementation commands

Routes to Scout or Ranger — both downstream reviewers apply `~/.claude/DoD.md` as the completion bar.

---

## Step 1: Identify the target

Determine the review target from:
- A PR number provided by the user (e.g., "review PR #482")
- A branch name (use `gh pr list --head <branch>` to find it)
- The current branch (use `gh pr list --head $(git branch --show-current)`)
- A file or directory path (standalone mode — complexity report only)

If the target cannot be determined, ask the user.

**If `gh` fails (auth, network, rate limit):**
- Check `gh auth status` — if not authenticated, prompt the user to run
  `gh auth login`
- If `gh pr view` or `gh pr diff` returns an error, surface the error and
  ask the user to verify the PR number/branch
- Follow CLAUDE.md error handling defaults

## Step 2: Complexity scoring — invoke the `code-auditor-score` workflow

Scoring runs through the saved `code-auditor-score` workflow
(`.claude/workflows/code-auditor-score.js`). The workflow owns the
topology — three parallel scorers plus deterministic weighted
aggregation — so the composite is computed in script arithmetic, not
re-derived by an agent. The skill's job here is a three-part contract:
invoke, validate, fall back.

1. **Invoke.** Invoke the `code-auditor-score` workflow, passing the
   target descriptor from Step 1 (PR number, branch name, or file
   paths) through the Workflow tool's `args`. In autonomous/swarm mode,
   include the word `autonomous` in `args` — the workflow detects it
   and applies the borderline-escalation rule (composite 65-74 →
   `ranger`) inside its own aggregation.
2. **Validate.** Check the workflow's return against
   [`.claude/workflows/schemas/auditor-composite.json`](../../workflows/schemas/auditor-composite.json).
   The five required fields must be present and well-typed:
   - `composite` (number, 0-100)
   - `band` (enum `Low` / `Medium` / `High`)
   - `recommendation` (enum `scout` / `ranger` / `none`)
   - `components` (per-scorer scores; a dead scorer's entry is `null`)
   - `degraded` (boolean)

   Validate **only those fields**. The workflow returns no prose — its
   narration goes to the run journal — so do not require or parse any
   text alongside the object.
3. **Fall back.** If the invocation errors, returns nothing, or the
   return fails validation, run the **legacy prose fan-out** (labelled
   fallback block below) and produce the composite the old way. **State
   plainly in the output that the fallback path ran**, e.g. *"Workflow
   invocation unavailable — scored via the prose fan-out path."* The
   user gets a correct audit either way; the only cost of a failed seam
   is a line of text.

**Journal diagnostic — check before declaring failure.** If the return
*seems* empty, consult the workflow run's `journal.jsonl` before
concluding the invocation failed. A workflow that ran correctly but
whose return did not surface looks identical to one that never ran; the
journal distinguishes them. Record what the journal showed alongside
the fallback notice.

**Fallback occurrences must be visible, not silent.** If the fallback
notice appears on every run, the workflow seam is broken and should be
treated as unproven rather than as a working feature — surface that
pattern to the user instead of quietly absorbing it.

## Step 2b: Interpret the validated return

A validated return maps directly onto the Step 3 summary:

- `composite` and `band` fill the score line. The bands are Low (0-39),
  Medium (40-69), High (70-100) — pinned inside the workflow.
- `components` fills the per-dimension lines (structural / impact /
  scope). A `null` component means that scorer died.
- `recommendation` seeds the routing recommendation: `scout`, `ranger`,
  or `none`. `none` means the workflow detected a documentation-only
  diff — report "Documentation-only change — no code review needed"
  and skip the review. The workflow also applies the trivial-diff
  fast-path internally (lines <= 10, 1-2 files, no security-sensitive
  paths → lightweight Scout pass).

**Degraded semantics (`degraded: true`):**

- **One scorer dead** → the workflow continues: the surviving weights
  are renormalized so the composite stays on the 0-100 scale, and
  `degraded` is `true` with a non-null `composite`. Present the result
  but note the gap in the Step 3 summary (e.g., "Impact: unavailable —
  scorer failed; weights renormalized").
- **Two or more scorers dead** → the workflow aborts rather than
  presenting a confident wrong score: it returns `null` for
  `composite`, `band`, and `recommendation` (with `degraded: true`).
  Those nulls **fail schema validation by design**, so the Step 2
  fallback engages automatically.

<!-- LEGACY FALLBACK — prose fan-out. Runs ONLY when the
     code-auditor-score workflow invocation or validation fails
     (Step 2, part 3). Do not run this when the workflow returned a
     valid composite. -->

### Fallback: legacy prose fan-out

Launch 3 parallel `fast` subagents against the diff (or specified files):

#### Agent 1: Structural complexity

For each changed function/method in the diff:
- Count decision points (if/else, switch cases, loops, ternary, catch
  blocks) as a proxy for cyclomatic complexity
- Measure max nesting depth
- Measure function length (lines)
- Measure file length
- Score: weighted sum normalized to 0-100

#### Agent 2: Fan-out / impact

For each changed file:
- `rg` for imports/usages of changed symbols across the codebase
- Count direct consumers (files that import from changed files)
- Flag if security-sensitive paths are touched (`app/views/`,
  `data/schemas/`, `app/lib-grpc/`)
- Score: 0-100 based on consumer count and sensitivity

#### Agent 3: Scope

Diff-level metrics:
- Total files changed
- Total lines added/removed
- Number of distinct directories touched
- Whether new abstractions (classes, interfaces, types) are introduced
- Whether database migrations are included
- Score: 0-100

**Subagent failure handling:**
If a subagent fails, times out, or returns empty:
- Log the failure and which agent it was
- Continue with results from the remaining agents
- Note the gap in the scoring (e.g., "Impact: unavailable — subagent
  failed")
- If 2 or more of the 3 agents fail, abort and report rather than
  presenting partial results

**Aggregate scores.** Compute a weighted composite score:

- Structural complexity: 40%
- Fan-out / impact: 35%
- Scope: 25%

Thresholds:
- **Low** (0-39): straightforward changes, limited blast radius
- **Medium** (40-69): meaningful changes, moderate risk
- **High** (70-100): complex changes, high blast radius or structural
  complexity

**Trivial diff fast-path:** If the scope agent reports total lines
changed <= 10 AND only 1-2 files AND no security-sensitive paths, skip
the full routing and recommend a lightweight single-pass review (Scout
with collapsed analysis). If the diff is documentation-only (*.md,
*.txt, comments only), report "Documentation-only change — no code
review needed" and skip the review.

<!-- END LEGACY FALLBACK -->


## Step 3: Route decision

Present the audit summary to the user:

```
Code Audit: PR #482

  Files changed: 7
  Lines: +142 / -38
  Complexity score: 62 / 100 (Medium)

  Structural:  55 — 2 functions with high nesting (>4), 1 function >80 lines
  Impact:      72 — changed code has 14 direct consumers, touches security-sensitive path
  Scope:       48 — 3 directories, no new abstractions, no migrations

  Recommendation: Scout (fast review)
  Rationale:     Structural complexity is moderate, but high fan-out warrants attention.
                 Scout + Ranger blocker confirmation will catch critical issues.

  -> g = Go — launch recommended reviewer
  -> r = Ranger — override to staff-level review
  -> s = Scout — override to fast review
  -> a = Audit only — show report, skip review
  -> x = Cancel
```

In autonomous/swarm mode: auto-select `g` unless the score is borderline
(65-74). If borderline, escalate to Ranger.

Wait for user input. **Never auto-launch a reviewer without approval in
gated mode.**

## Step 4: Launch reviewer

Launch the selected reviewer skill (`/scout-reviewer` or
`/ranger-reviewer`) as a subagent, passing:
- The PR number
- Any user-specified concerns
- The complexity audit summary (so the reviewer has context on what's
  complex)
- Ticket context (if provided by the caller — forward `ticket_context`
  and `ticket_key` as-is to the reviewer so it can run Requirements
  Coverage analysis against the ticket's acceptance criteria)

**Standalone mode**: If invoked on files/directories without a PR
context, skip Step 4. Just produce the audit report (Step 3 with option
`a` auto-selected).

### Routing handoff cues

The downstream reviewer (Scout or Ranger) is responsible for four
disciplines that the auditor does NOT re-implement:

1. **Verify findings before drafting comments.** The reviewer's
   confidence score is self-assessment; the reviewer orchestrator traces
   each finding to the code before drafting. See the chosen reviewer's SKILL.md (`scout-reviewer` / `ranger-reviewer`) § VERIFY-THEN-DRAFT.
2. **Stress-test findings for senior-staff bar-fit.** After verification,
   the reviewer orchestrator demotes or drops findings that nick rather
   than bend the codebase, that the author cannot act on, or whose
   severity tier is indefensible — surfacing the per-finding verdicts
   above the gate menu. See the chosen reviewer's SKILL.md (`scout-reviewer` / `ranger-reviewer`) § FINDINGS-CRITIQUE.
3. **Calibrate tone to author seniority.** Default is "staff-level
   explanatory"; the reviewer offers peer / minimal alternatives at draft
   time based on PR author signal. See the chosen reviewer's SKILL.md (`scout-reviewer` / `ranger-reviewer`) § TONE-CALIBRATION.
4. **Respect GitHub anchor constraints.** Multi-line comments must sit
   in the diff and in the same hunk; the reviewer pre-flights against
   `gh pr diff` before posting. See the chosen reviewer's SKILL.md (`scout-reviewer` / `ranger-reviewer`) § ANCHOR-CONSTRAINTS.

When presenting the routing recommendation (Step 3), the auditor can
reference these by name — e.g. *"Routing to Ranger; he will verify each
finding, demote any that don't pass the senior-staff bar, and offer a tone choice when drafting."* The
auditor does not perform the verification, bar-fit critique, tone selection, or anchor
check itself.

Both reviewers also share a small set of test/review heuristics — the four
lies of a green diff, "test only code you own", and scope-feedback-to-the-diff —
documented once in [`references/review-heuristics.md`](references/review-heuristics.md).
The auditor does not apply them (it routes, it does not review); the reference is
the canonical source the reviewers and Cyrus cite.

## Gate rules

- **Never auto-route in gated mode.** Present the recommendation and
  wait for user input.
- **Auditor never reviews.** If the user asks for findings, launch the
  appropriate reviewer.
- **Auditor never implements.** If the user wants fixes, hand off to
  Cyrus via the reviewer's fix option.
- **Auditor can run standalone.** No upstream agent is required.
- **Each reviewer runs as a subagent** to keep the main context clean.
- **Respect CLAUDE.md rules.** The PR Reviews & Comments section mandates
  draft-first, never-auto-post for all PR interactions.
- **Follow CLAUDE.md error handling defaults** for subagent and external
  tool failures.

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
