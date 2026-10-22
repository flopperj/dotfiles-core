#!/usr/bin/env bats
# Tests for the /record-demo skill: routing wiring (read from the rendered
# CLAUDE.md, so they stay RED until scripts/pre-commit.sh regenerates it), the
# upstream MIT notice, the single DevTools-port knob, and preflight.sh's
# report-and-exit contract.
#
# Run with: bats tests/record-demo.bats

setup() {
    TEST_HOME="$(mktemp -d)"
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    SKILL_DIR="$DOTFILES_DIR/.claude/skills/record-demo"
    if [ -f "$DOTFILES_DIR/.claude/CLAUDE.md" ]; then
        CLAUDE_MD="$DOTFILES_DIR/.claude/CLAUDE.md"
    else
        CLAUDE_MD="$DOTFILES_DIR/.claude/CLAUDE.md.generated"
    fi
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

@test "record-demo SKILL.md has the required frontmatter" {
    grep -q "^name: record-demo$" "$SKILL_DIR/SKILL.md"
    grep -q "^user-invocable:[[:space:]]*true" "$SKILL_DIR/SKILL.md"
}

@test "record-demo keeps the upstream MIT notice" {
    grep -q "^MIT License" "$SKILL_DIR/LICENSE"
    grep -q "Copyright (c) 2026 San'Quan Prioleau" "$SKILL_DIR/LICENSE"
    grep -qF '(MIT, see `LICENSE`)' "$SKILL_DIR/SKILL.md"
}

@test "record-demo trigger phrases and slash entry are wired into CLAUDE.md" {
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md(.generated) not present"
    local phrase missing=()
    for phrase in "record a demo" "make a demo video for the PR" "add a demo to the PR" \
        "record a before and after" "screen-record this"; do
        grep -qiwF -- "$phrase" "$CLAUDE_MD" || missing+=("$phrase")
    done
    [ "${#missing[@]}" -eq 0 ] || { printf 'missing trigger: "%s"\n' "${missing[@]}"; return 1; }
    grep -qE '^  - .*`/record-demo`' "$CLAUDE_MD"
}

@test "every script reaches the browser through DEMO_CDP_PORT" {
    # A bare 9333 outside a ${DEMO_CDP_PORT:-9333} / || 9333 default would
    # ignore an attached browser on another port.
    run grep -nE '9333' "$SKILL_DIR"/scripts/*.sh "$SKILL_DIR"/scripts/*.mjs
    [ "$status" -eq 0 ]
    local bad
    bad=$(printf '%s\n' "$output" | grep -vE 'DEMO_CDP_PORT' || true)
    [ -z "$bad" ] || { echo "hard-coded port: $bad"; return 1; }
}

@test "preflight reports a missing browser with its fix and exits 1" {
    # Port 9 (discard) never serves DevTools.
    DEMO_CDP_PORT=9 run bash "$SKILL_DIR/scripts/preflight.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISS  no browser DevTools on :9"* ]]
    [[ "$output" == *"fix: bash "*"demo-browser.sh start"* ]]
    [[ "$output" == *"gap(s)"* ]]
}

@test "preflight names the python it checked" {
    DEMO_PYTHON=/nonexistent/python DEMO_CDP_PORT=9 run bash "$SKILL_DIR/scripts/preflight.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISS  numpy + Pillow for /nonexistent/python"* ]]
}

@test "npm i in the skill writes no lockfile" {
    grep -qx "package-lock=false" "$SKILL_DIR/scripts/.npmrc"
    grep -qE '"playwright-core": "[0-9]+\.[0-9]+\.[0-9]+"' "$SKILL_DIR/scripts/package.json"
}

@test "preflight defaults to the record-demo venv when it exists" {
    mkdir -p "$HOME/.cache/record-demo-venv/bin"
    printf '#!/bin/sh\nexit 1\n' > "$HOME/.cache/record-demo-venv/bin/python"
    chmod +x "$HOME/.cache/record-demo-venv/bin/python"
    DEMO_CDP_PORT=9 run bash "$SKILL_DIR/scripts/preflight.sh"
    [[ "$output" == *"numpy + Pillow for $HOME/.cache/record-demo-venv/bin/python"* ]]
}
