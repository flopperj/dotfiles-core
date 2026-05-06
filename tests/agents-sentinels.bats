#!/usr/bin/env bats
# TDD RED tests for Item A: sentinel presence in SKILL.md files.
# These tests FAIL before sentinels are added (expected), then PASS after Step 3.
# Run with: bats tests/agents-sentinels.bats

load 'test_helper'

SKILLS_DIR="$DOTFILES_DIR/.claude/skills"

SENTINEL_SKILLS=(
    "aristotle-deconstructor"
    "code-auditor"
    "cyrus-tdd-engineer"
    "optimus-planner"
    "ranger-reviewer"
    "scout-reviewer"
    "swarm-retro"
    "team-lead"
    "ticket-pickup"
    "ticket-swarm"
)

# ---------------------------------------------------------------------------
# Sentinel presence: BEGIN marker
# ---------------------------------------------------------------------------
@test "all 10 SKILL.md files contain BEGIN RESPONSIBILITY BOUNDARIES sentinel" {
    local missing=()
    for skill in "${SENTINEL_SKILLS[@]}"; do
        local skill_md="$SKILLS_DIR/$skill/SKILL.md"
        if ! grep -q "BEGIN RESPONSIBILITY BOUNDARIES" "$skill_md"; then
            missing+=("$skill")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing BEGIN sentinel in: ${missing[*]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Sentinel presence: END marker
# ---------------------------------------------------------------------------
@test "all 10 SKILL.md files contain END RESPONSIBILITY BOUNDARIES sentinel" {
    local missing=()
    for skill in "${SENTINEL_SKILLS[@]}"; do
        local skill_md="$SKILLS_DIR/$skill/SKILL.md"
        if ! grep -q "END RESPONSIBILITY BOUNDARIES" "$skill_md"; then
            missing+=("$skill")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing END sentinel in: ${missing[*]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Sentinel pairing: BEGIN must precede END in each file
# ---------------------------------------------------------------------------
@test "BEGIN sentinel precedes END sentinel in each SKILL.md" {
    local bad=()
    for skill in "${SENTINEL_SKILLS[@]}"; do
        local skill_md="$SKILLS_DIR/$skill/SKILL.md"
        local begin_line end_line
        begin_line=$(grep -n "BEGIN RESPONSIBILITY BOUNDARIES" "$skill_md" | head -1 | cut -d: -f1)
        end_line=$(grep -n "END RESPONSIBILITY BOUNDARIES" "$skill_md" | head -1 | cut -d: -f1)
        if [ -z "$begin_line" ] || [ -z "$end_line" ] || [ "$begin_line" -ge "$end_line" ]; then
            bad+=("$skill (begin=$begin_line, end=$end_line)")
        fi
    done
    if [ "${#bad[@]}" -gt 0 ]; then
        echo "Sentinel order wrong in: ${bad[*]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Canonical table header present inside sentinel block
# ---------------------------------------------------------------------------
@test "canonical boundary table header present inside sentinel block" {
    local missing=()
    for skill in "${SENTINEL_SKILLS[@]}"; do
        local skill_md="$SKILLS_DIR/$skill/SKILL.md"
        local has_header
        has_header=$(awk '/BEGIN RESPONSIBILITY BOUNDARIES/{found=1} found && /Sole responsibility.*NEVER does/{print "yes"; exit} /END RESPONSIBILITY BOUNDARIES/{found=0}' "$skill_md")
        if [ "$has_header" != "yes" ]; then
            missing+=("$skill")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing table header inside sentinel block in: ${missing[*]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Idempotence: running boundaries-gen.sh twice produces no diff (RED until script exists)
# ---------------------------------------------------------------------------
@test "boundaries-gen.sh is idempotent (second run produces no diff)" {
    local gen_script="$DOTFILES_DIR/scripts/boundaries-gen.sh"
    [ -f "$gen_script" ] || skip "boundaries-gen.sh does not exist yet"

    local before after
    before="$(git -C "$DOTFILES_DIR" diff)"

    bash "$gen_script"
    bash "$gen_script"

    after="$(git -C "$DOTFILES_DIR" diff)"

    if [ "$before" != "$after" ]; then
        echo "Second run of boundaries-gen.sh produced changes:"
        echo "$after"
        return 1
    fi
}
