#!/usr/bin/env bats
# Static structural tests for the self-evaluate skill's mode-detection block.
# These prevent silent drift in the precedence rules that decide core vs
# overlay mode. They grep the SKILL.md for the exact precedence anchors
# documented in §0 of the skill body.

setup() {
    SKILL_MD="$BATS_TEST_DIRNAME/../.claude/skills/self-evaluate/SKILL.md"
    [ -f "$SKILL_MD" ]
}

@test "detection: SKILL.md exists at canonical core path" {
    [ -f "$SKILL_MD" ]
}

@test "detection: precedence section ## 0. Detect mode is present" {
    grep -qE "^## 0\. Detect mode" "$SKILL_MD"
}

@test "detection: rule 1 names --core and --overlay flag handling" {
    grep -qF -- "--core" "$SKILL_MD"
    grep -qF -- "--overlay" "$SKILL_MD"
}

@test "detection: rule 2 names overlay markers (dotfiles-core dir, overlay-context.md)" {
    grep -qF ".claude/dotfiles-core/" "$SKILL_MD"
    grep -qF "_shared/overlay-context.md" "$SKILL_MD"
}

@test "detection: rule 3 names core markers (lib-core-symlinks.sh, lib-core-seeds.sh)" {
    grep -qF "lib-core-symlinks.sh" "$SKILL_MD"
    grep -qF "lib-core-seeds.sh" "$SKILL_MD"
}

@test "detection: refusal branch is documented" {
    grep -qiE "(refuse|reject|polite)" "$SKILL_MD"
}

@test "detection: conflict-handling section names flag-precedes-cwd" {
    grep -qiE "(flag.*wins|flag.*overrides|explicit.*override|--core.*override)" "$SKILL_MD"
}

@test "detection: mode is reported in the report header" {
    grep -qiE "Mode:\**\s*(Overlay|Core)" "$SKILL_MD"
}

@test "detection: --core cross-tree audit case is documented" {
    grep -qE "cross.tree|cross-tree" "$SKILL_MD" || \
        grep -qE "from an overlay session" "$SKILL_MD"
}

@test "detection: --overlay from core refuses with clear error" {
    grep -qiE "(no overlay.*reach|overlay not reach|standalone.*core.*--overlay)" "$SKILL_MD"
}

@test "detection: rule 1 (flag) appears before rule 2 (overlay markers)" {
    flag_line=$(grep -nE '^1\. \*\*Explicit user flag wins' "$SKILL_MD" | head -1 | cut -d: -f1)
    overlay_line=$(grep -nE '^2\. \*\*Overlay markers' "$SKILL_MD" | head -1 | cut -d: -f1)
    [ -n "$flag_line" ] && [ -n "$overlay_line" ] && [ "$flag_line" -lt "$overlay_line" ]
}

@test "detection: rule 2 (overlay markers) appears before rule 3 (core markers)" {
    overlay_line=$(grep -nE '^2\. \*\*Overlay markers' "$SKILL_MD" | head -1 | cut -d: -f1)
    core_line=$(grep -nE '^3\. \*\*Core markers' "$SKILL_MD" | head -1 | cut -d: -f1)
    [ -n "$overlay_line" ] && [ -n "$core_line" ] && [ "$overlay_line" -lt "$core_line" ]
}

@test "detection: rule 3 (core markers) appears before rule 4 (refuse)" {
    core_line=$(grep -nE '^3\. \*\*Core markers' "$SKILL_MD" | head -1 | cut -d: -f1)
    refuse_line=$(grep -nE '^4\. \*\*No match' "$SKILL_MD" | head -1 | cut -d: -f1)
    [ -n "$core_line" ] && [ -n "$refuse_line" ] && [ "$core_line" -lt "$refuse_line" ]
}

@test "detection: SKILL.md passes lint-agents structural linter" {
    run bash "$BATS_TEST_DIRNAME/../scripts/lint-agents.sh" \
        --skills-dir "$BATS_TEST_DIRNAME/../.claude/skills" \
        --agents-dir "$BATS_TEST_DIRNAME/../.claude/agents"
    [ "$status" -eq 0 ]
}

@test "detection: SKILL.md contains no forbidden leakage tokens" {
    run bash "$BATS_TEST_DIRNAME/../scripts/check-no-leakage.sh" \
        "$BATS_TEST_DIRNAME/../.claude/skills/self-evaluate"
    [ "$status" -eq 0 ]
}
