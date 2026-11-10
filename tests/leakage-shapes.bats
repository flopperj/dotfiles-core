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

@test "in-tree portable-ticket-prefixes.txt is flagged" {
    mkdir -p "$SCRATCH/bad/scripts"
    echo "ZZQ" > "$SCRATCH/bad/scripts/portable-ticket-prefixes.txt"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCRATCH/bad"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"portable-ticket-prefixes.txt"* ]] || return 1
    [[ "$output" != *"ZZQ"* ]]
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

# Inside a git work tree only committable files are scanned (tracked plus
# untracked-but-not-ignored); a plain directory is scanned in full.
_git_scan_fixture() {
    SCAN="$SCRATCH/scan"
    mkdir -p "$SCAN"
    git -C "$SCAN" init -q
    git -C "$SCAN" config user.email "dev@example.com"
    git -C "$SCAN" config user.name "Dev"
    printf 'vendored/\n' > "$SCAN/.gitignore"
    git -C "$SCAN" add .gitignore
    git -C "$SCAN" commit -qm seed
}

_bad_skill() {   # _bad_skill <skill-dir>
    mkdir -p "$1"
    printf '%s\n' '---' 'name: demo' '---' 'Escalate to owner@acme-corp.com.' > "$1/SKILL.md"
}

@test "work tree: gitignored denylist file and corporate email are not reported" {
    _git_scan_fixture
    mkdir -p "$SCAN/vendored"
    echo "xyzzy" > "$SCAN/vendored/leakage-tokens.txt"
    printf 'vendored/\n.claude/skills/ignored/\n' > "$SCAN/.gitignore"
    _bad_skill "$SCAN/.claude/skills/ignored"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN"
    [ "$status" -eq 0 ]
}

@test "work tree: untracked, non-ignored denylist file and corporate email are reported" {
    _git_scan_fixture
    mkdir -p "$SCAN/scripts"
    echo "xyzzy" > "$SCAN/scripts/leakage-tokens.txt"
    _bad_skill "$SCAN/.claude/skills/demo"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"$SCAN/scripts/leakage-tokens.txt"* ]] || return 1
    [[ "$output" == *"$SCAN/.claude/skills/demo/SKILL.md"* ]]
}

@test "work tree: tracked corporate email is reported" {
    _git_scan_fixture
    _bad_skill "$SCAN/.claude/skills/demo"
    git -C "$SCAN" add -A
    git -C "$SCAN" commit -qm demo
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"$SCAN/.claude/skills/demo/SKILL.md"* ]]
}

@test "non-git directory: a .gitignore has no effect, every file is scanned" {
    SCAN="$SCRATCH/plain"
    mkdir -p "$SCAN/vendored"
    printf 'vendored/\n.claude/\n' > "$SCAN/.gitignore"
    echo "xyzzy" > "$SCAN/vendored/leakage-tokens.txt"
    _bad_skill "$SCAN/.claude/skills/demo"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"$SCAN/vendored/leakage-tokens.txt"* ]] || return 1
    [[ "$output" == *"$SCAN/.claude/skills/demo/SKILL.md"* ]]
}

@test "work tree: paths with spaces are scanned and reported whole" {
    _git_scan_fixture
    mkdir -p "$SCAN/dir with space"
    echo "xyzzy" > "$SCAN/dir with space/leakage-tokens.txt"
    _bad_skill "$SCAN/.claude/skills/my skill"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"$SCAN/dir with space/leakage-tokens.txt"* ]] || return 1
    [[ "$output" == *"$SCAN/.claude/skills/my skill/SKILL.md"* ]]
}

@test "work tree: scanning a sub-directory applies both shapes under that directory" {
    _git_scan_fixture
    mkdir -p "$SCAN/sub/scripts"
    echo "xyzzy" > "$SCAN/sub/scripts/leakage-tokens.txt"
    _bad_skill "$SCAN/sub/.claude/skills/demo"
    _bad_skill "$SCAN/.claude/skills/outside"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN/sub"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"$SCAN/sub/scripts/leakage-tokens.txt"* ]] || return 1
    [[ "$output" == *"$SCAN/sub/.claude/skills/demo/SKILL.md"* ]] || return 1
    [[ "$output" != *"outside"* ]]
}

@test "work tree: a trailing slash on the scan dir reports clean paths" {
    _git_scan_fixture
    _bad_skill "$SCAN/.claude/skills/demo"
    run bash "$CORE_DIR/scripts/check-leakage-shapes.sh" "$SCAN/"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"$SCAN/.claude/skills/demo/SKILL.md"* ]] || return 1
    [[ "$output" != *"//"* ]]
}
