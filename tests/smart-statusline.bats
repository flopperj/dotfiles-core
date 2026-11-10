#!/usr/bin/env bats
# Tests for .claude/skills/smart-statusline/scripts/statusline-command.sh
#
# The script reads Claude Code's status JSON on stdin and prints one or two
# lines. Assertions run on ANSI-stripped text; the only styling check is the
# 70% tier colour, because an orange identical to yellow was the defect.
#
# Run with: bats tests/smart-statusline.bats

load 'test_helper'

SL=""

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SL="$CORE_DIR/.claude/skills/smart-statusline/scripts/statusline-command.sh"
    SKILL="$CORE_DIR/.claude/skills/smart-statusline/SKILL.md"
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    WORK="$SCRATCH/nogit"
    mkdir -p "$WORK"
    command -v jq > /dev/null 2>&1 || skip "jq not installed"
}

teardown() {
    rm -rf "$SCRATCH"
}

_strip() {
    sed $'s/\x1b\\[[0-9;]*m//g'
}

_json() {
    printf '{"model":{"display_name":"%s"},"cost":{"total_cost_usd":%s},"context_window":{"used_percentage":%s}}' "$2" "$3" "$1"
}

_run_sl() {
    run bash -c 'cd "$1" && printf "%s" "$2" | bash "$3"' _ "${CWD:-$WORK}" "$1" "$SL"
}

_stripped() {
    printf '%s' "$output" | _strip
}

_isolate_git() {
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@example.com
    export GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@example.com
}

_lines_file() {
    local n="$1" i
    for i in $(seq 1 "$n"); do
        echo "line $i"
    done
}

@test "49% is the plain tier" {
    _run_sl "$(_json 49 Fable 1.2345)"
    [ "$status" -eq 0 ] || return 1
    text="$(_stripped)"
    [[ "$text" == *"49%"* ]] || return 1
    [[ "$text" != *compact* ]] || return 1
}

@test "50% says consider /compact" {
    _run_sl "$(_json 50 Fable 1)"
    [[ "$(_stripped)" == *"50% — consider /compact"* ]] || return 1
}

@test "70% says run /compact now" {
    _run_sl "$(_json 70 Fable 1)"
    [[ "$(_stripped)" == *"70% — run /compact now"* ]] || return 1
}

@test "90% says start new session" {
    _run_sl "$(_json 90 Fable 1)"
    [[ "$(_stripped)" == *"90% — start new session!"* ]] || return 1
}

@test "70% tier uses a different escape than the 50% tier" {
    _run_sl "$(_json 50 Fable 1)"
    at50="$output"
    _run_sl "$(_json 70 Fable 1)"
    at70="$output"
    orange=$'\x1b[38;5;208m'
    [[ "$at70" == *"$orange"* ]] || return 1
    [[ "$at50" != *"$orange"* ]] || return 1
}

@test "cost renders as an estimate" {
    _run_sl "$(_json 10 Fable 1.2345)"
    [[ "$(_stripped)" == *'💰 ~$1.23'* ]] || return 1
}

@test "null used_percentage renders model, cost and separators without a dangling bar" {
    _run_sl "$(_json null Fable 0.5)"
    [ "$status" -eq 0 ] || return 1
    [ "$(_stripped)" = '🤖 Fable | 💰 ~$0.50' ] || return 1
}

@test "percent sign in the model name is rendered literally" {
    _run_sl "$(_json 10 'Claude 100% Fable' 1)"
    [[ "$(_stripped)" == *"100% Fable"* ]] || return 1
}

@test "backslash sequences in the model name are rendered literally" {
    _run_sl "$(_json 10 'Model \\c\\n X' 1)"
    text="$(_stripped)"
    [[ "$text" == *'Model \c\n X | 💰 ~$1.00 | CTX'* ]] || return 1
}

@test "missing cost omits the cost segment" {
    _run_sl '{"model":{"display_name":"Fable"},"context_window":{"used_percentage":10}}'
    text="$(_stripped)"
    [[ "$text" != *💰* ]] || return 1
    [[ "$text" == "🤖 Fable | CTX █░░░░░░░░░ 10%" ]] || return 1
}

@test "lines changed count only the user's commits (merge-base), not upstream advances" {
    _isolate_git
    git init -q --bare -b main "$SCRATCH/origin.git"
    git clone -q "$SCRATCH/origin.git" "$SCRATCH/repo" 2> /dev/null
    (
        cd "$SCRATCH/repo" || exit 1
        git checkout -q -b main 2> /dev/null || true
        echo base > base.txt
        git add base.txt
        git commit -q -m base
        git push -q origin main
        git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
        git checkout -q -b feat
        _lines_file 3 > mine.txt
        git add mine.txt
        git commit -q -m mine
    ) || return 1
    git clone -q "$SCRATCH/origin.git" "$SCRATCH/other" 2> /dev/null
    (
        cd "$SCRATCH/other" || exit 1
        _lines_file 100 > upstream.txt
        git add upstream.txt
        git commit -q -m upstream
        git push -q origin main
    ) || return 1
    git -C "$SCRATCH/repo" fetch -q origin || return 1

    CWD="$SCRATCH/repo" _run_sl "$(_json 10 Fable 0)"
    text="$(_stripped)"
    [[ "$text" == *"+3 -0 (3 lines)"* ]] || return 1
    [[ "$text" != *103* ]] || return 1
}

@test "no origin/default omits the lines segment" {
    _isolate_git
    git init -q -b main "$SCRATCH/plain"
    (
        cd "$SCRATCH/plain" || exit 1
        echo one > one.txt
        git add one.txt
        git commit -q -m one
        echo two >> one.txt
    ) || return 1

    CWD="$SCRATCH/plain" _run_sl "$(_json 10 Fable 0)"
    text="$(_stripped)"
    [[ "$text" == *"⎇ main"* ]] || return 1
    [[ "$text" != *"lines)"* ]] || return 1
}

_fallback_repo() {
    _isolate_git
    git init -q --bare -b "$1" "$SCRATCH/origin.git"
    git clone -q "$SCRATCH/origin.git" "$SCRATCH/repo" 2> /dev/null
    (
        cd "$SCRATCH/repo" || exit 1
        git checkout -q -b "$1" 2> /dev/null || true
        echo base > base.txt
        git add base.txt
        git commit -q -m base
        git push -q origin "$1"
        git remote set-head origin -d 2> /dev/null || true
        git checkout -q -b feat
        _lines_file 2 > mine.txt
        git add mine.txt
        git commit -q -m mine
    ) || return 1
    ! git -C "$SCRATCH/repo" symbolic-ref -q refs/remotes/origin/HEAD > /dev/null || return 1
}

@test "origin/HEAD unset: lines segment falls back to origin/main" {
    _fallback_repo main || return 1
    CWD="$SCRATCH/repo" _run_sl "$(_json 10 Fable 0)"
    [[ "$(_stripped)" == *"⎇ feat | +2 -0 (2 lines)"* ]]
}

@test "origin/HEAD unset: lines segment falls back to origin/master" {
    _fallback_repo master || return 1
    CWD="$SCRATCH/repo" _run_sl "$(_json 10 Fable 0)"
    [[ "$(_stripped)" == *"⎇ feat | +2 -0 (2 lines)"* ]]
}

@test "SKILL.md thresholds match the script's -ge literals" {
    local tiers yellow orange red
    tiers="$(grep -oE '"\$used_int" -ge [0-9]+' "$SL" | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ')"
    read -r yellow orange red <<< "$tiers"
    [ -n "$red" ] || { echo "expected three tiers in the script, got: $tiers"; return 1; }
    grep -q "prompts at ${yellow}%" "$SKILL" || return 1
    grep -Eq "Yellow\*\* \(${yellow}–" "$SKILL" || return 1
    grep -Eq "Orange\*\* \(${orange}–" "$SKILL" || return 1
    grep -Eq "Red\*\* \(${red}%" "$SKILL" || return 1
}

@test "SKILL.md documents the estimate label and keeps its trigger phrases" {
    ! grep -q '30%' "$SKILL" || return 1
    grep -q 'estimate' "$SKILL" || return 1
    grep -qF 'show me context percentage' "$SKILL" || return 1
    grep -qF 'set up my statusline' "$SKILL" || return 1
    grep -qF 'I want to see how much context I have left' "$SKILL" || return 1
    grep -qF '/smart-statusline' "$SKILL" || return 1
}
