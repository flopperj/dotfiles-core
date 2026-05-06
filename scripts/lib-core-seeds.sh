#!/usr/bin/env bash
# lib-core-seeds.sh — agent memory seeding for dotfiles-core.
# Sourced by install.sh; RESEED is set by the orchestrator.

# Seed agent memory from dotfiles-core seeds directory (seed-once behavior).
# Usage: _seed_core_agent_memory <core_dir>
_seed_core_agent_memory() {
    local seeds_dir="$1/.claude/agent-memory-seeds"
    [ -d "$seeds_dir" ] || return 0

    if [ "$RESEED" = true ]; then
        echo ""
        echo "  WARNING: --reseed will overwrite existing agent memory seed files."
        echo "  Agent-accumulated knowledge in seeded files will be lost."
        echo ""
    fi

    local seed_agent_dir
    for seed_agent_dir in "$seeds_dir"/*/; do
        [ -d "$seed_agent_dir" ] || continue
        local agent_name
        agent_name="$(basename "$seed_agent_dir")"
        local target_dir="$HOME/.claude/agent-memory/$agent_name"
        mkdir -p "$target_dir"

        local seed_file
        for seed_file in "$seed_agent_dir"*; do
            [ -f "$seed_file" ] || continue
            local filename
            filename="$(basename "$seed_file")"
            local target_file="$target_dir/$filename"

            if [ "$filename" = "MEMORY.md" ]; then
                if [ ! -f "$target_file" ] || [ "$RESEED" = true ]; then
                    cp "$seed_file" "$target_file"
                    if [ "$RESEED" = true ]; then
                        echo "    Reseeded $agent_name/MEMORY.md"
                    else
                        echo "    Seeded $agent_name/MEMORY.md"
                    fi
                else
                    while IFS= read -r line || [ -n "$line" ]; do
                        if [[ "$line" == "- ["* ]] && ! grep -qF -- "$line" "$target_file"; then
                            echo "$line" >> "$target_file"
                            echo "    Appended missing entry to $agent_name/MEMORY.md"
                        fi
                    done < "$seed_file"
                fi
            else
                if [ ! -f "$target_file" ] || [ "$RESEED" = true ]; then
                    cp "$seed_file" "$target_file"
                    if [ "$RESEED" = true ]; then
                        echo "    Reseeded $agent_name/$filename"
                    else
                        echo "    Seeded $agent_name/$filename"
                    fi
                fi
            fi
        done
    done
}
