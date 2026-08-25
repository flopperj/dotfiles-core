#!/usr/bin/env bats
# Contract + data-vs-schema tests for the multi_repo_split metrics event.
#
# The event is emitted by ticket-pickup (Step 3.5) on both the gate path and
# the notice-only path; consumers are agent-stats (mode/gate_choice counts,
# notice-vs-gate false-positive denominator) and swarm-retro's quantitative
# step. The dedicated schema at .claude/evals/schemas/ is the documentation
# and test point; metrics-event.schema.json remains the enforcement point
# (its data.oneOf validates per-event payload shapes), so this file also
# pins the event_type enum there.
#
# The jq structural checker below is copied from tests/workflows-schemas.bats,
# which keeps the checker inline per bats file by design; only the schema
# directory differs (evals/schemas instead of workflows/schemas).
#
# Run with: bats tests/multi-repo-split-event.bats

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCHEMAS_DIR="$CORE_DIR/.claude/evals/schemas"
    export SCHEMAS_DIR
}

EVENT_SCHEMA="multi-repo-split-event.schema.json"

_validate_object() {
    # $1 = schema filename, $2 = candidate object as a JSON string.
    # Exits 0 when the object structurally satisfies the schema, 1 otherwise.
    echo "$2" | jq -e --slurpfile s "$SCHEMAS_DIR/$1" '
        def check($sch):
          . as $d
          | (($sch.required // []) | all(. as $k | $d | has($k)))
          and (
              ($sch.properties // {}) | to_entries
              | all(
                  .key as $k | .value as $ps
                  | if ($d | has($k)) | not then true
                    else ($d[$k]) as $v
                    | (if ($ps | has("enum")) then ($ps.enum | index($v)) != null
                       elif ($ps | has("type")) then
                         (if ($ps.type | type) == "array"
                          then any($ps.type[]; . == ($v | type))
                          else ($v | type) == $ps.type end)
                       else true end)
                    and (if (($v | type) == "object") and ($ps | has("properties"))
                         then ($v | check($ps)) else true end)
                    end
                )
            );
        check($s[0])' > /dev/null
}

_gate_event() {
    # Canonical gate-mode event (placeholder values only).
    cat <<'JSON'
{
  "event_type": "multi_repo_split",
  "agent": "ticket-pickup",
  "project": "my-repo",
  "ticket": "PROJ-1234",
  "data": {
    "mode": "gate",
    "repos_detected": ["my-repo", "other-repo", "legacy-api"],
    "repos_resolved": ["my-repo", "other-repo"],
    "repos_unresolved": ["legacy-api"],
    "gate_choice": "split",
    "subtask_keys": ["PROJ-1235", "PROJ-1236"],
    "proposed_order": ["other-repo", "my-repo"],
    "final_order": ["other-repo", "my-repo"]
  }
}
JSON
}

@test "event schema satisfies the schema contract (draft-07, required matches properties, no \$ref)" {
    local schema="$SCHEMAS_DIR/$EVENT_SCHEMA"
    [ -f "$schema" ]
    run jq -e . "$schema"
    [ "$status" -eq 0 ]
    run jq -e '."$schema" == "http://json-schema.org/draft-07/schema#"' "$schema"
    [ "$status" -eq 0 ]
    run jq -e '(.required | type == "array") and (.required | length > 0)' "$schema"
    [ "$status" -eq 0 ]
    run jq -e '
        [.. | objects
            | select(has("required") and has("properties"))
            | .required - (.properties | keys)
            | select(length > 0)]
        | length == 0' "$schema"
    [ "$status" -eq 0 ]
    run jq -e '[.. | objects | select(has("$ref"))] | length == 0' "$schema"
    [ "$status" -eq 0 ]
}

@test "valid gate-mode event PASSES validation" {
    run _validate_object "$EVENT_SCHEMA" "$(_gate_event)"
    [ "$status" -eq 0 ]
}

@test "valid notice-mode event (null gate_choice, empty arrays) PASSES validation" {
    run _validate_object "$EVENT_SCHEMA" '{
      "event_type": "multi_repo_split",
      "agent": "ticket-pickup",
      "project": "my-repo",
      "ticket": "PROJ-1234",
      "data": {
        "mode": "notice",
        "repos_detected": ["my-repo", "other-repo"],
        "repos_resolved": [],
        "repos_unresolved": ["my-repo", "other-repo"],
        "gate_choice": null,
        "subtask_keys": [],
        "proposed_order": [],
        "final_order": []
      }
    }'
    [ "$status" -eq 0 ]
}

@test "missing mode FAILS validation" {
    run _validate_object "$EVENT_SCHEMA" "$(_gate_event | jq 'del(.data.mode)')"
    [ "$status" -ne 0 ]
}

@test "out-of-enum gate_choice FAILS validation (checker is not vacuous)" {
    run _validate_object "$EVENT_SCHEMA" "$(_gate_event | jq '.data.gate_choice = "merge"')"
    [ "$status" -ne 0 ]
}

@test "missing repos_detected FAILS validation" {
    run _validate_object "$EVENT_SCHEMA" "$(_gate_event | jq 'del(.data.repos_detected)')"
    [ "$status" -ne 0 ]
}

@test "metrics-event.schema.json event_type enum contains multi_repo_split" {
    run jq -e '.properties.event_type.enum | index("multi_repo_split") != null' \
        "$SCHEMAS_DIR/metrics-event.schema.json"
    [ "$status" -eq 0 ]
}
