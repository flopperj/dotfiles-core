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

# Install scripts/<hook_name>.sh as a symlink at .git/hooks/<hook_name>.
# Resolves the real gitdir via `git rev-parse --git-dir` so hooks install in
# standalone clones and submodule worktrees (.git is a file pointing elsewhere).
# Idempotent: removes a pre-existing symlink before re-creating it so a re-run
# after a core_dir path change stays correct.
# Usage: _install_git_hook <core_dir> <hook_name>
_install_git_hook() {
    local core_dir="$1"
    local hook_name="$2"
    local git_dir hook_src hook_dst

    # Test-isolation bypass: tests/install.bats sets this to prevent writing to
    # the real .git/hooks/ directory during install.sh integration tests. The
    # variable keeps its historical name but bypasses ALL git-hook installs.
    # The dedicated tests/install-precommit-hook.bats does NOT set this — it
    # tests this function in proper isolation using a scratch fixture core.
    if [ -n "${_SKIP_PRECOMMIT_INSTALL:-}" ]; then
        return 0
    fi

    if ! git_dir="$(git -C "$core_dir" rev-parse --git-dir 2>/dev/null)"; then
        return 0
    fi
    if [[ "$git_dir" != /* ]]; then
        git_dir="$core_dir/$git_dir"
    fi

    hook_src="$core_dir/scripts/${hook_name}.sh"
    hook_dst="$git_dir/hooks/${hook_name}"

    mkdir -p "$git_dir/hooks"

    # Remove existing symlink so the link target stays current.
    # If a regular file exists (husky, lefthook, hand-written hook), back it up
    # before symlinking — mirrors the _link_file pattern.
    if [ -L "$hook_dst" ]; then
        rm "$hook_dst"
    elif [ -f "$hook_dst" ]; then
        echo "  WARNING: existing ${hook_name} hook at $hook_dst — backing up."
        _backup_collision "$hook_dst"
    fi

    ln -s "$hook_src" "$hook_dst"
    chmod +x "$hook_dst"
    echo "  Installed ${hook_name} hook -> scripts/${hook_name}.sh"
}

_install_precommit_hook() { _install_git_hook "$1" "pre-commit"; }
_install_prepush_hook() { _install_git_hook "$1" "pre-push"; }

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

    # --- evals directory ---
    if [ -d "$core_dir/.claude/evals" ]; then
        _link_dir "$core_dir/.claude/evals" "$HOME/.claude/evals"
        echo "  Linked evals"
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

    # --- Workflows ---
    if [ -d "$core_dir/.claude/workflows" ]; then
        mkdir -p "$HOME/.claude/workflows"
        _clean_stale_symlinks "$HOME/.claude/workflows"

        local workflow_file
        for workflow_file in "$core_dir/.claude/workflows/"*.js; do
            [ -f "$workflow_file" ] || continue
            local workflow_name
            workflow_name="$(basename "$workflow_file")"
            _link_file "$workflow_file" "$HOME/.claude/workflows/$workflow_name"
            echo "  Linked workflow: $workflow_name"
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
