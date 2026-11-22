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
