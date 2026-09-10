## Launching the agent

This skill ships its agent definition at [`agent.md`](agent.md), in the same
directory as this file. **Resolving `SKILL_DIR`:** it is the path shown as
"Base directory for this skill" when this skill loaded; if the host does not
show one, it is the directory containing this `SKILL.md` (e.g.
`.claude/skills/<name>/` on a project install, `~/.agents/skills/<name>/` on a
global install). Wherever this document says "launch the `{{AGENT}}` agent via
the Agent tool", apply this resolution order:

1. **Registered subagent (preferred).** If the Agent tool lists `{{AGENT}}`
   among its available agent types, call
   `Agent(subagent_type: "{{AGENT}}", prompt: <brief>)`. You get the pinned
   model, `maxTurns`, tool restrictions (where the agent declares
   `disallowedTools`), and persistent agent memory (where it declares `memory`).
2. **Fallback — general-purpose subagent.** Otherwise read `SKILL_DIR/agent.md`,
   drop its YAML frontmatter, and call
   `Agent(subagent_type: "general-purpose", prompt: <agent.md body> + "\n\n---\n\n" + <brief>)`.
   Prepend to the brief: *"No persistent memory is available this session —
   skip the Persistent Agent Memory instructions."* If `agent.md`'s frontmatter
   has `disallowedTools`, also prepend: *"You must not use these tools:
   `<list>`. Treat them as unavailable."* — the harness does not enforce
   `disallowedTools` for a `general-purpose` subagent, so this has to be
   stated in the brief instead. State once in your output:
   *"Running `{{AGENT}}` in fallback mode (subagent not registered). For the
   pinned model, turn caps and memory, run
   `bash <SKILL_DIR>/scripts/install-agent.sh` (substitute the resolved path)
   and restart your session."*
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

(substitute the resolved path for `<SKILL_DIR>`)

Restart your session afterwards; subagents load at session start.
