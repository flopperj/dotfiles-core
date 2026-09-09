## Portable bundle notes

This skill is one of a bundle exported from the maintainer's canonical
`dotfiles-core` repository. Read these notes before following the rest of the
document.

- **Sibling skills.** Skills named in this document that belong to the bundle
  (`aristotle-deconstructor`, `optimus-planner`, `cyrus-tdd-engineer`, `forge`,
  `grill-me`, `to-prd`, `code-auditor`, `scout-reviewer`, `ranger-reviewer`)
  are installed as siblings of this directory. If one is named but missing
  from your available-skills list, stop and tell the user to install it from
  the same skills repository this bundle came from. If the host has no Skill
  tool, read `SKILL_DIR/../<skill>/SKILL.md` and follow it inline.
- **Optional external skills.** Any other `/skill` named here
  (`/pr-create-from-commits`, `/review-context`, `/swarm-retro`,
  `/smart-compact`, `/create-*`, `/mc-*`, `/google-*`, `/mermaid-diagrams`,
  the `frontend-design` plugin) is optional and not part of this bundle. Use
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
