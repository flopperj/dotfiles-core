#!/usr/bin/env bats
# Integration tests for scripts/agent-stats.sh
#
# agent-stats.sh aggregates ~/.claude/tasks/*/metrics.jsonl into a plain-text
# pipeline-health summary. It is read-only and exits 0 on every "nothing to
# report" path (missing jq, missing tasks dir, empty window) — those are
# pinned by agent-stats/SKILL.md's failure-mode table.
#
# Every invocation runs under /bin/bash (3.2.57 on macOS) because core
# targets system bash: the overlay original used `mapfile` (bash 4 only)
# and unguarded "${arr[@]}" under set -u — both regressions are pinned here.
#
# Tests run the real script against real fixture metrics files — no mocking.
#
# Run with: bats tests/agent-stats.bats

setup() {
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    STATS="$DOTFILES_DIR/scripts/agent-stats.sh"
    export STATS

    # Isolate HOME so reads/writes never touch the real ~/.claude. Mirrors
    # the HOME-isolation guard in babysit-state.bats.
    ORIG_HOME="$HOME"
    export ORIG_HOME
    TEST_HOME="$(mktemp -d)"
    export TEST_HOME
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi

    TASKS_DIR="$HOME/.claude/tasks"
    export TASKS_DIR

    # Minimal PATH dir with every external tool the script needs EXCEPT jq,
    # to simulate jq absence without uninstalling it.
    NOJQ_PATH="$TEST_HOME/nojq-bin"
    export NOJQ_PATH
    mkdir -p "$NOJQ_PATH"
    local tool
    for tool in bash date find mktemp rm wc tr awk grep; do
        ln -sf "$(command -v "$tool")" "$NOJQ_PATH/$tool"
    done
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# Write a fixture metrics.jsonl for project $1 with one recent
# pipeline_complete event and one recent ticket_classified event.
_seed_project() {
    local project="$1"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$TASKS_DIR/$project"
    cat > "$TASKS_DIR/$project/metrics.jsonl" <<EOF
{"timestamp":"$now","event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"$project","ticket":"PROJ-1001","data":{"classification":"Medium","first_pass":true,"tests_passed":true,"ci_fix_attempts":0,"duration_seconds":100}}
{"timestamp":"$now","event_type":"ticket_classified","agent":"ticket-pickup","project":"$project","ticket":"PROJ-1001","data":{"classification":"Medium","override":null}}
EOF
}

# Write a fixture metrics.jsonl for project $1 with $2 recent
# pipeline_complete events, each carrying ci_fix_attempts $3 (a raw JSON
# number literal, so "1.5" seeds the float case).
_seed_pipelines() {
    local project="$1" count="$2" ci="$3"
    local now i
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$TASKS_DIR/$project"
    : > "$TASKS_DIR/$project/metrics.jsonl"
    i=0
    while [ "$i" -lt "$count" ]; do
        echo "{\"timestamp\":\"$now\",\"event_type\":\"pipeline_complete\",\"agent\":\"cyrus-tdd-engineer\",\"project\":\"$project\",\"ticket\":\"PROJ-$((1000 + i))\",\"data\":{\"classification\":\"Medium\",\"first_pass\":true,\"tests_passed\":true,\"ci_fix_attempts\":$ci,\"duration_seconds\":100}}" \
            >> "$TASKS_DIR/$project/metrics.jsonl"
        i=$((i + 1))
    done
}

# Write a fixture metrics.jsonl for project $1 with $2 gate-mode
# multi_repo_split events carrying gate_choice $3, and $4 notice-mode events.
_seed_splits() {
    local project="$1" gate_count="$2" choice="$3" notice_count="$4"
    local now i
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$TASKS_DIR/$project"
    : > "$TASKS_DIR/$project/metrics.jsonl"
    i=0
    while [ "$i" -lt "$gate_count" ]; do
        echo "{\"timestamp\":\"$now\",\"event_type\":\"multi_repo_split\",\"agent\":\"ticket-pickup\",\"project\":\"$project\",\"ticket\":\"PROJ-$((2000 + i))\",\"data\":{\"mode\":\"gate\",\"repos_detected\":[\"a\",\"b\"],\"repos_resolved\":[\"a\",\"b\"],\"repos_unresolved\":[],\"gate_choice\":\"$choice\",\"subtask_keys\":[],\"proposed_order\":[\"a\",\"b\"],\"final_order\":[\"a\",\"b\"]}}" \
            >> "$TASKS_DIR/$project/metrics.jsonl"
        i=$((i + 1))
    done
    i=0
    while [ "$i" -lt "$notice_count" ]; do
        echo "{\"timestamp\":\"$now\",\"event_type\":\"multi_repo_split\",\"agent\":\"ticket-pickup\",\"project\":\"$project\",\"ticket\":\"PROJ-$((3000 + i))\",\"data\":{\"mode\":\"notice\",\"repos_detected\":[\"a\",\"b\"],\"repos_resolved\":[],\"repos_unresolved\":[\"a\",\"b\"],\"gate_choice\":null,\"subtask_keys\":[],\"proposed_order\":[],\"final_order\":[]}}" \
            >> "$TASKS_DIR/$project/metrics.jsonl"
        i=$((i + 1))
    done
}

# ---------------------------------------------------------------------------
# Script exists
# ---------------------------------------------------------------------------

@test "agent-stats.sh exists" {
    [ -f "$STATS" ]
}

# ---------------------------------------------------------------------------
# Onboarding and degradation paths (all exit 0 per SKILL.md)
# ---------------------------------------------------------------------------

@test "no ~/.claude/tasks directory: exit 0 with onboarding text" {
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No metrics directory"* ]]
}

@test "jq absent: exit 0 with a one-line warning" {
    mkdir -p "$TASKS_DIR"
    run /bin/bash -c 'PATH="$NOJQ_PATH" /bin/bash "$STATS"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"jq not found"* ]]
}

@test "empty window: exit 0 with 'No events in window.'" {
    mkdir -p "$TASKS_DIR/proj"
    # One event far outside any reasonable window
    echo '{"timestamp":"2000-01-01T00:00:00Z","event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"proj","data":{}}' \
        > "$TASKS_DIR/proj/metrics.jsonl"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No events in window."* ]]
}

@test "tasks dir exists but holds no metrics files: exit 0 (empty-array guard)" {
    # Exercises the empty CANDIDATES array under `set -u` on bash 3.2 —
    # unguarded "${arr[@]}" would abort with 'unbound variable'.
    mkdir -p "$TASKS_DIR"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No events in window."* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "--project filter matching nothing: exit 0, no events" {
    _seed_project "realproj"
    run /bin/bash "$STATS" --project ghost
    [ "$status" -eq 0 ]
    [[ "$output" == *"No events in window."* ]]
}

# ---------------------------------------------------------------------------
# Populated window
# ---------------------------------------------------------------------------

@test "populated window: totals and sections render" {
    _seed_project "proj"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total events: 2"* ]]
    [[ "$output" == *"Pipelines completed:    1"* ]]
    [[ "$output" == *"Tickets classified: 1"* ]]
    [[ "$output" == *"## Health Flags"* ]]
}

@test "missing first_pass derives from tests_passed and ci_fix_attempts" {
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$TASKS_DIR/legacy"
    # Legacy events without a first_pass field: green run derives true,
    # failed-tests run derives false.
    cat > "$TASKS_DIR/legacy/metrics.jsonl" <<EOF
{"timestamp":"$now","event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"legacy","ticket":"PROJ-1","data":{"tests_passed":true,"ci_fix_attempts":0,"duration_seconds":100}}
{"timestamp":"$now","event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"legacy","ticket":"PROJ-2","data":{"tests_passed":false,"ci_fix_attempts":0,"duration_seconds":100}}
{"timestamp":"$now","event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"legacy","ticket":"PROJ-3","data":{"tests_passed":true,"ci_fix_attempts":2,"duration_seconds":100}}
EOF
    run /bin/bash "$STATS" --project legacy
    [ "$status" -eq 0 ] &&
        [[ "$output" == *"First-pass success:     1 / 3"* ]]
}

@test "explicit first_pass false is not overridden by derivation" {
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$TASKS_DIR/explicit"
    cat > "$TASKS_DIR/explicit/metrics.jsonl" <<EOF
{"timestamp":"$now","event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"explicit","ticket":"PROJ-1","data":{"first_pass":false,"tests_passed":true,"ci_fix_attempts":0,"duration_seconds":100}}
EOF
    run /bin/bash "$STATS" --project explicit
    [ "$status" -eq 0 ] &&
        [[ "$output" == *"First-pass success:     0 / 1"* ]]
}

@test "--project filter scopes to one project" {
    _seed_project "alpha"
    _seed_project "beta"
    run /bin/bash "$STATS" --project alpha
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project: alpha"* ]]
    [[ "$output" == *"Total events: 2"* ]]
}

@test "--days parses and appears in the header" {
    _seed_project "proj"
    run /bin/bash "$STATS" --days 7
    [ "$status" -eq 0 ]
    [[ "$output" == *"last 7 days"* ]]
}

@test "unknown argument exits 1 with usage" {
    run /bin/bash "$STATS" --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ---------------------------------------------------------------------------
# Multi-repo splits section
# ---------------------------------------------------------------------------
# agent-stats is a named consumer of the multi_repo_split event (see the
# schema's $comment and metrics-emit/SKILL.md): counts split by data.mode
# ("gate" vs "notice") and by data.gate_choice, plus the notice-vs-gate
# ratio — the detection false-positive denominator.

# Assertions inside each test are &&-chained into a single final command:
# bats on this machine runs under /bin/bash 3.2, where a failing standalone
# [[ ]] mid-test does NOT abort the test — only the last command's status
# counts. Chaining keeps every assertion load-bearing.

@test "no multi_repo_split events: section renders its placeholder" {
    _seed_project "proj"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ] &&
        [[ "$output" == *"## Multi-Repo Splits"* ]] &&
        [[ "$output" == *"No multi_repo_split events yet."* ]]
}

@test "split events: mode counts and notice-vs-gate ratio render" {
    _seed_splits "proj" 3 "split" 1
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ] &&
        [[ "$output" == *"Splits detected:        4"* ]] &&
        [[ "$output" == *"Gate shown:             3"* ]] &&
        [[ "$output" == *"Notice-only:            1"* ]] &&
        [[ "$output" == *"Notice-vs-gate ratio:   1/4 notice (25%)"* ]]
}

@test "split events: gate_choice distribution renders" {
    _seed_splits "proj" 2 "reorder" 0
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ] &&
        [[ "$output" == *"By gate choice:"* ]] &&
        [[ "$output" == *"reorder"* ]] &&
        [[ "$output" == *"2 events"* ]]
}

@test "notice-only split events: no gate-choice block, ratio is 100%" {
    _seed_splits "proj" 0 "" 2
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ] &&
        [[ "$output" == *"Notice-vs-gate ratio:   2/2 notice (100%)"* ]] &&
        [[ "$output" != *"By gate choice:"* ]]
}

# ---------------------------------------------------------------------------
# Health gate: numeric validation (fail closed, not open)
# ---------------------------------------------------------------------------
# CI_TOTAL is jq-derived from event data, so a float ci_fix_attempts sum
# ("7.5") is possible. `[ "$CI_TOTAL" -gt N ]` errors on non-integers, the
# error is swallowed inside the if-condition, and the health flag silently
# vanishes — the gate-fail-open-non-numeric trap. The gate must instead
# surface a visible unparseable-data flag while the script still exits 0.

@test "float ci_fix_attempts sum: unparseable-data flag surfaces, exit 0" {
    _seed_pipelines "proj" 5 "1.5"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unparseable"* ]]
}

@test "float ci_fix_attempts sum does not fire the CI-attempts flag" {
    _seed_pipelines "proj" 5 "1.5"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" != *"exceed pipeline count"* ]]
}

@test "integer ci_fix_attempts exceeding pipeline count fires the CI-attempts flag" {
    _seed_pipelines "proj" 5 "2"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI fix attempts (10) exceed pipeline count (5)"* ]]
    [[ "$output" != *"unparseable"* ]]
}

@test "integer ci_fix_attempts within pipeline count raises neither flag" {
    _seed_pipelines "proj" 5 "0"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" != *"exceed pipeline count"* ]]
    [[ "$output" != *"unparseable"* ]]
}

# ---------------------------------------------------------------------------
# bash 3.2 regression pins (Finding B)
# ---------------------------------------------------------------------------

@test "no 'mapfile: command not found' under /bin/bash" {
    _seed_project "proj"
    run /bin/bash "$STATS"
    [ "$status" -eq 0 ]
    [[ "$output" != *"mapfile"* ]]
}

@test "agent-stats.sh contains no bash-4-only constructs" {
    # Comments may mention the builtins (e.g. to document the 3.2 target);
    # only non-comment lines are pinned.
    run bash -c 'grep -vE "^[[:space:]]*#" "$STATS" | grep -E "\bmapfile\b|\breadarray\b|declare -A"'
    [ "$status" -ne 0 ]
}
