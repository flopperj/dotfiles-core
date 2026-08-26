#!/usr/bin/env bats
# Format-stability tests for the "Merge order" PR-body section defined in
# .claude/skills/pr-create-from-commits/SKILL.md (step 6.2b).
#
# The canonical fenced example in the SKILL.md is the single home of the
# format: these tests awk-extract the block between the merge-order:v1
# sentinels and parse it with the same line grammar downstream consumers
# (v2 babysit-prs) will use. If the example drifts from the grammar, or the
# sentinels are duplicated/removed, these tests fail.
#
# Run with: bats tests/merge-order-format.bats

load test_helper

SKILL_MD=""
OPEN_SENTINEL='<!-- merge-order:v1 -->'
CLOSE_SENTINEL='<!-- /merge-order:v1 -->'
# Entry grammar: `N. [ ] <repo> — <TICKET-KEY> — <url | this PR | PR pending>`
# Field separators are em-dashes (U+2014) surrounded by single spaces.
ENTRY_REGEX='^[0-9]+\. \[[ x]\] [A-Za-z0-9._-]+ — [A-Z][A-Z0-9]*-[0-9]+ — (https?://[^ ]+|this PR|PR pending)$'

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SKILL_MD="$CORE_DIR/.claude/skills/pr-create-from-commits/SKILL.md"
    export SKILL_MD
}

# Extract the lines strictly between the sentinels (sentinel lines excluded).
_extract_block() {
    awk -v open="$OPEN_SENTINEL" -v close_s="$CLOSE_SENTINEL" '
        index($0, close_s) { f = 0 }
        f { print }
        index($0, open) { f = 1 }
    ' "$SKILL_MD"
}

# Numbered entry lines inside the block (any other line is human prose).
_entry_lines() {
    _extract_block | grep -E '^[0-9]+\.' || true
}

@test "open and close sentinels each appear exactly once in the SKILL.md" {
    open_count="$(grep -cF "$OPEN_SENTINEL" "$SKILL_MD")"
    close_count="$(grep -cF "$CLOSE_SENTINEL" "$SKILL_MD")"
    [ "$open_count" -eq 1 ]
    [ "$close_count" -eq 1 ]
}

@test "extracted block is non-empty and contains numbered entries" {
    block="$(_extract_block)"
    [ -n "$block" ]
    entries="$(_entry_lines)"
    [ -n "$entries" ]
}

@test "every numbered line matches the merge-order entry grammar" {
    entries="$(_entry_lines)"
    [ -n "$entries" ]
    while IFS= read -r line; do
        if ! printf '%s\n' "$line" | grep -qE "$ENTRY_REGEX"; then
            echo "entry line fails grammar: $line" >&2
            return 1
        fi
    done <<< "$entries"
}

@test "entry indices are contiguous 1..N" {
    expected=1
    while IFS= read -r line; do
        idx="${line%%.*}"
        [ "$((10#$idx))" -eq "$expected" ] || {
            echo "expected index $expected, got: $line" >&2
            return 1
        }
        expected=$((expected + 1))
    done <<< "$(_entry_lines)"
    # At least two entries: a merge-order section for a single PR is
    # meaningless, and the canonical example must show real ordering.
    [ "$expected" -ge 3 ]
}

@test "exactly one entry is 'this PR'" {
    count="$(_entry_lines | grep -cE ' — this PR$')"
    [ "$count" -eq 1 ]
}

@test "canonical example carries the mandatory unmerged-provider caveat" {
    # An earlier entry in the example is not `this PR`, so the caveat
    # sentence is mandatory prose inside the block.
    _extract_block | grep -qi 'merge that one first'
}

@test "negative control: malformed line (missing em-dash field) fails the grammar" {
    # Same repo/ticket vocabulary, but only one em-dash separator — a parser
    # that accepted this would be vacuous.
    malformed='1. [ ] omni-agent — PROJ-1235 https://github.com/acme-corp/omni-agent/pull/42'
    run bash -c "printf '%s\n' \"\$1\" | grep -qE \"\$2\"" _ "$malformed" "$ENTRY_REGEX"
    [ "$status" -ne 0 ]
}

@test "negative control: hyphen instead of em-dash fails the grammar" {
    malformed='1. [ ] omni-agent - PROJ-1235 - this PR'
    run bash -c "printf '%s\n' \"\$1\" | grep -qE \"\$2\"" _ "$malformed" "$ENTRY_REGEX"
    [ "$status" -ne 0 ]
}
