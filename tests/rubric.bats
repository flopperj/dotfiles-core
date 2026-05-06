#!/usr/bin/env bats
# Consistency tests between the self-evaluate skill's SKILL.md and rubric.md.
# These prevent the same class of drift the previous PR refinement just fixed:
# rubric weights, band table, and verdict words must agree across both files.

setup() {
    SKILL_MD="$BATS_TEST_DIRNAME/../.claude/skills/self-evaluate/SKILL.md"
    RUBRIC_MD="$BATS_TEST_DIRNAME/../.claude/skills/self-evaluate/references/rubric.md"
    [ -f "$SKILL_MD" ] || skip "self-evaluate SKILL.md missing"
    [ -f "$RUBRIC_MD" ] || skip "self-evaluate rubric.md missing"
}

@test "rubric: all 5 verdict words appear in both SKILL.md and rubric.md" {
    for verdict in "below senior bar" "solid senior" "approaching staff" "staff-caliber" "principal-leaning"; do
        grep -qF "$verdict" "$SKILL_MD" || { echo "Missing in SKILL.md: $verdict"; return 1; }
        grep -qF "$verdict" "$RUBRIC_MD" || { echo "Missing in rubric.md: $verdict"; return 1; }
    done
}

@test "rubric: band table covers 9-45 with no gaps" {
    grep -qE '^\| 9-17 \|' "$RUBRIC_MD"
    grep -qE '^\| 18-26 \|' "$RUBRIC_MD"
    grep -qE '^\| 27-35 \|' "$RUBRIC_MD"
    grep -qE '^\| 36-44 \|' "$RUBRIC_MD"
    grep -qE '^\| 45 \|' "$RUBRIC_MD"
}

@test "rubric: weighted total maximum is 45" {
    grep -qF "Total maximum is **45**" "$RUBRIC_MD"
    grep -qF "/45" "$SKILL_MD"
}

@test "rubric: portability and operational safety are the double-weighted axes" {
    # Rubric explicitly names which two count double
    grep -qF "portability across machines" "$RUBRIC_MD"
    grep -qF "operational safety" "$RUBRIC_MD"
    grep -qE "(double|2x|2×)" "$RUBRIC_MD"

    # SKILL.md scorecard table marks the same two axes as bold
    grep -qF "**portability across machines**" "$SKILL_MD"
    grep -qF "**operational safety**" "$SKILL_MD"
}

@test "rubric: verdict-override rules are documented" {
    grep -qF "Any axis ≤ 2" "$RUBRIC_MD"
    grep -qF "Portability or operational safety = 1" "$RUBRIC_MD"
    # SKILL.md instructs the reviewer to cite caps
    grep -qF "capped" "$SKILL_MD"
}

@test "rubric: weighted total formula in SKILL.md matches rubric.md" {
    # Both files must reference the same formula shape: 2x port + 2x safety
    grep -qE "2.{0,3}port" "$SKILL_MD"
    grep -qE "2.{0,3}safety" "$SKILL_MD"
}
