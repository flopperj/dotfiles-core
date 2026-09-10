#!/usr/bin/env bats
# The "advisory" terminal outcome is a cross-skill contract: Aristotle returns
# it, ticket-pickup emits and comments it, ticket-swarm and team-lead count it
# apart from blocked, the metrics schema types it, and agent-stats excludes it
# from the first-pass denominator. These tests pin that every party names the
# same outcome so one file cannot drift back to two buckets on its own.
# Run with: bats tests/advisory-outcome.bats

load 'test_helper'

SKILLS="$DOTFILES_DIR/.claude/skills"
PICKUP="$SKILLS/ticket-pickup/SKILL.md"
SWARM="$SKILLS/ticket-swarm/SKILL.md"
LEAD="$SKILLS/team-lead/SKILL.md"
ARISTOTLE="$SKILLS/aristotle-deconstructor/SKILL.md"
METRICS="$SKILLS/metrics-emit/SKILL.md"
RETRO="$SKILLS/swarm-retro/SKILL.md"
STATS_SKILL="$SKILLS/agent-stats/SKILL.md"
SWARM_CONTEXT="$DOTFILES_DIR/.claude/workflows/schemas/swarm-context.json"

@test "aristotle returns outcome: advisory in autonomous mode" {
    grep -q '`outcome: advisory`' "$ARISTOTLE" || return 1
}

@test "ticket-pickup emits pipeline_complete with outcome: advisory and comments the verdict" {
    grep -q '`outcome: advisory`' "$PICKUP" || return 1
    grep -q "Looked into this one and the answer isn't a code" "$PICKUP" || return 1
    grep -q 'Three terminal outcomes, not two' "$PICKUP" || return 1
}

@test "ticket-pickup never files an advisory outcome as blocked" {
    grep -q 'Never file an advisory' "$PICKUP" || return 1
    grep -q 'Do not treat an advisory outcome as a failure' "$PICKUP" || return 1
}

@test "ticket-swarm has an ADVISORY dashboard state and an Advisory summary line" {
    grep -q '\[ADVISORY\]' "$SWARM" || return 1
    grep -qE '^  Advisory: +1 \(' "$SWARM" || return 1
    grep -q 'Launched: {N} | Completed: {N} | Advisory: {N} | Blocked: {N}' "$SWARM" || return 1
}

@test "ticket-swarm comments advisory tickets differently from blocked ones" {
    grep -q "For advisory tickets (correct no-code answer):" "$SWARM" || return 1
    grep -q "For blocked/aborted tickets:" "$SWARM" || return 1
}

@test "ticket-swarm swarm_complete data carries advisory and the adjusted first_pass_rate" {
    grep -q '^- `advisory`: tickets whose pipeline ended with a correct no-code answer' "$SWARM" || return 1
    grep -q 'first_pass_rate`: (completed on first attempt) / (tickets_total − advisory)' "$SWARM" || return 1
}

@test "team-lead reports Advisory apart from Blocked and skips failure analysis for it" {
    grep -qE '^  Advisory: +1 \(' "$LEAD" || return 1
    grep -q 'Tickets in `advisory` are \*\*not\*\* blocked' "$LEAD" || return 1
}

@test "swarm-context schema declares an optional advisory array with ticket and verdict" {
    jq -e '.properties.advisory.items.required == ["ticket","verdict"]' "$SWARM_CONTEXT" >/dev/null || return 1
    jq -e '(.required | index("advisory")) == null' "$SWARM_CONTEXT" >/dev/null || return 1
}

@test "metrics-emit documents the advisory outcome and its null fields" {
    grep -q '^- `advisory` — the pipeline ended deliberately with no code change' "$METRICS" || return 1
    grep -q '`tests_passed: null`' "$METRICS" || return 1
    grep -q 'completed + advisory + blocked == tickets_total' "$METRICS" || return 1
}

@test "swarm-retro does not read advisory as misclassification" {
    grep -q 'Advisory is not a misclassification signal' "$RETRO" || return 1
}

@test "agent-stats skill documents the advisory exclusion" {
    grep -q 'excluded from the first-pass denominator' "$STATS_SKILL" || return 1
}

@test "no skill still describes a two-bucket terminal model for Aristotle stops" {
    # The interim wording that routed a correct verdict into the blocked bucket.
    ! grep -rq 'ends without a PR as \*\*blocked\*\*' "$SKILLS" || return 1
}

@test "team-lead-waves workflow accepts status advisory and returns an advisory array" {
    local wf="$DOTFILES_DIR/.claude/workflows/team-lead-waves.js"
    grep -q "enum: \['done', 'advisory', 'blocked'\]" "$wf" || return 1
    grep -q "verdict: { type: 'string' }" "$wf" || return 1
    grep -q "r.status === 'advisory'" "$wf" || return 1
    grep -q "result = { waves, sequencing_reasons: sequencingReasons, domain, blocked, advisory }" "$wf" || return 1
    # The pipeline prompt tells the agent when to answer advisory.
    grep -q '"status": "done" if the pipeline produced a PR, "advisory" if' "$wf" || return 1
}

@test "team-lead-waves workflow never files an advisory result under blocked" {
    local wf="$DOTFILES_DIR/.claude/workflows/team-lead-waves.js"
    # The advisory branch pushes to `advisory`, not `blocked`, and runs before the done fallthrough.
    awk "/r.status === 'advisory'/,/} else {/" "$wf" | grep -q 'advisory.push' || return 1
    ! awk "/r.status === 'advisory'/,/} else {/" "$wf" | grep -q 'blocked.push' || return 1
}
