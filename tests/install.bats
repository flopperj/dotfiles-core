#!/usr/bin/env bats
# Tests for dotfiles-core install.sh
# RED phase: written before install.sh is authored.

load 'test_helper'

# Helpers: run install.sh against an isolated $HOME in $SCRATCH
_run_install() {
    local args="${1:-}"
    HOME="$SCRATCH/home" run bash "$CORE_DIR/install.sh" $args
}

setup() {
    # Call parent setup for CORE_DIR and SCRATCH
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    mkdir -p "$SCRATCH/home"
}

teardown() {
    rm -rf "$SCRATCH"
}

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------

@test "install.sh exists and is executable" {
    [ -f "$CORE_DIR/install.sh" ]
    [ -x "$CORE_DIR/install.sh" ]
}

# ---------------------------------------------------------------------------
# 2. --help exits 0
# ---------------------------------------------------------------------------

@test "install.sh --help exits 0" {
    HOME="$SCRATCH/home" run bash "$CORE_DIR/install.sh" --help
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. Normal install: agents symlinked into ~/.claude/agents/
# ---------------------------------------------------------------------------

@test "install creates ~/.claude/agents/ directory" {
    _run_install
    [ -d "$SCRATCH/home/.claude/agents" ]
}

@test "install symlinks aristotle-deconstructor.md into ~/.claude/agents/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/agents/aristotle-deconstructor.md" ]
}

@test "install symlinks cyrus-tdd-engineer.md into ~/.claude/agents/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/agents/cyrus-tdd-engineer.md" ]
}

@test "install symlinks optimus-planner.md into ~/.claude/agents/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/agents/optimus-planner.md" ]
}

@test "install symlinks ranger-reviewer.md into ~/.claude/agents/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/agents/ranger-reviewer.md" ]
}

@test "install symlinks scout-reviewer.md into ~/.claude/agents/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/agents/scout-reviewer.md" ]
}

# ---------------------------------------------------------------------------
# 4. Normal install: skills symlinked into ~/.claude/skills/
# ---------------------------------------------------------------------------

@test "install creates ~/.claude/skills/ directory" {
    _run_install
    [ -d "$SCRATCH/home/.claude/skills" ]
}

@test "install symlinks forge skill into ~/.claude/skills/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/skills/forge" ]
}

@test "install symlinks grill-me skill into ~/.claude/skills/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/skills/grill-me" ]
}

@test "install symlinks to-prd skill into ~/.claude/skills/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/skills/to-prd" ]
}

# ---------------------------------------------------------------------------
# 5. Normal install: _shared symlinked
# ---------------------------------------------------------------------------

@test "install symlinks _shared directory into ~/.claude/" {
    _run_install
    [ -L "$SCRATCH/home/.claude/_shared" ]
}

# ---------------------------------------------------------------------------
# 6. Memory seeds: seed-once behavior
# ---------------------------------------------------------------------------

@test "install seeds cyrus-tdd-engineer MEMORY.md on first run" {
    _run_install
    [ -f "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer/MEMORY.md" ]
}

@test "install does not overwrite existing MEMORY.md without --reseed" {
    mkdir -p "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer"
    echo "existing content" > "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer/MEMORY.md"
    _run_install
    grep -q "existing content" "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer/MEMORY.md"
}

@test "install --reseed overwrites existing MEMORY.md" {
    mkdir -p "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer"
    echo "existing content" > "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer/MEMORY.md"
    _run_install "--reseed"
    # After reseed, content should match the seed file (not "existing content")
    ! grep -q "existing content" "$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer/MEMORY.md"
}

@test "install --reseed backs up pre-reseed content to timestamped .bak file" {
    # Operational-safety contract: --reseed destroys agent-accumulated content,
    # so it must preserve the prior file in a timestamped backup. Without this,
    # a user invoking --reseed silently loses customized memory.
    local target_dir="$SCRATCH/home/.claude/agent-memory/cyrus-tdd-engineer"
    local target="$target_dir/MEMORY.md"
    mkdir -p "$target_dir"
    echo "CUSTOM_LINE_DO_NOT_OVERWRITE" > "$target"

    _run_install "--reseed"

    # Live target was overwritten (asserted by sibling test)
    # AND a backup containing the custom line must exist
    local backup_count
    backup_count="$(find "$target_dir" -maxdepth 1 -name 'MEMORY.md.bak.*' 2>/dev/null | wc -l)"
    [ "$backup_count" -ge 1 ]
    local backup_file
    backup_file="$(find "$target_dir" -maxdepth 1 -name 'MEMORY.md.bak.*' 2>/dev/null | head -1)"
    grep -q "CUSTOM_LINE_DO_NOT_OVERWRITE" "$backup_file"
}

# ---------------------------------------------------------------------------
# 7. Agent symlink targets are live (not broken)
# ---------------------------------------------------------------------------

@test "aristotle-deconstructor.md symlink target exists" {
    _run_install
    local link="$SCRATCH/home/.claude/agents/aristotle-deconstructor.md"
    [ -L "$link" ] && [ -e "$link" ]
}

@test "forge skill symlink target exists" {
    _run_install
    local link="$SCRATCH/home/.claude/skills/forge"
    [ -L "$link" ] && [ -e "$link" ]
}

# ---------------------------------------------------------------------------
# 8. --check mode: exits 0 on clean install, prints status
# ---------------------------------------------------------------------------

@test "install --check exits 0 after a successful install" {
    _run_install
    HOME="$SCRATCH/home" run bash "$CORE_DIR/install.sh" --check
    [ "$status" -eq 0 ]
}

@test "install --check output mentions agents" {
    _run_install
    HOME="$SCRATCH/home" run bash "$CORE_DIR/install.sh" --check
    echo "$output" | grep -qi "agent"
}

# ---------------------------------------------------------------------------
# 9. Idempotent: running twice produces no errors
# ---------------------------------------------------------------------------

@test "install is idempotent: running twice exits 0" {
    _run_install
    _run_install
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 10. _backup_collision: counter-suffix prevents silent overwrite
# ---------------------------------------------------------------------------
@test "_backup_collision with same suffix counter-suffix produces distinct .bak files" {
    # Source the library directly — unit test on _backup_collision alone.
    # CORE_DIR is set by setup(). _BACKUP_SUFFIX_OVERRIDE pins the base suffix
    # so the test is deterministic and fast (no wall-clock dependency).
    local target="$SCRATCH/target_file.txt"

    # First collision
    echo "first" > "$target"
    (
        export _BACKUP_SUFFIX_OVERRIDE="forced"
        source "$CORE_DIR/scripts/lib-core-symlinks.sh"
        _backup_collision "$target"
    )

    # Recreate target for second collision
    echo "second" > "$target"
    (
        export _BACKUP_SUFFIX_OVERRIDE="forced"
        source "$CORE_DIR/scripts/lib-core-symlinks.sh"
        _backup_collision "$target"
    )

    # .bak.forced must exist and contain "first" (not silently overwritten)
    [ -f "${target}.bak.forced" ]
    grep -q "first" "${target}.bak.forced"

    # .bak.forced.1 must exist and contain "second"
    [ -f "${target}.bak.forced.1" ]
    grep -q "second" "${target}.bak.forced.1"
}
