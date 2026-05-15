#!/usr/bin/env bats
# Tests for scripts/check-consult-grammar.sh
#
# RED phase: these tests are written before the script exists.
# Each test verifies a behavioral contract from the acceptance criteria in the plan.
#
# Exit code contract:
#   0 — all consult-instructions are valid (or none present)
#   1 — at least one grammar violation (vocabulary mismatch or anti-prose)
#   2 — fatal configuration error (empty vocabulary file)

load 'test_helper'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write a minimal SKILL.md with given consult-instruction content into a
# simulated skills directory structure, then run the grammar check.
_check_skill() {
    local consult_line="$1"
    mkdir -p "$SCRATCH/.claude/skills/test-skill"
    cat > "$SCRATCH/.claude/skills/test-skill/SKILL.md" <<HEREDOC
# Test Skill

$consult_line
HEREDOC
    run bash "$CORE_DIR/scripts/check-consult-grammar.sh" "$SCRATCH" "$CORE_DIR/scripts/consult-vocabulary.txt"
}

# ---------------------------------------------------------------------------
# 1. Valid consult-instruction with section in vocabulary → PASS (exit 0)
# ---------------------------------------------------------------------------

@test "valid consult-instruction matching vocabulary section passes" {
    _check_skill "For Jira, consult \`## Jira fallback\` in \`~/.claude/overlay-context.md\`. If absent, skip."
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. Consult-instruction with section NOT in vocabulary → FAIL (exit 1)
#    Output must name the file and the unknown section.
# ---------------------------------------------------------------------------

@test "unknown section name fails with exit 1 and names file and section" {
    _check_skill "consult \`## Some Made Up Name\` in \`~/.claude/overlay-context.md\`"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Some Made Up Name" ]]
    [[ "$output" =~ "SKILL.md" ]]
}

# ---------------------------------------------------------------------------
# 3. Prose-form overlay-context.md mention without backtick form → FAIL (exit 1)
#    Anti-prose: free text referencing overlay-context.md is not a valid
#    consult-instruction; it bypasses vocabulary enforcement.
# ---------------------------------------------------------------------------

@test "prose-form consult-instruction without backtick section fails" {
    # A line with "consult" + "overlay-context.md" but no backtick form is a
    # prose-form consult-instruction attempt and must be flagged.
    _check_skill "For Jira details, consult the overlay-context.md file directly."
    [ "$status" -eq 1 ]
    [[ "$output" =~ "SKILL.md" ]]
}

# ---------------------------------------------------------------------------
# 4. Empty vocabulary file → fatal error (exit 2)
# ---------------------------------------------------------------------------

@test "empty vocabulary file exits with code 2" {
    mkdir -p "$SCRATCH/.claude/skills/test-skill"
    echo "# no sections" > "$SCRATCH/.claude/skills/test-skill/SKILL.md"
    local empty_vocab="$SCRATCH/empty-vocab.txt"
    echo "# only a comment" > "$empty_vocab"
    run bash "$CORE_DIR/scripts/check-consult-grammar.sh" "$SCRATCH" "$empty_vocab"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "vocabulary" ]]
    [[ "$output" =~ "empty" ]]
}

# ---------------------------------------------------------------------------
# 5. Two valid consult-instructions on different lines → PASS (exit 0)
# ---------------------------------------------------------------------------

@test "two valid consult-instructions on separate lines both pass" {
    mkdir -p "$SCRATCH/.claude/skills/test-skill"
    cat > "$SCRATCH/.claude/skills/test-skill/SKILL.md" <<'HEREDOC'
# Multi-consult Skill

For Jira, consult `## Jira fallback` in `~/.claude/overlay-context.md`.
For Jenkins, consult `## Jenkins MCP clone URL` in `~/.claude/overlay-context.md`.
HEREDOC
    run bash "$CORE_DIR/scripts/check-consult-grammar.sh" "$SCRATCH" "$CORE_DIR/scripts/consult-vocabulary.txt"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 6. SKILL.md with no consult-instruction at all → PASS (exit 0)
# ---------------------------------------------------------------------------

@test "SKILL.md with no consult-instruction passes" {
    mkdir -p "$SCRATCH/.claude/skills/no-consult"
    cat > "$SCRATCH/.claude/skills/no-consult/SKILL.md" <<'HEREDOC'
# Skill Without Consult

This skill has no consult-instructions. It should pass the grammar check.
HEREDOC
    run bash "$CORE_DIR/scripts/check-consult-grammar.sh" "$SCRATCH" "$CORE_DIR/scripts/consult-vocabulary.txt"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 7. Grammar check operates on every .claude/skills/*/SKILL.md, not hardcoded
#    Verifies that multiple skills are scanned automatically.
# ---------------------------------------------------------------------------

@test "grammar check scans all SKILL.md files in .claude/skills subdirectories" {
    # First skill: valid
    mkdir -p "$SCRATCH/.claude/skills/skill-a"
    echo "consult \`## Jira fallback\` in \`~/.claude/overlay-context.md\`" \
        > "$SCRATCH/.claude/skills/skill-a/SKILL.md"
    # Second skill: invalid section name — should be caught
    mkdir -p "$SCRATCH/.claude/skills/skill-b"
    echo "consult \`## Unknown Section\` in \`~/.claude/overlay-context.md\`" \
        > "$SCRATCH/.claude/skills/skill-b/SKILL.md"

    run bash "$CORE_DIR/scripts/check-consult-grammar.sh" "$SCRATCH" "$CORE_DIR/scripts/consult-vocabulary.txt"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "skill-b" ]]
}
