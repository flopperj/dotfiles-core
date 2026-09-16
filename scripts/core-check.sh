#!/usr/bin/env bash
# core-check.sh — report symlink health for dotfiles-core install.
# Sourced by install.sh when --check is passed; CORE_DIR and HOME are set by caller.

# shellcheck source=scripts/_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Report one linked entry. Prints a status line; returns 1 on an error state.
# In the yadm layout a real (non-symlink) entry at the path is overlay-owned
# and expected, so it reports ok.
# Usage: _check_entry <link> <label> <layout>
_check_entry() {
    local link="$1" label="$2" layout="$3"
    if [ -L "$link" ] && [ -e "$link" ]; then
        echo "  ok    $label"
    elif [ -L "$link" ]; then
        echo "  BROKEN $label (dead symlink)"
        return 1
    elif [ -e "$link" ] && [ "$layout" = "yadm" ]; then
        echo "  ok    $label (overlay-owned, yadm layout)"
    elif [ -e "$link" ]; then
        echo "  COLLISION $label (exists and is not a symlink; re-run install.sh)"
        return 1
    else
        echo "  MISSING $label"
        return 1
    fi
}

# Walk a core directory and check each shipped entry under the merged
# destination, descending where both sides are real directories.
# Returns the number of failing entries.
# Usage: _check_tree <core-src-dir> <home-dst-dir> <layout>
_check_tree() {
    local src="$1" dst="$2" layout="$3"
    local failures=0 child name target
    for child in "$src"/* "$src"/.[!.]*; do
        [ -e "$child" ] || continue
        name="$(basename "$child")"
        target="$dst/$name"
        if [ -d "$child" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
            _check_tree "$child" "$target" "$layout" || failures=$((failures + $?))
        else
            _check_entry "$target" "${target#"$HOME"/.claude/}" "$layout" || failures=$((failures + 1))
        fi
    done
    return "$failures"
}

run_core_check() {
    local core_dir="$1"
    local errors=0
    local layout
    layout="$(_detect_layout)"

    echo "dotfiles-core symlink health check (layout: $layout)"
    echo "==================================="

    # Check agents
    echo ""
    echo "Agents (~/.claude/agents/):"
    local agent_file
    for agent_file in "$core_dir/.claude/agents/"*.md; do
        [ -f "$agent_file" ] || continue
        local filename
        filename="$(basename "$agent_file")"
        _check_entry "$HOME/.claude/agents/$filename" "$filename" "$layout" || errors=$((errors + 1))
    done

    # Check skills
    echo ""
    echo "Skills (~/.claude/skills/):"
    local skill_dir
    while IFS= read -r skill_dir; do
        local dirname
        dirname="$(basename "$skill_dir")"
        _check_entry "$HOME/.claude/skills/$dirname" "$dirname" "$layout" || errors=$((errors + 1))
    done < <(_iter_core_skill_dirs "$core_dir")

    # Check _shared and evals — merged directories: every entry core ships
    # must be a live symlink inside a real directory (overlay-owned siblings
    # are ignored).
    local merged
    for merged in _shared evals; do
        echo ""
        echo "$merged (~/.claude/$merged/):"
        local merged_dst="$HOME/.claude/$merged"
        if [ -L "$merged_dst" ]; then
            if _symlink_targets "$merged_dst" "$core_dir"; then
                echo "  STALE $merged is a whole-directory symlink (re-run install.sh to merge per entry)"
            else
                echo "  COLLISION $merged (symlink to $(readlink "$merged_dst"), not managed by core)"
            fi
            errors=$((errors + 1))
        elif [ ! -d "$merged_dst" ]; then
            echo "  MISSING $merged"
            errors=$((errors + 1))
        else
            _check_tree "$core_dir/.claude/$merged" "$merged_dst" "$layout" || errors=$((errors + $?))
        fi
    done

    # Check workflows
    echo ""
    echo "Workflows (~/.claude/workflows/):"
    local workflow_file
    for workflow_file in "$core_dir/.claude/workflows/"*.js; do
        [ -f "$workflow_file" ] || continue
        local wf_filename
        wf_filename="$(basename "$workflow_file")"
        local wf_link="$HOME/.claude/workflows/$wf_filename"
        if [ -L "$wf_link" ] && [ -e "$wf_link" ]; then
            echo "  ok    $wf_filename"
        elif [ -L "$wf_link" ]; then
            echo "  BROKEN $wf_filename (dead symlink)"
            errors=$((errors + 1))
        else
            echo "  MISSING $wf_filename"
            errors=$((errors + 1))
        fi
    done

    # Check workflow schemas
    echo ""
    echo "Workflow schemas (~/.claude/workflows/schemas/):"
    local schema_file
    for schema_file in "$core_dir/.claude/workflows/schemas/"*.json; do
        [ -f "$schema_file" ] || continue
        local schema_filename
        schema_filename="$(basename "$schema_file")"
        local schema_link="$HOME/.claude/workflows/schemas/$schema_filename"
        if [ -L "$schema_link" ] && [ -e "$schema_link" ]; then
            echo "  ok    $schema_filename"
        elif [ -L "$schema_link" ]; then
            echo "  BROKEN $schema_filename (dead symlink)"
            errors=$((errors + 1))
        else
            echo "  MISSING $schema_filename"
            errors=$((errors + 1))
        fi
    done

    # Check generated files (CLAUDE.md and AGENTS.md symlinks)
    echo ""
    echo "Generated files (~/.claude/):"
    for gen_name in "CLAUDE.md" "AGENTS.md"; do
        local link="$HOME/.claude/$gen_name"
        if [ -L "$link" ] && [ -e "$link" ]; then
            local src
            src="$(readlink "$link")"
            local core_src="$core_dir/.claude/${gen_name}.generated"
            if [ "$src" != "$core_src" ]; then
                echo "  ok    $gen_name (symlink points outside core — overlay-managed; skipping freshness check)"
            else
                local tmp
                tmp="$(mktemp)"
                local frag_dir
                case "$gen_name" in
                    CLAUDE.md) frag_dir="claude-md" ;;
                    AGENTS.md) frag_dir="agents-md" ;;
                esac
                if bash -c "
                    source '$core_dir/scripts/lib-overlays.sh' 2>/dev/null
                    concat_fragments '$tmp' '$core_dir/_shared/$frag_dir' 2>/dev/null
                " 2>/dev/null; then
                    if cmp -s "$tmp" "$src" 2>/dev/null; then
                        echo "  ok    $gen_name (symlink good, render fresh)"
                    else
                        echo "  STALE $gen_name (fragments changed; re-run install.sh)"
                        errors=$((errors + 1))
                    fi
                else
                    echo "  ok    $gen_name (symlink good)"
                fi
                rm -f "$tmp"
            fi
        elif [ -L "$link" ]; then
            echo "  BROKEN $gen_name (dead symlink)"
            errors=$((errors + 1))
        else
            echo "  MISSING $gen_name"
            errors=$((errors + 1))
        fi
    done

    echo ""
    if [ "$errors" -eq 0 ]; then
        echo "All checks passed."
    else
        echo "$errors check(s) failed."
    fi

    return "$errors"
}
