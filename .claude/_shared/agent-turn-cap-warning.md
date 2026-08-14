# Agent Turn-Cap Truncation Handling

The five reasoning agents have `maxTurns` set in their frontmatter — Aristotle 20, Optimus 30, Cyrus 100, Ranger 40, Scout 35. When the harness terminates a run at the cap, the agent's final message returns without any explicit signal, so the pipeline can silently consume partial output.

## Scope — prose-orchestrated calls only

The sentinel remains required for every `Agent`-tool call orchestrated from SKILL.md prose.

Stages executed by a saved workflow script are **exempt**: `agent()` with a `schema` returns a validated object or `null`, which is itself the completion signal — a sentinel adds nothing there. Workflow-owned stages also emit **no** `agent_truncated` metric: a `null` return is the workflow-native truncation/failure signal, handled by the workflow's own degradation rules and the invoking skill's invoke → validate → fall-back contract. The `agent_truncated` metric stays live for prose-orchestrated calls, where sentinel-absence is the detection rule below.

## Detection

A successful reasoning-agent run ends with the literal token on its own line:

```
<<task-complete>>
```

If the agent's returned text does not contain `<<task-complete>>`, treat the run as potentially truncated.

A response that lacks the sentinel **and** explicitly states a blocker is incomplete-but-intentional — not truncation. The blocker statement, not the sentinel, governs.

## Response — pipeline mode (`swarm_mode` not set)

1. **Halt the pipeline.** Do not pass the output to the next stage. A truncated Aristotle corrupts Optimus's brief; a truncated Optimus corrupts Cyrus's plan; a truncated Cyrus leaves code half-implemented.
2. **Surface to the user** verbatim:

   > ⚠ `<agent-name>` may have been truncated at its turn cap (maxTurns=`<N>`). The final message did not contain the completion sentinel.
   >
   > Options: (1) review the partial output below and decide whether it's salvageable, (2) re-run the agent with a tightened scope, (3) raise the agent's `maxTurns` in its frontmatter and re-run after a session restart.

3. **Emit the `agent_truncated` metric** — see `~/.claude/skills/metrics-emit/SKILL.md` → `agent_truncated`.
4. **Wait for user direction.** Do not proceed.

## Response — swarm mode (`swarm_mode: true`)

1. **Record and skip.** Mark the ticket blocked with reason `agent_truncated`.
2. **Emit the metric.**
3. **Move to the next ticket.** Do not halt the batch — `/swarm-retro` will surface the pattern across runs.

## Hard rules

- Never silently pass a truncated payload downstream.
- Never auto-retry on truncation — the same prompt against the same cap will hit the same wall. Resolution requires user intervention (scope reduction or cap raise + session restart).
- The sentinel check is the **orchestrator's** responsibility, not the agent's. The agent emits; the orchestrator verifies.
- The Agent tool does not surface a "terminated by maxTurns" flag in its return — sentinel-absence is the only available signal.
