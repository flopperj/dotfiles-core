#!/usr/bin/env bash
# lib-brew.sh — install the Homebrew formulae core skills need, from a brew.txt
# manifest. Sourced by core's install.sh and overlay's install-overlay.sh.
# Idempotent and best-effort: an installed formula is skipped, and a missing
# brew or a failed install warns without aborting the caller.

# _install_brew_formulae <dir>
#   <dir> holds ./brew.txt (core convention) or ./.claude/brew.txt (overlay
#   convention); the first one found wins. Skips entirely when
#   DOTFILES_SKIP_BREW=1 (install.sh --skip-brew) or no manifest exists.
_install_brew_formulae() {
    local base_dir="$1" manifest="" line formula
    [ "${DOTFILES_SKIP_BREW:-}" = 1 ] && { echo "  Skipping Homebrew formulae (--skip-brew)"; return 0; }
    if [ -f "$base_dir/brew.txt" ]; then
        manifest="$base_dir/brew.txt"
    elif [ -f "$base_dir/.claude/brew.txt" ]; then
        manifest="$base_dir/.claude/brew.txt"
    else
        return 0
    fi

    local formulae=()
    while IFS= read -r line || [ -n "$line" ]; do
        formula="${line%%#*}"
        formula="${formula//[[:space:]]/}"
        [ -n "$formula" ] && formulae+=("$formula")
    done < "$manifest"
    [ "${#formulae[@]}" -gt 0 ] || return 0

    if ! command -v brew &>/dev/null; then
        echo "  Homebrew not found; skipping formulae. Install them yourself: ${formulae[*]}"
        return 0
    fi

    for formula in "${formulae[@]}"; do
        if brew list --versions "$formula" &>/dev/null; then
            echo "  Homebrew formula already installed: $formula"
            continue
        fi
        echo "  Installing Homebrew formula: $formula (can take several minutes)"
        if ! brew install "$formula" 2>&1 | sed 's/^/    /'; then
            echo "  WARNING: Failed to install Homebrew formula: $formula" >&2
        fi
    done
}
