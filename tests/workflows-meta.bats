#!/usr/bin/env bats
# Contract tests for the workflow meta-block checks in scripts/lint-agents.sh
#
# Workflow scripts (.claude/workflows/*.js) are discovered by slash-command
# name, so every file must carry an `export const meta` block with `name`
# and `description` fields, and the name must match the filename stem —
# otherwise the workflow resolves under an unexpected command or not at all.
#
# Static text analysis only: CI has no model access and cannot execute
# workflows. `node --check` runs only when node is installed (node is NOT
# a core dependency); its absence emits a WARN, never a FAIL.
#
# Run with: bats tests/workflows-meta.bats

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    LINT="$CORE_DIR/scripts/lint-agents.sh"
    export LINT

    SCRATCH="$(mktemp -d)"
    export SCRATCH

    # Empty agents/skills dirs isolate the workflow checks from the real
    # repo's agent and skill files.
    mkdir -p "$SCRATCH/agents" "$SCRATCH/skills" "$SCRATCH/workflows"
    WF_DIR="$SCRATCH/workflows"
    export WF_DIR
}

teardown() {
    rm -rf "$SCRATCH"
}

_run_lint() {
    run bash "$LINT" --agents-dir "$SCRATCH/agents" --skills-dir "$SCRATCH/skills" --workflows-dir "$WF_DIR"
}

_write_valid_workflow() {
    # $1 = filename stem
    cat > "$WF_DIR/$1.js" <<EOF
export const meta = {
  name: '$1',
  description: 'Fixture workflow for lint contract tests.',
}

log('fixture body')
EOF
}

# ---------------------------------------------------------------------------
# Flag plumbing
# ---------------------------------------------------------------------------

@test "lint-agents.sh accepts --workflows-dir and exits 0 on an empty dir" {
    _run_lint
    [ "$status" -eq 0 ]
}

@test "lint-agents.sh still rejects unknown flags" {
    run bash "$LINT" --bogus-flag x
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Meta-block contract
# ---------------------------------------------------------------------------

@test "valid workflow passes all meta checks" {
    _write_valid_workflow "sample-flow"
    _run_lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"FAIL"* ]]
}

@test "workflow without export const meta fails" {
    echo "log('no meta here')" > "$WF_DIR/bare.js"
    _run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "workflow meta without name field fails" {
    cat > "$WF_DIR/anon.js" <<'EOF'
export const meta = {
  description: 'Has no name field.',
}
EOF
    _run_lint
    [ "$status" -eq 1 ]
}

@test "workflow meta without description field fails" {
    cat > "$WF_DIR/undescribed.js" <<'EOF'
export const meta = {
  name: 'undescribed',
}
EOF
    _run_lint
    [ "$status" -eq 1 ]
}

@test "workflow whose meta name mismatches the filename stem fails" {
    cat > "$WF_DIR/actual-name.js" <<'EOF'
export const meta = {
  name: 'different-name',
  description: 'Name does not match filename stem.',
}
EOF
    _run_lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# ---------------------------------------------------------------------------
# node --check: conditional, never a hard requirement
# ---------------------------------------------------------------------------

@test "syntax error fails when node is available" {
    if ! command -v node > /dev/null 2>&1; then
        skip "node not installed"
    fi
    cat > "$WF_DIR/broken.js" <<'EOF'
export const meta = {
  name: 'broken',
  description: 'Syntactically broken body.',
}
this is not javascript at all (((
EOF
    _run_lint
    [ "$status" -eq 1 ]
}

@test "node absent: syntax check is skipped with WARN, not FAIL" {
    # Build a PATH containing every tool lint-agents.sh needs except node.
    local stub="$SCRATCH/nonode-bin"
    mkdir -p "$stub"
    local tool
    for tool in bash grep sed head basename dirname cat realpath; do
        ln -sf "$(command -v "$tool")" "$stub/$tool"
    done
    if PATH="$stub" command -v node > /dev/null 2>&1; then
        skip "node still resolvable under restricted PATH"
    fi

    _write_valid_workflow "sample-flow"
    run bash -c 'PATH="$1" bash "$LINT" --agents-dir "$SCRATCH/agents" --skills-dir "$SCRATCH/skills" --workflows-dir "$WF_DIR"' _ "$stub"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" != *"FAIL"* ]]
}

# ---------------------------------------------------------------------------
# Real repo state
# ---------------------------------------------------------------------------

@test "repo .claude/workflows directory exists" {
    [ -d "$CORE_DIR/.claude/workflows" ]
}

@test "lint-agents.sh passes against the real repo" {
    run bash "$LINT"
    [ "$status" -eq 0 ]
}
