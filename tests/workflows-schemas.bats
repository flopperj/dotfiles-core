#!/usr/bin/env bats
# Contract tests for the typed handoff schemas in .claude/workflows/schemas/.
#
# These four files are REAL JSON Schema draft-07 (unlike babysit-prs's
# state-schema.json, which is deliberately an example document) because
# they are consumed by agent()'s `schema` option, which requires draft-07.
# They stay BASIC — type/required/properties/items/enum only — since $ref
# and advanced features are unverified against agent() and a silently
# ignored $ref is a contract that enforces nothing.
#
# Per schema, four invariants:
#   1. parses as JSON (jq -e)
#   2. declares $schema as draft-07
#   3. has a non-empty top-level `required` array
#   4. every `required` entry appears in `properties` — checked recursively
#      on every object that carries both keys, so nested item schemas
#      (e.g. optimus-to-cyrus steps items) are covered too. This is the
#      check that catches real drift.
#
# Run with: bats tests/workflows-schemas.bats

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCHEMAS_DIR="$CORE_DIR/.claude/workflows/schemas"
    export SCHEMAS_DIR
}

# All four handoff contracts. Kept in one place so adding a schema means
# adding it here once.
SCHEMA_FILES="auditor-composite.json aristotle-to-optimus.json optimus-to-cyrus.json swarm-context.json"

_assert_schema_contract() {
    # $1 = schema filename
    local schema="$SCHEMAS_DIR/$1"

    [ -f "$schema" ]

    # 1. Parses as JSON.
    run jq -e . "$schema"
    [ "$status" -eq 0 ]

    # 2. Declares draft-07.
    run jq -e '."$schema" == "http://json-schema.org/draft-07/schema#"' "$schema"
    [ "$status" -eq 0 ]

    # 3. Non-empty top-level required.
    run jq -e '(.required | type == "array") and (.required | length > 0)' "$schema"
    [ "$status" -eq 0 ]

    # 4. Every required entry appears in properties — recursively, on every
    #    object that declares both. An empty violation list means no drift.
    run jq -e '
        [.. | objects
            | select(has("required") and has("properties"))
            | .required - (.properties | keys)
            | select(length > 0)]
        | length == 0' "$schema"
    [ "$status" -eq 0 ]
}

@test "schemas directory exists" {
    [ -d "$SCHEMAS_DIR" ]
}

@test "all four handoff schemas are present" {
    local f
    for f in $SCHEMA_FILES; do
        [ -f "$SCHEMAS_DIR/$f" ]
    done
}

@test "auditor-composite.json satisfies the schema contract" {
    _assert_schema_contract "auditor-composite.json"
}

@test "aristotle-to-optimus.json satisfies the schema contract" {
    _assert_schema_contract "aristotle-to-optimus.json"
}

@test "optimus-to-cyrus.json satisfies the schema contract" {
    _assert_schema_contract "optimus-to-cyrus.json"
}

@test "swarm-context.json satisfies the schema contract" {
    _assert_schema_contract "swarm-context.json"
}

# ---------------------------------------------------------------------------
# auditor-composite: the abort contract
# ---------------------------------------------------------------------------
# code-auditor-score.js aborts (2+ dead scorers) by returning nulls for
# composite/band/recommendation, relying on THIS schema to reject that
# object so the caller's prose fallback takes over. If these fields ever
# admit null, an aborted run validates as a real score.

@test "auditor-composite: composite/band/recommendation do not admit null" {
    local schema="$SCHEMAS_DIR/auditor-composite.json"
    # composite is a bare non-null type
    run jq -e '.properties.composite.type == "number"' "$schema"
    [ "$status" -eq 0 ]
    # band and recommendation are enums that do not include null
    run jq -e '.properties.band.enum == ["Low", "Medium", "High"]' "$schema"
    [ "$status" -eq 0 ]
    run jq -e '.properties.recommendation.enum == ["scout", "ranger", "none"]' "$schema"
    [ "$status" -eq 0 ]
}

@test "auditor-composite: individual components admit null (single-scorer degradation)" {
    local schema="$SCHEMAS_DIR/auditor-composite.json"
    local k
    for k in structural impact scope; do
        run jq -e --arg k "$k" \
            '.properties.components.properties[$k].type == ["number", "null"]' "$schema"
        [ "$status" -eq 0 ]
    done
}

@test "no schema uses \$ref (unverified against agent(), stays basic)" {
    local f
    for f in $SCHEMA_FILES; do
        run jq -e '[.. | objects | select(has("$ref"))] | length == 0' "$SCHEMAS_DIR/$f"
        [ "$status" -eq 0 ]
    done
}
