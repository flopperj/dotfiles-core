#!/usr/bin/env bash
# install.sh — dotfiles-core installer.
#
# Installs core Claude agents, skills, _shared docs, agent-memory seeds,
# and universal Claude Code plugins into $HOME/.claude/.
# Universal plugins (frontend-design, playwright) are declared in plugins.txt
# at the repo root and installed via scripts/lib-plugins.sh.
# Does NOT handle yadm/CWS layouts, Jenkins MCP, or Cursor mirroring —
# those belong in the dotfiles overlay installer.
# Company-specific plugins belong in the overlay's .claude/plugins.txt.
set -euo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CORE_DIR/scripts"

export RESEED=false
CHECK=false

_usage() {
    echo "Usage: install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --check    Report symlink health without modifying anything"
    echo "  --reseed   Force-overwrite agent memory seed files"
    echo "  --help     Show this help message"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)  CHECK=true ;;
        --reseed) RESEED=true; export RESEED ;;
        --help)   _usage ;;
        *)        echo "Unknown option: $1" >&2; _usage ;;
    esac
    shift
done

# shellcheck source=scripts/lib-core-symlinks.sh
source "$SCRIPTS_DIR/lib-core-symlinks.sh"
# shellcheck source=scripts/lib-core-seeds.sh
source "$SCRIPTS_DIR/lib-core-seeds.sh"
# shellcheck source=scripts/lib-plugins.sh
source "$SCRIPTS_DIR/lib-plugins.sh"

if [ "$CHECK" = true ]; then
    # shellcheck source=scripts/core-check.sh
    source "$SCRIPTS_DIR/core-check.sh"
    run_core_check "$CORE_DIR"
    exit $?
fi

echo "Installing dotfiles-core from $CORE_DIR"

install_core_symlinks "$CORE_DIR"
_install_precommit_hook "$CORE_DIR"
_install_prepush_hook "$CORE_DIR"
_seed_core_agent_memory "$CORE_DIR"
_install_cli_and_plugins "$CORE_DIR"

echo "Done."
