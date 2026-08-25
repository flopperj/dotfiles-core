#!/usr/bin/env bats
# Tests for .claude/skills/ticket-pickup/scripts/repo-registry.sh
#
# The script is the sole name->path oracle for the "## Repo registry"
# section of the overlay context file. Exit-code contract:
#   0 ok / 1 not found / 2 invalid at resolution time / 3 no registry /
#   4 malformed entry.
#
# Every test pins OVERLAY_CONTEXT_FILE to a heredoc fixture in $SCRATCH —
# never the real ~/.claude/overlay-context.md.
#
# Run with: bats tests/repo-registry.bats

bats_require_minimum_version 1.5.0

load 'test_helper'

REG=""

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH

    REG="$CORE_DIR/.claude/skills/ticket-pickup/scripts/repo-registry.sh"
    export REG

    # Two valid git checkouts to resolve against.
    GOOD_REPO="$SCRATCH/checkouts/omni-agent"
    export GOOD_REPO
    mkdir -p "$GOOD_REPO"
    git -C "$GOOD_REPO" init --quiet

    GOOD_REPO2="$SCRATCH/checkouts/mc-omni-agent-ui"
    export GOOD_REPO2
    mkdir -p "$GOOD_REPO2"
    git -C "$GOOD_REPO2" init --quiet

    # A directory that exists but is not a git repo.
    PLAIN_DIR="$SCRATCH/checkouts/not-a-repo"
    export PLAIN_DIR
    mkdir -p "$PLAIN_DIR"

    CTX="$SCRATCH/overlay-context.md"
    export CTX
    export OVERLAY_CONTEXT_FILE="$CTX"
}

teardown() {
    rm -rf "$SCRATCH"
}

# Write a fixture context file with the given registry body.
_write_registry() {
    cat > "$CTX" <<EOF
# Overlay context

## Some other section

prose that must be ignored

## Repo registry

$1

## Trailing section

- this-looks-like-an-entry: /but/is/outside/the/section
EOF
}

# --- resolve: happy path ---

@test "resolve prints the absolute path and exits 0 for a valid entry" {
    _write_registry "- omni-agent: $GOOD_REPO"
    run bash "$REG" resolve omni-agent
    [ "$status" -eq 0 ]
    [ "$output" = "$GOOD_REPO" ]
}

@test "resolve works for an entry with all optional fields" {
    _write_registry "- mc-omni-agent-ui: $GOOD_REPO2 | components=Omni UI,Editor | prefixes=web/js/,src/ | depends_on=omni-agent
- omni-agent: $GOOD_REPO"
    run bash "$REG" resolve mc-omni-agent-ui
    [ "$status" -eq 0 ]
    [ "$output" = "$GOOD_REPO2" ]
}

# --- resolve: exit 1 (not found) ---

@test "resolve exits 1 for a name not in the registry" {
    _write_registry "- omni-agent: $GOOD_REPO"
    run bash "$REG" resolve no-such-repo
    [ "$status" -eq 1 ]
}

@test "resolve does not match entries outside the registry section" {
    _write_registry "- omni-agent: $GOOD_REPO"
    run bash "$REG" resolve this-looks-like-an-entry
    [ "$status" -eq 1 ]
}

# --- resolve: exit 2 (invalid at resolution time) ---

@test "resolve exits 2 when the registered path does not exist" {
    _write_registry "- gone: $SCRATCH/checkouts/deleted-repo"
    run bash "$REG" resolve gone
    [ "$status" -eq 2 ]
    [[ "$output" == *"path missing"* ]]
}

@test "resolve exits 2 when the path exists but is not a git repo" {
    _write_registry "- plain: $PLAIN_DIR"
    run bash "$REG" resolve plain
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a git repo"* ]]
}

# --- exit 3 (no registry) ---

@test "resolve exits 3 when the context file is absent" {
    export OVERLAY_CONTEXT_FILE="$SCRATCH/does-not-exist.md"
    run bash "$REG" resolve omni-agent
    [ "$status" -eq 3 ]
}

@test "resolve exits 3 when the file exists but has no registry section" {
    cat > "$CTX" <<EOF
# Overlay context

## Some other section

- omni-agent: $GOOD_REPO
EOF
    run bash "$REG" resolve omni-agent
    [ "$status" -eq 3 ]
}

@test "list exits 3 when the context file is absent" {
    export OVERLAY_CONTEXT_FILE="$SCRATCH/does-not-exist.md"
    run bash "$REG" list
    [ "$status" -eq 3 ]
}

# --- exit 4 (malformed entry) ---

@test "relative path exits 4 and the message names the line" {
    _write_registry "- omni-agent: Development/omni-agent"
    run bash "$REG" resolve omni-agent
    [ "$status" -eq 4 ]
    [[ "$output" == *"- omni-agent: Development/omni-agent"* ]]
}

@test "entry line without 'name: path' exits 4 and names the line" {
    _write_registry "- omni-agent has no colon separator"
    run bash "$REG" list
    [ "$status" -eq 4 ]
    [[ "$output" == *"- omni-agent has no colon separator"* ]]
}

# --- list ---

@test "list emits TSV with empty optional fields for a minimal entry" {
    _write_registry "- omni-agent: $GOOD_REPO"
    run bash "$REG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'omni-agent\t%s\t\t\t' "$GOOD_REPO")" ]
}

@test "list round-trips an entry with all optional fields" {
    _write_registry "- mc-omni-agent-ui: $GOOD_REPO2 | components=Omni UI,Editor | prefixes=web/js/,src/ | depends_on=omni-agent
- omni-agent: $GOOD_REPO"
    run bash "$REG" list
    [ "$status" -eq 0 ]
    expected="$(printf 'mc-omni-agent-ui\t%s\tOmni UI,Editor\tweb/js/,src/\tomni-agent\nomni-agent\t%s\t\t\t' "$GOOD_REPO2" "$GOOD_REPO")"
    [ "$output" = "$expected" ]
}

@test "list ignores prose and blank lines inside the section" {
    _write_registry "some human prose

- omni-agent: $GOOD_REPO

more prose"
    run bash "$REG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'omni-agent\t%s\t\t\t' "$GOOD_REPO")" ]
}

@test "list does not validate paths (validation is resolve-time only)" {
    _write_registry "- gone: $SCRATCH/checkouts/deleted-repo"
    run bash "$REG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'gone\t%s\t\t\t' "$SCRATCH/checkouts/deleted-repo")" ]
}

# --- unknown keys ---

@test "unknown key warns on stderr but the command succeeds" {
    _write_registry "- omni-agent: $GOOD_REPO | flavor=vanilla"
    run --separate-stderr bash "$REG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'omni-agent\t%s\t\t\t' "$GOOD_REPO")" ]
    [[ "$stderr" == *"flavor"* ]]
}

@test "unknown key does not break resolve" {
    _write_registry "- omni-agent: $GOOD_REPO | flavor=vanilla"
    run --separate-stderr bash "$REG" resolve omni-agent
    [ "$status" -eq 0 ]
    [ "$output" = "$GOOD_REPO" ]
    [[ "$stderr" == *"flavor"* ]]
}
