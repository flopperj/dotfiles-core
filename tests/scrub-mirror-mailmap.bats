#!/usr/bin/env bats
# Tests for the identity (mailmap) half of scripts/scrub-mirror-history.sh
#
# Mechanism tests only — every address below is synthetic. The real mailmap is
# data, not code: it lives outside every repo working tree and is never
# referenced here. SCRUB_MAILMAP_FILE is pinned in every test so a developer
# machine with a real mailmap installed and CI without one agree.

load 'test_helper'

SCRUB="$DOTFILES_DIR/scripts/scrub-mirror-history.sh"

# A repo with three commits: two under a "company" identity (one of them with a
# second company address as committer), one already public.
_repo_fixture() {
    REPO="$SCRATCH/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" config user.name "Dev"

    git -C "$REPO" config user.email "dev@xyzzy.example.com"
    echo one > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    git -C "$REPO" commit -q -m "one"

    echo two > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    GIT_COMMITTER_EMAIL="bot@xyzzy.example.com" GIT_COMMITTER_NAME="Bot" \
        git -C "$REPO" commit -q -m "two"

    git -C "$REPO" config user.email "dev@users.noreply.example.com"
    echo three > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    git -C "$REPO" commit -q -m "three"
}

# Pin the allowlist too: the fixture's public identity is under example.com.
export SCRUB_ALLOWED_EMAIL_DOMAINS="users.noreply.example.com"

_mailmap_fixture() {
    MAILMAP="$SCRATCH/mirror-mailmap"
    cat > "$MAILMAP" <<'EOF'
# synthetic mailmap — mechanism tests only
Dev <dev@users.noreply.example.com> <dev@xyzzy.example.com>
Dev <dev@users.noreply.example.com> <bot@xyzzy.example.com>
EOF
    export SCRUB_MAILMAP_FILE="$MAILMAP"
}

_identity_fields() {
    git -C "$REPO" log --all --format='%ae%n%ce'
}

@test "audit counts identity fields per mailmap source without printing addresses" {
    _repo_fixture
    _mailmap_fixture
    run bash "$SCRUB" audit "$REPO"
    # dev@xyzzy: author+committer on "one", author on "two" = 3; bot@xyzzy: committer on "two" = 1
    [[ "$output" == *"mailmap source 1: 3 identity field(s) match"* ]] || return 1
    [[ "$output" == *"mailmap source 2: 1 identity field(s) match"* ]] || return 1
    [[ "$output" == *"total matching identity fields: 4"* ]] || return 1
    [[ "$output" != *"xyzzy.example.com"* ]] || return 1
}

@test "audit exits non-zero while company identities remain" {
    _repo_fixture
    _mailmap_fixture
    run bash "$SCRUB" audit "$REPO"
    [ "$status" -ne 0 ] || return 1
}

@test "audit without a mailmap file skips the mailmap pass but still fails on unlisted domains" {
    _repo_fixture
    export SCRUB_MAILMAP_FILE="$SCRATCH/does-not-exist"
    run bash "$SCRUB" audit "$REPO"
    [[ "$output" == *"no mailmap file"* ]] || return 1
    # The allowlist pass does not need a mailmap and the fixture has company identities.
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"4 identity field(s) across 1 unlisted domain(s)"* ]] || return 1
}

@test "scrub rewrites every mapped identity and the audit then passes" {
    command -v git-filter-repo >/dev/null 2>&1 || skip "git-filter-repo not installed"
    _repo_fixture
    _mailmap_fixture
    run bash "$SCRUB" scrub "$REPO"
    [ "$status" -eq 0 ] || return 1
    # No company address survives in any author or committer field.
    ! _identity_fields | grep -q 'xyzzy.example.com' || return 1
    # All six fields (3 commits x author+committer) now carry the public address.
    [ "$(_identity_fields | grep -cxF 'dev@users.noreply.example.com')" -eq 6 ] || return 1
    [[ "$output" == *"total matching identity fields: 0"* ]] || return 1
    # Tree content is untouched by an identity rewrite.
    [ "$(git -C "$REPO" show HEAD:a.txt)" = "three" ] || return 1
}

@test "scrub without a mailmap warns and still runs the path rewrite" {
    command -v git-filter-repo >/dev/null 2>&1 || skip "git-filter-repo not installed"
    _repo_fixture
    export SCRUB_MAILMAP_FILE="$SCRATCH/does-not-exist"
    run bash "$SCRUB" scrub "$REPO"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"identities will NOT be rewritten"* ]] || return 1
    [ "$(_identity_fields | grep -c 'xyzzy.example.com')" -eq 4 ] || return 1
    [[ "$output" == *"audit still reports identities"* ]] || return 1
}

@test "mailmap source parsing ignores comments and name-only entries" {
    _repo_fixture
    MAILMAP="$SCRATCH/mirror-mailmap"
    cat > "$MAILMAP" <<'EOF'
# comment line
Proper Name <dev@users.noreply.example.com>
   # indented comment line
Dev <dev@users.noreply.example.com> <dev@xyzzy.example.com>
EOF
    export SCRUB_MAILMAP_FILE="$MAILMAP"
    run bash "$SCRUB" audit "$REPO"
    [[ "$output" == *"mailmap source 1: 3 identity field(s) match"* ]] || return 1
    [[ "$output" != *"mailmap source 2:"* ]] || return 1
}

# ---------------------------------------------------------------------------
# False-all-clear cases the mailmap pass alone cannot catch
# ---------------------------------------------------------------------------

@test "audit flags an unmapped company identity via the allowlist pass" {
    _repo_fixture
    # Mailmap covers dev@ but not bot@ — the mailmap pass alone would miss bot@.
    MAILMAP="$SCRATCH/mirror-mailmap"
    echo 'Dev <dev@users.noreply.example.com> <dev@xyzzy.example.com>' > "$MAILMAP"
    export SCRUB_MAILMAP_FILE="$MAILMAP"
    run bash "$SCRUB" audit "$REPO"
    [ "$status" -ne 0 ] || return 1
    # 4 fields from xyzzy.example.com (dev x3, bot x1), one unlisted domain.
    [[ "$output" == *"4 identity field(s) across 1 unlisted domain(s)"* ]] || return 1
    [[ "$output" != *"xyzzy.example.com"* ]] || return 1
}

@test "allowlist pass withholds domains unless SCRUB_SHOW_UNLISTED=1" {
    _repo_fixture
    _mailmap_fixture
    SCRUB_SHOW_UNLISTED=1 run bash "$SCRUB" audit "$REPO"
    [[ "$output" == *"xyzzy.example.com"* ]] || return 1
}

@test "allowlist pass matches domains case-insensitively" {
    _repo_fixture
    _mailmap_fixture
    export SCRUB_ALLOWED_EMAIL_DOMAINS="Users.NoReply.Example.COM xyzzy.example.com"
    run bash "$SCRUB" audit "$REPO"
    [[ "$output" == *"all identity fields use allowed domains"* ]] || return 1
}

@test "audit counts annotated-tag tagger identities" {
    _repo_fixture
    _mailmap_fixture
    export SCRUB_ALLOWED_EMAIL_DOMAINS="users.noreply.example.com xyzzy.example.com"
    GIT_COMMITTER_EMAIL="tagger@plugh.example.com" GIT_COMMITTER_NAME="Tagger" \
        git -C "$REPO" tag -a v0.1 -m "tag" HEAD
    run bash "$SCRUB" audit "$REPO"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"1 identity field(s) across 1 unlisted domain(s)"* ]] || return 1
}

@test "CRLF mailmap is parsed and still matches" {
    _repo_fixture
    MAILMAP="$SCRATCH/mirror-mailmap"
    printf 'Dev <dev@users.noreply.example.com> <dev@xyzzy.example.com>\r\n' > "$MAILMAP"
    export SCRUB_MAILMAP_FILE="$MAILMAP"
    run bash "$SCRUB" audit "$REPO"
    [[ "$output" == *"mailmap source 1: 3 identity field(s) match"* ]] || return 1
}

@test "mailmap with no mapping lines is an error, not a clean audit" {
    _repo_fixture
    MAILMAP="$SCRATCH/mirror-mailmap"
    printf '# comments only\nProper Name <dev@users.noreply.example.com>\n' > "$MAILMAP"
    export SCRUB_MAILMAP_FILE="$MAILMAP"
    run bash "$SCRUB" audit "$REPO"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"no mapping lines"* ]] || return 1
}

@test "a '#' inside an address is not treated as a comment" {
    _repo_fixture
    MAILMAP="$SCRATCH/mirror-mailmap"
    echo 'Dev <dev@users.noreply.example.com> <weird#tag@xyzzy.example.com>' > "$MAILMAP"
    export SCRUB_MAILMAP_FILE="$MAILMAP"
    run bash "$SCRUB" audit "$REPO"
    [[ "$output" == *"mailmap source 1: 0 identity field(s) match"* ]] || return 1
}

@test "audit passes on a fully clean repo" {
    REPO="$SCRATCH/clean"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" -c user.name=Dev -c user.email=dev@users.noreply.example.com commit -q --allow-empty -m clean
    _mailmap_fixture
    run bash "$SCRUB" audit "$REPO"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"total matching identity fields: 0"* ]] || return 1
    [[ "$output" == *"all identity fields use allowed domains"* ]] || return 1
}
