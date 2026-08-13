#!/usr/bin/env bats
# Integration tests for .claude/evals/scripts/emit-metric.sh
#
# emit-metric.sh appends structured metrics events to
# ~/.claude/tasks/<project>/metrics.jsonl. Its contract is fail-OPEN:
# a pipeline must never block on a metric write. With jq present it
# validates required fields and injects a timestamp; with jq absent it
# warns on stderr and appends unvalidated.
#
# Tests run the real script against a real temp filesystem — no mocking.
# jq absence is simulated by running under a PATH that excludes jq.
#
# Run with: bats tests/metrics-emit.bats

setup() {
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    EMIT="$DOTFILES_DIR/.claude/evals/scripts/emit-metric.sh"
    export EMIT

    # Isolate HOME so metrics writes land in a scratch tree, never the real
    # ~/.claude. Mirrors the HOME-isolation guard in babysit-state.bats.
    ORIG_HOME="$HOME"
    export ORIG_HOME
    TEST_HOME="$(mktemp -d)"
    export TEST_HOME
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi

    # Run from a non-git directory so the project name resolves from $PWD
    # basename deterministically ("proj"), independent of the checkout.
    PROJ_DIR="$TEST_HOME/proj"
    export PROJ_DIR
    mkdir -p "$PROJ_DIR"
    cd "$PROJ_DIR"

    METRICS_FILE="$HOME/.claude/tasks/proj/metrics.jsonl"
    export METRICS_FILE

    # Minimal PATH dir containing every external tool the script needs
    # EXCEPT jq, to simulate jq absence without uninstalling it.
    NOJQ_PATH="$TEST_HOME/nojq-bin"
    export NOJQ_PATH
    mkdir -p "$NOJQ_PATH"
    local tool
    for tool in bash cat git basename mkdir date; do
        ln -sf "$(command -v "$tool")" "$NOJQ_PATH/$tool"
    done

    VALID_EVENT='{"event_type":"pipeline_complete","agent":"cyrus-tdd-engineer","project":"proj","data":{"tests_passed":true}}'
    export VALID_EVENT
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Script exists
# ---------------------------------------------------------------------------

@test "emit-metric.sh exists" {
    [ -f "$EMIT" ]
}

# ---------------------------------------------------------------------------
# Valid event, jq present
# ---------------------------------------------------------------------------

@test "valid event is appended as one compact line" {
    run bash -c 'echo "$VALID_EVENT" | bash "$EMIT"'
    [ "$status" -eq 0 ]
    [ -f "$METRICS_FILE" ]
    [ "$(wc -l < "$METRICS_FILE" | tr -d ' ')" = "1" ]
    jq -e . "$METRICS_FILE" > /dev/null
}

@test "timestamp is injected when absent" {
    echo "$VALID_EVENT" | bash "$EMIT"
    run jq -r '.timestamp' "$METRICS_FILE"
    [ "$status" -eq 0 ]
    # ISO 8601 UTC shape: YYYY-MM-DDTHH:MM:SSZ
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "explicit timestamp is preserved, not overwritten" {
    echo '{"event_type":"swarm_complete","agent":"ticket-swarm","project":"proj","timestamp":"2020-01-01T00:00:00Z"}' | bash "$EMIT"
    run jq -r '.timestamp' "$METRICS_FILE"
    [ "$output" = "2020-01-01T00:00:00Z" ]
}

# ---------------------------------------------------------------------------
# Validation failures (jq present): exit 1, nothing appended
# ---------------------------------------------------------------------------

@test "missing event_type is rejected with exit 1 and nothing appended" {
    run bash -c 'echo "{\"agent\":\"a\",\"project\":\"p\"}" | bash "$EMIT"'
    [ "$status" -eq 1 ]
    [ ! -s "$METRICS_FILE" ]
}

@test "missing agent is rejected with exit 1" {
    run bash -c 'echo "{\"event_type\":\"pipeline_complete\",\"project\":\"p\"}" | bash "$EMIT"'
    [ "$status" -eq 1 ]
    [ ! -s "$METRICS_FILE" ]
}

@test "malformed JSON is rejected with exit 1 and nothing appended" {
    run bash -c 'echo "not json at all {" | bash "$EMIT"'
    [ "$status" -eq 1 ]
    [ ! -s "$METRICS_FILE" ]
}

@test "empty stdin exits 1 with a clear stderr message" {
    run bash -c 'printf "" | bash "$EMIT"'
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty input"* ]]
}

# ---------------------------------------------------------------------------
# jq absent: the fail-open contract
# ---------------------------------------------------------------------------

@test "jq absent: exit 0, line appended, warning on stderr" {
    run bash -c 'echo "$VALID_EVENT" | PATH="$NOJQ_PATH" bash "$EMIT"'
    [ "$status" -eq 0 ]
    [ -s "$METRICS_FILE" ]
    [[ "$output" == *"jq not found"* ]]
}

@test "jq absent: timestamp still injected without jq" {
    run bash -c 'echo "$VALID_EVENT" | PATH="$NOJQ_PATH" bash "$EMIT"'
    [ "$status" -eq 0 ]
    grep -q '"timestamp":"' "$METRICS_FILE"
}

@test "jq absent: explicit timestamp not duplicated" {
    run bash -c 'echo "{\"timestamp\":\"2020-01-01T00:00:00Z\",\"event_type\":\"x\",\"agent\":\"a\",\"project\":\"p\"}" | PATH="$NOJQ_PATH" bash "$EMIT"'
    [ "$status" -eq 0 ]
    [ "$(grep -c '"timestamp"' "$METRICS_FILE")" = "1" ]
}

# ---------------------------------------------------------------------------
# Sequential emits append
# ---------------------------------------------------------------------------

@test "two sequential emits produce two lines, both valid JSON" {
    echo "$VALID_EVENT" | bash "$EMIT"
    echo '{"event_type":"ticket_classified","agent":"ticket-pickup","project":"proj"}' | bash "$EMIT"
    [ "$(wc -l < "$METRICS_FILE" | tr -d ' ')" = "2" ]
    run jq -e . "$METRICS_FILE"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Schema file migrated alongside the script
# ---------------------------------------------------------------------------

@test "metrics-event.schema.json exists and is draft-07 JSON Schema" {
    local schema="$DOTFILES_DIR/.claude/evals/schemas/metrics-event.schema.json"
    [ -f "$schema" ]
    run jq -r '."$schema"' "$schema"
    [[ "$output" == *"draft-07"* ]]
}

@test "schema pins the four v1 event types" {
    local schema="$DOTFILES_DIR/.claude/evals/schemas/metrics-event.schema.json"
    run jq -r '.properties.event_type.enum | sort | join(",")' "$schema"
    [ "$output" = "agent_truncated,pipeline_complete,swarm_complete,ticket_classified" ]
}

# ---------------------------------------------------------------------------
# Portability: script must run under system bash 3.2
# ---------------------------------------------------------------------------

@test "emit-metric.sh runs under /bin/bash (3.2-safe)" {
    echo "$VALID_EVENT" | /bin/bash "$EMIT"
    [ -s "$METRICS_FILE" ]
}

@test "emit-metric.sh contains no bash-4-only constructs" {
    # Comments may mention the builtins; only non-comment lines are pinned.
    run bash -c 'grep -vE "^[[:space:]]*#" "$EMIT" | grep -E "\bmapfile\b|\breadarray\b|declare -A"'
    [ "$status" -ne 0 ]
}
