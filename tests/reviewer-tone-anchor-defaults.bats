#!/usr/bin/env bats
# Semantic default tests for the shared reviewer contract fragments:
# peer tone by default, a stated density budget, and affected-block anchoring.
#
# These assert against the fragments in .claude/_shared/reviewer-blocks/ —
# the canonical home. tests/reviewer-shared-blocks.bats already proves the
# SKILL.md copies match the fragments byte-for-byte.
#
# bash 3.2 note: assertions are &&-chained into each test's final command.
#
# Run with: bats tests/reviewer-tone-anchor-defaults.bats

load 'test_helper'

TONE_FRAGMENT="$DOTFILES_DIR/.claude/_shared/reviewer-blocks/tone-calibration.md"
ANCHOR_FRAGMENT="$DOTFILES_DIR/.claude/_shared/reviewer-blocks/anchor-constraints.md"
RANGER_AGENT="$DOTFILES_DIR/.claude/agents/ranger-reviewer.md"
SCOUT_AGENT="$DOTFILES_DIR/.claude/agents/scout-reviewer.md"

# ---------------------------------------------------------------------------
# Tone — flip #1: peer is the default voice
# ---------------------------------------------------------------------------

@test "tone: old explanatory-default declaration is gone" {
    [ -f "$TONE_FRAGMENT" ] && ! grep -Fq 'explanatory" — restate context' "$TONE_FRAGMENT"
}

@test "tone: fragment states peer as the default voice" {
    [ -f "$TONE_FRAGMENT" ] && grep -Fq 'default voice is **peer**' "$TONE_FRAGMENT"
}

@test "tone: menu marks peer as default" {
    local p_line
    p_line="$(grep -F -- '-> p = Peer' "$TONE_FRAGMENT" 2>/dev/null || true)"
    [ -n "$p_line" ] && echo "$p_line" | grep -Fq '(default)'
}

@test "tone: menu no longer marks explanatory as default" {
    local e_line
    e_line="$(grep -F -- '-> e = Explanatory' "$TONE_FRAGMENT" 2>/dev/null || true)"
    [ -n "$e_line" ] && ! echo "$e_line" | grep -Fq '(default)'
}

@test "tone: autonomous mode defaults to peer, not explanatory" {
    [ -f "$TONE_FRAGMENT" ] \
        && grep -Fq 'Default to peer if signal is ambiguous' "$TONE_FRAGMENT" \
        && ! grep -Fq 'Default to explanatory if signal is ambiguous' "$TONE_FRAGMENT"
}

@test "tone: explanatory rung survives for low-contribution authors" {
    # Peer default must not delete the junior-author path: fewer than 10
    # contributions still upgrades to the explanatory voice.
    [ -f "$TONE_FRAGMENT" ] \
        && grep -Fq 'lean **explanatory**' "$TONE_FRAGMENT" \
        && grep -Eq '(<|fewer than )10' "$TONE_FRAGMENT"
}

@test "tone: stale 'not changed everywhere' sentence is gone" {
    [ -f "$TONE_FRAGMENT" ] \
        && ! grep -Fq 'The default Ranger voice is not changed everywhere' "$TONE_FRAGMENT"
}

# ---------------------------------------------------------------------------
# Density — flip #2: a stated, checkable budget
# ---------------------------------------------------------------------------

@test "density: budget section exists in the tone fragment" {
    [ -f "$TONE_FRAGMENT" ] && grep -Eiq '^#+ Density budget' "$TONE_FRAGMENT"
}

@test "density: a numeric sentence ceiling is stated" {
    [ -f "$TONE_FRAGMENT" ] && grep -Fq 'at most two sentences' "$TONE_FRAGMENT"
}

@test "density: restating context is prohibited" {
    [ -f "$TONE_FRAGMENT" ] && grep -Fq 'No restated context' "$TONE_FRAGMENT"
}

@test "density: A/B prescription by default is prohibited" {
    [ -f "$TONE_FRAGMENT" ] && grep -Fq 'No A/B prescription by default' "$TONE_FRAGMENT"
}

@test "density: escape hatch for Blocking findings is named" {
    [ -f "$TONE_FRAGMENT" ] \
        && grep -Fiq 'escape hatch' "$TONE_FRAGMENT" \
        && grep -Fq 'Blocking' "$TONE_FRAGMENT" \
        && grep -Fq 'may exceed the ceiling' "$TONE_FRAGMENT"
}

# ---------------------------------------------------------------------------
# Anchor — flip #3: affected-block range by default, clamped to the hunk
# ---------------------------------------------------------------------------

@test "anchor: affected-block definition section is present" {
    [ -f "$ANCHOR_FRAGMENT" ] && grep -Fq '**Affected block.**' "$ANCHOR_FRAGMENT"
}

@test "anchor: block range is fallback rung 1 and stale narrow-range phrase is gone" {
    local rung1
    rung1="$(grep -A2 '### Fallback order' "$ANCHOR_FRAGMENT" 2>/dev/null | grep '^1\.' || true)"
    [ -n "$rung1" ] \
        && echo "$rung1" | grep -Fiq 'affected block' \
        && ! grep -Fq 'smallest contiguous range' "$ANCHOR_FRAGMENT"
}

@test "anchor: single-line is a fallback, not the general-purpose safe default" {
    [ -f "$ANCHOR_FRAGMENT" ] \
        && ! grep -Fq 'are the safest fallback' "$ANCHOR_FRAGMENT" \
        && grep -Eiq 'single.line.*fallback|fallback.*single.line' "$ANCHOR_FRAGMENT"
}

@test "anchor: hunk-crossing clamp rule is present" {
    [ -f "$ANCHOR_FRAGMENT" ] \
        && grep -Fq 'truncate to the hunk edge' "$ANCHOR_FRAGMENT" \
        && grep -Fiq 'clamp' "$ANCHOR_FRAGMENT"
}

@test "anchor: example payload demonstrates a multi-line comment with start_line" {
    [ -f "$ANCHOR_FRAGMENT" ] && grep -Fq '"start_line"' "$ANCHOR_FRAGMENT"
}

# ---------------------------------------------------------------------------
# Agent files — the posting instructions must not contradict the orchestrator
# ---------------------------------------------------------------------------

@test "agents: both reviewer agent files anchor with start_line" {
    [ -f "$RANGER_AGENT" ] && [ -f "$SCOUT_AGENT" ] \
        && grep -Fq 'start_line' "$RANGER_AGENT" \
        && grep -Fq 'start_line' "$SCOUT_AGENT"
}

@test "agents: stale single-line-only fallback framing is gone" {
    [ -f "$RANGER_AGENT" ] && [ -f "$SCOUT_AGENT" ] \
        && ! grep -Fq 'only if a comment cannot be anchored to a specific line' "$RANGER_AGENT" \
        && ! grep -Fq 'only if a comment cannot be anchored to a specific line' "$SCOUT_AGENT"
}

@test "anchor: all hard constraints and the 422 warning survive verbatim" {
    # Regression guard: widening the default anchor must not erode the
    # constraints that prevent a 422 from killing the entire review.
    [ -f "$ANCHOR_FRAGMENT" ] \
        && grep -Fq '**Both endpoints must be inside the diff.**' "$ANCHOR_FRAGMENT" \
        && grep -Fq '**Both endpoints must be in the same hunk.**' "$ANCHOR_FRAGMENT" \
        && grep -Fq '**`side` must be consistent.**' "$ANCHOR_FRAGMENT" \
        && grep -Fq 'returns HTTP 422 and the entire review (not just the offending comment) fails to post' "$ANCHOR_FRAGMENT"
}
