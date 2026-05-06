#!/usr/bin/env bats
# Tests for Wave C Step 4: agent-memory-seeds migration.
# RED phase: written before files are copied.

load 'test_helper'

# ---------------------------------------------------------------------------
# Directory structure
# ---------------------------------------------------------------------------

@test "agent-memory-seeds directory exists in dotfiles-core" {
    [ -d "$CORE_DIR/.claude/agent-memory-seeds" ]
}

@test "agent-memory-seeds/cyrus-tdd-engineer directory exists" {
    [ -d "$CORE_DIR/.claude/agent-memory-seeds/cyrus-tdd-engineer" ]
}

@test "agent-memory-seeds/optimus-planner directory exists" {
    [ -d "$CORE_DIR/.claude/agent-memory-seeds/optimus-planner" ]
}

@test "agent-memory-seeds/ranger-reviewer directory exists" {
    [ -d "$CORE_DIR/.claude/agent-memory-seeds/ranger-reviewer" ]
}

@test "agent-memory-seeds/scout-reviewer directory exists" {
    [ -d "$CORE_DIR/.claude/agent-memory-seeds/scout-reviewer" ]
}

# ---------------------------------------------------------------------------
# MEMORY.md files exist for each agent
# ---------------------------------------------------------------------------

@test "cyrus-tdd-engineer MEMORY.md exists" {
    [ -f "$CORE_DIR/.claude/agent-memory-seeds/cyrus-tdd-engineer/MEMORY.md" ]
}

@test "optimus-planner MEMORY.md exists" {
    [ -f "$CORE_DIR/.claude/agent-memory-seeds/optimus-planner/MEMORY.md" ]
}

@test "ranger-reviewer MEMORY.md exists" {
    [ -f "$CORE_DIR/.claude/agent-memory-seeds/ranger-reviewer/MEMORY.md" ]
}

@test "scout-reviewer MEMORY.md exists" {
    [ -f "$CORE_DIR/.claude/agent-memory-seeds/scout-reviewer/MEMORY.md" ]
}

# ---------------------------------------------------------------------------
# Leakage: memory seeds must not contain workspace-specific tokens
# ---------------------------------------------------------------------------

@test "agent-memory-seeds/ passes leakage check" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/.claude/agent-memory-seeds"
    [ "$status" -eq 0 ]
}
