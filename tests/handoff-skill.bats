#!/usr/bin/env bats
# Structural tests for /handoff skill.
# RED phase: authored before SKILL.md exists — all tests fail until Steps 1–7 complete.
#
# Coverage dimensions:
#   Frontmatter contract    — name, user-invocable, four trigger phrases (tests 1–4)
#   Schema documentation    — six kinds, branch/project resolution, storage path (tests 5–8)
#   Pre-queue filter        — lessons.md routing for meta-lessons (test 9)
#   Producer-drift guards   — tie-break rule, untyped-overflow warning (tests 10–11)
#   Read-half mechanics     — session-start auto-trigger, surface-block framing (tests 12–13)
#   Predicate bounds        — cannot-evaluate, bounded cost (tests 14–15)
#   Sub-commands / UX       — /handoff close, post-approval auto-clear (tests 16, 16b)
#   Integration touchpoints — ticket-pickup Step 2.6, obligations paired-handoff (tests 17–18)
#   Universality            — routing parity cross-check, leakage tokens absent (tests 19–20)

load 'test_helper'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SKILL_FILE=""

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    SKILL_FILE="$CORE_DIR/.claude/skills/handoff/SKILL.md"

    if [ -f "$CORE_DIR/.claude/CLAUDE.md" ]; then
        export CLAUDE_MD="$CORE_DIR/.claude/CLAUDE.md"
    else
        export CLAUDE_MD="$CORE_DIR/.claude/CLAUDE.md.generated"
    fi
}

teardown() {
    rm -rf "$SCRATCH"
}

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------

@test "SKILL.md exists at .claude/skills/handoff/SKILL.md" {
    [ -f "$SKILL_FILE" ]
}

# ---------------------------------------------------------------------------
# 2–4. Frontmatter contract
# ---------------------------------------------------------------------------

@test "frontmatter has name: handoff" {
    grep -q "^name: handoff" "$SKILL_FILE"
}

@test "frontmatter has user-invocable: true" {
    grep -q "^user-invocable: true" "$SKILL_FILE"
}

@test "description contains all four trigger phrases" {
    local phrases=(
        "park this session"
        "park work for a fresh session"
        "hand off this task"
        "checkpoint this session"
    )
    for phrase in "${phrases[@]}"; do
        grep -q "$phrase" "$SKILL_FILE" || {
            echo "Missing trigger phrase in description: $phrase"
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# 5. Six rejection kinds documented
# ---------------------------------------------------------------------------

@test "SKILL.md documents all six rejection kinds" {
    local kinds=(
        "structural"
        "contractual"
        "empirical-local"
        "empirical-external"
        "goal-conditional"
        "untyped"
    )
    for kind in "${kinds[@]}"; do
        grep -q "$kind" "$SKILL_FILE" || {
            echo "Missing rejection kind: $kind"
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# 6–8. Project/task-key resolution and storage path
# ---------------------------------------------------------------------------

@test "SKILL.md defines branch as task key via git branch --show-current" {
    grep -q "git branch --show-current" "$SKILL_FILE"
}

@test "SKILL.md defines project resolution via basename git rev-parse" {
    grep -q 'basename.*git rev-parse --show-toplevel' "$SKILL_FILE"
}

@test "SKILL.md defines storage path under handoff subdirectory" {
    grep -q '\.claude/tasks.*handoff.*\.md' "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# 9. Pre-queue meta-lesson filter
# ---------------------------------------------------------------------------

@test "SKILL.md documents pre-queue meta-lesson routing to lessons.md" {
    grep -q "lessons\.md" "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# 10–11. Producer-drift guards
# ---------------------------------------------------------------------------

@test "SKILL.md documents the classification tie-break rule (goal-conditional for soft preferences)" {
    grep -q "goal-conditional" "$SKILL_FILE" && grep -qE "tie.?break|selection criteria" "$SKILL_FILE"
}

@test "SKILL.md documents untyped-overflow warning with 1/3 threshold" {
    grep -qE "1/3|33%" "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# 12–13. Read-half mechanics
# ---------------------------------------------------------------------------

@test "SKILL.md documents read-half auto-trigger at session start" {
    grep -qiE "session.?start|session start" "$SKILL_FILE"
}

@test "SKILL.md documents 'Ground may have shifted' surface-block framing" {
    grep -qi "ground may have shifted" "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# 14–15. Predicate bounds
# ---------------------------------------------------------------------------

@test "SKILL.md documents cannot-evaluate partition outcome" {
    grep -q "cannot-evaluate" "$SKILL_FILE"
}

@test "SKILL.md documents bounded predicate cost (time budget and tool budget)" {
    grep -qE "2 second" "$SKILL_FILE" && grep -qE "at most 1" "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# 16–16b. Sub-commands and post-approval auto-clear
# ---------------------------------------------------------------------------

@test "SKILL.md documents /handoff close sub-command" {
    grep -q "/handoff close" "$SKILL_FILE"
}

@test "SKILL.md documents post-approval auto-clear instruction (Run /clear after approval gate)" {
    grep -qE 'Run.*/?clear' "$SKILL_FILE" && grep -qiE "after the approval gate|approval gate" "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# 17–18. Integration touchpoints
# ---------------------------------------------------------------------------

@test "ticket-pickup SKILL.md has Step 2.6 Handoff section" {
    grep -qiE "2\.6.*[Hh]andoff|[Hh]andoff.*2\.6" "$CORE_DIR/.claude/skills/ticket-pickup/SKILL.md"
}

@test "obligations SKILL.md has Paired handoff obligation section" {
    grep -qi "Paired handoff obligation" "$CORE_DIR/.claude/skills/obligations/SKILL.md"
}

# ---------------------------------------------------------------------------
# 19. Routing parity cross-check (CLAUDE.md contains all four trigger phrases)
# ---------------------------------------------------------------------------

@test "all four trigger phrases are wired into CLAUDE.md routing" {
    local phrases=(
        "park this session"
        "park work for a fresh session"
        "hand off this task"
        "checkpoint this session"
    )
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md not generated yet"
    for phrase in "${phrases[@]}"; do
        grep -qi "$phrase" "$CLAUDE_MD" || {
            echo "Trigger phrase not found in CLAUDE.md: $phrase"
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# 20. No leakage tokens in handoff SKILL.md
# ---------------------------------------------------------------------------

@test "handoff SKILL.md contains no company-specific leakage tokens" {
    local tokens=(
        "Jira"
        "JIRA"
        "JQL"
        "Atlassian"
        "DAST-Orch"
        "Mailchimp"
        "Intuit"
    )
    for token in "${tokens[@]}"; do
        if grep -qF "$token" "$SKILL_FILE"; then
            echo "Leakage token found in handoff SKILL.md: $token"
            return 1
        fi
    done
}
