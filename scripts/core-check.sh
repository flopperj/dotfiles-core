#!/usr/bin/env bash
# core-check.sh — report symlink health for dotfiles-core install.
# Sourced by install.sh when --check is passed; CORE_DIR and HOME are set by caller.

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
    for skill_dir in "$core_dir/.claude/skills/"/*/; do
        [ -d "$skill_dir" ] || continue
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
    done

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

    echo ""
    if [ "$errors" -eq 0 ]; then
        echo "All checks passed."
    else
        echo "$errors check(s) failed."
    fi

    return "$errors"
}
