#!/usr/bin/env bats
# The posted review body contract shared by Scout and Ranger
# (.claude/_shared/reviewer-blocks/review-body-format.md), spliced into both
# SKILL.md files by scripts/reviewer-blocks-gen.sh. reviewer-shared-blocks.bats
# proves the splice is faithful; this file pins what the contract says, so a
# rewrite cannot quietly drop the parts the marker rule, the approval path and
# review-respond rely on.
#
# Run with: bats tests/reviewer-body-format.bats

setup() {
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    FRAGMENT="$DOTFILES_DIR/.claude/_shared/reviewer-blocks/review-body-format.md"
    RANGER_SKILL="$DOTFILES_DIR/.claude/skills/ranger-reviewer/SKILL.md"
    SCOUT_SKILL="$DOTFILES_DIR/.claude/skills/scout-reviewer/SKILL.md"
    RANGER_AGENT="$DOTFILES_DIR/.claude/agents/ranger-reviewer.md"
    SCOUT_AGENT="$DOTFILES_DIR/.claude/agents/scout-reviewer.md"
    REVIEW_RESPOND="$DOTFILES_DIR/.claude/skills/review-respond/SKILL.md"
}

@test "fragment exists and opens with a level-4 heading like the other reviewer blocks" {
    [ -s "$FRAGMENT" ]
    [[ "$(head -n 1 "$FRAGMENT")" == "#### "* ]]
}

@test "the body template starts with the robot marker and a bold verdict, not a heading" {
    local first
    first="$(awk '/^```$/ { fence++; next } fence == 1 { print; exit }' "$FRAGMENT")"
    [ "$first" = '🤖 **<Verdict> @ `<short-sha>`**' ]
}

@test "the contract fixes the verdict vocabulary" {
    local v
    for v in '✅ No blockers' '✅ Approving' '🟡 Needs changes' '🔴 Blocked'; do
        grep -qF -- "$v" "$FRAGMENT" || { echo "missing verdict: $v"; return 1; }
    done
}

@test "blockers stay visible and only non-blocking items collapse" {
    grep -qF 'Blockers are never collapsed' "$FRAGMENT"
    grep -qF '<details>' "$FRAGMENT"
    grep -qF 'Non-blocking' "$FRAGMENT"
}

@test "re-review mode, CI at the head, cross-repo links and literal gh hosts are all stated" {
    grep -qF 'Re-review @' "$FRAGMENT"
    grep -qF 'Unchanged since my review' "$FRAGMENT"
    grep -qF 'gh pr checks' "$FRAGMENT"
    grep -qF '[owner/repo#N — title](url)' "$FRAGMENT"
    grep -qF -- '--hostname <host>' "$FRAGMENT"
}

@test "both reviewer SKILL.md files carry the block with its directive" {
    local f
    for f in "$RANGER_SKILL" "$SCOUT_SKILL"; do
        grep -qF '<!-- BEGIN REVIEW-BODY-FORMAT -->' "$f" || { echo "no BEGIN sentinel in $f"; return 1; }
        grep -qF '<!-- REVIEWER_BLOCK: review-body-format -->' "$f" || { echo "no directive in $f"; return 1; }
        grep -qF '<!-- END REVIEW-BODY-FORMAT -->' "$f" || { echo "no END sentinel in $f"; return 1; }
    done
}

@test "both reviewer SKILL.md files route the posted body and the approval body through the block" {
    local f
    for f in "$RANGER_SKILL" "$SCOUT_SKILL"; do
        # Two sentinels plus the post step, the approve step and the gate rule.
        [ "$(grep -c 'REVIEW-BODY-FORMAT' "$f")" -ge 5 ] || { echo "too few references in $f"; return 1; }
        grep -qF 'Approving @' "$f" || { echo "approval first line missing in $f"; return 1; }
        grep -qF -- '--approve --body-file' "$f" || { echo "approval not posted from a body file in $f"; return 1; }
    done
}

@test "both reviewer SKILL.md files read CI and prior reviews before reviewing" {
    local f
    for f in "$RANGER_SKILL" "$SCOUT_SKILL"; do
        grep -qF 'pulls/<n>/reviews' "$f" || { echo "prior reviews not read in $f"; return 1; }
        grep -qF 'gh pr checks <n> --repo <host>/<o>/<r>' "$f" || { echo "CI not read in $f"; return 1; }
    done
}

@test "both agent prompts point at the block and map Merge Readiness onto its vocabulary" {
    local f
    for f in "$RANGER_AGENT" "$SCOUT_AGENT"; do
        grep -qF 'REVIEW-BODY-FORMAT' "$f" || { echo "no pointer in $f"; return 1; }
        grep -qF 'NEEDS CHANGES → `🟡 Needs changes`' "$f" || { echo "no vocabulary mapping in $f"; return 1; }
    done
}

@test "review-respond cross-links the reviewer body format" {
    grep -qF 'REVIEW-BODY-FORMAT' "$REVIEW_RESPOND"
}
