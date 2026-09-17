#!/usr/bin/env bash
# lib-core-symlinks.sh — symlink management for dotfiles-core.
# Sourced by install.sh; CORE_DIR and HOME are set by the orchestrator.
#
# Ownership contract (PROTOCOL.md § Path ownership under ~/.claude):
#   * agents/, skills/, hooks/, workflows/ — per-entry symlinks into core.
#   * _shared/, evals/ — real directories; core links its own children into
#     them (recursively, merging with real sub-directories) and never touches
#     entries it did not ship. Overlays keep their own children there.
#   * In the yadm layout a real entry at a path core wants to link is
#     overlay-owned: core leaves it alone and says so. In the local layout a
#     real entry is a collision: identical content is replaced silently,
#     differing content is moved to ~/.claude/.backups/<ts>/<path> first.

# shellcheck source=scripts/_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Layout for this run. install.sh sets DOTFILES_LAYOUT once after detection;
# library functions read it lazily so unit tests can source this file and set
# it per call.
_layout() { printf '%s\n' "${DOTFILES_LAYOUT:-$(_detect_layout)}"; }

# Core checkout used by _link_entry's same-object guard when a caller passes
# no third argument (the historical _link_file/_link_dir signatures).
# install_core_symlinks sets it for the whole run.
_LINK_CORE_DIR="${_LINK_CORE_DIR:-}"

# Remove symlinks in a target directory whose targets no longer exist.
# With an optional prefix, only dead symlinks pointing under that prefix are
# removed — used for merged directories so an overlay's own dead links are
# never cleaned up by core.
# Usage: _clean_stale_symlinks <dir> [<only-targets-under-prefix>]
_clean_stale_symlinks() {
    local dir="$1"
    local prefix="${2:-}"
    [ -d "$dir" ] || return 0
    local link target
    for link in "$dir"/* "$dir"/.[!.]*; do
        [ -L "$link" ] && [ ! -e "$link" ] || continue
        if [ -n "$prefix" ]; then
            target="$(readlink "$link")"
            case "$target" in
                "$prefix"/*) ;;
                *) continue ;;
            esac
        fi
        rm "$link"
        echo "  Removed stale symlink: $(basename "$link")"
    done
}

# Root of the relocated backup store.
_backup_root() { printf '%s\n' "${DOTFILES_BACKUP_ROOT:-$HOME/.claude/.backups}"; }

# Move a colliding non-symlink file/dir out of the way.
#
# Paths under $HOME move to <backup-root>/<suffix>/<path-relative-to-HOME>, so
# a backup never sits beside the live entry in a directory Claude Code scans
# (~/.claude/skills/, ~/.claude/agents/). Paths outside $HOME — for example the
# hooks of a checkout that lives outside your home directory — keep the
# historical sibling shape <path>.bak.<suffix>; a checkout under $HOME has its
# hook files under $HOME, so those backups relocate (and are pruned) too.
#
# A counter suffix is appended when the destination already exists, so
# repeated calls in the same second never overwrite a prior backup. Tests can
# pin the base suffix via _BACKUP_SUFFIX_OVERRIDE.
_backup_collision() {
    local path="$1"
    local base_suffix="${_BACKUP_SUFFIX_OVERRIDE:-$(date +%s)}"
    local backup counter=1
    case "$path" in
        "$HOME"/*)
            local rel="${path#"$HOME"/}"
            local root
            root="$(_backup_root)"
            backup="$root/$base_suffix/$rel"
            while [ -e "$backup" ]; do
                backup="$root/$base_suffix.$counter/$rel"
                counter=$((counter + 1))
            done
            mkdir -p "$(dirname "$backup")"
            ;;
        *)
            backup="${path}.bak.${base_suffix}"
            while [ -e "$backup" ]; do
                backup="${path}.bak.${base_suffix}.${counter}"
                counter=$((counter + 1))
            done
            ;;
    esac
    if ! mv "$path" "$backup"; then
        echo "  ERROR: failed to back up $path to $backup" >&2
        return 1
    fi
    echo "  Backed up to $backup"
}

# Remove backup sets older than DOTFILES_BACKUP_RETENTION_DAYS (default 30;
# 0, never or off keeps everything). Only sets this installer creates are
# candidates — <epoch>, <epoch>.<n> and legacy-<suffix> — so anything else a
# user parks under the backup root is left alone. Each install writes at most
# one set, so pruning by the set directory's own age is enough.
_prune_backups() {
    local root days
    root="$(_backup_root)"
    days="${DOTFILES_BACKUP_RETENTION_DAYS:-30}"
    case "$days" in
        0|never|off) return 0 ;;
        ''|*[!0-9]*)
            echo "  WARNING: DOTFILES_BACKUP_RETENTION_DAYS='$days' is not a number of days (or 0/never/off); backups were not pruned."
            return 0 ;;
    esac
    [ -d "$root" ] || return 0
    local set_dir name
    while IFS= read -r set_dir; do
        name="$(basename "$set_dir")"
        case "$name" in
            legacy-*) ;;
            *) [[ "$name" =~ ^[0-9]+(\.[0-9]+)?$ ]] || continue ;;
        esac
        rm -rf "$set_dir"
        echo "  Pruned backup set: $name"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -mtime "+$days" 2>/dev/null)
}

# Move sibling backups left by older cores out of directories the host scans.
# Before v1.21.0 a collision became <path>.bak.<ts> next to the live entry, so
# ~/.claude/skills/<name>.bak.<ts> was loaded by Claude Code as a skill. Each
# such entry (skills, agents, and the whole-directory _shared/evals backups)
# moves to <backup-root>/legacy-<suffix>/<path-relative-to-HOME>. Nothing is
# deleted here; the set then ages out under the normal retention window.
_relocate_legacy_backups() {
    local root suffix entry rel moved=0
    root="$(_backup_root)"
    suffix="legacy-${_BACKUP_SUFFIX_OVERRIDE:-$(date +%s)}"
    for entry in "$HOME/.claude/skills/"*.bak.* "$HOME/.claude/agents/"*.bak.* \
                 "$HOME/.claude/"_shared.bak.* "$HOME/.claude/"evals.bak.*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        rel="${entry#"$HOME"/}"
        mkdir -p "$root/$suffix/$(dirname "$rel")"
        mv "$entry" "$root/$suffix/$rel"
        moved=$((moved + 1))
    done
    if [ "$moved" -gt 0 ]; then
        echo "  Moved $moved legacy backup(s) out of ~/.claude into $root/$suffix/"
    fi
    return 0
}

# True when two paths have identical content (files: cmp; dirs: diff -rq).
_same_content() {
    local a="$1" b="$2"
    if [ -d "$a" ] && [ -d "$b" ]; then
        diff -rq "$a" "$b" >/dev/null 2>&1
    elif [ -f "$a" ] && [ -f "$b" ]; then
        cmp -s "$a" "$b"
    else
        return 1
    fi
}

# Link one entry (file or directory) from core into $HOME.
#
#   symlink at dst, already pointing at src  → no-op
#   dst is src itself, or sits inside the core checkout (a ~/.claude or
#     ~/.claude/skills that is a symlink into core) → left alone with a note;
#     core never removes, backs up or creates anything inside its own tree
#   dst is the real ~/.claude/_shared or ~/.claude/evals directory → left
#     alone; those are merged per entry, never collapsed to one symlink
#   symlink at dst, pointing elsewhere       → replaced
#   real entry, yadm layout                  → kept (overlay-owned); a note is
#                                              printed, WARNING when it differs
#   real entry, local layout, identical      → replaced without backup
#   real entry, local layout, differs        → backed up, then linked
#
# Returns 0 in every handled case so callers under `set -e` keep going.
# Usage: _link_entry <src> <dst> [<core-dir>]   (default: _LINK_CORE_DIR)
_link_entry() {
    local src="$1"
    local dst="$2"
    local core_dir="${3:-$_LINK_CORE_DIR}"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        return 0
    fi
    if [ ! -L "$dst" ] && [ -e "$dst" ] && [ "$src" -ef "$dst" ]; then
        echo "  Left in place (already the core file itself): $dst"
        return 0
    fi
    if _path_inside "$dst" "$core_dir"; then
        echo "  Skipped (inside the core checkout): $dst"
        return 0
    fi
    case "$dst" in
        "$HOME/.claude/_shared"|"$HOME/.claude/evals")
            if [ -d "$dst" ] && [ ! -L "$dst" ]; then
                echo "  Left in place (merged directory, never replaced by one symlink): $dst"
                return 0
            fi ;;
    esac
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        if [ "$(_layout)" = "yadm" ]; then
            if _same_content "$src" "$dst"; then
                echo "  Kept overlay-owned entry (identical to core): $dst"
            else
                echo "  WARNING: $dst is overlay-owned and differs from core — kept as-is (yadm layout)."
                echo "           Drop the overlay copy if core is canonical for it."
            fi
            return 0
        fi
        if _same_content "$src" "$dst"; then
            rm -rf "$dst"
        else
            echo "  WARNING: $dst exists and is not a symlink. Backing up."
            _backup_collision "$dst"
        fi
    fi
    ln -s "$src" "$dst"
}

# Historical names, kept for callers and tests; both delegate to _link_entry.
_link_file() { _link_entry "$1" "$2"; }
_link_dir()  { _link_entry "$1" "$2"; }

# Merge-link a core directory into a real directory under $HOME.
#
# dst becomes (or stays) a real directory. Every child of src is linked into
# it with _link_entry; when both sides have a real directory of the same name
# the merge descends instead of colliding. Entries in dst that core did not
# ship — an overlay's *.d/ fragment dirs, overlay-context.md, leakage
# tokens — are never touched. A whole-directory symlink into the core
# checkout, left by an older core, is replaced by the merged directory; a
# symlink to anywhere else is not core's to remove, so it is left alone with
# a WARNING and this root is skipped. A dst that is core's own directory
# (through a symlinked ~/.claude) is left alone too.
# Usage: _merge_link_tree <src-dir> <dst-dir> <core-dir>
_merge_link_tree() {
    local src="$1"
    local dst="$2"
    local core_dir="$3"

    if [ ! -L "$dst" ] && [ -d "$dst" ] && [ "$src" -ef "$dst" ]; then
        echo "  Left in place (already the core directory itself): $dst"
        return 0
    fi
    if _path_inside "$dst" "$core_dir"; then
        echo "  Skipped (inside the core checkout): $dst"
        return 0
    fi
    if [ -L "$dst" ]; then
        if _symlink_targets "$dst" "$core_dir"; then
            rm "$dst"
        else
            echo "  WARNING: $dst is a symlink to $(readlink "$dst") (not managed by core) — left untouched; core's $(basename "$dst") entries were not merged. Remove the symlink to let core merge them."
            return 0
        fi
    elif [ -e "$dst" ] && [ ! -d "$dst" ]; then
        echo "  WARNING: $dst exists and is not a directory. Backing up."
        _backup_collision "$dst"
    fi
    mkdir -p "$dst"
    _clean_stale_symlinks "$dst" "$core_dir"

    local child name target
    for child in "$src"/* "$src"/.[!.]*; do
        [ -e "$child" ] || continue
        name="$(basename "$child")"
        target="$dst/$name"
        if [ -d "$child" ] && [ ! -L "$child" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
            _merge_link_tree "$child" "$target" "$core_dir"
        else
            _link_entry "$child" "$target"
        fi
    done
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
    _LINK_CORE_DIR="$core_dir"

    mkdir -p "$HOME/.claude"
    _relocate_legacy_backups
    _prune_backups

    # --- _shared and evals: merged directories ---
    # Core links its own children into a real directory so overlay-owned
    # children (fragment *.d/ dirs, overlay-context.md, leakage-tokens.txt,
    # overlay eval scripts) survive at the same paths.
    if [ -d "$core_dir/.claude/_shared" ]; then
        _merge_link_tree "$core_dir/.claude/_shared" "$HOME/.claude/_shared" "$core_dir"
        echo "  Linked _shared (per entry)"
    fi

    if [ -d "$core_dir/.claude/evals" ]; then
        _merge_link_tree "$core_dir/.claude/evals" "$HOME/.claude/evals" "$core_dir"
        echo "  Linked evals (per entry)"
    fi

    # --- Agents ---
    mkdir -p "$HOME/.claude/agents"
    _clean_stale_symlinks "$HOME/.claude/agents"

    local agent_file
    for agent_file in "$core_dir/.claude/agents/"*.md; do
        [ -f "$agent_file" ] || continue
        local filename
        filename="$(basename "$agent_file")"
        _link_entry "$agent_file" "$HOME/.claude/agents/$filename"
        echo "  Linked agent: $filename"
    done

    # --- Skills ---
    mkdir -p "$HOME/.claude/skills"
    _clean_stale_symlinks "$HOME/.claude/skills"

    local skill_dir
    while IFS= read -r skill_dir; do
        local dirname
        dirname="$(basename "$skill_dir")"
        _link_entry "${skill_dir%/}" "$HOME/.claude/skills/$dirname"
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
            _link_entry "$hook_file" "$HOME/.claude/hooks/$hook_name"
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
            _link_entry "$workflow_file" "$HOME/.claude/workflows/$workflow_name"
            echo "  Linked workflow: $workflow_name"
        done

        # Handoff schemas are read at runtime from ~/.claude/workflows/schemas/
        # by the workflow-consuming skills, so they must be linked per-file too.
        if [ -d "$core_dir/.claude/workflows/schemas" ]; then
            mkdir -p "$HOME/.claude/workflows/schemas"
            _clean_stale_symlinks "$HOME/.claude/workflows/schemas"

            local schema_file
            for schema_file in "$core_dir/.claude/workflows/schemas/"*.json; do
                [ -f "$schema_file" ] || continue
                local schema_name
                schema_name="$(basename "$schema_file")"
                _link_entry "$schema_file" "$HOME/.claude/workflows/schemas/$schema_name"
                echo "  Linked workflow schema: $schema_name"
            done
        fi
    fi

    # --- Generated CLAUDE.md and AGENTS.md ---
    # Symlink the core-only rendered views so ~/.claude/CLAUDE.md and
    # ~/.claude/AGENTS.md are always up-to-date with the latest fragments.
    # The overlay installer may later re-point these symlinks at its own
    # overlay-rendered versions — that is intentional.
    local claude_gen="$core_dir/.claude/CLAUDE.md.generated"
    local agents_gen="$core_dir/.claude/AGENTS.md.generated"

    if [ -f "$claude_gen" ]; then
        _link_entry "$claude_gen" "$HOME/.claude/CLAUDE.md"
        echo "  Linked CLAUDE.md -> CLAUDE.md.generated"
    fi

    if [ -f "$agents_gen" ]; then
        _link_entry "$agents_gen" "$HOME/.claude/AGENTS.md"
        echo "  Linked AGENTS.md -> AGENTS.md.generated"
    fi
}
