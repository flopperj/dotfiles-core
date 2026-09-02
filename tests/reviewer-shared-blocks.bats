#!/usr/bin/env bats
# Structural tests for the shared reviewer contract blocks and their generator.
#
# The four blocks (TONE-CALIBRATION, ANCHOR-CONSTRAINTS, FINDINGS-CRITIQUE,
# VERIFY-THEN-DRAFT) are byte-identical across the two reviewer SKILL.md files
# and are generated from .claude/_shared/reviewer-blocks/ fragments by
# scripts/reviewer-blocks-gen.sh.
#
# Hermeticity: every generator run and every committed-state check happens in
# a scratch clone of HEAD (_make_scratch_repo), never against the real working
# tree. This keeps the drift guard live — a generator run against the real
# repo would silently repair the very drift the guard exists to catch — and
# keeps `make test` from leaving modified SKILL.md files behind. The
# setup_file/teardown_file pair asserts the real tree is byte-identical before
# and after the suite.
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

# setup_file/teardown_file override the test_helper versions: same exports,
# plus a snapshot of the real tree so teardown_file can prove the suite
# mutated nothing. Generator runs happen only in scratch clones (below), so
# this guard should never fire — it exists to keep that invariant tested.
setup_file() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR
    git -C "$DOTFILES_DIR" status --porcelain > "$BATS_FILE_TMPDIR/tree-before" \
        && git -C "$DOTFILES_DIR" diff > "$BATS_FILE_TMPDIR/diff-before"
}

teardown_file() {
    git -C "$DOTFILES_DIR" status --porcelain > "$BATS_FILE_TMPDIR/tree-after" \
        && git -C "$DOTFILES_DIR" diff > "$BATS_FILE_TMPDIR/diff-after" \
        && cmp -s "$BATS_FILE_TMPDIR/tree-before" "$BATS_FILE_TMPDIR/tree-after" \
        && cmp -s "$BATS_FILE_TMPDIR/diff-before" "$BATS_FILE_TMPDIR/diff-after" || {
        echo "reviewer-shared-blocks.bats mutated the real working tree:" >&2
        diff "$BATS_FILE_TMPDIR/tree-before" "$BATS_FILE_TMPDIR/tree-after" >&2 || true
        return 1
    }
}

# Clone the repo's committed state (HEAD) into $SCRATCH so generator runs
# never touch the real working tree. Sets SCRATCH_REPO. The drift guard
# compares generator output against this committed state, so it fires on both
# drift classes: a hand-edit of a generated block, and a fragment edit
# committed without regeneration. Uncommitted local WIP is invisible here by
# design — it is validated once committed (and on CI, HEAD is the checkout).
_make_scratch_repo() {
    SCRATCH_REPO="$SCRATCH/repo"
    git clone --quiet --no-hardlinks "$DOTFILES_DIR" "$SCRATCH_REPO" \
        && [ -f "$SCRATCH_REPO/scripts/reviewer-blocks-gen.sh" ]
}

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
# Test 3: Generator runs successfully on a scratch clone (never the real tree)
# ---------------------------------------------------------------------------
@test "reviewer-blocks-gen.sh runs successfully on a scratch clone" {
    _make_scratch_repo
    run bash "$SCRATCH_REPO/scripts/reviewer-blocks-gen.sh"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 4: Drift guard — gen(committed) == committed — plus idempotence
# ---------------------------------------------------------------------------
@test "reviewer-blocks-gen.sh output matches committed state (drift guard) and is idempotent" {
    _make_scratch_repo

    # Drift guard: regenerating from committed fragments must reproduce the
    # committed SKILL.md files byte-for-byte. A non-empty diff means either a
    # hand-edit of a generated block or a fragment edit without regeneration.
    local drift
    bash "$SCRATCH_REPO/scripts/reviewer-blocks-gen.sh"
    drift="$(git -C "$SCRATCH_REPO" diff)"
    if [ -n "$drift" ]; then
        echo "reviewer-blocks-gen.sh output differs from committed state (drift):"
        echo "$drift"
        echo "Run 'make gen-reviewer-blocks' and commit the result."
        return 1
    fi

    # Second-run stability: gen(gen(x)) == gen(x).
    bash "$SCRATCH_REPO/scripts/reviewer-blocks-gen.sh"
    drift="$(git -C "$SCRATCH_REPO" diff)"
    if [ -n "$drift" ]; then
        echo "Second run of reviewer-blocks-gen.sh produced changes:"
        echo "$drift"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 5: Each block is byte-identical across ranger and scout SKILL.md
# ---------------------------------------------------------------------------
@test "each reviewer block is identical across ranger and scout SKILL.md" {
    # Committed state via scratch clone: the parity check must see the files
    # as committed, never a version freshly repaired by a generator run.
    _make_scratch_repo
    local ranger scout key label r s
    ranger="$SCRATCH_REPO/.claude/skills/ranger-reviewer/SKILL.md"
    scout="$SCRATCH_REPO/.claude/skills/scout-reviewer/SKILL.md"
    for key in $REVIEWER_BLOCK_KEYS; do
        label="$(_label_for_key "$key")"
        r="$(_extract_block "$ranger" "$label")"
        s="$(_extract_block "$scout" "$label")"
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
    # Committed state via scratch clone, same rationale as the parity test:
    # fidelity is checked between committed fragments and committed SKILL.md,
    # so a fragment edit committed without regeneration fails here.
    _make_scratch_repo
    local key label file body fragment
    for key in $REVIEWER_BLOCK_KEYS; do
        label="$(_label_for_key "$key")"
        fragment="$(cat "$SCRATCH_REPO/.claude/_shared/reviewer-blocks/${key}.md" 2>/dev/null)"
        [ -n "$fragment" ] || { echo "Fragment for $key is empty or missing"; return 1; }
        for file in "$SCRATCH_REPO/.claude/skills/ranger-reviewer/SKILL.md" \
                    "$SCRATCH_REPO/.claude/skills/scout-reviewer/SKILL.md"; do
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
