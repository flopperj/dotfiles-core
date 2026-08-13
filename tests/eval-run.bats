#!/usr/bin/env bats
# Unit tests for .claude/evals/scripts/eval-run.sh
#
# eval-run.sh scores a predictions file offline against a classifier eval set
# (the answer key). It never invokes an LLM. Contract under test:
#   - per-case PASS/FAIL lines + an accuracy summary, always printed
#   - exit 0 iff accuracy >= --min-accuracy; exit 1 otherwise
#   - --warn-only: same full report, WARN line on a miss, always exit 0
#   - fail-closed numerics: non-numeric --min-accuracy is a hard error;
#     leading-zero values are read base-10, never octal
#   - malformed JSONL records are skipped with a warning and counted
#   - a case with no prediction counts as FAIL, never silently skipped
#
# Tests run the real script against synthetic heredoc fixtures — no mocking.
#
# Run with: bats tests/eval-run.bats

setup() {
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    RUNNER="$DOTFILES_DIR/.claude/evals/scripts/eval-run.sh"
    export RUNNER
    SET_FILE="$DOTFILES_DIR/.claude/evals/sets/classifier-v1.jsonl"
    export SET_FILE

    # Isolate HOME so nothing can leak into the real ~/.claude. The runner is
    # pure (reads only the paths it is given), but the guard mirrors the
    # babysit-state.bats convention used by every eval-layer test.
    ORIG_HOME="$HOME"
    export ORIG_HOME
    TEST_HOME="$(mktemp -d)"
    export TEST_HOME
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi

    FIX="$TEST_HOME/fixtures"
    export FIX
    mkdir -p "$FIX"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# Fixture builder: a 4-case set with inline predictions, 3 correct 1 wrong
# (75% accuracy). Inline `predicted` fields exercise the no---predictions path.
_write_set_75() {
    cat > "$FIX/set75.jsonl" <<'EOF'
{"id":"c1","summary":"s1","description":"d1","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Simple"}
{"id":"c2","summary":"s2","description":"d2","files_touched":3,"expected":"Medium","rationale":"r","source":"authored","predicted":"Medium"}
{"id":"c3","summary":"s3","description":"d3","files_touched":6,"expected":"Complex","rationale":"r","source":"authored","predicted":"Complex"}
{"id":"c4","summary":"s4","description":"d4","files_touched":2,"expected":"Simple","rationale":"r","source":"authored","predicted":"Medium"}
EOF
}

# Fixture builder: 2 cases, 1 correct (50% accuracy).
_write_set_50() {
    cat > "$FIX/set50.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Simple"}
{"id":"c2","summary":"s","description":"d","files_touched":4,"expected":"Medium","rationale":"r","source":"authored","predicted":"Complex"}
EOF
}

# ---------------------------------------------------------------------------
# Script exists and follows the repo script conventions
# ---------------------------------------------------------------------------

@test "eval-run.sh exists" {
    [ -f "$RUNNER" ]
}

@test "eval-run.sh contains no bash-4-only constructs" {
    # Comments may mention the builtins; only non-comment lines are pinned.
    run bash -c 'grep -vE "^[[:space:]]*#" "$RUNNER" | grep -E "\bmapfile\b|\breadarray\b|declare -A"'
    [ "$status" -ne 0 ]
}

@test "eval-run.sh runs under /bin/bash (3.2-safe)" {
    _write_set_75
    run /bin/bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy 50
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Accuracy math and per-case report
# ---------------------------------------------------------------------------

@test "all-correct set scores 100% and passes the default threshold" {
    cat > "$FIX/set.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Simple"}
{"id":"c2","summary":"s","description":"d","files_touched":4,"expected":"Medium","rationale":"r","source":"authored","predicted":"Medium"}
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"accuracy: 100% (2/2)"* ]]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "3-of-4 correct reports 75% with per-case PASS/FAIL lines" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy 50
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS c1"* ]]
    [[ "$output" == *"PASS c2"* ]]
    [[ "$output" == *"PASS c3"* ]]
    [[ "$output" == *"FAIL c4"* ]]
    [[ "$output" == *"expected=Simple predicted=Medium"* ]]
    [[ "$output" == *"accuracy: 75% (3/4)"* ]]
}

# ---------------------------------------------------------------------------
# Threshold gate: exit 0 iff accuracy >= --min-accuracy
# ---------------------------------------------------------------------------

@test "accuracy below threshold exits 1 with RESULT: FAIL" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy 80
    [ "$status" -eq 1 ]
    [[ "$output" == *"RESULT: FAIL"* ]]
    [[ "$output" == *"accuracy: 75% (3/4)"* ]]
}

@test "accuracy exactly at threshold exits 0" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy 75
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "default threshold is 100: any miss fails" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"RESULT: FAIL"* ]]
}

# ---------------------------------------------------------------------------
# Fail-closed numerics
# ---------------------------------------------------------------------------

@test "non-numeric --min-accuracy fails closed with exit 1" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy banana
    [ "$status" -eq 1 ]
    [[ "$output" == *"min-accuracy"* ]]
    [[ "$output" != *"RESULT: PASS"* ]]
}

@test "empty --min-accuracy fails closed with exit 1" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy ""
    [ "$status" -eq 1 ]
    [[ "$output" != *"RESULT: PASS"* ]]
}

@test "non-numeric --min-accuracy fails closed even under --warn-only" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy banana --warn-only
    [ "$status" -eq 1 ]
}

@test "leading-zero --min-accuracy is read base-10, not octal" {
    # 049 is an invalid octal literal (bash would error without 10#) and 49
    # in base-10. A 50%-accurate set must PASS against min 49.
    _write_set_50
    run bash "$RUNNER" --set "$FIX/set50.jsonl" --min-accuracy 049
    [ "$status" -eq 0 ]
    [[ "$output" == *"accuracy: 50% (1/2)"* ]]
    [[ "$output" == *"RESULT: PASS"* ]]
}

# ---------------------------------------------------------------------------
# Set-file error handling (hard errors, even under --warn-only)
# ---------------------------------------------------------------------------

@test "missing --set is a usage error" {
    run bash "$RUNNER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--set"* ]]
}

@test "nonexistent set file exits 1" {
    run bash "$RUNNER" --set "$FIX/nope.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "empty set file exits 1 even under --warn-only" {
    : > "$FIX/empty.jsonl"
    run bash "$RUNNER" --set "$FIX/empty.jsonl" --warn-only
    [ "$status" -eq 1 ]
    [[ "$output" == *"no scorable records"* ]]
}

@test "unknown argument is rejected" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --bogus x
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown argument"* ]]
}

# ---------------------------------------------------------------------------
# Malformed records: skip with a warning, count in the summary
# ---------------------------------------------------------------------------

@test "malformed record is skipped with a warning and counted; valid cases still scored" {
    cat > "$FIX/set.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Simple"}
this is not json {
{"id":"c2","summary":"s","description":"d","files_touched":4,"expected":"Medium","rationale":"r","source":"authored","predicted":"Medium"}
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping malformed set record"* ]]
    [[ "$output" == *"2 scored, 1 malformed skipped"* ]]
    [[ "$output" == *"accuracy: 100% (2/2)"* ]]
}

@test "record missing expected field counts as malformed" {
    cat > "$FIX/set.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"rationale":"r","source":"authored","predicted":"Simple"}
{"id":"c2","summary":"s","description":"d","files_touched":4,"expected":"Medium","rationale":"r","source":"authored","predicted":"Medium"}
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 scored, 1 malformed skipped"* ]]
}

@test "all records malformed exits 1" {
    cat > "$FIX/set.jsonl" <<'EOF'
nope
also nope {
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no scorable records"* ]]
}

# ---------------------------------------------------------------------------
# --warn-only: full report, WARN on miss, always exit 0
# ---------------------------------------------------------------------------

@test "warn-only with a miss exits 0 but still reports the miss and the accuracy" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy 80 --warn-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL c4"* ]]
    [[ "$output" == *"accuracy: 75% (3/4)"* ]]
    [[ "$output" == *"WARN"* ]]
}

@test "warn-only above threshold exits 0 with no WARN line" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --min-accuracy 50 --warn-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
    [[ "$output" != *"WARN"* ]]
}

# ---------------------------------------------------------------------------
# External predictions file
# ---------------------------------------------------------------------------

@test "external predictions file scores against the key by id" {
    cat > "$FIX/set.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored"}
{"id":"c2","summary":"s","description":"d","files_touched":4,"expected":"Medium","rationale":"r","source":"authored"}
{"id":"c3","summary":"s","description":"d","files_touched":6,"expected":"Complex","rationale":"r","source":"authored"}
EOF
    cat > "$FIX/preds.jsonl" <<'EOF'
{"id":"c1","predicted":"Simple"}
{"id":"c2","predicted":"Medium"}
{"id":"c3","predicted":"Medium"}
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl" --predictions "$FIX/preds.jsonl" --min-accuracy 50
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS c1"* ]]
    [[ "$output" == *"FAIL c3"* ]]
    [[ "$output" == *"accuracy: 66% (2/3)"* ]]
}

@test "case with no prediction counts as FAIL, never skipped" {
    cat > "$FIX/set.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored"}
{"id":"c2","summary":"s","description":"d","files_touched":4,"expected":"Medium","rationale":"r","source":"authored"}
EOF
    cat > "$FIX/preds.jsonl" <<'EOF'
{"id":"c1","predicted":"Simple"}
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl" --predictions "$FIX/preds.jsonl" --min-accuracy 50
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL c2 (expected=Medium predicted=(none))"* ]]
    [[ "$output" == *"accuracy: 50% (1/2)"* ]]
}

@test "malformed prediction line is skipped with a warning" {
    cat > "$FIX/set.jsonl" <<'EOF'
{"id":"c1","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored"}
EOF
    cat > "$FIX/preds.jsonl" <<'EOF'
garbage {
{"id":"c1","predicted":"Simple"}
EOF
    run bash "$RUNNER" --set "$FIX/set.jsonl" --predictions "$FIX/preds.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping malformed prediction line"* ]]
    [[ "$output" == *"accuracy: 100% (1/1)"* ]]
}

@test "nonexistent predictions file exits 1" {
    _write_set_75
    run bash "$RUNNER" --set "$FIX/set75.jsonl" --predictions "$FIX/nope.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# The seeded answer key: classifier-v1.jsonl integrity
# ---------------------------------------------------------------------------

@test "classifier-v1.jsonl exists with at least 12 cases" {
    [ -f "$SET_FILE" ]
    [ "$(wc -l < "$SET_FILE" | tr -d ' ')" -ge 12 ]
}

@test "every seeded record is valid JSON with the required fields" {
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '%s' "$line" | jq -e \
            '.id and .summary and .description and (.files_touched | type == "number") and .expected and .rationale and .source' \
            > /dev/null
    done < "$SET_FILE"
}

@test "every seeded expected label is Simple, Medium, or Complex" {
    run bash -c 'jq -r ".expected" "$SET_FILE" | grep -vE "^(Simple|Medium|Complex)$"'
    [ "$status" -ne 0 ]
}

@test "every seeded source is retro, metrics, or authored" {
    run bash -c 'jq -r ".source" "$SET_FILE" | grep -vE "^(retro|metrics|authored)$"'
    [ "$status" -ne 0 ]
}

@test "seeded case ids are unique" {
    local total unique
    total="$(jq -r '.id' "$SET_FILE" | wc -l | tr -d ' ')"
    unique="$(jq -r '.id' "$SET_FILE" | sort -u | wc -l | tr -d ' ')"
    [ "$total" = "$unique" ]
}

@test "seeded cases carry only placeholder PROJ- ticket keys" {
    # Anonymization guard: any ticket-key-shaped token must use the PROJ-
    # placeholder prefix, never a real project key.
    run bash -c 'grep -oE "[A-Z][A-Z]+-[0-9]+" "$SET_FILE" | grep -v "^PROJ-"'
    [ "$status" -ne 0 ]
}

@test "runner scores the seeded set at 100% against its own key" {
    # Self-consistency: a perfect predictions file derived from the key itself
    # must score 100% — proves set and runner agree on ids and labels.
    jq -c '{id: .id, predicted: .expected}' "$SET_FILE" > "$FIX/perfect.jsonl"
    run bash "$RUNNER" --set "$SET_FILE" --predictions "$FIX/perfect.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"accuracy: 100%"* ]]
}

# ---------------------------------------------------------------------------
# --ratchet: mechanical warn-only/blocking flip on the set's case count.
# count < 30 -> warn-only (report + WARN, exit 0); count >= 30 -> blocking.
# The count comes from the set file itself — no human toggle — and an
# indeterminable count is a hard error, never a silent warn-only default.
# ---------------------------------------------------------------------------

# Fixture builder: n records, all correct except the last (one miss), so the
# warn-only and blocking arms produce different exit codes under the default
# 100% threshold.
_write_set_n_with_miss() {
    local n="$1" out="$2" i=1
    : > "$out"
    while [ "$i" -lt "$n" ]; do
        printf '{"id":"r%d","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Simple"}\n' "$i" >> "$out"
        i=$((i + 1))
    done
    printf '{"id":"r%d","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Medium"}\n' "$n" >> "$out"
}

# Fixture builder: n records, all correct.
_write_set_n_all_correct() {
    local n="$1" out="$2" i=1
    : > "$out"
    while [ "$i" -le "$n" ]; do
        printf '{"id":"r%d","summary":"s","description":"d","files_touched":1,"expected":"Simple","rationale":"r","source":"authored","predicted":"Simple"}\n' "$i" >> "$out"
        i=$((i + 1))
    done
}

@test "ratchet: 29-record set with a miss is warn-only — exit 0, WARN, arm + count printed" {
    _write_set_n_with_miss 29 "$FIX/set29.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/set29.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ratchet: 29 cases < 30 -> warn-only"* ]]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"FAIL r29"* ]]
}

@test "ratchet: 30-record set with a miss is blocking — exit 1, arm + count printed" {
    _write_set_n_with_miss 30 "$FIX/set30.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/set30.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ratchet: 30 cases >= 30 -> blocking"* ]]
    [[ "$output" == *"RESULT: FAIL"* ]]
}

@test "ratchet: 31-record set with a miss is blocking — exit 1" {
    _write_set_n_with_miss 31 "$FIX/set31.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/set31.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ratchet: 31 cases >= 30 -> blocking"* ]]
}

@test "ratchet: passing warn-only arm still prints arm + count, no WARN" {
    _write_set_n_all_correct 29 "$FIX/set29ok.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/set29ok.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ratchet: 29 cases < 30 -> warn-only"* ]]
    [[ "$output" == *"RESULT: PASS"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "ratchet: passing blocking arm exits 0 and prints arm + count" {
    _write_set_n_all_correct 30 "$FIX/set30ok.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/set30ok.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ratchet: 30 cases >= 30 -> blocking"* ]]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "ratchet: unreadable set file errors rather than defaulting to warn-only" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "root ignores file modes"
    fi
    _write_set_n_with_miss 29 "$FIX/locked.jsonl"
    chmod 000 "$FIX/locked.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/locked.jsonl"
    chmod 644 "$FIX/locked.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot determine case count"* ]]
    [[ "$output" != *"-> warn-only"* ]]
}

@test "ratchet: empty set still hard-errors (never a silent warn-only pass)" {
    : > "$FIX/empty.jsonl"
    run bash "$RUNNER" --ratchet --set "$FIX/empty.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no scorable records"* ]]
}

@test "ratchet cannot be combined with --warn-only (no human toggle)" {
    _write_set_75
    run bash "$RUNNER" --ratchet --set "$FIX/set75.jsonl" --warn-only
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be combined"* ]]
}

# ---------------------------------------------------------------------------
# make eval: the CI entry point — ratcheted self-check over the committed key
# ---------------------------------------------------------------------------

@test "make eval runs the ratcheted self-check green against the committed key" {
    run make -C "$DOTFILES_DIR" eval
    [ "$status" -eq 0 ]
    [[ "$output" == *"ratchet:"* ]]
    [[ "$output" == *"accuracy: 100%"* ]]
}
