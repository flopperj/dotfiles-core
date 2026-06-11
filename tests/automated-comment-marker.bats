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
    # Scope the emoji check to the rule's own section — an unscoped whole-file
    # grep would pass even if the emoji were deleted from the rule but present
    # in some unrelated future section.
    run grep -A20 "## Automated Comment Marker" "$FRAGMENT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$ROBOT"* ]]
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
    # Assert both the heading AND an operative body line — a render that kept
    # the heading but truncated/mangled the rule body would otherwise pass.
    grep -qF "## Automated Comment Marker" "$GENERATED"
    grep -qF "must begin with" "$GENERATED"
}

# ---------------------------------------------------------------------------
# Posting skills/agents reference the canonical rule AND carry the operative
# prefix instruction. Asserting only the section-name citation would let a
# regression that kept the heading reference but deleted the "prefix the
# comment body with 🤖" instruction pass green — the exact drift this file
# exists to prevent. Each reviewer surface must therefore assert both:
#   (a) the canonical-rule citation, and
#   (b) the operative "Prefix … comment body with 🤖 " instruction.
# ---------------------------------------------------------------------------

# The GitHub PR-comment surfaces (scout/ranger, skill + agent) had no marker
# before this rule, so the operative instruction is the load-bearing assertion.
@test "scout-reviewer skill cites the rule and carries the prefix instruction" {
    local f="$CORE_DIR/.claude/skills/scout-reviewer/SKILL.md"
    grep -qF "Automated Comment Marker" "$f"
    grep -qE "Prefix (each|every) comment body with .$ROBOT" "$f"
}

@test "ranger-reviewer skill cites the rule and carries the prefix instruction" {
    local f="$CORE_DIR/.claude/skills/ranger-reviewer/SKILL.md"
    grep -qF "Automated Comment Marker" "$f"
    grep -qE "Prefix (each|every) comment body with .$ROBOT" "$f"
}

@test "scout-reviewer agent cites the rule and carries the prefix instruction" {
    local f="$CORE_DIR/.claude/agents/scout-reviewer.md"
    grep -qF "Automated Comment Marker" "$f"
    grep -qE "Prefix (each|every) comment body with .$ROBOT" "$f"
}

@test "ranger-reviewer agent cites the rule and carries the prefix instruction" {
    local f="$CORE_DIR/.claude/agents/ranger-reviewer.md"
    grep -qF "Automated Comment Marker" "$f"
    grep -qE "Prefix (each|every) comment body with .$ROBOT" "$f"
}

# The Jira-ping surfaces (ticket-pickup/swarm) cite the rule and carry the
# prefix inline on their example comment strings (asserted below).
@test "ticket-pickup cites the rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/skills/ticket-pickup/SKILL.md"
}

@test "ticket-swarm cites the rule" {
    grep -qF "Automated Comment Marker" "$CORE_DIR/.claude/skills/ticket-swarm/SKILL.md"
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
