# Agent Turn-Cap Truncation Handling

The five reasoning agents have `maxTurns` set in their frontmatter — Aristotle 40, Optimus 60, Cyrus 300, Ranger 80, Scout 70. The cap applies **per invocation**: an agent resumed with `SendMessage` keeps its full context and gets a fresh turn budget. So hitting the cap does not have to mean losing the work. Continue the agent first, and fall back to halting only when continuation is exhausted or stalls.

## Scope — prose-orchestrated calls only

The sentinel remains required for every `Agent`-tool call orchestrated from SKILL.md prose.

<!-- BEGIN CORE-ONLY -->
Stages executed by a saved workflow script are **exempt**: `agent()` with a `schema` returns a validated object or `null`, which is itself the completion signal — a sentinel adds nothing there. Workflow-owned stages also emit **no** `agent_truncated` metric: a `null` return is the workflow-native truncation/failure signal, handled by the workflow's own degradation rules and the invoking skill's invoke → validate → fall-back contract. The `agent_truncated` metric stays live for prose-orchestrated calls, where sentinel-absence is the detection rule below.
<!-- END CORE-ONLY -->
<!-- PORTABLE-ONLY
Stages executed by a saved workflow script are **exempt**: `agent()` with a `schema` returns a validated object or `null`, which is itself the completion signal — a sentinel adds nothing there. A `null` return is the workflow-native truncation/failure signal, handled by the workflow's own degradation rules and the invoking skill's invoke → validate → fall-back contract. For prose-orchestrated calls, sentinel-absence is the detection rule below.
-->

## Detection

A successful reasoning-agent run ends with the literal token on its own line:

```
<<task-complete>>
```

Two signals mark a run as truncated:

- **Harness note (definitive).** Claude Code prefixes the returned text of a capped agent with a note that it *stopped at its N-turn limit before finishing*. Treat this as confirmed truncation.
- **Missing sentinel (suspected).** The returned text does not contain `<<task-complete>>`. On hosts that add no harness note, this is the only signal.

A response that lacks the sentinel **and** explicitly states a blocker is incomplete-but-intentional — not truncation. The blocker statement, not the sentinel, governs. Do not continue a blocked agent.

## Continuation — before any halt or skip

When a run is truncated, resume **the same agent** rather than re-running it:

1. **Send** `SendMessage` to the agent's ID with: "You hit your turn limit. Continue where you left off; do not redo completed work. End with `<<task-complete>>` when done."
2. **Wait** for the resumed run's result. A resumed agent runs in the background and its result arrives as a task notification. Do not poll, and do not consume partial output in the meantime.
3. **Re-check** the new result with the detection rules above, and repeat while the continuation budget allows.

**Continuation budget:**

- **Default: 2 continuations** per agent invocation. This absorbs the common case of an agent that needed a bit more room, and still bounds a looping agent.
- **Unbounded: on explicit user request for this task.** When the user's request says "no turn limit", "ignore turn limits", "unbounded", or passes `--unbounded`, continue until the sentinel appears, the agent states a blocker, or the stall guard below fires. The opt-in covers that one task only. Record it as the flag `unbounded: true`; every skill that forwards `swarm_mode` and `execution_mode` to downstream skills forwards `unbounded` alongside them, so a chained or swarmed run honours it at every stage.
- **Stall guard (both modes).** If two consecutive continuations report no new progress — the same step, no new files, commits or findings — stop continuing. The agent is looping, and more turns will not fix it.

Continuation is **not** a retry. A retry re-sends the original prompt and discards the work; a continuation resumes the same context from where it stopped. The rule against auto-retry below still holds.

If the host cannot resume an agent (no `SendMessage` or equivalent), skip this section and go straight to the response for the current mode.

## Response — pipeline mode (`swarm_mode` not set)

Applies once the continuation budget is exhausted or the stall guard fires.

1. **Halt the pipeline.** Do not pass the output to the next stage. A truncated Aristotle corrupts Optimus's brief; a truncated Optimus corrupts Cyrus's plan; a truncated Cyrus leaves code half-implemented.
2. **Surface to the user** verbatim:

   > ⚠ `<agent-name>` stopped at its turn cap (maxTurns=`<N>`) and did not finish after `<K>` continuation(s).
   >
   > Options: (1) continue it further — reply "continue" or re-run the task with "no turn limit", (2) review the partial output below and decide whether it's salvageable, (3) re-run the agent with a tightened scope, (4) raise the agent's `maxTurns` in its frontmatter and re-run after a session restart.

<!-- BEGIN CORE-ONLY -->
3. **Emit the `agent_truncated` metric** — see `~/.claude/skills/metrics-emit/SKILL.md` → `agent_truncated`.
4. **Wait for user direction.** Do not proceed. If the user replies "continue", resume the same agent with `SendMessage`; do not start a new one.
<!-- END CORE-ONLY -->
<!-- PORTABLE-ONLY
3. **Wait for user direction.** Do not proceed. If the user replies "continue", resume the same agent; do not start a new one.
-->

## Response — swarm mode (`swarm_mode: true`)

Applies once the continuation budget is exhausted or the stall guard fires. Swarm mode uses the same budget, and is unbounded when the swarm was invoked with `unbounded: true`.

1. **Record and skip.** Mark the ticket blocked with reason `agent_truncated`, noting the number of continuations attempted.
<!-- BEGIN CORE-ONLY -->
2. **Emit the metric.**
3. **Move to the next ticket.** Do not halt the batch — `/swarm-retro` will surface the pattern across runs.
<!-- END CORE-ONLY -->
<!-- PORTABLE-ONLY
2. **Move to the next ticket.** Do not halt the batch.
-->

<!-- BEGIN CORE-ONLY -->
## Metric

Emit **one** `agent_truncated` event per agent invocation that hit the cap at least once, after it resolves: `resolution: completed_after_continuation` when a continuation finished the work, `halted` or `skipped` otherwise. Include `continuations` (how many were sent) and `unbounded`. A run that completes after continuation still counts, because the rate of cap hits is the signal for tuning `maxTurns`.
<!-- END CORE-ONLY -->

## Hard rules

- Never silently pass a truncated payload downstream. Output is consumable only once a run carries the sentinel.
- Never auto-retry on truncation — re-sending the original prompt against the same cap hits the same wall and throws away the work done so far. Continuing the same agent is the sanctioned path; anything beyond the continuation budget needs the user.
- The sentinel check is the **orchestrator's** responsibility, not the agent's. The agent emits; the orchestrator verifies.
- Verify state directly before treating truncation as lost work. A truncated agent may have finished its real work (committed code, written the plan file) and run out of turns during wrap-up. Check git status and the artifact before deciding to halt.
