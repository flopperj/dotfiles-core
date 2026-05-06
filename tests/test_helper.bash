#!/usr/bin/env bash
# Shared setup/teardown for dotfiles-core bats tests.
# Each test gets an isolated temp dir as CORE_DIR-relative fixtures.

setup() {
    # CORE_DIR is the root of the dotfiles-core repo.
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR

    # Isolated scratch dir for tests that write files.
    SCRATCH="$(mktemp -d)"
    export SCRATCH
}

teardown() {
    rm -rf "$SCRATCH"
}
