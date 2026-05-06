#!/usr/bin/env bats
# Tests for Wave C Step 2: _shared/ migration.
# RED phase: written before files are copied.

load 'test_helper'

# ---------------------------------------------------------------------------
# role-guards/
# ---------------------------------------------------------------------------

@test "_shared/role-guards directory exists" {
    [ -d "$CORE_DIR/.claude/_shared/role-guards" ]
}

@test "_shared/role-guards/aristotle.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/role-guards/aristotle.md" ]
}

@test "_shared/role-guards/optimus.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/role-guards/optimus.md" ]
}

@test "_shared/role-guards/cyrus.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/role-guards/cyrus.md" ]
}

@test "_shared/role-guards/reviewer.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/role-guards/reviewer.md" ]
}

# ---------------------------------------------------------------------------
# _shared/ top-level files
# ---------------------------------------------------------------------------

@test "_shared/responsibility-boundaries.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/responsibility-boundaries.md" ]
}

@test "_shared/responsibility-boundaries-extras.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/responsibility-boundaries-extras.md" ]
}

@test "_shared/lessons-signs-format.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/lessons-signs-format.md" ]
}

@test "_shared/model-tiers.md exists" {
    [ -f "$CORE_DIR/.claude/_shared/model-tiers.md" ]
}

# ---------------------------------------------------------------------------
# Leakage: shared files must not contain workspace-specific tokens
# ---------------------------------------------------------------------------

@test "_shared/ passes leakage check" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/.claude/_shared"
    [ "$status" -eq 0 ]
}
