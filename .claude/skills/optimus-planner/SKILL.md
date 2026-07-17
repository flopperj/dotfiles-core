---
name: optimus-planner
description: "Produce a detailed, actionable execution plan before implementation begins. Use when the user types /optimus-planner, starts a prompt with 'Optimus', or asks to 'plan this out', 'create an execution plan', 'break this down into steps', 'architect this', or 'what's the plan for...'. Launches the optimus-planner agent, presents the plan, and offers to hand off to Cyrus for TDD implementation."
user-invocable: true
# parity-ignore: what's the plan for...
---

<!-- shape: checklist-v1 -->

# Optimus Planner

> **Agent definition**: [`optimus-planner.md`](../../agents/optimus-planner.md)

This skill orchestrates: **Optimus -> Cyrus** with a user gate.

## When to Use

- The user types `/optimus-planner` or starts a prompt with `Optimus, ...`.
- The user asks to "plan this out", "create an execution plan", "break this down into steps", "architect this", or "what's the plan for...".
- The user has a non-trivial engineering problem (3+ steps or architectural decisions) and wants a detailed execution plan before any code is written.
- An upstream `aristotle-deconstructor` has produced strategic direction and the pipeline now needs to make it executable — the Aristotelian Move is passed forward as context.
- A `ticket-swarm` or `ticket-pickup` pipeline is processing a Medium- or Complex-tier ticket and needs Optimus's plan as the input to Cyrus (autonomous mode).

> Skip Optimus for trivial single-step changes — those go straight to Cyrus or get handled inline. Optimus's overhead is justified when the plan itself is the deliverable.

## Workflow

### Step 0: Resolve plan storage path

Before launching Optimus, detect the host platform and set the plan storage base path.

Run via Bash:

```bash
echo "${CLAUDECODE:-}"
```

- **Non-empty** → `plan_base = ~/.claude/tasks/<project>/plans/` (Claude Code)
- **Empty** → `plan_base = ~/.cursor/plans/` (Cursor)

Store `plan_base` for use in all subsequent steps. When passing the plan file path to Optimus or Cyrus, use the resolved `plan_base` — never hardcode either path.

### Step 1: Launch Optimus

Extract the user's problem from their prompt (strip any "Optimus" prefix, "/optimus-planner" prefix, or similar). Launch the `optimus-planner` agent via the Agent tool with the user's problem as the prompt.

Include any relevant context the user provided: Jira ticket numbers, file paths, architectural constraints, or upstream Aristotle analysis if present.

If upstream Aristotle analysis is present, instruct Optimus explicitly: "This strategic direction comes from Aristotle's first-principles analysis. Do not re-litigate the strategy — your job is to make it executable."

**Always instruct Optimus to append a Plan Critique block** at the end of the 12-section plan, before the gate. The Critique is Optimus's self-review against the five staff-grade checks below. Each check returns one line: ✅ pass, ⚠️ partial (with what's thin), or ❌ fail (with what's missing). Pass the following block verbatim into Optimus's prompt:

```
## Plan Critique (required, append to the end of the 12-section plan)

Score the plan against these five staff-grade checks. For each, output one line:
✅ <check name> — <one-sentence justification>
⚠️ <check name> — <what's thin and why>
❌ <check name> — <what's missing and why it matters>

1. **Reversibility** — Does every step that touches shared state (DB, deploy, public API) have a documented rollback path (revert, flag flip, migration reversal)? DoD §9.
2. **Test strategy specificity** — For each step that adds production code, is the test approach named (unit/integration/contract/e2e) and the boundary (mock vs real) decided? DoD §7.
3. **Failure mode coverage** — Have at least two non-happy-path failure modes been identified for the change? (e.g., partial write, concurrent caller, downstream timeout, migration rollback during traffic). DoD §1.
4. **Boundary fit & reuse** — Does the plan respect the existing layer/package structure, and reuse existing helpers where they cover the need (§4a)? Every *new* utility/abstraction must justify why no existing code covers it — an unjustified new helper is a ❌, since it becomes a duplicate at implementation time. DoD §2.
5. **Observability gap** — At what step does logging/metrics/tracing get added? If nowhere, why? DoD §8.

After the five lines, output a one-sentence verdict on the form:
**Verdict:** READY | NEEDS REVISION | BLOCKED — <reason>.

Do not ship a plan with a ❌ unaddressed. If a ❌ is unavoidable (e.g., the user's scope explicitly excludes one of these), call it out in the verdict so the gate reviewer sees it.
```

Wait for the full execution plan (12 sections + Plan Critique block).

**Subagent failure handling:** Follow CLAUDE.md error handling defaults. If a subagent fails or times out, surface the failure and stop — do not present a partial execution plan.

**Validate output before presenting:** If Optimus produces full method implementations or command executions — note this to the user as a boundary violation. Brief structural snippets (class skeletons, method signatures, interface shapes) within plan steps are acceptable guidance, not violations. Optimus plans; it does not build.

### Step 2: Present plan and gate

Show the user Optimus's complete plan, including the Plan Critique block.

**Surface the Critique verdict as the first line above the gate menu.** If the verdict is `NEEDS REVISION` or `BLOCKED`, default the gate prompt's recommendation to `r` (revise) rather than `i` (implement). Do not hide a ❌ from the user — it must appear above the menu so the user reads it before choosing.

If autonomous mode is active and the verdict is `BLOCKED`, **do not auto-proceed** to Cyrus. Pause and surface the verdict to the user — autonomous-mode auto-approval applies to clean handoffs, not to acknowledged plan defects.

**In gated mode:** Ask:

```
Optimus has produced the execution plan. What next?

  -> i  = Hand to Cyrus for TDD implementation (sequential)
  -> ip = Hand to Cyrus for parallel TDD implementation (wave-based)
  -> r  = Revise the plan (tell me what to change)
  -> a  = Run Aristotle first (deconstruct assumptions before planning)
  -> x  = Stop here (plan only, no implementation)
```

If Section 12 of the plan says "Sequential execution recommended," note this to the user next to the `ip` option and suggest `i` instead.

Wait for user input. Do not proceed without explicit approval.

**In autonomous mode:** Log the plan summary and auto-proceed to Step 3 (Cyrus). Use sequential execution (`i`) unless Section 12 explicitly provides a wave table with parallelizable steps, in which case use parallel (`ip`). Forward `swarm_mode`, `execution_mode` flags, and the plan file path (resolved from Step 0's `plan_base`) to Cyrus.

### Step 3: Launch Cyrus (if approved)

If the user chooses "i" (sequential):

Launch the `cyrus-tdd-engineer` agent via the Agent tool. Pass it **only** the handoff contract output:
- Optimus's full execution plan (all 12 sections)
- The strategic context (Aristotelian Move or original problem)
- Any user modifications or constraints mentioned during the gate
- Execution mode: `sequential`
- Plan file path: resolved from Step 0's `plan_base` (Cyrus uses this for progress tracking)

**Instruct Cyrus explicitly:** "This plan comes from Optimus. Execute it step-by-step with TDD discipline. Do not redesign the architecture or re-sequence the steps — if you hit a blocker, surface it rather than working around it."

If the user chooses "ip" (parallel):

Invoke the Cyrus skill's parallel execution mode by launching the `cyrus-tdd-engineer` skill orchestrator. Pass:
- Optimus's full execution plan (all 12 sections)
- The strategic context
- Any user modifications or constraints
- Execution mode: `parallel`
- Section 12 wave table as the scheduling input
- Plan file path: resolved from Step 0's `plan_base` (Cyrus uses this for progress tracking)

The Cyrus skill will fan out one agent per step per wave, collect results, and report between waves.

### Step 4: Handle revision (if requested)

If the user chooses "r" or asks for changes:

1. Launch a new `optimus-planner` agent with the original plan + revision instructions.
2. When the revised plan is returned, **overwrite the existing plan file** at `~/.claude/tasks/<project>/plans/<name>.md` with the updated content. Preserve the original `created` timestamp; update the frontmatter to reflect changes.
3. Present the revised plan and re-show the gate menu.

This keeps a single plan file as the source of truth rather than producing disconnected revisions.

### Gate rules

- **In gated mode: never skip the gate.** The plan must be reviewed before implementation.
- **In autonomous mode: the Cyrus handoff auto-approves.** The orchestrator logs the plan summary and proceeds. Optimus still produces the full plan — only the gate behavior changes.
- **Plan-only is valid.** The user may just want the plan for reference (gated mode only).
- **Aristotle can be inserted upstream.** If the user picks "a" (gated mode), launch `aristotle-deconstructor` with the problem, then feed its output back to Optimus per the aristotle-deconstructor skill's handoff contract.
- **Each agent runs as a subagent** to keep the main context clean.
- **Enforce boundaries at the handoff.** You are the orchestrator — if Optimus strays into implementation, filter its output before passing to Cyrus.
- **Forward swarm flags.** When `swarm_mode` and `execution_mode` are present, pass them through to the Cyrus skill invocation.

## Checklist

- [ ] `plan_base` resolved via `echo "${CLAUDECODE:-}"` (Claude Code vs Cursor)
- [ ] Existing plan detected at the resolved path (date-prefixed glob covers both legacy and new forms)
- [ ] Optimus subagent launched with user's problem + any upstream Aristotle analysis
- [ ] Boundary check on Optimus output — implementation code stripped before handoff
- [ ] Plan presented to user (gated) or summary logged (autonomous)
- [ ] Gate decision captured: i / ip / r / a / x
- [ ] If `i` or `ip`: Cyrus launched with full handoff contract + plan file path + flags
- [ ] If `r`: revised plan overwrites existing file, frontmatter `created` preserved
- [ ] If `x` (gated only): plan file marked `status: abandoned` and moved to archive
- [ ] On Cyrus completion: plan marked `status: completed`, Execution Notes appended, archived
- [ ] In swarm mode: plan path reported back to swarm orchestrator for run-log cross-reference

## Tools

- **Bash** — `echo "${CLAUDECODE:-}"` for host detection (Step 0); `date +%Y-%m-%d` for plan filename prefix; `mv` for archiving plans on abandonment/completion.
- **Agent tool** — launches the `optimus-planner` agent for the 12-section plan; launches the `cyrus-tdd-engineer` agent (sequential) or skill orchestrator (parallel) on handoff; launches `aristotle-deconstructor` upstream if user picks `a`.
- **Filesystem reads/writes** — `~/.claude/tasks/<project>/plans/<plan>.md` (Claude Code) or `~/.cursor/plans/<slug>_<hex8>.plan.md` (Cursor); `~/.claude/agent-memory/optimus-planner/` for learning capture; `~/.claude/tasks/<project>/plans/archive/` for completed/abandoned plans.

## Resources

- **Agent prompt** — [`../../agents/optimus-planner.md`](../../agents/optimus-planner.md) (the Optimus agent's full instruction set, including the 12-section plan template)
- **Upstream skill** — `/aristotle-deconstructor` (when invoked, produces an Aristotelian Move that becomes Optimus's strategic context)
- **Downstream skill** — `/cyrus-tdd-engineer` (the only agent allowed to translate the plan into code)
- **Plan storage**: Claude Code → `~/.claude/tasks/<project>/plans/`, Cursor → `~/.cursor/plans/`
- **Archive location** (Claude Code only) — `~/.claude/tasks/<project>/plans/archive/` — abandoned and completed plans land here, never deleted
- **Agent memory** — `~/.claude/agent-memory/optimus-planner/` — patterns worth preserving across plans land here on Cyrus completion
- **Swarm linkage** — in autonomous/swarm mode, the plan path is reported back to the swarm orchestrator for `/swarm-retro` cross-reference

## Examples

**User invokes Optimus directly (gated mode):**

```
User: Optimus, plan how to migrate our user service from Express to Fastify

Flow:
1. Step 0   — Bash echo $CLAUDECODE returns "1" → plan_base = ~/.claude/tasks/<project>/plans/
2. Plan Lifecycle: existing-plan detection globs *user-service-fastify.md
              under plan_base → no match → fresh plan
3. Step 1   — launches optimus-planner agent with the migration problem;
              waits for the full 12-section plan
4. Step 2   — presents the plan to user; asks gate (i / ip / r / a / x)

User: i

5. Step 3   — launches cyrus-tdd-engineer agent with the handoff contract:
              full plan + strategic context + execution_mode=sequential +
              plan_file_path = ~/.claude/tasks/<project>/plans/2026-04-24-user-service-fastify.md
6. Cyrus runs TDD; Optimus orchestrator awaits completion
7. On Cyrus completion: plan frontmatter set to status: completed,
              Execution Notes appended, plan archived to plans/archive/
```

**Autonomous swarm-mode invocation:**

```
ticket-swarm passes a Medium-tier ticket through Optimus:

Flow:
1. Step 0 — host-detect → plan_base resolved
2. Plan Lifecycle: existing-plan glob → no match → fresh plan
3. Step 1 — Optimus produces 12-section plan (same quality, no shortcuts)
4. Step 2 — autonomous mode: log summary, auto-proceed (no gate prompt)
5. Step 3 — Cyrus launched with execution_mode from Section 12 (sequential
            unless wave table is present and viable), swarm_mode=true,
            plan_file_path forwarded
6. On Cyrus completion: plan archived as in gated mode; plan path is
   ALSO reported back to swarm orchestrator for /swarm-retro
```

---

## Execution modes

This skill supports two execution modes, passed by the caller:

- **`gated`** (default) — the plan is presented and the user must approve before Cyrus is launched. Used when invoked directly by the user ("Optimus, ..." or `/optimus-planner`).
- **`autonomous`** — Optimus still produces the full 12-section plan (quality is non-negotiable), but the Cyrus handoff auto-approves. The orchestrator logs the plan summary and proceeds directly to implementation. Used when invoked by `ticket-swarm`, `ticket-pickup`, or the `aristotle-deconstructor` skill in autonomous mode.

When `swarm_mode: true` is also passed, forward both flags to the Cyrus skill so it knows to report results back to the swarm orchestrator rather than presenting interactive menus.

---

## Handoff contract: Optimus -> Cyrus

Pass **only** these from Optimus's output:
- **The full execution plan** — all 12 sections (including Section 12: Parallelization Strategy)
- **The strategic context** — the Aristotelian Move if the pipeline started from Aristotle, or the user's original problem statement if Optimus was invoked directly
- **User modifications** — any changes the user requested during the gate
- **Execution mode flag** — `sequential` or `parallel` (based on user's gate choice)

**Strip before passing:**
- Optimus's internal reasoning or alternative approaches it considered
- Any code snippets beyond plan-step pseudocode

**UI steps — frontend-design skill:**
For any plan step that touches UI (components, styles, layout, visual properties), the plan must list `frontend-design` as the first action in that step. Cyrus depends on this annotation to know when to invoke the skill — if the plan omits it, Cyrus may skip it.

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

Optimus produces **plans, not code**. If Optimus's output contains implementation code (beyond brief illustrative pseudocode within plan steps), that is a boundary violation — strip it before passing to Cyrus.

---

## Plan Lifecycle

The skill orchestrator (not Cyrus) owns the full plan lifecycle:

### Plan filename convention

**New plans** are written with a date prefix: `<plan_base>/YYYY-MM-DD-<slug>.md` (e.g. `2026-04-24-gitnexus-adoption.md`). Use the current local date via `date +%Y-%m-%d`. The prefix gives chronological sort order via `ls`, makes "show me April plans" a trivial glob, and avoids the foot-gun of two unrelated tickets sharing a slug across months.

**Legacy plans** (without the date prefix) are NOT renamed. They continue to resolve via the detection logic below; the prefix applies forward-only.

### Existing plan detection

Before launching Optimus, check if a plan already exists at the resolved `plan_base` path. The detection glob must match **both** the legacy bare-slug form AND the new date-prefixed form, so resumption works for plans created before this convention landed:

- **Claude Code:** Glob `~/.claude/tasks/<project>/plans/*<ticket-or-slug>.md` — matches `<ticket-or-slug>.md` (legacy) AND `YYYY-MM-DD-<ticket-or-slug>.md` (new). The leading `*` is a wildcard so it also matches any unrelated file ending in the slug suffix (e.g. `team-foo-<ticket-or-slug>.md`). Slug collisions are rare in a per-project plans dir — pick the most-recently-modified match if multiple resolve, and **prefer exact-prefix matches over wildcard-prefix matches** when both exist (i.e. `<slug>.md` and `YYYY-MM-DD-<slug>.md` win over `team-foo-<slug>.md`). If false-positive matches become common, tighten to `(?:[0-9]{4}-[0-9]{2}-[0-9]{2}-)?<slug>.md`.
- **Cursor:** Search `~/.cursor/plans/` for files matching `*<ticket-or-slug>*.plan.md`

If found:
- If `status: planned` or `status: abandoned` (Claude Code) or the plan exists (Cursor) -> ask: "An existing plan for <name> was found. Resume it, or start fresh?"
- If `status: in_progress` (Claude Code only) -> warn: "This plan is currently being executed. Overwriting will lose progress. Continue?" Require explicit confirmation.
- If resuming, read the plan file and hand off to Cyrus starting from the first `pending` todo.

### Abandonment (gate "x")

When the user chooses "x" (plan only, no implementation):

**Claude Code:**
1. Update the plan file: set `status: abandoned` in frontmatter.
2. Move to archive: `mv ~/.claude/tasks/<project>/plans/<name>.md ~/.claude/tasks/<project>/plans/archive/<name>.md`
   (create `~/.claude/tasks/<project>/plans/archive/` if needed).
3. Report: "Plan archived to `~/.claude/tasks/<project>/plans/archive/<name>.md`"

**Cursor:**
1. Delete the plan file from `~/.cursor/plans/`. Cursor has no archive convention.
2. Report: "Plan removed from `~/.cursor/plans/<slug>_<hex8>.plan.md`"

### Completion (after Cyrus returns)

When Cyrus reports execution complete (all todos `completed`):
1. Read the plan file.
2. Set `status: completed` in frontmatter.
3. Append an **Execution Notes** section at the end of the plan:

```markdown
## Execution Notes

### Blockers
- Step N: <description of blocker and resolution>

### Deviations
- Step N: <what changed from original plan and why>

### Learnings
- <patterns worth recording in agent memory>

### Implementation Summary
- **Changes**: list of files changed and what was done
- **Feature Gating**: flag name, off behavior, on behavior
- **Tests**: test files modified/created
- **Verify**: steps to manually test the change
```

Omit empty subsections (e.g., if no blockers, skip that heading).

4. If any patterns are worth preserving, update `~/.claude/agent-memory/optimus-planner/` with the learning.
5. Archive the plan:
   - **Claude Code:** `mv ~/.claude/tasks/<project>/plans/<name>.md ~/.claude/tasks/<project>/plans/archive/<name>.md`
     Report: "Plan completed and archived to `~/.claude/tasks/<project>/plans/archive/<name>.md`"
   - **Cursor:** Delete the plan file from `~/.cursor/plans/`. Cursor has no archive convention.
     Report: "Plan completed and removed from `~/.cursor/plans/<slug>_<hex8>.plan.md`"

### Swarm mode linkage

In autonomous/swarm mode, after writing the plan file, report its path back to the swarm orchestrator so it can be included in the swarm run log for cross-referencing by `/swarm-retro`.

## Truncation handling

When this skill invokes Optimus via the `Agent` tool, the orchestrator must verify the returned response contains the `<<task-complete>>` sentinel before consuming its output. See `~/.claude/_shared/agent-turn-cap-warning.md` for the detection rule, halt/skip behavior, and the `agent_truncated` metric to emit. A truncated Optimus plan is especially dangerous because Cyrus consumes it directly — partial section coverage means partial implementation.

## Maintenance

If you discover something during this task that would improve this skill, propose the change and ask me to confirm before saving it.
