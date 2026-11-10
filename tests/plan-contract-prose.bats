#!/usr/bin/env bats
# Pins the plan contract between the planner template and the implementer:
# acceptance criteria and their traceability to steps and tests, the flag
# Off/On statement with its flag-off regression test, and the scope-overrun
# pause. These live only in prose, so a paraphrase in a later template edit
# would otherwise drop the rule silently. Textual pins only.
#
# bash 3.2 note: every mid-test assertion ends in `|| return 1` so a failing
# `grep -q` cannot pass vacuously.
#
# Run with: bats tests/plan-contract-prose.bats

load 'test_helper'

# Prose wraps at ~78 columns, so multi-word phrases may span lines. _flat
# joins a file into one space-normalised line for phrase greps; anchored
# (^...) patterns still grep the raw file.
_flat() { tr '\n' ' ' < "$1" | tr -s ' '; }

OPT_AGENT="$DOTFILES_DIR/.claude/agents/optimus-planner.md"
OPT_SKILL="$DOTFILES_DIR/.claude/skills/optimus-planner/SKILL.md"
CYR_AGENT="$DOTFILES_DIR/.claude/agents/cyrus-tdd-engineer.md"
CYR_SKILL="$DOTFILES_DIR/.claude/skills/cyrus-tdd-engineer/SKILL.md"

# --- plan template ------------------------------------------------------------

@test "template: Section 1 defines acceptance criteria as numbered, ticket-derived, testable statements" {
    grep -q '^\*\*Acceptance criteria\*\*' "$OPT_AGENT" || return 1
    _flat "$OPT_AGENT" | grep -q 'a numbered list (AC-1, AC-2, …) of testable statements'
}

@test "template: Section 6 carries the acceptance-criteria traceability table with the three columns" {
    grep -qF '| AC | Delivered by (Section 4 step ids) | Proven by (test, or MANUAL: <check>) |' "$OPT_AGENT"
}

@test "template: Section 6 forbids dropping a criterion silently" {
    _flat "$OPT_AGENT" | grep -q 'a gap the plan states, never one it omits'
}

@test "template: Section 5 states Off and On behavior, Off equal to today's behavior by default" {
    grep -q '^- \*\*Off:\*\*' "$OPT_AGENT" || return 1
    grep -q '^- \*\*On:\*\*' "$OPT_AGENT" || return 1
    _flat "$OPT_AGENT" | grep -q 'must equal today.s behavior'
}

@test "template: Off/On lines sit inside Section 5 and outside any CORE-ONLY block so the portable render keeps them" {
    local s5 off s6 open
    s5="$(grep -n '^### 5\. ' "$OPT_AGENT" | head -1 | cut -d: -f1)"
    s6="$(grep -n '^### 6\. ' "$OPT_AGENT" | head -1 | cut -d: -f1)"
    off="$(grep -n '^- \*\*Off:\*\*' "$OPT_AGENT" | head -1 | cut -d: -f1)"
    [ -n "$s5" ] && [ -n "$s6" ] && [ -n "$off" ] || return 1
    [ "$off" -gt "$s5" ] || return 1
    [ "$off" -lt "$s6" ] || return 1
    open="$(awk -v o="$off" 'NR < o && /<!-- BEGIN CORE-ONLY -->/ { n++ } NR < o && /<!-- END CORE-ONLY -->/ { n-- } END { print n + 0 }' "$OPT_AGENT")"
    [ "$open" -eq 0 ]
}

@test "template: Section 6 requires a flag-off regression test when Section 5 proposes a flag" {
    _flat "$OPT_AGENT" | grep -q 'at least one test runs with the flag off'
}

@test "template: section headings the handoff relies on are unchanged" {
    grep -q '^### 1\. Problem Summary' "$OPT_AGENT" || return 1
    grep -q '^### 3\. Affected Areas' "$OPT_AGENT" || return 1
    grep -q '^### 4\. Execution Plan' "$OPT_AGENT" || return 1
    grep -q '^### 4a\. Reuse & Consolidation' "$OPT_AGENT" || return 1
    grep -q '^### 5\. Feature Flag Strategy' "$OPT_AGENT" || return 1
    grep -q '^### 6\. Testing Plan' "$OPT_AGENT" || return 1
    ! grep -q '^### 1a\.' "$OPT_AGENT"
}

@test "critique: check 2 names the traceability table in the agent and the skill" {
    _flat "$OPT_AGENT" | grep -q '§6 traceability table map every §1 acceptance criterion' || return 1
    _flat "$OPT_SKILL" | grep -q '§6 traceability table map every §1 acceptance criterion'
}

# --- implementer rules ----------------------------------------------------------

@test "cyrus: plan review names Section 1 acceptance criteria and the Section 6 traceability rows" {
    _flat "$CYR_AGENT" | grep -q 'the traceability rows in Section 6'
}

@test "cyrus: checklist maps every acceptance criterion to a passing test or a stated manual check and surfaces unmet ones" {
    grep -q '^- \[ \] Every acceptance criterion in the plan.s Section 1 maps to a passing test' "$CYR_AGENT" || return 1
    grep -q 'unmet criteria are listed in the report, never dropped' "$CYR_AGENT"
}

@test "cyrus: checklist tests both flag states when the plan has a flag" {
    grep -q '^- \[ \] When the plan.s Section 5 proposes a feature flag, both states are tested' "$CYR_AGENT"
}

@test "cyrus: scope-overrun pause names Section 3, the materially-larger trigger and both addressees" {
    _flat "$CYR_AGENT" | grep -q 'needs a file outside Section 3 (Affected Areas)' || return 1
    _flat "$CYR_AGENT" | grep -q 'materially larger than the step describes' || return 1
    _flat "$CYR_AGENT" | grep -q 'to the orchestrating skill in autonomous or swarm mode' || return 1
    _flat "$CYR_AGENT" | grep -q 'Never widen the scope silently'
}

@test "cyrus: checklist has no out-of-plan file change without a recorded, surfaced Deviation" {
    grep -q '^- \[ \] No file outside the plan.s Section 3 was changed' "$CYR_AGENT"
}

@test "cyrus skill: launch instruction carries the pause rule and Step 3 reports acceptance criteria and deviations" {
    _flat "$CYR_SKILL" | grep -q 'record a Deviation and stop' || return 1
    _flat "$CYR_SKILL" | grep -q 'a pause, not a boundary violation' || return 1
    grep -q '^- Acceptance criteria: met / unmet' "$CYR_SKILL" || return 1
    grep -q '^- Deviations recorded' "$CYR_SKILL"
}

@test "optimus skill: Deviations template records trigger and approver" {
    grep -qF -- 'trigger: <out-of-scope file | materially larger step | other>' "$OPT_SKILL" || return 1
    grep -qF -- 'approved by: <user | orchestrator>' "$OPT_SKILL"
}

@test "no company tokens in the plan-contract files" {
    local f tok
    for f in "$OPT_AGENT" "$OPT_SKILL" "$CYR_AGENT" "$CYR_SKILL"; do
        for tok in 'JQL' 'Atlassian'; do
            ! grep -q "$tok" "$f" || { echo "found $tok in $f"; return 1; }
        done
    done
}
