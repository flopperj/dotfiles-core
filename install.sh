#!/usr/bin/env bash
# install.sh — dotfiles-core installer.
#
# Installs core Claude agents, skills, _shared docs, agent-memory seeds,
# and universal Claude Code plugins into $HOME/.claude/.
# Universal plugins (frontend-design, playwright) are declared in plugins.txt
# at the repo root and installed via scripts/lib-plugins.sh. Homebrew formulae
# core skills need (ffmpeg for record-demo) are declared in brew.txt and
# installed via scripts/lib-brew.sh when brew is present.
# Layout-aware: in the local layout (repo in its own directory) it symlinks
# into ~/.claude/; in the yadm/CWS layout (overlay checked out into $HOME) it
# merges around overlay-owned entries instead of backing them up. See
# PROTOCOL.md § Path ownership under ~/.claude. Jenkins MCP, Cursor
# mirroring, and company-specific plugins belong in the overlay installer.
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
    echo "  --skip-brew  Do not install the Homebrew formulae in brew.txt"
    echo "  --help     Show this help message"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)  CHECK=true ;;
        --reseed) RESEED=true; export RESEED ;;
        --skip-brew) DOTFILES_SKIP_BREW=1; export DOTFILES_SKIP_BREW ;;
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
# shellcheck source=scripts/lib-brew.sh
source "$SCRIPTS_DIR/lib-brew.sh"

# Detect the layout once so every library function in this run agrees on the
# answer. The export reaches only this process and its children; an overlay
# runs core as a child process (`bash …/install.sh`) and sources its own steps
# afterwards, so it must detect the layout itself — source scripts/_lib.sh and
# call _detect_layout, or use its own DOTFILES_DIR == $HOME check.
DOTFILES_LAYOUT="$(_detect_layout)"
export DOTFILES_LAYOUT

if [ "$CHECK" = true ]; then
    # shellcheck source=scripts/core-check.sh
    source "$SCRIPTS_DIR/core-check.sh"
    run_core_check "$CORE_DIR"
    exit $?
fi

echo "Installing dotfiles-core from $CORE_DIR (layout: $DOTFILES_LAYOUT)"

install_core_symlinks "$CORE_DIR"
_install_precommit_hook "$CORE_DIR"
_install_prepush_hook "$CORE_DIR"
_seed_core_agent_memory "$CORE_DIR"
_install_cli_and_plugins "$CORE_DIR"
_install_brew_formulae "$CORE_DIR"

echo "Done."
