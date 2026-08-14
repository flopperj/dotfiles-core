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

# ---------------------------------------------------------------------------
# Data-vs-schema validation
# ---------------------------------------------------------------------------
# The tests above only inspect the schemas' declaration text; these validate
# real candidate objects against a schema so the abort contract is proven by
# behavior, not by reading the declaration. Core has no JSON Schema validator
# and no node dependency, so this is a minimal jq structural check scoped to
# the basic subset these schemas restrict themselves to: required presence,
# type / type-array matching (null only passes where declared), enum
# membership, and one level of recursion into object properties.

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

@test "auditor-composite: the abort object FAILS validation (prose fallback engages)" {
    # Exactly what code-auditor-score.js returns on a 2+ dead-scorer abort.
    run _validate_object "auditor-composite.json" \
        '{"composite":null,"band":null,"recommendation":null,"components":{"structural":null,"impact":null,"scope":null},"degraded":true}'
    [ "$status" -ne 0 ]
}

@test "auditor-composite: a valid composite object PASSES validation" {
    run _validate_object "auditor-composite.json" \
        '{"composite":55,"band":"Medium","recommendation":"scout","components":{"structural":50,"impact":60,"scope":55},"degraded":false}'
    [ "$status" -eq 0 ]
}

@test "auditor-composite: degraded-but-valid object (one null component) PASSES validation" {
    run _validate_object "auditor-composite.json" \
        '{"composite":60,"band":"Medium","recommendation":"ranger","components":{"structural":null,"impact":60,"scope":55},"degraded":true}'
    [ "$status" -eq 0 ]
}

@test "auditor-composite: missing required field FAILS validation (checker is not vacuous)" {
    run _validate_object "auditor-composite.json" \
        '{"composite":55,"band":"Medium","recommendation":"scout","degraded":false}'
    [ "$status" -ne 0 ]
}

@test "auditor-composite: out-of-enum band FAILS validation (checker is not vacuous)" {
    run _validate_object "auditor-composite.json" \
        '{"composite":55,"band":"Extreme","recommendation":"scout","components":{"structural":50,"impact":60,"scope":55},"degraded":false}'
    [ "$status" -ne 0 ]
}
