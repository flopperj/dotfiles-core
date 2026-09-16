#!/usr/bin/env bats
# Tests for scripts/check-leakage-shapes.sh — secret-free structural scan.

load 'test_helper'

@test "check-leakage-shapes.sh exists and is executable" {
    [ -f "$CORE_DIR/scripts/check-leakage-shapes.sh" ]
    [ -x "$CORE_DIR/scripts/check-leakage-shapes.sh" ]
}

@test "clean tree exits 0" {
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$CORE_DIR"
    [ "$status" -eq 0 ]
}

@test "in-tree leakage-tokens.txt is flagged" {
    mkdir -p "$SCRATCH/bad/scripts"
    echo "xyzzy" > "$SCRATCH/bad/scripts/leakage-tokens.txt"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"leakage-tokens.txt"* ]]
    [[ "$output" == *"content withheld"* ]]
}

@test "dotfiles-guard material in tree is flagged" {
    mkdir -p "$SCRATCH/bad/dotfiles-guard"
    echo "marker" > "$SCRATCH/bad/dotfiles-guard/company-context"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dotfiles-guard"* ]]
}

@test "example.com email in skill prose is allowed" {
    mkdir -p "$SCRATCH/ok/.claude/skills/demo"
    printf '%s\n' '---' 'name: demo' '---' 'Contact user@example.com for help.' \
        > "$SCRATCH/ok/.claude/skills/demo/SKILL.md"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/ok"
    [ "$status" -eq 0 ]
}

@test "non-safe corporate email shape in skill prose is flagged" {
    mkdir -p "$SCRATCH/bad/.claude/skills/demo"
    printf '%s\n' '---' 'name: demo' '---' 'Escalate to owner@acme-corp.com immediately.' \
        > "$SCRATCH/bad/.claude/skills/demo/SKILL.md"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SKILL.md"* ]]
    [[ "$output" == *"content withheld"* ]]
}

@test "failure output never echoes the matched email" {
    mkdir -p "$SCRATCH/bad/.claude/agents"
    echo 'Reach dev@secret-org.io for access.' > "$SCRATCH/bad/.claude/agents/demo.md"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/bad"
    [ "$status" -eq 1 ]
    [[ "$output" != *"secret-org.io"* ]]
}

@test "corporate email shape in a skill companion file, a skill script and a nested _shared file is flagged" {
    mkdir -p "$SCRATCH/bad/.claude/skills/demo/scripts" "$SCRATCH/bad/.claude/_shared/portable"
    printf '%s\n' '---' 'name: demo' '---' 'See reference.md.' > "$SCRATCH/bad/.claude/skills/demo/SKILL.md"
    echo 'Ask owner@acme-corp.com for the project id.' > "$SCRATCH/bad/.claude/skills/demo/reference.md"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "Default owner: owner@acme-corp.com"' > "$SCRATCH/bad/.claude/skills/demo/scripts/y.sh"
    echo 'contact owner@acme-corp.com' > "$SCRATCH/bad/.claude/_shared/portable/notes.txt"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skills/demo/reference.md"* ]] || return 1
    [[ "$output" == *"skills/demo/scripts/y.sh"* ]] || return 1
    [[ "$output" == *"_shared/portable/notes.txt"* ]] || return 1
    [[ "$output" != *"acme-corp.com"* ]] || return 1
}
