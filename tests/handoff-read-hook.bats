#!/usr/bin/env bats
# Behavioral tests for .claude/hooks/handoff-read.py: real temp git repos,
# isolated HOME, JSON hook payload on stdin. No mocking of git.
#
# bash 3.2 note: every mid-test assertion ends in `|| return 1`.

load 'test_helper'
bats_require_minimum_version 1.5.0

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"; export CORE_DIR
    HOOK="$CORE_DIR/.claude/hooks/handoff-read.py"; export HOOK
    ORIG_HOME="$HOME"
    TEST_HOME="$(mktemp -d)"; export TEST_HOME
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2; exit 99
    fi
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@example.com
    export GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@example.com
    TASKS="$HOME/.claude/tasks"; export TASKS
}

teardown() { rm -rf "$TEST_HOME"; }

_repo() {
    mkdir -p "$1"; git -C "$1" init -q -b "$2"
    echo seed > "$1/seed.txt"; git -C "$1" add -A; git -C "$1" commit -qm seed
}

_handoff() {
    mkdir -p "$TASKS/$1/handoff"; cat > "$TASKS/$1/handoff/$2.md"
}

_hook() {
    run --separate-stderr bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | python3 "$2"' _ "$1" "$HOOK"
}

_old_format_body() { cat <<'EOF'
---
task_key: feat-x
project: repo
written: 2026-11-09T10:00:00
intent: finish the parser
goal: null
rejections:
  - kind: structural
    claim: keep Foo final
    anchor: seed.txt
    predicate: grep -q seed seed.txt
    fallback: drop and surface to user
  - kind: goal-conditional
    claim: user still prefers the smaller approach
    anchor: null
    predicate: user still wants the smaller approach
    fallback: drop and surface to user
---
EOF
}

@test "no git repo: silent exit 0" {
    mkdir -p "$TEST_HOME/plain"
    _hook "$TEST_HOME/plain"
    [ "$status" -eq 0 ] || return 1
    [ -z "$output" ] || return 1
    [ -z "$stderr" ]
}

@test "detached HEAD: silent exit 0" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    git -C "$TEST_HOME/repo" checkout -q --detach
    _hook "$TEST_HOME/repo"
    [ "$status" -eq 0 ] || return 1
    [ -z "$output" ]
}

@test "no handoff file: silent exit 0" {
    _repo "$TEST_HOME/repo" feat/x
    _hook "$TEST_HOME/repo"
    [ "$status" -eq 0 ] || return 1
    [ -z "$output" ]
}

@test "old-format handoff renders the documented block plus one working-tree line" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    _hook "$TEST_HOME/repo"
    expected="Open handoff detected for feat-x (written 2026-11-09T10:00:00).
  Working tree: 0 uncommitted file(s); no upstream

  Immediate next intent:
    finish the parser

  Active goal:
    (omitted; recoverable from PR/ticket)

  Holding (these gate this session — do not re-try without a stated reason):
    [structural] keep Foo final

  Cannot evaluate (surface to user):
    [goal-conditional] user still prefers the smaller approach
      reason: cannot-evaluate — goal-conditional — surface to user by design

  -> Proceeding. To re-examine the handoff later, read $TASKS/repo/handoff/feat-x.md"
    [ "$status" -eq 0 ] || return 1
    [ "$output" = "$expected" ]
}

_malformed_line() {
    printf 'Handoff file at %s is malformed; skipping. Inspect manually.' "$TASKS/repo/handoff/feat-x.md"
}

@test "malformed frontmatter: exit 0 and a single warning line on stdout" {
    _repo "$TEST_HOME/repo" feat/x
    printf -- '---\nintent: [unterminated\n---\n' | _handoff repo feat-x
    _hook "$TEST_HOME/repo"
    [ "$status" -eq 0 ] || return 1
    [ "${#lines[@]}" -eq 1 ] || return 1
    case "$output" in "$(_malformed_line) ("*")") ;; *) return 1 ;; esac
}

_tree_line() {
    printf '%s\n' "$output" | grep '^  Working tree:'
}

@test "working tree: counts untracked and modified files" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    echo x > "$TEST_HOME/repo/new.txt"
    echo y >> "$TEST_HOME/repo/seed.txt"
    _hook "$TEST_HOME/repo"
    case "$(_tree_line)" in *"2 uncommitted file(s)"*) ;; *) return 1 ;; esac
}

@test "working tree: no upstream reads no upstream" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    _hook "$TEST_HOME/repo"
    [ "$(_tree_line)" = "  Working tree: 0 uncommitted file(s); no upstream" ]
}

_with_upstream() {
    git init -q --bare "$TEST_HOME/remote.git"
    git -C "$TEST_HOME/repo" remote add origin "$TEST_HOME/remote.git"
    git -C "$TEST_HOME/repo" push -q -u origin feat/x 2>/dev/null
}

@test "working tree: counts commits ahead of upstream" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    _with_upstream
    echo a > "$TEST_HOME/repo/a.txt"; git -C "$TEST_HOME/repo" add -A; git -C "$TEST_HOME/repo" commit -qm a
    echo b > "$TEST_HOME/repo/b.txt"; git -C "$TEST_HOME/repo" add -A; git -C "$TEST_HOME/repo" commit -qm b
    _hook "$TEST_HOME/repo"
    [ "$(_tree_line)" = "  Working tree: 0 uncommitted file(s); 2 unpushed commit(s)" ]
}

@test "working tree: zero ahead renders 0 unpushed commit(s)" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    _with_upstream
    _hook "$TEST_HOME/repo"
    [ "$(_tree_line)" = "  Working tree: 0 uncommitted file(s); 0 unpushed commit(s)" ]
}

@test "working tree line sits directly under the header line" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    _hook "$TEST_HOME/repo"
    [ "${lines[1]}" = "  Working tree: 0 uncommitted file(s); no upstream" ]
}

_surfaces() {
    case "$output" in *"Open handoff detected for $1"*) return 0 ;; *) return 1 ;; esac
}

@test "project: normal checkout keys by the repo folder name" {
    _repo "$TEST_HOME/src/mainrepo" feat/x
    _old_format_body | _handoff mainrepo feat-x
    _hook "$TEST_HOME/src/mainrepo"
    _surfaces feat-x
}

@test "project: linked worktree keys by the main checkout" {
    _repo "$TEST_HOME/src/mainrepo" main
    mkdir -p "$TEST_HOME/wt"
    git -C "$TEST_HOME/src/mainrepo" worktree add -q "$TEST_HOME/wt/feat-x" -b feat/x
    _old_format_body | _handoff mainrepo feat-x
    _hook "$TEST_HOME/wt/feat-x"
    _surfaces feat-x
}

@test "project: handoff filed under the worktree folder name is not surfaced as the handoff" {
    _repo "$TEST_HOME/src/mainrepo" main
    mkdir -p "$TEST_HOME/wt"
    git -C "$TEST_HOME/src/mainrepo" worktree add -q "$TEST_HOME/wt/feat-x" -b feat/x
    _old_format_body | _handoff feat-x feat-x
    _hook "$TEST_HOME/wt/feat-x"
    [ "$status" -eq 0 ] || return 1
    ! _surfaces feat-x || return 1
    case "$output" in *'legacy project key "feat-x"'*) ;; *) return 1 ;; esac
    case "$output" in *"$TASKS/mainrepo/handoff/feat-x.md"*) ;; *) return 1 ;; esac
}

@test "project: linked worktree with no handoff under either key prints nothing" {
    _repo "$TEST_HOME/src/mainrepo" main
    mkdir -p "$TEST_HOME/wt"
    git -C "$TEST_HOME/src/mainrepo" worktree add -q "$TEST_HOME/wt/feat-x" -b feat/x
    _old_format_body | _handoff unrelated feat-x
    _hook "$TEST_HOME/wt/feat-x"
    [ "$status" -eq 0 ] || return 1
    [ -z "$output" ] || return 1
    [ -z "$stderr" ]
}

@test "project: worktree of a bare repository keys by the bare directory name without .git" {
    _repo "$TEST_HOME/seed" main
    git clone -q --bare "$TEST_HOME/seed" "$TEST_HOME/src/myproj.git"
    git -C "$TEST_HOME/src/myproj.git" worktree add -q "$TEST_HOME/src/myproj-wt" -b feat/x
    _old_format_body | _handoff myproj feat-x
    _hook "$TEST_HOME/src/myproj-wt"
    _surfaces feat-x
}

_submodule() {
    _repo "$TEST_HOME/src/mainrepo" main
    _repo "$TEST_HOME/super" main
    git -C "$TEST_HOME/super" -c protocol.file.allow=always submodule add -q "$TEST_HOME/src/mainrepo" mod 2>/dev/null
    git -C "$TEST_HOME/super/mod" checkout -q -b feat/x
}

@test "project: submodule keys by the submodule directory name" {
    _submodule
    _old_format_body | _handoff mod feat-x
    _hook "$TEST_HOME/super/mod"
    _surfaces feat-x
}

@test "project: linked worktree of a submodule keys by the submodule checkout" {
    _submodule
    mkdir -p "$TEST_HOME/wt"
    git -C "$TEST_HOME/super/mod" worktree add -q "$TEST_HOME/wt/sub-wt" -b feat/y
    _old_format_body | sed "s/feat-x/feat-y/" | _handoff mod feat-y
    _hook "$TEST_HOME/wt/sub-wt"
    _surfaces feat-y
}

_body_plus() {
    _old_format_body | sed '$d'
    cat
    echo '---'
}

_has_line() {
    printf '%s\n' "$output" | grep -qxF -- "$1"
}

@test "in_flight: stopped item renders its restart command" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
in_flight:
  - what: dev server (npm run dev)
    kind: background-shell
    stopped: true
    cwd: /abs/path/to/repo
    restart: npm run dev
EOF
    _hook "$TEST_HOME/repo"
    _has_line "  In flight at handoff (restart to resume):" || return 1
    _has_line "    dev server (npm run dev) — stopped; cwd /abs/path/to/repo" || return 1
    _has_line "      restart: npm run dev"
}

@test "in_flight: subagent brief shows only its first line plus a pointer to the file" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
in_flight:
  - what: parity-check subagent for PR 12
    kind: subagent
    stopped: true
    cwd: /abs/path/to/repo
    restart: null
    brief: |
      Relaunch prompt that stands on its own: goal, inputs, files, done-condition.
      Second line that must not be surfaced.
EOF
    _hook "$TEST_HOME/repo"
    _has_line "    parity-check subagent for PR 12 — stopped; cwd /abs/path/to/repo" || return 1
    _has_line "      brief: Relaunch prompt that stands on its own: goal, inputs, files, done-condition. (full brief in the handoff file)" || return 1
    ! printf '%s\n' "$output" | grep -q 'Second line' || return 1
    ! printf '%s\n' "$output" | grep -q 'restart:' || return 1
}

@test "in_flight: stopped false renders left running" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
in_flight:
  - what: storybook the user started in another terminal
    kind: other
    stopped: false
    cwd: /abs/path/to/repo
    restart: npm run storybook
EOF
    _hook "$TEST_HOME/repo"
    _has_line "    storybook the user started in another terminal — left running; cwd /abs/path/to/repo" || return 1
    _has_line "      restart: npm run storybook"
}

@test "in_flight: item without cwd or restart renders just its first line" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
in_flight:
  - what: file watcher
    kind: background-shell
EOF
    _hook "$TEST_HOME/repo"
    _has_line "    file watcher — stopped" || return 1
    ! printf '%s\n' "$output" | grep -q 'restart:' || return 1
    ! printf '%s\n' "$output" | grep -q 'cwd' || return 1
}

@test "in_flight: absent or empty list omits the heading" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
in_flight:
EOF
    _hook "$TEST_HOME/repo"
    [ "$status" -eq 0 ] || return 1
    _surfaces feat-x || return 1
    ! printf '%s\n' "$output" | grep -q 'In flight' || return 1
}

@test "in_flight: restart commands are rendered, never executed" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<EOF | _handoff repo feat-x
in_flight:
  - what: marker writer
    kind: other
    restart: touch $TEST_HOME/executed
EOF
    _hook "$TEST_HOME/repo"
    [ ! -e "$TEST_HOME/executed" ] || return 1
    _has_line "      restart: touch $TEST_HOME/executed"
}

@test "refs: mapping entries render with their kinds" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
refs:
  - kind: pr
    value: https://github.com/example/repo/pull/12
  - kind: plan
    value: ~/.claude/tasks/repo/plans/parser.md
EOF
    _hook "$TEST_HOME/repo"
    _has_line "  Refs:" || return 1
    _has_line "    [pr] https://github.com/example/repo/pull/12" || return 1
    _has_line "    [plan] ~/.claude/tasks/repo/plans/parser.md"
}

@test "refs: scalar entry renders as a generic ref" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
refs:
  - https://github.com/example/repo/pull/12
EOF
    _hook "$TEST_HOME/repo"
    _has_line "    [ref] https://github.com/example/repo/pull/12"
}

@test "refs: absent omits the heading" {
    _repo "$TEST_HOME/repo" feat/x
    _old_format_body | _handoff repo feat-x
    _hook "$TEST_HOME/repo"
    ! printf '%s\n' "$output" | grep -q 'Refs:'
}

@test "refs and in_flight sit after the active goal and before the holding list" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
refs:
  - kind: pr
    value: https://github.com/example/repo/pull/12
in_flight:
  - what: dev server
    kind: background-shell
EOF
    _hook "$TEST_HOME/repo"
    goal=$(printf '%s\n' "$output" | grep -n 'Active goal:' | cut -d: -f1)
    refs=$(printf '%s\n' "$output" | grep -n '  Refs:' | cut -d: -f1)
    flight=$(printf '%s\n' "$output" | grep -n 'In flight at handoff' | cut -d: -f1)
    holding=$(printf '%s\n' "$output" | grep -n '  Holding' | cut -d: -f1)
    [ "$goal" -lt "$refs" ] || return 1
    [ "$refs" -lt "$flight" ] || return 1
    [ "$flight" -lt "$holding" ]
}

@test "parser: block-scalar goal, quoted claim and comment lines are honored" {
    _repo "$TEST_HOME/repo" feat/x
    cat <<'EOF' | _handoff repo feat-x
---
task_key: feat-x
written: 2026-11-09T10:00:00
# a comment line
intent: "ship it: carefully"
goal: |
  first goal line
  second goal line
rejections:
  - kind: structural
    claim: 'keep Foo ''final'''
    anchor: seed.txt
    predicate: grep -q 'seed' seed.txt
---
EOF
    _hook "$TEST_HOME/repo"
    _has_line "    ship it: carefully" || return 1
    _has_line "    first goal line" || return 1
    _has_line "    second goal line" || return 1
    _has_line "    [structural] keep Foo 'final'"
}

@test "parser: flow collections are reported as malformed" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
refs: [a, b]
EOF
    _hook "$TEST_HOME/repo"
    [ "${#lines[@]}" -eq 1 ] || return 1
    case "$output" in "$(_malformed_line) ("*")") ;; *) return 1 ;; esac
}

@test "parser: double-quoted values unescape only the documented escapes" {
    _repo "$TEST_HOME/repo" feat/x
    cat <<'EOF' | _handoff repo feat-x
---
task_key: feat-x
written: 2026-11-09T10:00:00
intent: "tab\tkept \"q\" back\\slash\nsecond"
---
EOF
    _hook "$TEST_HOME/repo"
    _has_line '    tab\tkept "q" back\slash' || return 1
    _has_line '    second'
}

_slow_grep() {
    mkdir -p "$TEST_HOME/bin"
    printf '#!/bin/sh\nexec sleep 10\n' > "$TEST_HOME/bin/grep"
    chmod +x "$TEST_HOME/bin/grep"
}

@test "time budget: slow predicates cannot push the hook past the SessionStart timeout" {
    _repo "$TEST_HOME/repo" feat/x
    _body_plus <<'EOF' | _handoff repo feat-x
  - kind: structural
    claim: second slow claim
    anchor: seed.txt
    predicate: grep -q seed seed.txt
  - kind: structural
    claim: third slow claim
    anchor: seed.txt
    predicate: grep -q seed seed.txt
EOF
    _slow_grep
    local start end
    start=$(python3 -c 'import time; print(time.time())')
    run --separate-stderr bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | PATH="$3:$PATH" python3 "$2"' _ "$TEST_HOME/repo" "$HOOK" "$TEST_HOME/bin"
    end=$(python3 -c 'import time; print(time.time())')
    python3 -c "import sys; sys.exit(0 if $end - $start < 4.95 else 1)" || return 1
    _surfaces feat-x || return 1
    case "$output" in *"hook time budget spent"*) ;; *) return 1 ;; esac
}
