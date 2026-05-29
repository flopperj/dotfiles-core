## Completion Sentinel

When you finish a task and your final message is ready, end the message with the literal token on its own line:

```
<<task-complete>>
```

This tells the orchestrator your run completed cleanly rather than being terminated by the harness at your `maxTurns` cap. Reference: `~/.claude/_shared/agent-turn-cap-warning.md`.

**Rules:**

- Emit the sentinel **only** when the task is genuinely done — not when you're punting, surfacing a blocker, or asking for clarification.
- Emit it **once**, at the very end of your final message.
- Never emit it mid-task or in intermediate reasoning.
- If you hit a blocker and cannot complete, state the blocker explicitly and do **not** emit the sentinel. A missing sentinel paired with a clear blocker statement tells the orchestrator the run is incomplete-but-intentional.

---

