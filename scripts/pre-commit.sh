#!/usr/bin/env bash
# pre-commit.sh — dotfiles-core pre-commit hook orchestrator.
#
# Installed at .git/hooks/pre-commit by install.sh.
# Runs on every commit; non-zero exit aborts the commit.
#
# Phase 1: leakage check.
# Phase 2: leakage check + render CLAUDE.md.generated and AGENTS.md.generated.
# Phase 3 will append: lint-agents.

set -euo pipefail

# git always invokes hooks from the repo root; git rev-parse is authoritative.
REPO_ROOT="$(git rev-parse --show-toplevel)"

bash "$REPO_ROOT/scripts/check-no-leakage.sh" "$REPO_ROOT"

# Render core-only view of CLAUDE.md and AGENTS.md from fragments.
# shellcheck source=scripts/lib-overlays.sh
source "$REPO_ROOT/scripts/lib-overlays.sh"

concat_fragments \
    "$REPO_ROOT/.claude/CLAUDE.md.generated" \
    "$REPO_ROOT/_shared/claude-md"

concat_fragments \
    "$REPO_ROOT/.claude/AGENTS.md.generated" \
    "$REPO_ROOT/_shared/agents-md"

# Stage generated files so they travel with the commit.
git add "$REPO_ROOT/.claude/CLAUDE.md.generated" "$REPO_ROOT/.claude/AGENTS.md.generated"
