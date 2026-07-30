#!/usr/bin/env bats
# Tests for scripts/pre-push.sh
#
# The hook computes the publication set (every pushed commit not already
# reachable from a remote-tracking ref) and feeds the SHAs to
# check-no-leakage.sh --commits. These tests exercise the hook's own
# responsibilities — range computation, stdin ref-line protocol, and exit
# propagation; checker internals are covered by tests/leakage-check.bats.
#
# Every token below is synthetic (xyzzy-corp, plugh, xyzzy.example.com).
# The real token list is data, not code: it lives outside every repo working
# tree and is never referenced here.

load 'test_helper'

ZERO_SHA="0000000000000000000000000000000000000000"

# Pin BOTH overrides in every test. A developer machine has real guard data
# installed and CI does not — unpinned tests would change verdict per host.
# The guard dir lives outside the fixture repo so its token list is never
# part of any scanned tree.
_guard_fixture() {
    GUARD="$SCRATCH/guard"
    mkdir -p "$GUARD"
    cat > "$GUARD/leakage-tokens.txt" <<'EOF'
# synthetic tokens — mechanism tests only
xyzzy-corp
plugh
xyzzy.example.com
EOF
    echo "fixture" > "$GUARD/company-context"
    export LEAKAGE_TOKENS_FILE="$GUARD/leakage-tokens.txt"
    export LEAKAGE_MARKER_FILE="$GUARD/company-context"
}

# Fixture repo with committed copies of both scripts: the hook resolves the
# checker via `git rev-parse --show-toplevel`, so both must exist inside the
# repo the hook runs from.
_repo_fixture() {
    REPO="$SCRATCH/repo"
    mkdir -p "$REPO/scripts"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email "dev@example.com"
    git -C "$REPO" config user.name "Dev"
    cp "$CORE_DIR/scripts/check-no-leakage.sh" "$REPO/scripts/"
    cp "$CORE_DIR/scripts/pre-push.sh" "$REPO/scripts/"
    git -C "$REPO" add scripts
    git -C "$REPO" commit -qm "baseline"
}

# Invoke the hook the way git does: cwd inside the repo, $1 = remote name,
# $2 = remote URL, one `<local_ref> <local_sha> <remote_ref> <remote_sha>`
# line per argument on stdin.
_run_hook() {
    run bash -c "cd '$REPO' && printf '%s\n' \"\$@\" \
        | bash scripts/pre-push.sh origin ssh://host.invalid/repo.git" _ "$@"
}

# ---------------------------------------------------------------------------
# Script contract: existence
# ---------------------------------------------------------------------------

@test "pre-push.sh exists and is executable" {
    [ -f "$CORE_DIR/scripts/pre-push.sh" ]
    [ -x "$CORE_DIR/scripts/pre-push.sh" ]
}

# ---------------------------------------------------------------------------
# Clean publication set passes
# ---------------------------------------------------------------------------

@test "clean commit pushed to a new remote branch exits 0" {
    _guard_fixture
    _repo_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add notes.txt
    git -C "$REPO" commit -qm "add notes"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha refs/heads/main $ZERO_SHA"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Leaky content anywhere in a pushed commit blocks the push
# ---------------------------------------------------------------------------

@test "commit with a leaky tree blocks the push and withholds the content" {
    _guard_fixture
    _repo_fixture
    echo "xyzzy-corp lives in this file" > "$REPO/leaky.txt"
    git -C "$REPO" add leaky.txt
    git -C "$REPO" commit -qm "add file"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha refs/heads/main $ZERO_SHA"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "leaky.txt"
    ! echo "$output" | grep -q "xyzzy-corp"
}

@test "commit with a leaky commit message blocks the push" {
    _guard_fixture
    _repo_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add notes.txt
    git -C "$REPO" commit -qm "integrate with xyzzy-corp systems"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha refs/heads/main $ZERO_SHA"
    [ "$status" -eq 1 ]
}

@test "commit with a leaky author email blocks the push" {
    _guard_fixture
    _repo_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add notes.txt
    git -C "$REPO" -c user.email="dev@xyzzy-corp.example" commit -qm "clean message"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha refs/heads/main $ZERO_SHA"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Every pushed commit's FULL tree is scanned — content added in one commit
# and removed in a later one still publishes with the push
# ---------------------------------------------------------------------------

@test "token added then removed across two commits pushed together blocks the push" {
    _guard_fixture
    _repo_fixture
    echo "xyzzy-corp was here" > "$REPO/leaky.txt"
    git -C "$REPO" add leaky.txt
    git -C "$REPO" commit -qm "first"
    git -C "$REPO" rm -q leaky.txt
    git -C "$REPO" commit -qm "second"
    local sha2
    sha2="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha2 refs/heads/main $ZERO_SHA"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Commits already reachable from a remote-tracking ref are pre-existing
# public history — out of scope, never rescanned
# ---------------------------------------------------------------------------

@test "commits already reachable from a remote-tracking ref are excluded" {
    _guard_fixture
    _repo_fixture
    echo "xyzzy-corp was here" > "$REPO/leaky.txt"
    git -C "$REPO" add leaky.txt
    git -C "$REPO" commit -qm "first"
    local sha1
    sha1="$(git -C "$REPO" rev-parse HEAD)"
    git -C "$REPO" update-ref refs/remotes/origin/main "$sha1"
    git -C "$REPO" rm -q leaky.txt
    git -C "$REPO" commit -qm "second"
    local sha2
    sha2="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha2 refs/heads/main $sha1"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Branch deletion publishes nothing: git sends an all-zero local sha
# ---------------------------------------------------------------------------

@test "branch-deletion line with all-zero local sha exits 0 despite leaky history" {
    _guard_fixture
    _repo_fixture
    echo "xyzzy-corp was here" > "$REPO/leaky.txt"
    git -C "$REPO" add leaky.txt
    git -C "$REPO" commit -qm "add file"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "(delete) $ZERO_SHA refs/heads/topic $sha"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Marker gate propagates through the hook: absent marker means this machine
# cannot possess the token list — skip cleanly. Present marker with a
# missing list fails closed.
# ---------------------------------------------------------------------------

@test "marker absent: push of leaky commits exits 0 with a skip notice" {
    _guard_fixture
    export LEAKAGE_MARKER_FILE="$GUARD/absent"
    _repo_fixture
    echo "xyzzy-corp lives in this file" > "$REPO/leaky.txt"
    git -C "$REPO" add leaky.txt
    git -C "$REPO" commit -qm "add file"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha refs/heads/main $ZERO_SHA"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "skipped"
}

@test "marker present + token list missing: hook blocks with exit 2" {
    _guard_fixture
    export LEAKAGE_TOKENS_FILE="$GUARD/no-such-tokens.txt"
    _repo_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add notes.txt
    git -C "$REPO" commit -qm "add notes"
    local sha
    sha="$(git -C "$REPO" rev-parse HEAD)"
    _run_hook "refs/heads/main $sha refs/heads/main $ZERO_SHA"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "ERROR"
}
