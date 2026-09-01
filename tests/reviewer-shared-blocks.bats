#!/usr/bin/env bats
# Structural tests for the shared reviewer contract blocks and their generator.
#
# The four blocks (TONE-CALIBRATION, ANCHOR-CONSTRAINTS, FINDINGS-CRITIQUE,
# VERIFY-THEN-DRAFT) are byte-identical across the two reviewer SKILL.md files
# and are generated from .claude/_shared/reviewer-blocks/ fragments by
# scripts/reviewer-blocks-gen.sh.
#
# bash 3.2 note: assertions are &&-chained into each test's final command, and
# every sed/awk extraction is guarded with a non-empty check so a mistyped
# sentinel cannot produce a vacuous pass.
#
# Run with: bats tests/reviewer-shared-blocks.bats

load 'test_helper'

GEN="$DOTFILES_DIR/scripts/reviewer-blocks-gen.sh"
FRAGMENTS_DIR="$DOTFILES_DIR/.claude/_shared/reviewer-blocks"
RANGER_SKILL="$DOTFILES_DIR/.claude/skills/ranger-reviewer/SKILL.md"
SCOUT_SKILL="$DOTFILES_DIR/.claude/skills/scout-reviewer/SKILL.md"

REVIEWER_BLOCK_KEYS="tone-calibration anchor-constraints findings-critique verify-then-draft"

# Derive the sentinel label from a fragment key: tone-calibration -> TONE-CALIBRATION
_label_for_key() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Extract a sentinel block (inclusive of sentinel lines) from a file.
_extract_block() {
    local file="$1" label="$2"
    sed -n "/<!-- BEGIN ${label} -->/,/<!-- END ${label} -->/p" "$file"
}

# ---------------------------------------------------------------------------
# Test 1: All four fragments exist and are non-empty
# ---------------------------------------------------------------------------
@test "reviewer-block fragments exist and are non-empty" {
    local missing=()
    local key
    for key in $REVIEWER_BLOCK_KEYS; do
        [ -s "$FRAGMENTS_DIR/${key}.md" ] || missing+=("$key")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing or empty fragments: ${missing[*]:-}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 2: Generator script exists and is executable
# ---------------------------------------------------------------------------
@test "reviewer-blocks-gen.sh exists and is executable" {
    [ -f "$GEN" ] && [ -x "$GEN" ]
}

# ---------------------------------------------------------------------------
# Test 3: Generator runs successfully on current repo
# ---------------------------------------------------------------------------
@test "reviewer-blocks-gen.sh runs successfully on current repo" {
    run bash "$GEN"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 4: Generator is idempotent and produces no drift vs. committed state
# ---------------------------------------------------------------------------
@test "reviewer-blocks-gen.sh is idempotent (second run produces no diff)" {
    local before after
    before="$(git -C "$DOTFILES_DIR" diff)"

    bash "$GEN"
    bash "$GEN"

    after="$(git -C "$DOTFILES_DIR" diff)"

    # Second-run stability: gen(gen(x)) == gen(x).
    if [ "$before" != "$after" ]; then
        echo "Second run of reviewer-blocks-gen.sh produced changes:"
        echo "$after"
        return 1
    fi

    # Drift guard from committed state: gen(committed) == committed.
    # Catches a hand-edit of a generated block or a fragment edit without
    # regeneration. Skipped when the tree was already dirty before the test
    # (local WIP); effective on CI's clean checkout.
    if [ -z "$before" ] && [ -n "$after" ]; then
        echo "reviewer-blocks-gen.sh produced changes relative to committed state (drift):"
        echo "$after"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 5: Each block is byte-identical across ranger and scout SKILL.md
# ---------------------------------------------------------------------------
@test "each reviewer block is identical across ranger and scout SKILL.md" {
    local key label r s
    for key in $REVIEWER_BLOCK_KEYS; do
        label="$(_label_for_key "$key")"
        r="$(_extract_block "$RANGER_SKILL" "$label")"
        s="$(_extract_block "$SCOUT_SKILL" "$label")"
        # Non-empty guards are load-bearing: two empty extractions compare equal.
        [ -n "$r" ] && [ -n "$s" ] && [ "$r" = "$s" ] || {
            echo "Block $label empty or differs between ranger and scout"
            diff <(echo "$r") <(echo "$s") || true
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# Test 6: Each spliced block body matches its fragment (modulo directive line)
# ---------------------------------------------------------------------------
@test "each spliced block body matches its fragment" {
    local key label file body fragment
    for key in $REVIEWER_BLOCK_KEYS; do
        label="$(_label_for_key "$key")"
        fragment="$(cat "$FRAGMENTS_DIR/${key}.md" 2>/dev/null)"
        [ -n "$fragment" ] || { echo "Fragment for $key is empty or missing"; return 1; }
        for file in "$RANGER_SKILL" "$SCOUT_SKILL"; do
            # Block body: between the sentinels, minus sentinel lines, minus
            # the leading REVIEWER_BLOCK directive line.
            body="$(_extract_block "$file" "$label" | sed '1d;$d' | sed '/<!-- REVIEWER_BLOCK:/d')"
            [ -n "$body" ] && [ "$body" = "$fragment" ] || {
                echo "Spliced $label body in $file does not match fragment ${key}.md"
                diff <(echo "$body") <(echo "$fragment") || true
                return 1
            }
        done
    done
}

# ---------------------------------------------------------------------------
# Test 7: Each block carries its REVIEWER_BLOCK directive in both SKILL.md files
# ---------------------------------------------------------------------------
@test "each block carries its REVIEWER_BLOCK directive in both SKILL.md files" {
    local key label file block missing=()
    for key in $REVIEWER_BLOCK_KEYS; do
        label="$(_label_for_key "$key")"
        for file in "$RANGER_SKILL" "$SCOUT_SKILL"; do
            block="$(_extract_block "$file" "$label")"
            if [ -z "$block" ] || ! echo "$block" | grep -q "<!-- REVIEWER_BLOCK: ${key} -->"; then
                missing+=("$key in $(basename "$(dirname "$file")")")
            fi
        done
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Blocks missing their REVIEWER_BLOCK directive: ${missing[*]:-}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 8: Generator warns (exit 0) on unknown directive key — hermetic fixture
# ---------------------------------------------------------------------------
@test "reviewer-blocks-gen.sh warns on unknown directive key" {
    local tmp_skills_dir
    tmp_skills_dir="$SCRATCH/skills"
    mkdir -p "$tmp_skills_dir/fixture-reviewer"

    cat > "$tmp_skills_dir/fixture-reviewer/SKILL.md" <<'EOF'
# Fixture reviewer

<!-- BEGIN NONEXISTENT-KEY -->
<!-- REVIEWER_BLOCK: nonexistent-key -->
<!-- END NONEXISTENT-KEY -->
EOF

    local stderr_out
    stderr_out="$(bash "$GEN" --skills-dir "$tmp_skills_dir" 2>&1 >/dev/null)" || true

    if ! echo "$stderr_out" | grep -q "WARNING"; then
        echo "Generator did not emit WARNING for unknown key. stderr was:"
        echo "$stderr_out"
        return 1
    fi

    run bash "$GEN" --skills-dir "$tmp_skills_dir"
    [ "$status" -eq 0 ]
}
