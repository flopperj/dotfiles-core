#!/usr/bin/env bash
# install.sh — dotfiles-core installer.
#
# Installs core Claude agents, skills, _shared docs, and agent-memory seeds
# into $HOME/.claude/. Does NOT handle yadm/CWS layouts, Jenkins MCP,
# Cursor mirroring, or Claude plugin installation — those belong in the
# dotfiles overlay installer.
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

if [ "$CHECK" = true ]; then
    # shellcheck source=scripts/core-check.sh
    source "$SCRIPTS_DIR/core-check.sh"
    run_core_check "$CORE_DIR"
    exit $?
fi

echo "Installing dotfiles-core from $CORE_DIR"

install_core_symlinks "$CORE_DIR"
_seed_core_agent_memory "$CORE_DIR"

echo "Done."
