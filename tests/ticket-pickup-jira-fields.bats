#!/usr/bin/env bats
# Picking up a ticket fills in two Jira fields: the assignee (the user, unless
# they named someone else or asked for no change) and story points (an
# estimate, when the issue type has a points field and the ticket has none).
# ticket-pickup owns both rules; ticket-swarm transitions tickets itself, so it
# must apply them too. Taking a teammate's ticket needs approval: the gate in
# gated mode, a named assignee in autonomous mode.
# Run with: bats tests/ticket-pickup-jira-fields.bats

load 'test_helper'

SKILLS="$DOTFILES_DIR/.claude/skills"
PICKUP="$SKILLS/ticket-pickup/SKILL.md"
SWARM="$SKILLS/ticket-swarm/SKILL.md"

squash() { tr '\n' ' ' | tr -s ' '; }

step7() {
    sed -n '/^## Step 7: Jira status transition/,/^## Gate rules/p' "$PICKUP"
}

@test "ticket-pickup defaults the assignee target to the user, with named and no-change overrides" {
    grep -q 'resolve the \*\*assignee target\*\*' "$PICKUP" || return 1
    grep -q -- '- \*\*Default: the user.\*\*' "$PICKUP" || return 1
    grep -q -- '- \*\*A named person\*\*' "$PICKUP" || return 1
    grep -q -- '- \*\*No change\*\*' "$PICKUP" || return 1
}

@test "ticket-pickup shows the assignee and points changes at the gate with overrides" {
    grep -q 'Assignee:   Alex Kim -> you (reassigning)' "$PICKUP" || return 1
    grep -q 'Points:     none -> 3 (estimated)' "$PICKUP" || return 1
    grep -q -- '-> k  = Keep the current assignee, then go' "$PICKUP" || return 1
    grep -q -- '-> p N = Use N story points instead (1, 2, 3, 5, or 8)' "$PICKUP" || return 1
}

@test "ticket-pickup finds the story points field by name, not a hardcoded custom field ID" {
    grep -q '`getJiraIssueTypeMetaWithFields`' "$PICKUP" || return 1
    grep -q 'match the field named "Story Points" or "Story point estimate"' "$PICKUP" || return 1
    run grep -n 'customfield_[0-9]' "$PICKUP"
    [ "$status" -ne 0 ] || return 1
}

@test "ticket-pickup estimates on the Fibonacci scale and never overwrites existing points" {
    grep -q '^### Story point estimate' "$PICKUP" || return 1
    grep -q '\*\*1, 2, 3,$' "$PICKUP" || return 1
    grep -q 'Never overwrite an existing value' "$PICKUP" || return 1
    grep -q 'Never overwrite existing points' "$PICKUP" || return 1
}

@test "ticket-pickup Step 7 assigns, then sets points, then transitions" {
    local s
    s=$(step7)
    grep -q '^1\. Assign the ticket' <<<"$s" || return 1
    grep -q '^2\. Set story points' <<<"$s" || return 1
    grep -q '^3\. Call `getTransitionsForJiraIssue`' <<<"$s" || return 1
    grep -q '`atlassianUserInfo`' <<<"$s" || return 1
    grep -q '`lookupJiraAccountId`' <<<"$s" || return 1
    grep -q '`fields={"assignee": {"accountId": "<id>"}}`' <<<"$s" || return 1
    grep -q '`fields={"<points-field-id>": <N>}`' <<<"$s" || return 1
}

@test "ticket-pickup never takes a teammate's ticket unapproved in autonomous mode" {
    grep -q 'In autonomous mode, reassign' "$PICKUP" || return 1
    grep -q 'only when the caller named the assignee' "$PICKUP" || return 1
    grep -q 'A picked-up ticket is assigned to the user' "$PICKUP" || return 1
}

@test "ticket-swarm assigns and points at transition time and reports skipped reassignments" {
    grep -q "following ticket-pickup Step 7.1's autonomous" "$SWARM" || return 1
    grep -q 'following ticket-pickup Step 7.2' "$SWARM" || return 1
    grep -q 'mapping as ticket-pickup Step 7.5' "$SWARM" || return 1
    grep -q 'Left with their assignee:' "$SWARM" || return 1
}

@test "ticket-swarm triage estimates points and shows them at Gate 1" {
    grep -q 'Looks up the story points field and, if the ticket has none, estimates' "$SWARM" || return 1
    grep -q 'Complexity  Points  Summary' "$SWARM" || return 1
    grep -q -- '-> p N M  = Use M story points for ticket N' "$SWARM" || return 1
}

@test "ticket-pickup skips Step 7 in swarm mode because ticket-swarm owns the Jira writes" {
    step7 | squash | grep -qF '**In swarm mode:** Skip this step — ticket-swarm Step 4.5 assigns, sets story points, transitions and comments'
}

@test "ticket-pickup wording that assumed Step 7 always runs is scoped to outside swarm mode" {
    local flat
    flat=$(squash < "$PICKUP")
    grep -qF 'IMPORTANT:** Outside swarm mode, immediately after launching the pipeline, proceed to Step 7' <<<"$flat" || return 1
    grep -qF 'NEVER skip Jira transitions.** They happen at pipeline launch (Step 7, or ticket-swarm Step 4.5 in swarm mode)' <<<"$flat" || return 1
    grep -qF 'already In Progress from Step 7, or from ticket-swarm Step 4.5 in swarm mode' <<<"$flat"
}

@test "ticket-pickup forwards the assignee target in both ticket-swarm delegations" {
    local flat
    flat=$(squash < "$PICKUP")
    grep -qF '`assignee`: the assignee target from Step 1' <<<"$flat" || return 1
    grep -qF '`swarm_mode`, `unbounded` and `assignee` forwarded' <<<"$flat" || return 1
    grep -qF 'A caller-passed `assignee`' <<<"$flat"
}

@test "ticket-swarm takes an assignee input, from the caller or the user's request, and Step 4.5 uses it" {
    local s
    s=$(sed -n '/^## Step 4.5: Transition Jira tickets/,/^## Step 5/p' "$SWARM" | squash)
    grep -qF 'default the user, a named person, or no change' <(squash < "$SWARM") || return 1
    grep -qF 'Assign it to the `assignee` target' <<<"$s" || return 1
    grep -qF 'reassigned only when an assignee was named' <<<"$s" || return 1
    grep -qF 'In swarm mode ticket-pickup skips its Step 7' <<<"$s"
}
