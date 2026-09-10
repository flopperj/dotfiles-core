#!/usr/bin/env bats
# Content-level guards for the Aristotle agent and its orchestrating skill.
#
# The structural suites (frontmatter, sentinels, role guards) cannot fail on a
# prose change. These tests pin the sections that a small prompt edit has
# already silently dropped once (the Implementation Handoff rule), and the
# Phase 0 contract that the agent and the skill must agree on.
# Run with: bats tests/agents-aristotle-content.bats

load 'test_helper'

AGENT="$DOTFILES_DIR/.claude/agents/aristotle-deconstructor.md"
SKILL="$DOTFILES_DIR/.claude/skills/aristotle-deconstructor/SKILL.md"
ROLE_GUARD_FRAGMENT="$DOTFILES_DIR/.claude/_shared/role-guards/aristotle.md"

# ---------------------------------------------------------------------------
# Agent: analytical sequence
# ---------------------------------------------------------------------------

@test "aristotle agent declares PHASE 0 framing check before PHASE 1" {
    local p0 p1
    p0=$(grep -n '^### PHASE 0: FRAMING CHECK' "$AGENT" | cut -d: -f1)
    p1=$(grep -n '^### PHASE 1: ASSUMPTION AUTOPSY' "$AGENT" | cut -d: -f1)
    [ -n "$p0" ] || return 1
    [ -n "$p1" ] || return 1
    [ "$p0" -lt "$p1" ] || return 1
}

@test "aristotle agent Phase 0 tells the agent to stop when analogy is the right tool" {
    grep -q 'If analogy is the better tool, stop' "$AGENT" || return 1
    grep -q 'Do not run the five phases' "$AGENT" || return 1
}

@test "aristotle agent Phase 0 override conditions on the current prompt, not memory" {
    grep -q 'current prompt contains an explicit override line' "$AGENT" || return 1
    # The dead form that asked a memoryless agent to remember a prior verdict.
    ! grep -q 'overridden a prior' "$AGENT" || return 1
}

@test "aristotle agent Phase 1 lists all six assumption-origin tags" {
    for tag in Convention Anchoring Fear Identity Inertia Tooling; do
        grep -qE "^- \*\*$tag\*\* —" "$AGENT" || return 1
    done
}

@test "aristotle agent Phase 5 requires a second-order effects field" {
    grep -q '^- \*\*Second-order effects:\*\*' "$AGENT" || return 1
}

@test "aristotle agent handoff section says measurement is code" {
    grep -q '^- \*\*Measurement is code\.\*\*' "$AGENT" || return 1
}

@test "aristotle agent handoff rule does not misdescribe the orchestrator" {
    # The orchestrator halts on an explicit "no code changes" statement in
    # autonomous mode only; a missing handoff section is not the trigger.
    ! grep -q 'reads a missing handoff as' "$AGENT" || return 1
}

# ---------------------------------------------------------------------------
# Skill: the orchestrator must handle both agent outcomes
# ---------------------------------------------------------------------------

@test "aristotle skill names the Phase 0 stop as a legal outcome" {
    grep -q '^\*\*Phase 0 stop (either mode):\*\*' "$SKILL" || return 1
}

@test "aristotle skill Step 2 offers an override on a Phase 0 stop" {
    grep -q -- '-> o = Override' "$SKILL" || return 1
}

@test "aristotle skill autonomous halt covers the Phase 0 stop" {
    grep -q 'or ends in a Phase 0' "$SKILL" || return 1
}

@test "aristotle skill documents the override re-invocation line" {
    grep -q '^\*\*Override re-invocation\.\*\*' "$SKILL" || return 1
    grep -q 'Override: the user has reviewed your Phase 0' "$SKILL" || return 1
}

@test "skill override line and agent override clause agree on the required wording" {
    # I5 was a drift bug between these two files: the agent must accept exactly the
    # literal the skill prepends. The agent conditions on "an explicit override line
    # stating that the user has seen a \"wrong tool\" verdict"; the skill's literal
    # must therefore contain both "Override" and the quoted verdict phrase.
    local literal
    # The literal wraps across markdown lines; flatten before matching.
    literal=$(tr '\n' ' ' < "$SKILL" | grep -o 'Override: the user has reviewed your Phase 0[^`]*' | head -1)
    [ -n "$literal" ] || return 1
    [[ "$literal" == *'"wrong tool" verdict'* ]] || return 1
    [[ "$literal" == *"full five-phase analysis"* ]] || return 1
    grep -q 'override line stating that the user has seen a "wrong tool" verdict' "$AGENT" || return 1
}

@test "aristotle skill autonomous Phase 0 branch returns an advisory outcome, not blocked" {
    grep -q 'Return an \*\*advisory outcome\*\*' "$SKILL" || return 1
    grep -q 'counts it under Advisory, not' "$SKILL" || return 1
    # The interim wording that filed a correct verdict under the blocked bucket is gone.
    ! grep -q 'ends without a PR as \*\*blocked\*\*' "$SKILL" || return 1
}

@test "aristotle skill gate rules route a no-code-changes conclusion to the advisory outcome" {
    grep -q 'return an advisory outcome to the caller' "$SKILL" || return 1
}

@test "aristotle skill truncation rule does not treat a missing handoff as truncation" {
    grep -q 'A missing handoff is not by itself the truncation signature' "$SKILL" || return 1
}

@test "aristotle skill no longer promises an unconditional 5-phase analysis" {
    ! grep -q 'still runs the full 5-phase analysis' "$SKILL" || return 1
}

# ---------------------------------------------------------------------------
# Role guard: the shared fragment and the injected copy agree
# ---------------------------------------------------------------------------

@test "aristotle role guard admits the Phase 0 verdict as a deliverable" {
    grep -q 'or a Phase 0 framing verdict' "$ROLE_GUARD_FRAGMENT" || return 1
    grep -q 'or a Phase 0 framing verdict' "$AGENT" || return 1
}
