# Claude Code-Specific Supplement

> **Canonical source: [AGENTS.md](./AGENTS.md).** Start there. AGENTS.md holds the editor-agnostic agent behavior — output style, reasoning depth, workflow orchestration, task management, code comments, error handling defaults, PR review drafting rules, and frontend design token requirements. This file holds **only** Claude-Code-runtime-specific supplements: slash commands, skill routing, harness-specific tooling, and PR-creation workflow nuances tied to the `/pr-create-from-commits` skill.

> **Dotfiles structure note**: This file is generated from numbered fragments by `lib-overlays.sh`. The source fragments live in `_shared/claude-md/` (core) and `_shared/claude-md.d/` (overlay). Edit the fragments, not this file directly; regenerate by running `scripts/pre-commit.sh` or `install.sh`.

---
