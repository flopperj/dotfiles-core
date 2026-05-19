#!/usr/bin/env bash
# lib-core-symlinks.sh — symlink management for dotfiles-core.
# Sourced by install.sh; CORE_DIR and HOME are set by the orchestrator.

# shellcheck source=scripts/_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Remove symlinks in a target directory whose targets no longer exist.
_clean_stale_symlinks() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    for link in "$dir"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            rm "$link"
            echo "  Removed stale symlink: $(basename "$link")"
        fi
    done
}

# Move a colliding non-symlink file/dir to a .bak with a counter suffix so
# repeated calls on the same target in the same second never overwrite a prior
# backup.  Tests can pin the base suffix via _BACKUP_SUFFIX_OVERRIDE.
# Shape: <path>.bak.<suffix>  then  <path>.bak.<suffix>.1  .2  ... until free.
_backup_collision() {
    local path="$1"
    local base_suffix="${_BACKUP_SUFFIX_OVERRIDE:-$(date +%s)}"
    local backup="${path}.bak.${base_suffix}"
    local counter=1
    while [ -e "$backup" ]; do
        backup="${path}.bak.${base_suffix}.${counter}"
        counter=$((counter + 1))
    done
    if ! mv "$path" "$backup"; then
        echo "  ERROR: failed to back up $path to $backup" >&2
        return 1
    fi
    echo "  Backed up to $backup"
}

# Symlink a single file: remove existing symlink, back up collision, create new link.
_link_file() {
    local src="$1"
    local dst="$2"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -f "$dst" ]; then
        echo "  WARNING: $dst exists and is not a symlink. Backing up."
        _backup_collision "$dst"
    fi
    ln -s "$src" "$dst"
}

# Symlink a single directory: remove existing symlink, back up collision dir, create new link.
_link_dir() {
    local src="$1"
    local dst="$2"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -d "$dst" ]; then
        echo "  WARNING: $dst exists and is not a symlink. Backing up."
        _backup_collision "$dst"
    fi
    ln -s "$src" "$dst"
}

# Install scripts/pre-commit.sh as a symlink at .git/hooks/pre-commit.
# Skips when .git is a file (submodule worktree — hook management belongs to the
# parent repo in that case). Idempotent: removes a pre-existing symlink before
# re-creating it so a re-run after a core_dir path change stays correct.
# Usage: _install_precommit_hook <core_dir>
_install_precommit_hook() {
    local core_dir="$1"
    local git_entry="$core_dir/.git"
    local hook_src="$core_dir/scripts/pre-commit.sh"
    local hook_dst="$core_dir/.git/hooks/pre-commit"

    # Test-isolation bypass: tests/install.bats sets this to prevent writing to
    # the real .git/hooks/ directory during install.sh integration tests. The
    # dedicated tests/install-precommit-hook.bats does NOT set this — it tests
    # this function in proper isolation using a scratch fixture core.
    if [ -n "${_SKIP_PRECOMMIT_INSTALL:-}" ]; then
        return 0
    fi

    # Skip submodule worktrees where .git is a file, not a directory.
    if [ ! -d "$git_entry" ]; then
        return 0
    fi

    mkdir -p "$core_dir/.git/hooks"

    # Remove existing symlink so the link target stays current.
    # If a regular file exists (husky, lefthook, hand-written hook), back it up
    # before symlinking — mirrors the _link_file pattern.
    if [ -L "$hook_dst" ]; then
        rm "$hook_dst"
    elif [ -f "$hook_dst" ]; then
        echo "  WARNING: existing pre-commit hook at $hook_dst — backing up."
        _backup_collision "$hook_dst"
    fi

    ln -s "$hook_src" "$hook_dst"
    chmod +x "$hook_dst"
    echo "  Installed pre-commit hook -> scripts/pre-commit.sh"
}

# Create all dotfiles-core symlinks in $HOME.
# Usage: install_core_symlinks <core_dir>
install_core_symlinks() {
    local core_dir="$1"

    mkdir -p "$HOME/.claude"

    # --- _shared directory ---
    if [ -d "$core_dir/.claude/_shared" ]; then
        _link_dir "$core_dir/.claude/_shared" "$HOME/.claude/_shared"
        echo "  Linked _shared"
    fi

    # --- Agents ---
    mkdir -p "$HOME/.claude/agents"
    _clean_stale_symlinks "$HOME/.claude/agents"

    local agent_file
    for agent_file in "$core_dir/.claude/agents/"*.md; do
        [ -f "$agent_file" ] || continue
        local filename
        filename="$(basename "$agent_file")"
        _link_file "$agent_file" "$HOME/.claude/agents/$filename"
        echo "  Linked agent: $filename"
    done

    # --- Skills ---
    mkdir -p "$HOME/.claude/skills"
    _clean_stale_symlinks "$HOME/.claude/skills"

    local skill_dir
    while IFS= read -r skill_dir; do
        local dirname
        dirname="$(basename "$skill_dir")"
        _link_dir "$skill_dir" "$HOME/.claude/skills/$dirname"
        echo "  Linked skill: $dirname"
    done < <(_iter_core_skill_dirs "$core_dir")

    # --- Hooks ---
    if [ -d "$core_dir/.claude/hooks" ]; then
        mkdir -p "$HOME/.claude/hooks"
        _clean_stale_symlinks "$HOME/.claude/hooks"

        local hook_file
        for hook_file in "$core_dir/.claude/hooks/"*; do
            [ -f "$hook_file" ] || continue
            local hook_name
            hook_name="$(basename "$hook_file")"
            _link_file "$hook_file" "$HOME/.claude/hooks/$hook_name"
            echo "  Linked hook: $hook_name"
        done
    fi

    # --- Generated CLAUDE.md and AGENTS.md ---
    # Symlink the core-only rendered views so ~/.claude/CLAUDE.md and
    # ~/.claude/AGENTS.md are always up-to-date with the latest fragments.
    # The overlay installer may later re-point these symlinks at its own
    # overlay-rendered versions — that is intentional.
    local claude_gen="$core_dir/.claude/CLAUDE.md.generated"
    local agents_gen="$core_dir/.claude/AGENTS.md.generated"

    if [ -f "$claude_gen" ]; then
        _link_file "$claude_gen" "$HOME/.claude/CLAUDE.md"
        echo "  Linked CLAUDE.md -> CLAUDE.md.generated"
    fi

    if [ -f "$agents_gen" ]; then
        _link_file "$agents_gen" "$HOME/.claude/AGENTS.md"
        echo "  Linked AGENTS.md -> AGENTS.md.generated"
    fi
}
