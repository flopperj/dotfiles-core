#!/usr/bin/env bats
# Step 6 — RED-phase tests for _install_precommit_hook.
# Written before implementation; all tests must fail first.

load 'test_helper'

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH

    # Fixture core dir with a real .git directory (not a submodule file)
    FIXTURE_CORE="$SCRATCH/fixture_core"
    mkdir -p "$FIXTURE_CORE/.git/hooks"
    # pre-commit.sh must exist in the fixture so the symlink target is real
    mkdir -p "$FIXTURE_CORE/scripts"
    cp "$CORE_DIR/scripts/pre-commit.sh" "$FIXTURE_CORE/scripts/pre-commit.sh"
}

teardown() {
    rm -rf "$SCRATCH"
}

# ---------------------------------------------------------------------------
# 1. Function is defined in lib-core-symlinks.sh
# ---------------------------------------------------------------------------

@test "_install_precommit_hook is defined in lib-core-symlinks.sh" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-core-symlinks.sh"
    declare -f _install_precommit_hook > /dev/null
}

# ---------------------------------------------------------------------------
# 2. Symlink is created when .git is a directory
# ---------------------------------------------------------------------------

@test "_install_precommit_hook creates symlink at .git/hooks/pre-commit when .git is a dir" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-core-symlinks.sh"
    _install_precommit_hook "$FIXTURE_CORE"

    local hook="$FIXTURE_CORE/.git/hooks/pre-commit"
    [ -L "$hook" ]
    # Symlink must point at scripts/pre-commit.sh inside fixture core
    local target
    target="$(readlink "$hook")"
    [ "$target" = "$FIXTURE_CORE/scripts/pre-commit.sh" ]
}

# ---------------------------------------------------------------------------
# 3. Hook is executable after install
# ---------------------------------------------------------------------------

@test "_install_precommit_hook makes .git/hooks/pre-commit executable" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-core-symlinks.sh"
    _install_precommit_hook "$FIXTURE_CORE"

    [ -x "$FIXTURE_CORE/.git/hooks/pre-commit" ]
}

# ---------------------------------------------------------------------------
# 4. Idempotent: calling twice exits 0, single symlink remains
# ---------------------------------------------------------------------------

@test "_install_precommit_hook is idempotent: second call succeeds and leaves one symlink" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-core-symlinks.sh"
    _install_precommit_hook "$FIXTURE_CORE"
    _install_precommit_hook "$FIXTURE_CORE"

    local hook="$FIXTURE_CORE/.git/hooks/pre-commit"
    [ -L "$hook" ]
    # Still exactly one hook file — not duplicated
    local count
    count="$(find "$FIXTURE_CORE/.git/hooks" -maxdepth 1 -name 'pre-commit*' | wc -l)"
    [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 5. Skips when .git is a file (submodule worktree)
# ---------------------------------------------------------------------------

@test "_install_precommit_hook skips when .git is a file not a directory" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-core-symlinks.sh"

    # Simulate submodule worktree: .git is a file, not a dir
    local submod_core="$SCRATCH/submod_core"
    mkdir -p "$submod_core/scripts"
    cp "$CORE_DIR/scripts/pre-commit.sh" "$submod_core/scripts/pre-commit.sh"
    echo "gitdir: /some/other/.git" > "$submod_core/.git"

    _install_precommit_hook "$submod_core"

    # No hooks directory should have been created
    [ ! -d "$submod_core/.git/hooks" ]
}

# ---------------------------------------------------------------------------
# 6. Graceful handling of existing regular-file hook (husky, lefthook, etc.)
# ---------------------------------------------------------------------------

@test "_install_precommit_hook backs up regular-file collision and installs symlink" {
    # shellcheck source=/dev/null
    source "$CORE_DIR/scripts/lib-core-symlinks.sh"

    local hook="$FIXTURE_CORE/.git/hooks/pre-commit"

    # Plant a regular (non-symlink) hook file — simulates husky/lefthook/hand-written hook
    echo "#!/bin/sh" > "$hook"
    echo "# existing hook" >> "$hook"

    _install_precommit_hook "$FIXTURE_CORE"

    # install must succeed: hook is now a symlink pointing at pre-commit.sh
    [ -L "$hook" ]
    local target
    target="$(readlink "$hook")"
    [ "$target" = "$FIXTURE_CORE/scripts/pre-commit.sh" ]

    # Original regular file must be preserved as a .bak file
    local bak_count
    bak_count="$(find "$FIXTURE_CORE/.git/hooks" -maxdepth 1 -name 'pre-commit.bak.*' 2>/dev/null | wc -l)"
    [ "$bak_count" -ge 1 ]

    # Backup must contain the original hook content
    local bak_file
    bak_file="$(find "$FIXTURE_CORE/.git/hooks" -maxdepth 1 -name 'pre-commit.bak.*' 2>/dev/null | head -1)"
    grep -q "existing hook" "$bak_file"
}
