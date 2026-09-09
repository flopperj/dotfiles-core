## Launching the agent

This skill ships its agent definition at [`agent.md`](agent.md), in the same
directory as this file. Resolve `SKILL_DIR` = the directory containing this
`SKILL.md`. Wherever this document says "launch the `{{AGENT}}` agent via the
Agent tool", apply this resolution order:

1. **Registered subagent (preferred).** If the Agent tool lists `{{AGENT}}`
   among its available agent types, call
   `Agent(subagent_type: "{{AGENT}}", prompt: <brief>)`. You get the pinned
   model, `maxTurns`, tool restrictions, and persistent agent memory.
2. **Fallback — general-purpose subagent.** Otherwise read `SKILL_DIR/agent.md`,
   drop its YAML frontmatter, and call
   `Agent(subagent_type: "general-purpose", prompt: <agent.md body> + "\n\n---\n\n" + <brief>)`.
   Prepend to the brief: *"No persistent memory is available this session —
   skip the Persistent Agent Memory instructions."* State once in your output:
   *"Running `{{AGENT}}` in fallback mode (subagent not registered). For the
   pinned model, turn caps and memory, run
   `bash SKILL_DIR/scripts/install-agent.sh` and restart your session."*
   Role-guard enforcement is prose-only in this mode, so apply this skill's
   output-validation checks strictly.
3. **No subagent tool at all (e.g. Cursor).** Follow `agent.md` yourself in the
   current context, then continue with this skill's orchestration steps.

The brief always includes a runtime-paths block the agent uses instead of
hard-coded home paths:

```
Runtime paths:
  SKILL_DIR: <absolute path of this skill's directory>
  PLAN_BASE: ~/.claude/tasks/<project>/plans/ (Claude Code) | ~/.cursor/plans/ (Cursor)
```

The `<<task-complete>>` sentinel check
([`references/agent-turn-cap-warning.md`](references/agent-turn-cap-warning.md))
applies in modes 1 and 2.

## Optional: install as a registered subagent

```bash
bash <SKILL_DIR>/scripts/install-agent.sh          # → ~/.claude/agents/{{AGENT}}.md
bash <SKILL_DIR>/scripts/install-agent.sh --project # → ./.claude/agents/{{AGENT}}.md
```

Restart your session afterwards; subagents load at session start.
