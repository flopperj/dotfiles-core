#!/usr/bin/env bats
# Deterministic structural linter tests for agent/skill prompt files.
# Tests drive the development of scripts/lint-agents.sh (TDD Item B).
# Run with: bats tests/agents.bats

load 'test_helper'

LINTER="$DOTFILES_DIR/scripts/lint-agents.sh"
AGENTS_DIR="$DOTFILES_DIR/.claude/agents"
SKILLS_DIR="$DOTFILES_DIR/.claude/skills"

# ---------------------------------------------------------------------------
# Test 1: Linter exists and is executable
# ---------------------------------------------------------------------------
@test "lint-agents.sh exists and is executable" {
    [ -f "$LINTER" ]
    [ -x "$LINTER" ] || bash -n "$LINTER"
}

# ---------------------------------------------------------------------------
# Test 2: Linter passes on current (known-good) agent and skill files
# ---------------------------------------------------------------------------
@test "lint-agents.sh passes on current agent and skill files" {
    run bash "$LINTER"
    if [ "$status" -ne 0 ]; then
        echo "Linter failed on known-good files:"
        echo "$output"
    fi
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 3: Linter catches missing Role Guard in agent file
# ---------------------------------------------------------------------------
@test "lint-agents.sh catches missing Role Guard in agent file" {
    # Copy a real agent file to tmp, remove the Role Guard section
    local tmp_agents_dir
    tmp_agents_dir="$(mktemp -d)"
    cp "$AGENTS_DIR/optimus-planner.md" "$tmp_agents_dir/optimus-planner.md"

    # Remove the ## Role Guard line
    grep -v "## Role Guard" "$tmp_agents_dir/optimus-planner.md" \
        > "$tmp_agents_dir/optimus-planner.md.tmp" \
        && mv "$tmp_agents_dir/optimus-planner.md.tmp" "$tmp_agents_dir/optimus-planner.md"

    run bash "$LINTER" --agents-dir "$tmp_agents_dir" --skills-dir "$SKILLS_DIR"
    rm -rf "$tmp_agents_dir"

    if [ "$status" -eq 0 ]; then
        echo "Expected linter to fail on missing Role Guard, but it passed"
        echo "$output"
    fi
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Role Guard" ]] || [[ "$output" =~ "FAIL" ]]
}

# ---------------------------------------------------------------------------
# Test 4: Linter catches missing YAML frontmatter in skill file
# ---------------------------------------------------------------------------
@test "lint-agents.sh catches missing YAML frontmatter in skill file" {
    local tmp_skills_dir tmp_skill_dir
    tmp_skills_dir="$(mktemp -d)"
    tmp_skill_dir="$tmp_skills_dir/optimus-planner"
    mkdir -p "$tmp_skill_dir"
    cp "$SKILLS_DIR/optimus-planner/SKILL.md" "$tmp_skill_dir/SKILL.md"

    # Remove YAML frontmatter by stripping lines 1 through the closing --- marker
    awk 'NR==1{next} /^---$/{if(!past_first){past_first=1;next}} past_first{print}' \
        "$tmp_skill_dir/SKILL.md" > "$tmp_skill_dir/SKILL.md.tmp" \
        && mv "$tmp_skill_dir/SKILL.md.tmp" "$tmp_skill_dir/SKILL.md"

    run bash "$LINTER" --agents-dir "$AGENTS_DIR" --skills-dir "$tmp_skills_dir"
    rm -rf "$tmp_skills_dir"

    if [ "$status" -eq 0 ]; then
        echo "Expected linter to fail on missing frontmatter, but it passed"
        echo "$output"
    fi
    [ "$status" -ne 0 ]
    [[ "$output" =~ "frontmatter" ]] || [[ "$output" =~ "FAIL" ]]
}

# ---------------------------------------------------------------------------
# Test 5: Linter catches missing boundary sentinels in skill file
# ---------------------------------------------------------------------------
@test "lint-agents.sh catches missing boundary sentinels in skill file" {
    local tmp_skills_dir tmp_skill_dir
    tmp_skills_dir="$(mktemp -d)"
    tmp_skill_dir="$tmp_skills_dir/optimus-planner"
    mkdir -p "$tmp_skill_dir"
    cp "$SKILLS_DIR/optimus-planner/SKILL.md" "$tmp_skill_dir/SKILL.md"

    # Remove the BEGIN sentinel line
    grep -v "BEGIN RESPONSIBILITY BOUNDARIES" "$tmp_skill_dir/SKILL.md" \
        > "$tmp_skill_dir/SKILL.md.tmp" \
        && mv "$tmp_skill_dir/SKILL.md.tmp" "$tmp_skill_dir/SKILL.md"

    run bash "$LINTER" --agents-dir "$AGENTS_DIR" --skills-dir "$tmp_skills_dir"
    rm -rf "$tmp_skills_dir"

    if [ "$status" -eq 0 ]; then
        echo "Expected linter to fail on missing boundary sentinel, but it passed"
        echo "$output"
    fi
    [ "$status" -ne 0 ]
    [[ "$output" =~ "sentinel" ]] || [[ "$output" =~ "FAIL" ]] || [[ "$output" =~ "RESPONSIBILITY BOUNDARIES" ]]
}

# ---------------------------------------------------------------------------
# Test 6: Linter catches missing skill cross-reference in agent file
# ---------------------------------------------------------------------------
@test "lint-agents.sh catches missing skill cross-reference in agent file" {
    local tmp_agents_dir
    tmp_agents_dir="$(mktemp -d)"
    cp "$AGENTS_DIR/optimus-planner.md" "$tmp_agents_dir/optimus-planner.md"

    # Remove the > **Skill**: line
    grep -v '\*\*Skill\*\*:' "$tmp_agents_dir/optimus-planner.md" \
        > "$tmp_agents_dir/optimus-planner.md.tmp" \
        && mv "$tmp_agents_dir/optimus-planner.md.tmp" "$tmp_agents_dir/optimus-planner.md"

    run bash "$LINTER" --agents-dir "$tmp_agents_dir" --skills-dir "$SKILLS_DIR"
    rm -rf "$tmp_agents_dir"

    if [ "$status" -eq 0 ]; then
        echo "Expected linter to fail on missing skill cross-reference, but it passed"
        echo "$output"
    fi
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Skill" ]] || [[ "$output" =~ "cross-reference" ]] || [[ "$output" =~ "FAIL" ]]
}

# ---------------------------------------------------------------------------
# Test 7: Linter output format shows PASS/FAIL per check
# ---------------------------------------------------------------------------
@test "lint-agents.sh output contains PASS or FAIL markers" {
    run bash "$LINTER"
    [[ "$output" =~ "PASS" ]] || [[ "$output" =~ "FAIL" ]]
}

# ---------------------------------------------------------------------------
# Test 8: DoD.md exists (linked or regular file) in dotfiles .claude directory
# ---------------------------------------------------------------------------
@test "DoD.md exists in dotfiles .claude directory" {
    # DoD.md lives only in the overlay; skip in dotfiles-core.
    [ -f "$DOTFILES_DIR/.claude/DoD.md" ] || skip "DoD.md not present in dotfiles-core (overlay-only)"
}

# ---------------------------------------------------------------------------
# Test 9: review-context skill has required frontmatter fields
# ---------------------------------------------------------------------------
@test "review-context skill has required frontmatter fields" {
    local skill_file="$SKILLS_DIR/review-context/SKILL.md"
    [ -f "$skill_file" ]
    grep -q "^name: review-context" "$skill_file"
    grep -q "^user-invocable: true" "$skill_file"
    grep -q "review-context" "$skill_file"
}

# ---------------------------------------------------------------------------
# Test 10: review-context skill storage rule forbids writing inside working repo
# ---------------------------------------------------------------------------
@test "review-context skill documents storage outside working repo" {
    local skill_file="$SKILLS_DIR/review-context/SKILL.md"
    grep -q '~/.claude/review-context' "$skill_file"
    grep -q 'MUST' "$skill_file"
    # Storage rule must assert the correct path prefix
    grep -q '~/.claude/review-context/<project>/llms.txt' "$skill_file"
    # No instruction to write inside the working repo
    ! grep -q 'write.*\./llms\.txt\|write.*\.claude/review-context\.md' "$skill_file"
}

# ---------------------------------------------------------------------------
# Test 11: AGENTS.md exists in dotfiles .claude directory (editor-agnostic core)
# ---------------------------------------------------------------------------
@test "AGENTS.md exists in dotfiles .claude directory" {
    # In dotfiles-core the rendered file is AGENTS.md.generated; the live
    # AGENTS.md lives in the overlay.  Accept either form.
    [ -f "$DOTFILES_DIR/.claude/AGENTS.md" ] || \
        [ -f "$DOTFILES_DIR/.claude/AGENTS.md.generated" ] || \
        { echo "Neither AGENTS.md nor AGENTS.md.generated found"; return 1; }
}

# ---------------------------------------------------------------------------
# Test 12: CLAUDE.md points to AGENTS.md as the canonical source
# ---------------------------------------------------------------------------
@test "CLAUDE.md cites AGENTS.md as canonical source" {
    # In dotfiles-core the live CLAUDE.md is CLAUDE.md.generated; both forms
    # are accepted here.
    local claude_md
    if [ -f "$DOTFILES_DIR/.claude/CLAUDE.md" ]; then
        claude_md="$DOTFILES_DIR/.claude/CLAUDE.md"
    elif [ -f "$DOTFILES_DIR/.claude/CLAUDE.md.generated" ]; then
        claude_md="$DOTFILES_DIR/.claude/CLAUDE.md.generated"
    else
        echo "Neither CLAUDE.md nor CLAUDE.md.generated found"; return 1
    fi
    grep -q 'AGENTS.md' "$claude_md"
}

# ---------------------------------------------------------------------------
# Test 13: Cursor rules pointer exists and references AGENTS.md
# ---------------------------------------------------------------------------
@test "Cursor rules index.mdc exists and references AGENTS.md" {
    local rule_file="$DOTFILES_DIR/.cursor/rules/index.mdc"
    # .cursor rules live only in the overlay; skip in dotfiles-core.
    [ -f "$rule_file" ] || skip ".cursor/rules/index.mdc not present in dotfiles-core (overlay-only)"
    grep -q 'AGENTS.md' "$rule_file"
}

# ---------------------------------------------------------------------------
# Test 14: checklist-v1 soft check warns (does NOT fail) on missing headings
# ---------------------------------------------------------------------------
# Skills opt in to the checklist-v1 shape via "<!-- shape: checklist-v1 -->".
# A marked skill missing the canonical headings must produce WARN output
# without flipping the linter's exit code — preserves the gradual-rollout invariant.
@test "checklist-v1 soft check emits WARN, not FAIL, on missing headings" {
    local tmp_skills_dir
    tmp_skills_dir="$(mktemp -d)"
    local fake_skill="$tmp_skills_dir/fake-checklist-skill"
    mkdir -p "$fake_skill"

    cat > "$fake_skill/SKILL.md" <<'EOF'
---
name: fake-checklist-skill
description: A skill that opts into checklist-v1 but is missing the headings
user-invocable: true
---

<!-- shape: checklist-v1 -->

# Fake Skill

Body without any of the six required headings.
EOF

    run bash "$LINTER" --agents-dir "$AGENTS_DIR" --skills-dir "$tmp_skills_dir"
    rm -rf "$tmp_skills_dir"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "checklist-v1: ## When to Use" ]]
}

# ---------------------------------------------------------------------------
# Test 15: pr-create-from-commits documents the 100-byte min-body check
# ---------------------------------------------------------------------------
# Phase 2 enhancement: PR bodies must be >= 100 bytes and contain at
# least one of Summary/Why/Motivation/Context/Overview headings before
# `gh pr create` fires. Lock the documentation so future edits don't drop it.
# (Threshold is bytes via `wc -c` for cross-platform consistency, not Unicode
# codepoints — thin English bodies are the failure mode this check prevents.)
@test "pr-create-from-commits documents 100-byte min-body validation" {
    local skill_file="$SKILLS_DIR/pr-create-from-commits/SKILL.md"
    [ -f "$skill_file" ]
    grep -q '100 bytes' "$skill_file"
    grep -q -i 'Summary\|Why\|Motivation\|Context\|Overview' "$skill_file"
    grep -q 'skip_body_validation' "$skill_file"
}

# ---------------------------------------------------------------------------
# Test 16: optimus-planner adopts YYYY-MM-DD-<slug>.md plan filename convention
# ---------------------------------------------------------------------------
# Phase 2: new plans use a date prefix for chronological sort. Legacy plans
# (without prefix) must still resolve via the detection glob. Lock both halves
# of the convention so future edits don't drop one.
@test "optimus-planner documents date-prefixed plan filename convention" {
    local skill_file="$SKILLS_DIR/optimus-planner/SKILL.md"
    [ -f "$skill_file" ]
    grep -q 'YYYY-MM-DD-<slug>' "$skill_file"
    grep -q -i 'legacy' "$skill_file"
    # Detection glob must mention matching both forms (forward-compat AND backwards-compat)
    grep -q '\*<ticket-or-slug>' "$skill_file"
}
