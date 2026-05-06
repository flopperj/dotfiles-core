#!/usr/bin/env bats
# Tests for Wave C Step 1: skills migration (forge, grill-me, to-prd).
# RED phase: written before files are copied — expected to fail until migration runs.

load 'test_helper'

# ---------------------------------------------------------------------------
# forge skill
# ---------------------------------------------------------------------------

@test "forge skill directory exists in dotfiles-core" {
    [ -d "$CORE_DIR/.claude/skills/forge" ]
}

@test "forge skill SKILL.md exists" {
    [ -f "$CORE_DIR/.claude/skills/forge/SKILL.md" ]
}

@test "forge SKILL.md has name: forge in frontmatter" {
    grep -q "^name: forge" "$CORE_DIR/.claude/skills/forge/SKILL.md"
}

@test "forge SKILL.md user-invocable is true" {
    grep -q "user-invocable: true" "$CORE_DIR/.claude/skills/forge/SKILL.md"
}

# ---------------------------------------------------------------------------
# grill-me skill
# ---------------------------------------------------------------------------

@test "grill-me skill directory exists in dotfiles-core" {
    [ -d "$CORE_DIR/.claude/skills/grill-me" ]
}

@test "grill-me skill SKILL.md exists" {
    [ -f "$CORE_DIR/.claude/skills/grill-me/SKILL.md" ]
}

@test "grill-me SKILL.md has name: grill-me in frontmatter" {
    grep -q "^name: grill-me" "$CORE_DIR/.claude/skills/grill-me/SKILL.md"
}

# ---------------------------------------------------------------------------
# to-prd skill
# ---------------------------------------------------------------------------

@test "to-prd skill directory exists in dotfiles-core" {
    [ -d "$CORE_DIR/.claude/skills/to-prd" ]
}

@test "to-prd skill SKILL.md exists" {
    [ -f "$CORE_DIR/.claude/skills/to-prd/SKILL.md" ]
}

@test "to-prd SKILL.md has name: to-prd in frontmatter" {
    grep -q "^name: to-prd" "$CORE_DIR/.claude/skills/to-prd/SKILL.md"
}

# ---------------------------------------------------------------------------
# Leakage: migrated skills must not contain workspace-specific tokens
# ---------------------------------------------------------------------------

@test "forge SKILL.md passes leakage check" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/.claude/skills/forge"
    [ "$status" -eq 0 ]
}

@test "grill-me SKILL.md passes leakage check" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/.claude/skills/grill-me"
    [ "$status" -eq 0 ]
}

@test "to-prd SKILL.md passes leakage check" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/.claude/skills/to-prd"
    [ "$status" -eq 0 ]
}
