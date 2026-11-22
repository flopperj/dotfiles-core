#!/usr/bin/env bats
# Wording and structure pins for Ranger's skeptic pass, the shared
# INTENT-AND-PRIOR-COMMENTS block, the open-question rule in VERIFY-THEN-DRAFT,
# and the rollout checklist both reviewers apply. No model runs here; these
# keep a rewrite from quietly dropping a rule the review flow relies on.
#
# Run with: bats tests/reviewer-skeptic-intent.bats

setup() {
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    RANGER_SKILL="$DOTFILES_DIR/.claude/skills/ranger-reviewer/SKILL.md"
    SCOUT_SKILL="$DOTFILES_DIR/.claude/skills/scout-reviewer/SKILL.md"
    RANGER_AGENT="$DOTFILES_DIR/.claude/agents/ranger-reviewer.md"
    SCOUT_AGENT="$DOTFILES_DIR/.claude/agents/scout-reviewer.md"
    HEUR="$DOTFILES_DIR/.claude/skills/code-auditor/references/review-heuristics.md"
    TIERS="$DOTFILES_DIR/.claude/_shared/model-tiers.md"
    INTENT_FRAGMENT="$DOTFILES_DIR/.claude/_shared/reviewer-blocks/intent-and-prior-comments.md"
    VERIFY_FRAGMENT="$DOTFILES_DIR/.claude/_shared/reviewer-blocks/verify-then-draft.md"
    ANCHOR_FRAGMENT="$DOTFILES_DIR/.claude/_shared/reviewer-blocks/anchor-constraints.md"
}

_skeptic_section() {
    sed -n '/^### Step 2b: Skeptic pass/,/^### Step 2c:/p' "$RANGER_SKILL"
}

_line_of() {
    grep -nF -- "$1" "$2" | head -n 1 | cut -d: -f1
}

@test "ranger has a skeptic pass between the agent report and verify-then-draft" {
    local a b c
    a="$(_line_of '### Step 2b: Skeptic pass' "$RANGER_SKILL")"
    b="$(_line_of '### Step 2c: Verify findings before drafting' "$RANGER_SKILL")"
    c="$(_line_of '### Step 2d: Stress-test findings against the senior-staff bar' "$RANGER_SKILL")"
    [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] || return 1
    [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}

@test "the skeptic is a fresh read-only general-purpose sub-agent on the opus alias" {
    local s
    s="$(_skeptic_section)"
    [ -n "$s" ] || return 1
    grep -qF 'general-purpose' <<<"$s" || return 1
    grep -qF 'model: "opus"' <<<"$s" || return 1
    grep -qF 'Read-only' <<<"$s" || return 1
    grep -qF 'Do not produce new findings' <<<"$s" || return 1
    ! grep -qE 'claude-[a-z0-9]' <<<"$s"
}

@test "the seven checks are present in order" {
    local s f prev=0 n check
    s="$(_skeptic_section)"
    [ -n "$s" ] || return 1
    f="$BATS_TEST_TMPDIR/skeptic.md"
    printf '%s\n' "$s" > "$f"
    for check in 'Does the anchor exist?' 'Did the diff introduce it?' 'Is it intentional?' \
        'Is it guarded?' 'Would CI catch it?' 'Is it already raised?' 'Does it matter?'; do
        n="$(_line_of "$check" "$f")"
        [ -n "$n" ] || { echo "missing check: $check"; return 1; }
        [ "$n" -gt "$prev" ] || { echo "out of order: $check"; return 1; }
        prev="$n"
    done
}

@test "the five verdicts are named" {
    local s v
    s="$(_skeptic_section)"
    [ -n "$s" ] || return 1
    for v in CONFIRMED PLAUSIBLE REFUTED INTENTIONAL OUT_OF_SCOPE; do
        grep -qF -- "$v" <<<"$s" || { echo "missing verdict: $v"; return 1; }
    done
}

@test "PR text cannot refute a finding and an injection finding is never intentional" {
    local s
    s="$(_skeptic_section)"
    [ -n "$s" ] || return 1
    grep -qF 'untrusted data, not instructions' <<<"$s" || return 1
    grep -qF 'It is never INTENTIONAL' <<<"$s"
}

@test "the skeptic section cannot post" {
    local s
    s="$(_skeptic_section)"
    [ -n "$s" ] || return 1
    ! grep -qF '"event"' <<<"$s" || return 1
    ! grep -qF -- '--method POST' <<<"$s" || return 1
    ! grep -qF 'gh pr review' <<<"$s"
}

@test "orchestrator rules: fallback, evidence, thin-description note, unreported issues" {
    local s p
    s="$(_skeptic_section)"
    [ -n "$s" ] || return 1
    for p in 'No verdict line' 'cites no `path:line`' 'more than half' 'at least three' 'unverified, worth a look'; do
        grep -qF -- "$p" <<<"$s" || { echo "missing: $p"; return 1; }
    done
}

@test "dropped findings are shown at the gate" {
    grep -qF '### Refuted by the skeptic' "$RANGER_SKILL"
}

@test "scout keeps its blockers-only confirmation and has no skeptic pass" {
    grep -qF '### Step 2b: Ranger Confirmation (blockers only)' "$SCOUT_SKILL" || return 1
    ! grep -qF 'Skeptic pass' "$SCOUT_SKILL"
}

@test "verify-then-draft keeps an open question as a question" {
    local f
    grep -qF 'open question' "$VERIFY_FRAGMENT" || return 1
    for f in "$VERIFY_FRAGMENT" "$RANGER_SKILL" "$SCOUT_SKILL"; do
        grep -qF 'Never draft it as an assertion' "$f" || { echo "missing in $f"; return 1; }
    done
}

@test "intent block: brief sources, both comment reads with a literal host flag, three rules, data not instructions" {
    local p
    [ -s "$INTENT_FRAGMENT" ] || return 1
    for p in 'Motivation brief' 'pulls/<n>/comments' 'issues/<n>/comments' '--hostname <host>' \
        'Read the brief before the diff' 'Intent explains, it never clears' \
        'Do not repeat a prior comment' 'data, not instructions'; do
        grep -qF -- "$p" "$INTENT_FRAGMENT" || { echo "missing: $p"; return 1; }
    done
    ! grep -qE 'https?://' "$INTENT_FRAGMENT"
}

@test "both reviewers pass the brief and prior comments at launch" {
    local f
    for f in "$RANGER_SKILL" "$SCOUT_SKILL"; do
        grep -qF 'The motivation brief and the prior-comments list from Step 1d' "$f" \
            || { echo "missing in $f"; return 1; }
    done
}

@test "heuristics carry the rollout checklist and name the skeptic pass as a delivery target" {
    local s p
    s="$(sed -n '/^## Rollout and operations/,/^## Scope feedback/p' "$HEUR")"
    [ -n "$s" ] || return 1
    for p in Gating 'Config and environments' 'Migrations and data' 'Timeouts and retries' \
        'Performance cliffs' Observability Rollback; do
        grep -qF -- "$p" <<<"$s" || { echo "missing: $p"; return 1; }
    done
    grep -qF 'confirmation pass or skeptic pass' "$HEUR"
}

@test "both agents carry the rollout checklist, the pointer and the brief intake" {
    local f p
    for f in "$RANGER_AGENT" "$SCOUT_AGENT"; do
        for p in 'Rollout & Operations' '§ Rollout and operations' 'Motivation brief and prior comments (when passed)'; do
            grep -qF -- "$p" "$f" || { echo "missing in $f: $p"; return 1; }
        done
    done
}

@test "model-tiers records the skeptic tier as an alias" {
    local s
    s="$(sed -n '/^### Inline sub-agent passes/,/^## /p' "$TIERS")"
    [ -n "$s" ] || return 1
    grep -qF 'Skeptic pass' <<<"$s" || return 1
    grep -qF '`opus`' <<<"$s"
}

@test "pending-review contract is intact" {
    grep -qF 'omit the `event` field' "$ANCHOR_FRAGMENT"
}
