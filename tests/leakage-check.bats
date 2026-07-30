#!/usr/bin/env bats
# Tests for scripts/check-no-leakage.sh
#
# Mechanism tests only — every token below is synthetic (xyzzy-corp, plugh,
# xyzzy.example.com, grault-sentinel). The real token list is data, not code:
# it lives outside every repo working tree and is never referenced here.

load 'test_helper'

# Pin BOTH overrides in every test. A developer machine has real guard data
# installed and CI does not — unpinned tests would change verdict per host.
_guard_fixture() {
    GUARD="$SCRATCH/guard"
    SCAN="$SCRATCH/scan"           # scanned dir — must NOT contain the fixture list
    mkdir -p "$GUARD" "$SCAN"
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

_check_file() {
    printf '%s\n' "$1" > "$SCAN/subject.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCAN"
}

_git_fixture() {
    REPO="$SCRATCH/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email "dev@example.com"
    git -C "$REPO" config user.name "Dev"
}

# Run the checker in --commits mode with cwd inside the fixture repo,
# feeding the given lines (one SHA per line) on stdin.
_check_commits() {
    run bash -c "cd '$REPO' && printf '%s\n' \"\$@\" | bash '$CORE_DIR/scripts/check-no-leakage.sh' --commits" _ "$@"
}

# ---------------------------------------------------------------------------
# Script contract: existence + clean scan
# ---------------------------------------------------------------------------

@test "check-no-leakage.sh exists and is executable" {
    _guard_fixture
    [ -f "$CORE_DIR/scripts/check-no-leakage.sh" ]
    [ -x "$CORE_DIR/scripts/check-no-leakage.sh" ]
}

@test "clean directory exits 0" {
    _guard_fixture
    echo "This file has no forbidden tokens — just universal content." \
        > "$SCAN/clean.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCAN"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Token matching: case-insensitive
# ---------------------------------------------------------------------------

@test "catches 'xyzzy-corp' (lowercase)" {
    _guard_fixture
    _check_file "See the xyzzy-corp documentation."
    [ "$status" -eq 1 ]
}

@test "catches 'Xyzzy-Corp' (title case)" {
    _guard_fixture
    _check_file "The Xyzzy-Corp platform."
    [ "$status" -eq 1 ]
}

@test "catches 'XYZZY-CORP' (uppercase)" {
    _guard_fixture
    _check_file "XYZZY-CORP CONFIDENTIAL"
    [ "$status" -eq 1 ]
}

@test "catches 'plugh' in prose" {
    _guard_fixture
    _check_file "The plugh service handles this."
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Word-boundary semantics: _ and - are non-word chars; alnum is a word char
# ---------------------------------------------------------------------------

@test "word boundary: 'plughing' does NOT match 'plugh'" {
    _guard_fixture
    _check_file "We are plughing along nicely."
    [ "$status" -eq 0 ]
}

@test "word boundary: 'xyzzy-corporate' does NOT match 'xyzzy-corp'" {
    _guard_fixture
    _check_file "A xyzzy-corporate strategy document."
    [ "$status" -eq 0 ]
}

@test "word boundary: 'xyzzy-corp_secrets' DOES match (underscore is not a word char)" {
    _guard_fixture
    _check_file "xyzzy-corp_secrets.json"
    [ "$status" -eq 1 ]
}

@test "word boundary: 'prefix-xyzzy-corp' DOES match (hyphen is not a word char)" {
    _guard_fixture
    _check_file "your-prefix-xyzzy-corp value"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Regex-special escaping: '.' in a token is literal
# ---------------------------------------------------------------------------

@test "catches 'xyzzy.example.com' (dot-containing token)" {
    _guard_fixture
    _check_file "see xyzzy.example.com endpoint"
    [ "$status" -eq 1 ]
}

@test "dot is literal: 'xyzzyzexamplezcom' does NOT match 'xyzzy.example.com'" {
    _guard_fixture
    _check_file "the string xyzzyzexamplezcom is harmless"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Tokens inside code blocks, frontmatter, comments still caught
# ---------------------------------------------------------------------------

@test "token inside markdown fenced code block is caught" {
    _guard_fixture
    _check_file '```bash
# Connect to xyzzy-corp services
curl https://xyzzy.example.com/api
```'
    [ "$status" -eq 1 ]
}

@test "token inside YAML frontmatter is caught" {
    _guard_fixture
    _check_file '---
owner: user@xyzzy-corp.example
---
Content here.'
    [ "$status" -eq 1 ]
}

@test "token inside shell comment is caught" {
    _guard_fixture
    _check_file '#!/usr/bin/env bash
# Uses the plugh MCP for campaign data'
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Token list is data: appending to the (fixture) list changes behavior
# ---------------------------------------------------------------------------

@test "new token appended to the tokens file is picked up" {
    _guard_fixture
    echo "grault-sentinel" >> "$GUARD/leakage-tokens.txt"
    _check_file "grault-sentinel appears in this file"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Redaction: findings name locations only — matched content is never printed
# ---------------------------------------------------------------------------

@test "failure output names the file but never the matched token" {
    _guard_fixture
    _check_file "This contains xyzzy-corp somewhere."
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "subject.txt"
    ! echo "$output" | grep -q "xyzzy-corp"
}

# ---------------------------------------------------------------------------
# .git/ is excluded from directory scans
# ---------------------------------------------------------------------------

@test ".git directory is excluded from leakage scan" {
    _guard_fixture
    mkdir -p "$SCAN/.git"
    echo "xyzzy-corp is here" > "$SCAN/.git/config_hack"
    echo "clean content only" > "$SCAN/clean.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCAN"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Marker gate: absent marker means this machine cannot possess the token
# list — skip cleanly. Present marker with missing/empty list fails closed.
# ---------------------------------------------------------------------------

@test "marker absent: skips with exit 0 even when a leaky file is present" {
    _guard_fixture
    export LEAKAGE_MARKER_FILE="$GUARD/absent"
    _check_file "xyzzy-corp would match if the scan ran"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "skipped"
}

@test "marker present + tokens file missing: fail closed with exit 2" {
    _guard_fixture
    export LEAKAGE_TOKENS_FILE="$GUARD/no-such-tokens.txt"
    _check_file "any content"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "ERROR"
}

@test "marker present + comments-only tokens file: fail closed with exit 2" {
    _guard_fixture
    cat > "$GUARD/leakage-tokens.txt" <<'EOF'
# only comments in here

# nothing effective
EOF
    _check_file "any content"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "ERROR"
}

# ---------------------------------------------------------------------------
# --commits mode: scan each commit's full tree plus its metadata
# ---------------------------------------------------------------------------

@test "--commits: clean commit exits 0" {
    _guard_fixture
    _git_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "add notes"
    _check_commits "$(git -C "$REPO" rev-parse HEAD)"
    [ "$status" -eq 0 ]
}

@test "--commits: leaky tree exits 1 and names the path, not the token" {
    _guard_fixture
    _git_fixture
    echo "xyzzy-corp lives in this file" > "$REPO/notes.txt"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "add notes"
    _check_commits "$(git -C "$REPO" rev-parse HEAD)"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "notes.txt"
    ! echo "$output" | grep -q "xyzzy-corp"
}

@test "--commits: token only in the commit message exits 1" {
    _guard_fixture
    _git_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "integrate with xyzzy-corp systems"
    _check_commits "$(git -C "$REPO" rev-parse HEAD)"
    [ "$status" -eq 1 ]
}

@test "--commits: token in the author email exits 1" {
    _guard_fixture
    _git_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add -A
    git -C "$REPO" -c user.email="dev@xyzzy-corp.example" commit -qm "clean message"
    _check_commits "$(git -C "$REPO" rev-parse HEAD)"
    [ "$status" -eq 1 ]
}

@test "--commits: token added then removed across two commits still exits 1" {
    _guard_fixture
    _git_fixture
    echo "xyzzy-corp was here" > "$REPO/leaky.txt"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "first"
    local sha1
    sha1="$(git -C "$REPO" rev-parse HEAD)"
    git -C "$REPO" rm -q leaky.txt
    git -C "$REPO" commit -qm "second"
    local sha2
    sha2="$(git -C "$REPO" rev-parse HEAD)"
    _check_commits "$sha1" "$sha2"
    [ "$status" -eq 1 ]
}

@test "--commits: empty stdin exits 0" {
    _guard_fixture
    _git_fixture
    run bash -c "cd '$REPO' && printf '' | bash '$CORE_DIR/scripts/check-no-leakage.sh' --commits"
    [ "$status" -eq 0 ]
}

@test "--commits: garbage SHA exits 2" {
    _guard_fixture
    _git_fixture
    echo "clean content" > "$REPO/notes.txt"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "add notes"
    _check_commits "not-a-real-sha"
    [ "$status" -eq 2 ]
}
