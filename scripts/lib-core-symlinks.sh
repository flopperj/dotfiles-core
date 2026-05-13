#!/usr/bin/env bash
# lib-core-symlinks.sh — symlink management for dotfiles-core.
# Sourced by install.sh; CORE_DIR and HOME are set by the orchestrator.

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
    for skill_dir in "$core_dir/.claude/skills/"/*/; do
        [ -d "$skill_dir" ] || continue
        local dirname
        dirname="$(basename "$skill_dir")"
        _link_dir "$skill_dir" "$HOME/.claude/skills/$dirname"
        echo "  Linked skill: $dirname"
    done

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
