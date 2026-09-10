## Portable bundle notes

This skill is one of a bundle exported from the maintainer's canonical
`dotfiles-core` repository. Read these notes before following the rest of the
document.

{{DEPS}}

- **Sibling dependencies.** Skills listed above (if any) that belong to the
  bundle are installed as siblings of this directory. Everything up to the
  point where a sibling is needed runs normally; at that point, if the sibling
  is missing from your available-skills list, stop and tell the user to
  install it from the same skills repository this bundle came from (do not
  improvise a substitute). If the host has no Skill tool, read
  `SKILL_DIR/../<skill>/SKILL.md` and follow it inline.
  **Resolving `SKILL_DIR`:** it is the path shown as "Base directory for this skill" when this skill loaded; if the host does not show one, it is the
  directory containing this `SKILL.md` (e.g. `.claude/skills/<name>/` on a
  project install, `~/.agents/skills/<name>/` on a global install).
- **Optional external skills.** Any other `/skill` named here
  (`/pr-create-from-commits`, `/review-context`, `/swarm-retro`,
  `/smart-compact`, `/create-*`, `/mc-*`, `/google-*`, `/mermaid-diagrams`,
  `/code-review`, the `frontend-design` plugin) is optional and not part of
  this bundle. Use
  it only if it appears in your available-skills list; otherwise perform the
  action directly. For PR creation that means `gh pr create --draft`,
  honouring the repository's PR template.
- **Orchestrator-only modes.** `swarm_mode`, `execution_mode: autonomous`,
  and references to `ticket-swarm` / `ticket-pickup` describe behaviour when
  an orchestrating skill passes those flags. No such orchestrator ships in
  this bundle; on a direct invocation these paths are inactive.
- **Optional personal context.** `~/.claude/AGENTS.md`, `~/.claude/DoD.md`,
  `~/.claude/project-templates/`, and `~/.claude/review-context/` are the
  maintainer's personal files. Where this document cites one, use it if it
  exists; otherwise the inline rule beside the citation applies.
- **Runtime artifacts.** Plans and PRDs are written under
  `~/.claude/tasks/<project>/` (outside the repository). Directories are
  created on demand.
