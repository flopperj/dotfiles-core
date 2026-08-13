---
name: aristotle-deconstructor
description: "First-principles pipeline: Aristotle deconstructs the problem, Optimus plans the solution, Cyrus implements with TDD. Use when the user types /aristotle-deconstructor, starts a prompt with 'Aristotle', or asks to 'deconstruct this to first principles', 'think from first principles', 'strip the assumptions', or 'what's really true here'. Triggers the full Aristotle -> Optimus -> Cyrus pipeline with user approval gates between each stage."
user-invocable: true
---

# Aristotle Pipeline

> **Agent definition**: [`aristotle-deconstructor.md`](../../agents/aristotle-deconstructor.md)

The user wants first-principles reasoning applied to a problem, with automatic
handoff to planning and implementation if the problem requires code changes.

This skill orchestrates: **Aristotle -> Optimus -> Cyrus** with user gates.

---

## Execution modes

This skill supports two execution modes, determined by the caller:

- **`gated`** (default) — every stage transition requires explicit user
  approval. Used when invoked directly by the user ("Aristotle, ..." or
  `/aristotle-deconstructor`).
- **`autonomous`** — Aristotle still runs the full 5-phase analysis (quality
  is non-negotiable), but gates auto-approve for Optimus and Cyrus
  transitions. The orchestrator logs each gate decision instead of blocking.
  Only PR creation gates on user approval. Used when invoked by `ticket-swarm`
  or `ticket-pickup` with `execution_mode: autonomous`.

When `swarm_mode: true` is also passed (typically from `ticket-swarm`),
forward both flags to all downstream skills (Optimus, Cyrus) so they know
to report results back to the swarm orchestrator rather than presenting
interactive menus.

---

## Responsibility boundaries

Each agent has a strict lane. The orchestrator (you) enforces these at every
handoff. If an agent's output bleeds into another agent's domain, strip the
offending content before passing it downstream.

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

---

## Handoff contracts

Each stage produces a **defined output shape**. Only this output crosses the
boundary — everything else stays within the agent.

Both handoffs are **typed contracts** with JSON Schemas:
[`aristotle-to-optimus.json`](../../workflows/schemas/aristotle-to-optimus.json)
and [`optimus-to-cyrus.json`](../../workflows/schemas/optimus-to-cyrus.json)
(installed at `~/.claude/workflows/schemas/`). These stages are
prose-orchestrated `Agent` tool calls, not saved workflow scripts, so the
schemas are **written contracts the orchestrator (you) validates by hand** —
they are not `agent()`-enforced returns. Structure each handoff per the
schema's fields and check that every `required` field is present and
non-empty before launching the downstream agent. If a field cannot be filled
from the upstream output, treat the stage as deficient — surface the gap
(see Truncation handling), never fabricate the field.

> **Why these stages are not saved workflows (conversion audit, 2026-08):**
> in gated mode every inter-gate span here is a single agent call, and the
> autonomous-mode Aristotle -> Optimus -> Cyrus stretch has plan-dependent
> topology — Step 2 can halt on a no-code-changes verdict, and Step 4 picks
> sequential vs wave-parallel Cyrus from the plan's Section 12 — so no
> gate-free span has the fixed 2+-agent topology a workflow script requires.
> The typed contracts apply regardless of orchestration style.

### Aristotle -> Optimus handoff

Structure the handoff per `aristotle-to-optimus.json`:

- `aristotelian_move` — **The Aristotelian Move**: the single
  highest-leverage action (1-2 sentences)
- `bedrock_truths` — **Irreducible truths**: the first principles that
  survive Phase 2
- `assumptions_stripped` — the inherited assumptions the Assumption Autopsy
  removed from the framing, recorded so Optimus does not reintroduce them
- `constraints` — hard constraints on the solution space, including any user
  modifications or constraints stated at the gate

Alongside the typed object, pass the **Implementation Handoff section** —
Aristotle's summary of what needs to be built, written as a strategic brief
(what and why, never how). It is the narrative companion to
`aristotelian_move`, not a schema field.

**Strip before passing:**
- The full Phase 1-4 analysis (user has already seen it; Optimus doesn't need it)
- Any file paths, class names, or implementation specifics Aristotle may have
  included (these are Optimus's job)

### Optimus -> Cyrus handoff

Structure the typed core of the handoff per `optimus-to-cyrus.json`:

- `steps` — ordered execution steps as `{id, what, where, why}` objects,
  drawn from the plan's Section 4 steps and its YAML todo checklist ids
- `test_plan` — Section 6's tests, one entry per test
- `files_to_create` / `files_to_modify` — Section 3's Affected Areas lists
- `risks` — Section 9's risk table entries

Alongside the typed object, pass:
- **The full execution plan** — all 12 sections (problem summary through
  parallelization strategy); the typed object indexes the plan, it does not
  replace it
- **The Aristotelian Move** (if pipeline started from Aristotle) — so Cyrus
  understands the strategic why

**Strip before passing:**
- Optimus's internal reasoning or alternative approaches it considered
- Any code snippets Optimus may have included (Cyrus writes all code)

---

## Step 1: Launch Aristotle

Extract the user's problem from their prompt (strip any "Aristotle" prefix,
"/aristotle-deconstructor" prefix, or similar). Launch the
`aristotle-deconstructor` agent via the Agent tool with the user's problem
as the prompt.

Wait for the full analysis (5 phases + Aristotelian Move).

**Subagent failure handling:** Follow CLAUDE.md error handling defaults.
If a subagent fails or times out, surface the failure and stop — do not
present partial strategic analysis.

**Validate output before presenting:** If Aristotle's response contains code
blocks, file paths, or implementation specifics beyond its Implementation
Handoff section, note this to the user as a boundary violation and present
only the strategic analysis.

## Step 2: Present analysis and gate

Show the user Aristotle's complete output.

**In gated mode:** Ask:

```
Aristotle has identified the highest-leverage path. What next?

  -> p = Proceed to Optimus for a detailed execution plan
  -> d = Drill deeper into a specific phase
  -> s = Stress-test the Aristotelian Move against objections
  -> x = Stop here (no code changes needed)
```

Wait for user input. Do not proceed without explicit approval.

**In autonomous mode:** Log the analysis summary and auto-proceed to
Step 3 (Optimus). If the Aristotelian Move explicitly states no code
changes are needed, halt and report back to the caller instead.

## Step 3: Launch Optimus (if approved)

If the user chooses "p" or says to proceed:

Launch the `optimus-planner` agent via the Agent tool. Pass it **only** the
handoff contract output, structured per `aristotle-to-optimus.json`
(see Handoff contracts):
- `aristotelian_move` — The Aristotelian Move
- `bedrock_truths` — the irreducible truths
- `assumptions_stripped` — the assumptions removed from the framing
- `constraints` — fold in any additional context or constraints the user
  provided at the gate
- The Implementation Handoff section (narrative companion to the typed object)

Validate the object by hand against the schema's `required` fields before
launching — this is a written contract, not an `agent()`-enforced one.

**Instruct Optimus explicitly:** "This strategic direction comes from
Aristotle's first-principles analysis. Do not re-litigate the strategy —
your job is to make it executable."

Wait for the full execution plan.

**Validate output before presenting:** If Optimus's response contains code
implementations (beyond illustrative pseudocode in plan steps), note this
to the user as a boundary violation.

## Step 4: Present plan and gate

Show the user Optimus's complete plan.

**In gated mode:** Ask:

```
Optimus has produced the execution plan. What next?

  -> i  = Hand to Cyrus for TDD implementation (sequential)
  -> ip = Hand to Cyrus for parallel TDD implementation (wave-based)
  -> r  = Revise the plan (tell me what to change)
  -> x  = Stop here (plan only, no implementation)
```

If Section 12 of the plan says "Sequential execution recommended," note this
to the user next to the `ip` option and suggest `i` instead.

Wait for user input.

**In autonomous mode:** Log the plan summary and auto-proceed to Step 5
(Cyrus). Use sequential execution (`i`) unless Section 12 explicitly
provides a wave table with parallelizable steps, in which case use
parallel (`ip`).

## Step 5: Launch Cyrus (if approved)

If the user chooses "i" (sequential):

Launch the `cyrus-tdd-engineer` agent via the Agent tool. Pass it **only**
the handoff contract output, with the typed core structured per
`optimus-to-cyrus.json` (see Handoff contracts):
- The typed core: `steps`, `test_plan`, `files_to_create`,
  `files_to_modify`, `risks`
- Optimus's full execution plan (all 12 sections)
- The Aristotelian Move (strategic context)
- Any user modifications or constraints mentioned during the gates
- Execution mode: `sequential`

Validate the typed core by hand against the schema's `required` fields
before launching — this is a written contract, not an `agent()`-enforced
one.

**Instruct Cyrus explicitly:** "This plan comes from Optimus. Execute it
step-by-step with TDD discipline. Do not redesign the architecture or
re-sequence the steps — if you hit a blocker, surface it rather than
working around it."

If the user chooses "ip" (parallel):

Invoke the Cyrus skill's parallel execution mode. Pass:
- The typed handoff core per `optimus-to-cyrus.json` (see Handoff
  contracts), validated by hand the same way as the sequential path
- Optimus's full execution plan (all 12 sections)
- The Aristotelian Move (strategic context)
- Any user modifications or constraints mentioned during the gates
- Execution mode: `parallel`
- Section 12 wave table as the scheduling input

The Cyrus skill will fan out one agent per step per wave, report between
waves, and aggregate final results.

## Gate rules

- **In gated mode: never skip gates.** Each stage transition requires
  explicit user approval.
- **In autonomous mode: gates auto-approve.** The orchestrator logs each
  decision and proceeds. Only PR creation (handled downstream by
  `/pr-create-from-commits`) gates on user approval. If Aristotle's
  analysis concludes no code changes are needed, halt and report back.
- **Aristotle-only is valid.** Strategic questions may not need code.
- **Optimus can be skipped.** If Aristotle identifies a trivial, fully-specified
  change (single function rename, one-line config), offer to skip straight
  to Cyrus — but only if the what, where, and how are all unambiguous.
- **Each agent runs as a subagent** to keep the main context clean.
- **Enforce boundaries at every handoff.** You are the orchestrator — if an
  agent strays outside its lane, filter its output before passing downstream.
- **If the user says "drill deeper" or "stress-test"** (gated mode only),
  send follow-up prompts to the Aristotle agent (or launch a new one with
  that context).
- **Forward swarm flags.** When `swarm_mode` and `execution_mode` are
  present, pass them through to every downstream skill invocation.

## Truncation handling

When this skill invokes Aristotle, Optimus, or Cyrus via the `Agent` tool, the orchestrator must verify the returned response contains the `<<task-complete>>` sentinel before consuming its output. See `~/.claude/_shared/agent-turn-cap-warning.md` for the detection rule, halt/skip behavior, and the `agent_truncated` metric to emit. Aristotle-truncation is especially load-bearing here — a truncated Implementation Handoff section silently corrupts Optimus's brief.

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
