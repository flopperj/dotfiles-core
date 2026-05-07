#!/usr/bin/env bats
# Tests for core plugin install: lib-plugins.sh + install.sh integration.
# RED phase: written before production code exists.
#
# Mock strategy: `claude` is a process-boundary dependency (it shells out to an
# external CLI binary). Mocked because it crosses a process boundary and we must
# not run real plugin installs in CI. `curl` is mocked in the CLI-absent path
# for the same reason (network I/O).

load 'test_helper'

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    mkdir -p "$SCRATCH/home"
    mkdir -p "$SCRATCH/bin"
}

teardown() {
    rm -rf "$SCRATCH"
}

# Plant a `claude` stub that records its arguments to $SCRATCH/claude-calls.log.
# The stub appends one line per invocation: "$@"
_plant_claude_stub() {
    cat > "$SCRATCH/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "${SCRATCH}/claude-calls.log"
exit 0
STUB
    chmod +x "$SCRATCH/bin/claude"
}

# Plant a `curl` stub that exits non-zero (simulates network failure on auto-install).
_plant_curl_fail_stub() {
    cat > "$SCRATCH/bin/curl" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$SCRATCH/bin/curl"
}

# Run install.sh with the scratch claude stub on PATH and isolated $HOME.
_run_install_with_mock_claude() {
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" HOME="$SCRATCH/home" \
        run bash "$CORE_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# 1. plugins.txt exists and contains the expected 2 universal plugins
# ---------------------------------------------------------------------------

@test "core plugins.txt exists at repo root" {
    [ -f "$CORE_DIR/plugins.txt" ]
}

@test "core plugins.txt contains frontend-design@claude-plugins-official" {
    grep -q "^frontend-design@claude-plugins-official$" "$CORE_DIR/plugins.txt"
}

@test "core plugins.txt contains playwright@claude-plugins-official" {
    grep -q "^playwright@claude-plugins-official$" "$CORE_DIR/plugins.txt"
}

@test "core plugins.txt has no company-specific content (no devassist-plugins-registry)" {
    ! grep -q "devassist-plugins-registry" "$CORE_DIR/plugins.txt"
}

# ---------------------------------------------------------------------------
# 2. lib-plugins.sh is loadable and exports _install_cli_and_plugins
# ---------------------------------------------------------------------------

@test "lib-plugins.sh exists at scripts/lib-plugins.sh" {
    [ -f "$CORE_DIR/scripts/lib-plugins.sh" ]
}

@test "_install_cli_and_plugins is declared after sourcing lib-plugins.sh" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    declare -f _install_cli_and_plugins > /dev/null
}

# ---------------------------------------------------------------------------
# 3. install.sh records exactly 2 plugin install calls via mocked claude CLI
# ---------------------------------------------------------------------------

@test "install installs the 2 declared plugins via mocked claude CLI" {
    _plant_claude_stub
    _run_install_with_mock_claude
    [ "$status" -eq 0 ]

    [ -f "$SCRATCH/claude-calls.log" ]
    grep -q "plugin install frontend-design@claude-plugins-official --scope user" "$SCRATCH/claude-calls.log"
    grep -q "plugin install playwright@claude-plugins-official --scope user" "$SCRATCH/claude-calls.log"
    # Exactly 2 invocations.
    [ "$(wc -l < "$SCRATCH/claude-calls.log")" -eq 2 ]
}

@test "install installs frontend-design before playwright (preserves file order)" {
    _plant_claude_stub
    _run_install_with_mock_claude
    [ "$status" -eq 0 ]

    [ -f "$SCRATCH/claude-calls.log" ]
    local line1 line2
    line1="$(sed -n '1p' "$SCRATCH/claude-calls.log")"
    line2="$(sed -n '2p' "$SCRATCH/claude-calls.log")"
    echo "$line1" | grep -q "frontend-design@claude-plugins-official"
    echo "$line2" | grep -q "playwright@claude-plugins-official"
}

# ---------------------------------------------------------------------------
# 4. Idempotency: two install.sh runs produce 4 total invocations (2 per run)
# ---------------------------------------------------------------------------

@test "install is idempotent: running twice records 4 plugin install calls total" {
    _plant_claude_stub
    # First run
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" HOME="$SCRATCH/home" \
        bash "$CORE_DIR/install.sh"
    # Second run (same $HOME — real idempotency path)
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" HOME="$SCRATCH/home" \
        run bash "$CORE_DIR/install.sh"
    [ "$status" -eq 0 ]

    [ -f "$SCRATCH/claude-calls.log" ]
    [ "$(wc -l < "$SCRATCH/claude-calls.log")" -eq 4 ]
}

# ---------------------------------------------------------------------------
# 5. CLI-absent + curl fails: exits 0, emits WARNING, no crash
# ---------------------------------------------------------------------------

@test "install exits 0 when claude CLI absent and curl fails (network error)" {
    # Plant a failing curl stub. Build a PATH that includes system dirs but
    # excludes any dir containing the real `claude` binary, so command -v claude
    # returns non-zero while bash/ln/etc. remain available.
    _plant_curl_fail_stub
    local safe_path="$SCRATCH/bin:/usr/bin:/bin:/opt/homebrew/bin"
    SCRATCH="$SCRATCH" PATH="$safe_path" HOME="$SCRATCH/home" \
        run bash "$CORE_DIR/install.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "WARNING"
}

@test "install does not create claude-calls.log when claude CLI absent" {
    _plant_curl_fail_stub
    local safe_path="$SCRATCH/bin:/usr/bin:/bin:/opt/homebrew/bin"
    SCRATCH="$SCRATCH" PATH="$safe_path" HOME="$SCRATCH/home" \
        run bash "$CORE_DIR/install.sh"
    [ "$status" -eq 0 ]
    # No claude invocations when CLI is missing.
    [ ! -f "$SCRATCH/claude-calls.log" ]
}

# ---------------------------------------------------------------------------
# 6. plugins.txt-absent graceful path: exits 0 and emits "Skipping" message
#
# Uses a scratch copy of the core dir so no live-repo file is ever moved or
# mutated. teardown() cleans up $SCRATCH automatically, making these tests
# safe under SIGKILL / CI timeout.
# ---------------------------------------------------------------------------

@test "install exits 0 and skips plugins when plugins.txt is absent" {
    _plant_claude_stub
    # Build a scratch tree with plugins.txt absent (no file created).
    mkdir -p "$SCRATCH/fake-core/scripts"
    cp "$CORE_DIR/scripts/lib-plugins.sh" "$SCRATCH/fake-core/scripts/lib-plugins.sh"

    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" \
        run _install_cli_and_plugins "$SCRATCH/fake-core"

    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "skipping"
}

@test "install records no plugin calls when plugins.txt is absent" {
    _plant_claude_stub
    mkdir -p "$SCRATCH/fake-core"
    # No plugins.txt in fake-core — absence is the condition under test.

    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" \
        _install_cli_and_plugins "$SCRATCH/fake-core"

    [ ! -f "$SCRATCH/claude-calls.log" ]
}

# ---------------------------------------------------------------------------
# 7. Empty plugins.txt is a no-op: exits 0 and invokes claude zero times
# ---------------------------------------------------------------------------

@test "_install_cli_and_plugins exits 0 and records no calls when plugins.txt is empty" {
    _plant_claude_stub
    mkdir -p "$SCRATCH/empty-plugins"
    # Zero-byte file — no plugins declared.
    : > "$SCRATCH/empty-plugins/plugins.txt"

    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" \
        run _install_cli_and_plugins "$SCRATCH/empty-plugins"

    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/claude-calls.log" ]
}

@test "_install_cli_and_plugins exits 0 and records no calls when plugins.txt has only blank lines and comments" {
    _plant_claude_stub
    mkdir -p "$SCRATCH/comment-only-plugins"
    printf '# this is a comment\n\n# another comment\n\n' \
        > "$SCRATCH/comment-only-plugins/plugins.txt"

    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" \
        run _install_cli_and_plugins "$SCRATCH/comment-only-plugins"

    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/claude-calls.log" ]
}

# ---------------------------------------------------------------------------
# 8. Dual-path precedence: root plugins.txt wins over .claude/plugins.txt
# ---------------------------------------------------------------------------

@test "_install_cli_and_plugins uses root plugins.txt when both root and .claude/plugins.txt exist" {
    _plant_claude_stub
    mkdir -p "$SCRATCH/both-paths/.claude"
    echo "root-plugin@root-registry" > "$SCRATCH/both-paths/plugins.txt"
    echo "dotclaude-plugin@dotclaude-registry" > "$SCRATCH/both-paths/.claude/plugins.txt"

    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" \
        _install_cli_and_plugins "$SCRATCH/both-paths"

    grep -q "plugin install root-plugin@root-registry" "$SCRATCH/claude-calls.log"
    # Exactly one install call recorded — the root plugin, not the .claude one.
    [ "$(wc -l < "$SCRATCH/claude-calls.log")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 9. lib-plugins.sh reads overlay's .claude/plugins.txt when root plugins.txt absent
# ---------------------------------------------------------------------------

@test "_install_cli_and_plugins falls back to .claude/plugins.txt when root plugins.txt absent" {
    _plant_claude_stub
    # Set up a fake overlay dir with only .claude/plugins.txt.
    mkdir -p "$SCRATCH/fake-overlay/.claude"
    echo "some-plugin@some-registry" > "$SCRATCH/fake-overlay/.claude/plugins.txt"

    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-plugins.sh"
    SCRATCH="$SCRATCH" PATH="$SCRATCH/bin:$PATH" \
        _install_cli_and_plugins "$SCRATCH/fake-overlay"

    grep -q "plugin install some-plugin@some-registry --scope user" "$SCRATCH/claude-calls.log"
}
