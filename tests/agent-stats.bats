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
