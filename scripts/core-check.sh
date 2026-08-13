#!/usr/bin/env bash
# core-check.sh — report symlink health for dotfiles-core install.
# Sourced by install.sh when --check is passed; CORE_DIR and HOME are set by caller.

# shellcheck source=scripts/_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

run_core_check() {
    local core_dir="$1"
    local errors=0

    echo "dotfiles-core symlink health check"
    echo "==================================="

    # Check agents
    echo ""
    echo "Agents (~/.claude/agents/):"
    local agent_file
    for agent_file in "$core_dir/.claude/agents/"*.md; do
        [ -f "$agent_file" ] || continue
        local filename
        filename="$(basename "$agent_file")"
        local link="$HOME/.claude/agents/$filename"
        if [ -L "$link" ] && [ -e "$link" ]; then
            echo "  ok    $filename"
        elif [ -L "$link" ]; then
            echo "  BROKEN $filename (dead symlink)"
            errors=$((errors + 1))
        else
            echo "  MISSING $filename"
            errors=$((errors + 1))
        fi
    done

    # Check skills
    echo ""
    echo "Skills (~/.claude/skills/):"
    local skill_dir
    while IFS= read -r skill_dir; do
        local dirname
        dirname="$(basename "$skill_dir")"
        local link="$HOME/.claude/skills/$dirname"
        if [ -L "$link" ] && [ -e "$link" ]; then
            echo "  ok    $dirname"
        elif [ -L "$link" ]; then
            echo "  BROKEN $dirname (dead symlink)"
            errors=$((errors + 1))
        else
            echo "  MISSING $dirname"
            errors=$((errors + 1))
        fi
    done < <(_iter_core_skill_dirs "$core_dir")

    # Check _shared
    echo ""
    echo "_shared (~/.claude/_shared):"
    local shared_link="$HOME/.claude/_shared"
    if [ -L "$shared_link" ] && [ -e "$shared_link" ]; then
        echo "  ok    _shared"
    elif [ -L "$shared_link" ]; then
        echo "  BROKEN _shared (dead symlink)"
        errors=$((errors + 1))
    else
        echo "  MISSING _shared"
        errors=$((errors + 1))
    fi

    # Check evals
    echo ""
    echo "evals (~/.claude/evals):"
    local evals_link="$HOME/.claude/evals"
    if [ -L "$evals_link" ] && [ -e "$evals_link" ]; then
        echo "  ok    evals"
    elif [ -L "$evals_link" ]; then
        echo "  BROKEN evals (dead symlink)"
        errors=$((errors + 1))
    else
        echo "  MISSING evals"
        errors=$((errors + 1))
    fi

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
