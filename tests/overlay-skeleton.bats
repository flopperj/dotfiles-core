#!/usr/bin/env bats
# Tests for scripts/overlay-skeleton/ — static overlay skeleton fixtures.
#
# RED phase: written before the fixture files exist.
# Covers:
#   (a) every expected .template file exists
#   (b) install.sh.template delegates to core and sources install-overlay.sh
#   (c) overlay-fragments.yaml.template is exactly "fragments: []" and parses
#       as an empty manifest via apply_manifest
#   (d) gate-safety guard — no fixture is visible to the consult-grammar
#       SKILL.md glob, and no fixture contains a leakage token

load 'test_helper'

SKEL_DIR=""

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
    SKEL_DIR="$CORE_DIR/scripts/overlay-skeleton"

    SCRATCH="$(mktemp -d)"
    export SCRATCH
}

teardown() {
    rm -rf "$SCRATCH"
}

# ---------------------------------------------------------------------------
# (a) Fixture file existence
# ---------------------------------------------------------------------------

@test "skeleton: install.sh.template exists" {
    [ -f "$SKEL_DIR/install.sh.template" ]
}

@test "skeleton: gitignore.template exists" {
    [ -f "$SKEL_DIR/gitignore.template" ]
}

@test "skeleton: README.md.template exists" {
    [ -f "$SKEL_DIR/README.md.template" ]
}

@test "skeleton: scripts/install-overlay.sh.template exists" {
    [ -f "$SKEL_DIR/scripts/install-overlay.sh.template" ]
}

@test "skeleton: dotclaude/overlay-fragments.yaml.template exists" {
    [ -f "$SKEL_DIR/dotclaude/overlay-fragments.yaml.template" ]
}

@test "skeleton: dotclaude/overlay-context.md.template exists" {
    [ -f "$SKEL_DIR/dotclaude/overlay-context.md.template" ]
}

@test "skeleton: dotclaude/plugins.txt.template exists" {
    [ -f "$SKEL_DIR/dotclaude/plugins.txt.template" ]
}

# ---------------------------------------------------------------------------
# (b) install.sh.template shape — delegates to core and sources install-overlay
# ---------------------------------------------------------------------------

@test "skeleton: install.sh.template delegates to dotfiles-core install.sh" {
    grep -q '\.claude/dotfiles-core/install\.sh.*"\$@"' \
        "$SKEL_DIR/install.sh.template"
}

@test "skeleton: install.sh.template sources scripts/install-overlay.sh" {
    grep -q 'scripts/install-overlay\.sh' \
        "$SKEL_DIR/install.sh.template"
}

# ---------------------------------------------------------------------------
# (c) overlay-fragments.yaml.template is exactly "fragments: []" and parses
# ---------------------------------------------------------------------------

@test "skeleton: overlay-fragments.yaml.template contains exactly 'fragments: []'" {
    local content
    content="$(cat "$SKEL_DIR/dotclaude/overlay-fragments.yaml.template")"
    [ "$content" = "fragments: []" ]
}

@test "skeleton: overlay-fragments.yaml.template parses as empty manifest via apply_manifest" {
    source "$CORE_DIR/scripts/lib-overlays.sh"
    cp "$SKEL_DIR/dotclaude/overlay-fragments.yaml.template" "$SCRATCH/m.yaml"
    run apply_manifest "$SCRATCH/m.yaml"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# (d) Gate-safety guard — fixtures are invisible to scanner globs
# ---------------------------------------------------------------------------

@test "skeleton: no fixture path matches the consult-grammar SKILL.md glob" {
    # The consult-grammar scanner uses: find ... -path "*/.claude/skills/*/SKILL.md"
    # None of our fixtures must match that path pattern.
    # Guard: if the dir doesn't exist at all, the constraint is trivially satisfied.
    [ -d "$SKEL_DIR" ] || return 0
    local matches
    matches="$(find "$SKEL_DIR" -path "*/.claude/skills/*/SKILL.md" -type f 2>/dev/null || true)"
    [ -z "$matches" ]
}

@test "skeleton: no fixture contains a leakage token" {
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$CORE_DIR/scripts/overlay-skeleton"
    [ "$status" -eq 0 ]
}
