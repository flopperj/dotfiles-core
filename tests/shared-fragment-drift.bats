#!/usr/bin/env bats
# Tests for scripts/check-shared-fragment-drift.sh
#
# Exit code contract:
#   0 — no drift (or nothing to compare)
#   1 — drift detected between shared fragment and at least one consumer
#   2 — fatal config error (unpaired sentinel or duplicate sentinel name)

load 'test_helper'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal *-shared.md at .claude/skills/<name>.
_shared() {
    local name="$1"
    local content="$2"
    mkdir -p "$SCRATCH/.claude/skills"
    cat > "$SCRATCH/.claude/skills/${name}.md" <<HEREDOC
$content
HEREDOC
}

# Create a consumer SKILL.md at .claude/skills/<dir>/SKILL.md.
_consumer() {
    local dir="$1"
    local content="$2"
    mkdir -p "$SCRATCH/.claude/skills/$dir"
    cat > "$SCRATCH/.claude/skills/$dir/SKILL.md" <<HEREDOC
$content
HEREDOC
}

# Run the drift check against SCRATCH.
_run_check() {
    run bash "$CORE_DIR/scripts/check-shared-fragment-drift.sh" "$SCRATCH"
}

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------

@test "check-shared-fragment-drift.sh exists and is executable" {
    [ -f "$CORE_DIR/scripts/check-shared-fragment-drift.sh" ]
    [ -x "$CORE_DIR/scripts/check-shared-fragment-drift.sh" ]
}

# ---------------------------------------------------------------------------
# 2. No shared fragments present → exit 0 silently
# ---------------------------------------------------------------------------

@test "no shared fragments present exits 0 silently" {
    mkdir -p "$SCRATCH/.claude/skills/some-skill"
    echo "# Just a skill" > "$SCRATCH/.claude/skills/some-skill/SKILL.md"
    _run_check
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# 3. Shared fragment with a sentinel block but no consumer references it → exit 0
# ---------------------------------------------------------------------------

@test "shared fragment sentinel not referenced by any consumer exits 0" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
inner content
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "# Skill A
No sentinel blocks here."
    _run_check
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 4. Matching sentinel block byte-identical in fragment and consumer → exit 0
# ---------------------------------------------------------------------------

@test "byte-identical sentinel block in fragment and consumer exits 0" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
identical content line
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "# Skill A
<!-- BEGIN MY-BLOCK -->
identical content line
<!-- END MY-BLOCK -->"
    _run_check
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. Drift by one byte between fragment and consumer → exit 1 with output
# ---------------------------------------------------------------------------

@test "one-byte drift between fragment and consumer exits 1" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
original content
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "# Skill A
<!-- BEGIN MY-BLOCK -->
modified content
<!-- END MY-BLOCK -->"
    _run_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MY-BLOCK" ]]
}

# ---------------------------------------------------------------------------
# 6. Drift output names both files involved
# ---------------------------------------------------------------------------

@test "drift output names the fragment file and the consumer file" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
original
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "# Skill A
<!-- BEGIN MY-BLOCK -->
different
<!-- END MY-BLOCK -->"
    _run_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ "review-shared" ]]
    [[ "$output" =~ "skill-a" ]]
}

# ---------------------------------------------------------------------------
# 7. Consumer has a sentinel NOT in any shared fragment → that is fine, exit 0
# ---------------------------------------------------------------------------

@test "consumer-only sentinel block is not flagged" {
    _shared "review-shared" "<!-- BEGIN SHARED-BLOCK -->
shared content
<!-- END SHARED-BLOCK -->"
    _consumer "skill-a" "# Skill A
<!-- BEGIN CONSUMER-ONLY -->
private content
<!-- END CONSUMER-ONLY -->
<!-- BEGIN SHARED-BLOCK -->
shared content
<!-- END SHARED-BLOCK -->"
    _run_check
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 8. Multiple consumers, all matching → exit 0
# ---------------------------------------------------------------------------

@test "multiple consumers all byte-identical exits 0" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
content line
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "<!-- BEGIN MY-BLOCK -->
content line
<!-- END MY-BLOCK -->"
    _consumer "skill-b" "<!-- BEGIN MY-BLOCK -->
content line
<!-- END MY-BLOCK -->"
    _run_check
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 9. Multiple consumers, one drifted → exit 1
# ---------------------------------------------------------------------------

@test "multiple consumers with one drifted exits 1" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
content line
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "<!-- BEGIN MY-BLOCK -->
content line
<!-- END MY-BLOCK -->"
    _consumer "skill-b" "<!-- BEGIN MY-BLOCK -->
DIFFERENT content
<!-- END MY-BLOCK -->"
    _run_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ "skill-b" ]]
}

# ---------------------------------------------------------------------------
# 10. Unpaired BEGIN (no END) in shared fragment → exit 2
# ---------------------------------------------------------------------------

@test "unpaired BEGIN in shared fragment exits 2" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
content without end"
    _run_check
    [ "$status" -eq 2 ]
    [[ "$output" =~ "MY-BLOCK" ]]
    [[ "$output" =~ "review-shared" ]]
}

# ---------------------------------------------------------------------------
# 11. Unpaired END (no BEGIN) in consumer → exit 2
# ---------------------------------------------------------------------------

@test "unpaired END in consumer exits 2" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
content
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "content
<!-- END ORPHAN-BLOCK -->"
    _run_check
    [ "$status" -eq 2 ]
    [[ "$output" =~ "ORPHAN-BLOCK" ]]
}

# ---------------------------------------------------------------------------
# 12. Duplicate sentinel name in a single file → exit 2
# ---------------------------------------------------------------------------

@test "duplicate sentinel name in consumer exits 2" {
    _shared "review-shared" "<!-- BEGIN MY-BLOCK -->
content
<!-- END MY-BLOCK -->"
    _consumer "skill-a" "<!-- BEGIN MY-BLOCK -->
content
<!-- END MY-BLOCK -->
<!-- BEGIN MY-BLOCK -->
second copy
<!-- END MY-BLOCK -->"
    _run_check
    [ "$status" -eq 2 ]
    [[ "$output" =~ "MY-BLOCK" ]]
}

# ---------------------------------------------------------------------------
# 13. Actual repo tree exits 0 (byte-identical content validated at PR time)
# ---------------------------------------------------------------------------

@test "actual repo tree exits 0 (no drift)" {
    run bash "$CORE_DIR/scripts/check-shared-fragment-drift.sh" "$CORE_DIR"
    [ "$status" -eq 0 ]
}
