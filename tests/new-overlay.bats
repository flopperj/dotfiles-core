#!/usr/bin/env bats
# Tests for scripts/new-overlay.sh — the deterministic overlay scaffold engine.
#
# RED phase: written before the engine exists.
# All tests use an offline local bare-repo fixture for git submodule add so
# they run without network access.
#
# Hermetic --check note (plan Risk R5): the bare repo fixture contains only a
# marker file, not a real dotfiles-core install.sh. When the scaffolded
# install.sh runs --check it delegates to .claude/dotfiles-core/install.sh
# which does not exist in the bare fixture. That delegation therefore fails.
# For happy-path tests (1,2,5,7) we assert on FILES and GIT STATE that are
# set up BEFORE the --check step; we treat --check non-zero as acceptable in
# this hermetic context. Test 8 exploits this same reality for the
# non-destructive --check-failure case.

load 'test_helper'

ENGINE=""
BARE=""

setup_file() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR
}

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR
    ENGINE="$CORE_DIR/scripts/new-overlay.sh"

    # Create SCRATCH first so we can redirect GIT_CONFIG_GLOBAL into it.
    SCRATCH="$(mktemp -d)"
    export SCRATCH

    # --- Scope git config mutations to this test run ---
    # Point git at a throwaway config file inside SCRATCH instead of mutating
    # the developer's/CI's real global config. SCRATCH is removed in teardown(),
    # so this file dies with it. Export so child git processes (submodule add,
    # etc.) also see the scoped config.
    export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"

    # --- Build an offline bare-repo fixture ---
    # This gives git submodule add a real local repo to fetch from.
    # git 2.38.1+ blocks file:// transport by default; allow it for this
    # hermetic test fixture only (writes to the throwaway config above).
    git config --global protocol.file.allow always

    BARE="$SCRATCH/fake-core.git"
    # -b main pins HEAD to match the push target (HEAD:main below); without it,
    # git uses init.defaultBranch which defaults to "master" on Ubuntu CI,
    # making the bare repo's HEAD point at an empty branch and causing
    # "fatal: unable to checkout submodule" when git submodule add runs.
    git init --bare "$BARE" -q -b main
    local work="$SCRATCH/seed"
    git clone "$BARE" "$work" -q
    echo "core" > "$work/marker"
    git -C "$work" add -A
    git -C "$work" -c user.email="t@t" -c user.name="t" commit -q -m "init"
    git -C "$work" push origin HEAD:main -q
    rm -rf "$work"

    export BARE
}

teardown() {
    rm -rf "$SCRATCH"
}

# ---------------------------------------------------------------------------
# Helper: run the engine targeting $SCRATCH/ov with the bare-repo fixture.
# Accepts extra args. Always uses --core-url $BARE to avoid local-path errors.
# ---------------------------------------------------------------------------
_scaffold() {
    run bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" "$@"
}

# ---------------------------------------------------------------------------
# Test 1 — Skeleton file set exists with expected content after scaffold
# ---------------------------------------------------------------------------

@test "new-overlay: skeleton files exist with .template stripped and dotclaude/ renamed to .claude/" {
    # Run the engine; ignore --check exit status (hermetic bare repo, no real install.sh)
    bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" || true

    [ -f "$SCRATCH/ov/install.sh" ]
    [ -f "$SCRATCH/ov/.gitignore" ]
    [ -f "$SCRATCH/ov/README.md" ]
    [ -f "$SCRATCH/ov/scripts/install-overlay.sh" ]
    [ -f "$SCRATCH/ov/.claude/overlay-fragments.yaml" ]
    [ -f "$SCRATCH/ov/.claude/overlay-context.md" ]
    [ -f "$SCRATCH/ov/.claude/plugins.txt" ]

    # Verify .template suffix was stripped (no .template files in target)
    local template_files
    template_files="$(find "$SCRATCH/ov" -name '*.template' 2>/dev/null | grep -v '.git' || true)"
    [ -z "$template_files" ]

    # Verify dotclaude/ was renamed to .claude/ (not dotclaude/ in target)
    [ ! -d "$SCRATCH/ov/dotclaude" ]
    [ -d "$SCRATCH/ov/.claude" ]

    # Verify {{OVERLAY_NAME}} was substituted with the actual overlay name
    grep -q "testoverlay" "$SCRATCH/ov/README.md"
    run grep -F "{{OVERLAY_NAME}}" "$SCRATCH/ov/README.md"
    [ "$status" -ne 0 ]

    # Verify {{CORE_URL}} was substituted with the bare-repo path and the token
    # is no longer present in the generated file
    grep -q "$BARE" "$SCRATCH/ov/README.md"
    run grep -F "{{CORE_URL}}" "$SCRATCH/ov/README.md"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Test 2 — .claude/overlay-fragments.yaml is valid "fragments: []"
# ---------------------------------------------------------------------------

@test "new-overlay: .claude/overlay-fragments.yaml is a valid empty manifest" {
    bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" || true

    [ -f "$SCRATCH/ov/.claude/overlay-fragments.yaml" ]

    # Content is exactly fragments: []
    local content
    content="$(cat "$SCRATCH/ov/.claude/overlay-fragments.yaml")"
    [ "$content" = "fragments: []" ]

    # apply_manifest treats it as a no-op (exit 0)
    source "$CORE_DIR/scripts/lib-overlays.sh"
    run apply_manifest "$SCRATCH/ov/.claude/overlay-fragments.yaml"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 3 — Refuses a non-empty target without --force
# ---------------------------------------------------------------------------

@test "new-overlay: refuses non-empty target dir without --force (exit non-zero, target untouched)" {
    mkdir -p "$SCRATCH/ov"
    echo "existing" > "$SCRATCH/ov/existing-file.txt"

    run bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE"
    [ "$status" -ne 0 ]

    # Target must be untouched — still just the one file we put there
    [ -f "$SCRATCH/ov/existing-file.txt" ]
    [ ! -f "$SCRATCH/ov/install.sh" ]
}

# ---------------------------------------------------------------------------
# Test 4 — Local-path rejection via the injected-origin testability seam
# ---------------------------------------------------------------------------

@test "new-overlay: _resolve_submodule_url rejects a local path" {
    # Source the engine to get access to the testability seam function.
    # The seam: _resolve_submodule_url <injected_origin> prints the validated URL
    # or errors with non-zero exit.
    source "$ENGINE"

    # Empty string → rejected
    run _resolve_submodule_url ""
    [ "$status" -ne 0 ]

    # Absolute local path → rejected
    run _resolve_submodule_url "/home/user/repos/core"
    [ "$status" -ne 0 ]

    # Relative path → rejected
    run _resolve_submodule_url "./local-core"
    [ "$status" -ne 0 ]

    # file:// scheme → rejected
    run _resolve_submodule_url "file:///home/user/repos/core"
    [ "$status" -ne 0 ]

    # Tilde path → rejected
    run _resolve_submodule_url "~/repos/core"
    [ "$status" -ne 0 ]

    # Existing local dir → rejected (use $SCRATCH which exists)
    run _resolve_submodule_url "$SCRATCH"
    [ "$status" -ne 0 ]

    # A real remote-style URL → accepted
    run _resolve_submodule_url "https://github.com/example/dotfiles-core.git"
    [ "$status" -eq 0 ]
    [ "$output" = "https://github.com/example/dotfiles-core.git" ]
}

# ---------------------------------------------------------------------------
# Test 5 — --core-url override wires the bare fixture into .gitmodules
# ---------------------------------------------------------------------------

@test "new-overlay: --core-url overrides URL and .gitmodules references it" {
    bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" || true

    [ -f "$SCRATCH/ov/.gitmodules" ]
    grep -q "dotfiles-core" "$SCRATCH/ov/.gitmodules"

    # The URL in .gitmodules must contain the BARE path
    grep -q "$BARE" "$SCRATCH/ov/.gitmodules"
}

# ---------------------------------------------------------------------------
# Test 6 — Idempotency: re-run with --force is clean
# ---------------------------------------------------------------------------

@test "new-overlay: --force re-run is idempotent (no duplicate submodule, no error)" {
    # First run
    bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" || true

    # Second run with --force
    run bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" --force
    # Engine should not error due to existing submodule registration
    # (exit 0 OR non-zero only because of --check in hermetic env)
    # We assert skeleton files still exist and no duplicate .gitmodules entries
    [ -f "$SCRATCH/ov/install.sh" ]
    [ -f "$SCRATCH/ov/.claude/overlay-fragments.yaml" ]

    # No duplicate submodule entries in .gitmodules
    local count
    count="$(grep -c 'dotfiles-core' "$SCRATCH/ov/.gitmodules" 2>/dev/null || echo 0)"
    # submodule add writes exactly one [submodule "..."] block; dotfiles-core
    # appears in both the submodule name line and the path line, so 2 mentions.
    [ "$count" -le 2 ]

    # S1: engine must print the skip-note so the user knows the existing
    # submodule URL was retained and --core-url was not applied.
    echo "$output" | grep -q "submodule already registered"
}

# ---------------------------------------------------------------------------
# Test 7 — git init ran, files staged but NOT committed
# ---------------------------------------------------------------------------

@test "new-overlay: git init ran and files are staged but not committed" {
    bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE" || true

    # git repo must exist
    [ -d "$SCRATCH/ov/.git" ]

    # No commits
    local commit_count
    commit_count="$(git -C "$SCRATCH/ov" rev-list --count HEAD 2>/dev/null || echo 0)"
    [ "$commit_count" -eq 0 ]

    # Files are staged (status --short shows entries with leading letter in col 1)
    local staged
    staged="$(git -C "$SCRATCH/ov" status --short 2>/dev/null)"
    [ -n "$staged" ]
}

# ---------------------------------------------------------------------------
# Test 8 — --check failure is non-destructive
# ---------------------------------------------------------------------------
# The hermetic bare-repo fixture intentionally causes --check to fail because
# the submodule lacks a real install.sh. We use this reality directly:
# the engine exits non-zero, but the skeleton must still exist.
#
# NEGATIVE CONTROL: we verify the engine actually exits non-zero in this
# hermetic context; if --check passed unexpectedly, the test would catch it.

@test "new-overlay: --check failure is non-destructive (skeleton survives, engine exits non-zero)" {
    run bash "$ENGINE" "$SCRATCH/ov" "testoverlay" --core-url "$BARE"

    # NEGATIVE CONTROL: engine MUST exit non-zero in hermetic context
    # because the bare fixture has no real install.sh for --check delegation.
    [ "$status" -ne 0 ]

    # Skeleton must still exist (non-destructive)
    [ -f "$SCRATCH/ov/install.sh" ]
    [ -f "$SCRATCH/ov/.claude/overlay-fragments.yaml" ]
    [ -d "$SCRATCH/ov/.git" ]
}

# ---------------------------------------------------------------------------
# Test 9 — B1 regression: overlay names with sed metacharacters are safe
# ---------------------------------------------------------------------------
# Verifies that names containing `/` and `&` (characters that break `sed s///`)
# are substituted literally into the generated README without aborting the
# engine.  Uses a separate target dir so it doesn't collide with the main
# fixture.

@test "new-overlay: overlay name with / and & substitutes literally (B1 regression)" {
    local metachar_name="feat/my&overlay"
    local ov2="$SCRATCH/ov2"

    # Engine must not abort — scaffold dir and README.md must be created.
    # Ignore --check exit status (hermetic bare repo, same as other happy-path tests).
    bash "$ENGINE" "$ov2" "$metachar_name" --core-url "$BARE" || true

    # Scaffold must have been created (engine did not abort before file copy)
    [ -f "$ov2/README.md" ]

    # The literal metachar name must appear verbatim — no sed corruption
    grep -qF "$metachar_name" "$ov2/README.md"

    # The raw token must be gone
    run grep -F "{{OVERLAY_NAME}}" "$ov2/README.md"
    [ "$status" -ne 0 ]
}
