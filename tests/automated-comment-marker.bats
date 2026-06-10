#!/usr/bin/env bats
# Guards the canonical "Automated Comment Marker — 🤖 prefix" rule.
#
# The rule says: every comment an agent posts on the user's behalf (Jira and
# GitHub alike) is prefixed with 🤖, unless the user explicitly instructs
# otherwise. Its canonical home is the AGENTS.md task-orchestration fragment;
# the comment-posting skills/agents must reference it so the convention can't
# silently drift back to being sprinkled into example strings only.

load 'test_helper'

FRAGMENT="$CORE_DIR/_shared/agents-md/20-task-orchestration.md"
GENERATED="$CORE_DIR/.claude/AGENTS.md.generated"
ROBOT="🤖"

# ---------------------------------------------------------------------------
# Canonical rule presence
# ---------------------------------------------------------------------------

@test "AGENTS.md fragment defines the Automated Comment Marker section" {
    grep -qF "## Automated Comment Marker" "$FRAGMENT"
}

@test "Automated Comment Marker rule names the 🤖 prefix" {
    grep -qF "$ROBOT" "$FRAGMENT"
}

@test "Automated Comment Marker rule covers both Jira and GitHub" {
    run grep -A12 "## Automated Comment Marker" "$FRAGMENT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Jira"* ]]
    [[ "$output" == *"GitHub"* ]]
}

@test "Automated Comment Marker rule carries the 'unless instructed' carve-out" {
    run grep -A20 "## Automated Comment Marker" "$FRAGMENT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unless"* ]] || [[ "$output" == *"carve-out"* ]] || [[ "$output" == *"explicit"* ]]
}

@test "rule is rendered into the generated AGENTS.md" {
    # The pre-commit hook concatenates fragments into AGENTS.md.generated.
    # If this fails, run scripts/pre-commit.sh (or the concat step) to re-render.
    grep -qF "## Automated Comment Marker" "$GENERATED"
}

# ---------------------------------------------------------------------------
# Posting skills/agents reference the canonical rule
# ---------------------------------------------------------------------------

@test "ticket-pickup references the Automated Comment Marker rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/skills/ticket-pickup/SKILL.md"
}

@test "ticket-swarm references the Automated Comment Marker rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/skills/ticket-swarm/SKILL.md"
}

@test "scout-reviewer skill references the Automated Comment Marker rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/skills/scout-reviewer/SKILL.md"
}

@test "ranger-reviewer skill references the Automated Comment Marker rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/skills/ranger-reviewer/SKILL.md"
}

@test "scout-reviewer agent references the Automated Comment Marker rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/agents/scout-reviewer.md"
}

@test "ranger-reviewer agent references the Automated Comment Marker rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/agents/ranger-reviewer.md"
}

# ---------------------------------------------------------------------------
# Autonomous Jira pings still carry the prefix inline (regression guard for
# the original convention that motivated the rule)
# ---------------------------------------------------------------------------

@test "ticket-pickup example Jira comments carry the 🤖 prefix" {
    grep -qF "$ROBOT Picked this one up" "$CORE_DIR/.claude/skills/ticket-pickup/SKILL.md"
}

@test "ticket-swarm example Jira comments carry the 🤖 prefix" {
    grep -qF "$ROBOT Submitted PR" "$CORE_DIR/.claude/skills/ticket-swarm/SKILL.md"
}
