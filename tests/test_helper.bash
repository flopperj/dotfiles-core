#!/usr/bin/env bash
# Shared setup/teardown for dotfiles-core bats tests.
# Each test gets an isolated temp dir as CORE_DIR-relative fixtures.

# setup_file runs once per bats file before any tests execute.
# It exports CORE_DIR / DOTFILES_DIR early so that file-level global variable
# assignments (e.g. GEN="$DOTFILES_DIR/scripts/role-guard-gen.sh") are
# evaluated with the correct value.  These declarations live at file parse time
# which is after the file is sourced but BEFORE the first setup() call — hence
# the need for setup_file rather than (or in addition to) setup().
setup_file() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR
}

setup() {
    # CORE_DIR is the root of the dotfiles-core repo.
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    # DOTFILES_DIR is an alias for CORE_DIR used by bats files migrated from the
    # overlay. In the overlay DOTFILES_DIR points at the repo root; in core it is
    # the same as CORE_DIR.
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR

    # Isolated scratch dir for tests that write files.
    SCRATCH="$(mktemp -d)"
    export SCRATCH
}

teardown() {
    rm -rf "$SCRATCH"
}
