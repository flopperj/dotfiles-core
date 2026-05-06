#!/usr/bin/env bats
# Tests for Wave C Step 3: reasoning agents migration.
# RED phase: written before files are copied.

load 'test_helper'

# ---------------------------------------------------------------------------
# Agent files exist
# ---------------------------------------------------------------------------

@test "aristotle-deconstructor.md exists in dotfiles-core agents" {
    [ -f "$CORE_DIR/.claude/agents/aristotle-deconstructor.md" ]
}

@test "optimus-planner.md exists in dotfiles-core agents" {
    [ -f "$CORE_DIR/.claude/agents/optimus-planner.md" ]
}

@test "cyrus-tdd-engineer.md exists in dotfiles-core agents" {
    [ -f "$CORE_DIR/.claude/agents/cyrus-tdd-engineer.md" ]
}

@test "ranger-reviewer.md exists in dotfiles-core agents" {
    [ -f "$CORE_DIR/.claude/agents/ranger-reviewer.md" ]
}

@test "scout-reviewer.md exists in dotfiles-core agents" {
    [ -f "$CORE_DIR/.claude/agents/scout-reviewer.md" ]
}

# ---------------------------------------------------------------------------
# Agent frontmatter has expected name field
# ---------------------------------------------------------------------------

@test "aristotle-deconstructor.md has name in frontmatter" {
    grep -q "^name:" "$CORE_DIR/.claude/agents/aristotle-deconstructor.md"
}

@test "optimus-planner.md has name in frontmatter" {
    grep -q "^name:" "$CORE_DIR/.claude/agents/optimus-planner.md"
}

@test "cyrus-tdd-engineer.md has name in frontmatter" {
    grep -q "^name:" "$CORE_DIR/.claude/agents/cyrus-tdd-engineer.md"
}

@test "ranger-reviewer.md has name in frontmatter" {
    grep -q "^name:" "$CORE_DIR/.claude/agents/ranger-reviewer.md"
}

@test "scout-reviewer.md has name in frontmatter" {
    grep -q "^name:" "$CORE_DIR/.claude/agents/scout-reviewer.md"
}

# ---------------------------------------------------------------------------
# Leakage: agent files must not contain workspace-specific tokens
# ---------------------------------------------------------------------------

@test "agents/ directory passes leakage check" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/.claude/agents"
    [ "$status" -eq 0 ]
}
