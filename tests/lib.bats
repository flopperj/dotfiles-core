#!/usr/bin/env bats
# Unit tests for scripts/_lib.sh shared library functions.
# Run with: bats tests/lib.bats
# Or via:   make test-agents (after adding lib.bats to the recipe)

load 'test_helper'

# ---------------------------------------------------------------------------
# _replace_between_sentinels: missing END sentinel aborts without data loss
# ---------------------------------------------------------------------------
@test "_replace_between_sentinels aborts and preserves file when END sentinel is missing" {
    # Arrange: fixture file with BEGIN but no END sentinel
    local fixture
    fixture="$(mktemp)"
    cat > "$fixture" <<'EOF'
line 1
<!-- BEGIN ROLE GUARD -->
old content
(no END sentinel here)
line 5
line 6
EOF
    # Capture original bytes for byte-identical comparison later
    local original_content
    original_content="$(cat "$fixture")"

    # Arrange: replacement content
    local replacement
    replacement="$(mktemp)"
    printf 'new content\n' > "$replacement"

    # Act: source the lib and call the function directly in a subshell.
    # Using a wrapper script avoids quoting/expansion issues in bash -c.
    local wrapper
    wrapper="$(mktemp)"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
source "$DOTFILES_DIR/scripts/_lib.sh"
_replace_between_sentinels "$fixture" "ROLE GUARD" "ROLE GUARD" "$replacement"
EOF
    chmod +x "$wrapper"
    run bash "$wrapper"
    rm -f "$wrapper"

    # Assert: function must exit non-zero
    if [ "$status" -eq 0 ]; then
        echo "Expected non-zero exit but got 0 — missing END sentinel was not detected"
        rm -f "$fixture" "$replacement"
        return 1
    fi

    # Assert: original file must be byte-identical to pre-call state
    local after_content
    after_content="$(cat "$fixture")"
    if [ "$original_content" != "$after_content" ]; then
        echo "File was modified despite missing END sentinel:"
        diff <(echo "$original_content") <(echo "$after_content")
        rm -f "$fixture" "$replacement"
        return 1
    fi

    rm -f "$fixture" "$replacement"
}

# ---------------------------------------------------------------------------
# _replace_between_sentinels: happy path still works (regression guard)
# ---------------------------------------------------------------------------
@test "_replace_between_sentinels replaces content when both sentinels are present" {
    # Arrange: well-formed fixture with both sentinels
    local fixture
    fixture="$(mktemp)"
    cat > "$fixture" <<'EOF'
line 1
<!-- BEGIN ROLE GUARD -->
old content
<!-- END ROLE GUARD -->
line 5
EOF

    local replacement
    replacement="$(mktemp)"
    printf 'new content\n' > "$replacement"

    # Act
    local wrapper
    wrapper="$(mktemp)"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
source "$DOTFILES_DIR/scripts/_lib.sh"
_replace_between_sentinels "$fixture" "ROLE GUARD" "ROLE GUARD" "$replacement"
EOF
    chmod +x "$wrapper"
    run bash "$wrapper"
    rm -f "$wrapper"

    # Assert: exit 0
    if [ "$status" -ne 0 ]; then
        echo "Expected exit 0 but got $status"
        echo "stderr: $output"
        rm -f "$fixture" "$replacement"
        return 1
    fi

    # Assert: new content is present between sentinels
    local spliced
    spliced="$(awk '/BEGIN ROLE GUARD/,/END ROLE GUARD/' "$fixture")"
    if ! echo "$spliced" | grep -q "new content"; then
        echo "Replacement content not found between sentinels. File contents:"
        cat "$fixture"
        rm -f "$fixture" "$replacement"
        return 1
    fi

    # Assert: old content is gone
    if grep -q "old content" "$fixture"; then
        echo "Old content still present after replacement. File contents:"
        cat "$fixture"
        rm -f "$fixture" "$replacement"
        return 1
    fi

    rm -f "$fixture" "$replacement"
}

# ---------------------------------------------------------------------------
# role-guard-gen.sh: no tempfile leaks on abnormal exit
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh leaves no tempfiles behind when _replace_between_sentinels fails mid-loop" {
    # Strategy: write a wrapper script that puts a mktemp stub on PATH (absolute-path
    # delegation to /usr/bin/mktemp to avoid recursion), then runs role-guard-gen.sh.
    # The wrapper also exports MKTEMP_MANIFEST so the stub can record created paths.
    # After the generator exits non-zero, we verify every recorded path is gone.
    #
    # Everything is done in a single `run bash wrapper.sh` call to minimize forks.

    local work_dir
    work_dir="$(mktemp -d)"

    local manifest="$work_dir/manifest.txt"
    local stub_bin="$work_dir/bin"
    local fragments_dir="$work_dir/fragments"
    local agents_dir="$work_dir/agents"

    mkdir -p "$stub_bin" "$fragments_dir" "$agents_dir"

    # mktemp stub: absolute path delegation avoids infinite recursion
    cat > "$stub_bin/mktemp" <<'STUB'
#!/usr/bin/env bash
real_path="$(/usr/bin/mktemp "$@")"
echo "$real_path" >> "$MKTEMP_MANIFEST"
echo "$real_path"
STUB
    chmod +x "$stub_bin/mktemp"

    printf 'fragment content\n' > "$fragments_dir/mykey.md"

    # Agent file: BEGIN ROLE GUARD present (grep -rl matches), but END is absent.
    # The generator enters the loop and calls mktemp for tmp_content, then
    # _replace_between_sentinels fails (no END in awk output) → set -e exits.
    cat > "$agents_dir/broken-agent.md" <<'EOF'
<!-- BEGIN ROLE GUARD -->
<!-- ROLE_GUARD: mykey -->
(no END sentinel)
EOF

    # Wrapper sets up PATH and MKTEMP_MANIFEST, then runs the real generator.
    # Using a file-based wrapper (not `run env ...`) keeps the bats process
    # leaner and avoids extra forks in the test runner.
    local wrapper="$work_dir/run.sh"
    cat > "$wrapper" <<WRAPPER
#!/usr/bin/env bash
export PATH="$stub_bin:/usr/bin:/bin"
export MKTEMP_MANIFEST="$manifest"
bash "$DOTFILES_DIR/scripts/role-guard-gen.sh" \
    --agents-dir "$agents_dir" \
    --fragments-dir "$fragments_dir"
WRAPPER
    chmod +x "$wrapper"

    # Act
    run bash "$wrapper"

    # Assert: generator exited non-zero (missing END sentinel causes failure)
    if [ "$status" -eq 0 ]; then
        echo "Expected non-zero exit when END sentinel is missing, got $status"
        rm -rf "$work_dir"
        return 1
    fi

    # Assert: manifest must exist — confirms mktemp was called (leak path ran)
    if [ ! -f "$manifest" ]; then
        echo "mktemp was never called — the leak path was not exercised"
        rm -rf "$work_dir"
        return 1
    fi

    # Assert: every recorded tempfile has been cleaned up (EXIT trap fired)
    local leaked=0
    while IFS= read -r tmpfile; do
        if [ -f "$tmpfile" ]; then
            echo "Leaked tempfile still exists: $tmpfile"
            leaked=$((leaked + 1))
        fi
    done < "$manifest"

    rm -rf "$work_dir"

    if [ "$leaked" -ne 0 ]; then
        return 1
    fi
}
