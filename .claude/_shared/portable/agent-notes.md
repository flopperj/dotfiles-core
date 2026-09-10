## Portable bundle notes

This agent definition ships inside the `{{SKILL}}` skill directory and may run
either as a registered subagent or as a `general-purpose` subagent primed with
this file (see the skill's *Launching the agent* section).

- **Skills are optional.** Any other `/skill` named below
  (`/pr-create-from-commits`, `/review-context`, `/swarm-retro`,
  `/smart-compact`, `/create-*`, `/google-*`, `/mermaid-diagrams`,
  `/code-review`, the `frontend-design` plugin) that is not in your
  available-skills list is unavailable: perform the action directly instead of
  invoking it. For PR creation that means `gh pr create --draft`, honouring the
  repository's PR template.
- **Personal context is optional.** `~/.claude/AGENTS.md`, `~/.claude/DoD.md`,
  and `~/.claude/project-templates/` are the maintainer's files. Use them if
  they exist; otherwise the inline rule beside each citation applies.
- **Memory applies only when registered.** The Persistent Agent Memory
  section below is live only when you run as a registered subagent with a
  memory directory. If your brief says no persistent memory is available,
  skip that section entirely.
- **Runtime paths come from the brief.** Use the `Runtime paths` block in your
  brief (`SKILL_DIR`, `PLAN_BASE`) rather than assuming a layout.
- **Tool restrictions in this file's frontmatter (`disallowedTools`) apply in
  every mode.** When running as a registered subagent the harness enforces
  them; when running as `general-purpose` it does not, so enforce them
  yourself — treat every tool named there as unavailable regardless of what
  the runtime otherwise permits.
- **Completion sentinel.** This bundle ships outside the maintainer's
  `~/.claude/AGENTS.md`, so state it here explicitly: when you finish a run
  and your final message is ready, end it with the literal token on its own
  line — `<<task-complete>>` — so the orchestrator can tell a completed run
  from one truncated at your turn cap. Emit it only when genuinely done, once,
  at the very end. Omit it if you hit a blocker and cannot complete; state the
  blocker instead.
