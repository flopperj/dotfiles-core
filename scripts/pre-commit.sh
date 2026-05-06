#!/usr/bin/env bash
# pre-commit.sh — dotfiles-core pre-commit hook orchestrator.
#
# Installed at .git/hooks/pre-commit by install.sh.
# Runs on every commit; non-zero exit aborts the commit.
#
# Phase 1: leakage check.
# Phase 2 will append: render-fragments, role-guard-gen, boundaries-gen.
# Phase 3 will append: lint-agents.

set -euo pipefail

# git always invokes hooks from the repo root; git rev-parse is authoritative.
REPO_ROOT="$(git rev-parse --show-toplevel)"

bash "$REPO_ROOT/scripts/check-no-leakage.sh" "$REPO_ROOT"
