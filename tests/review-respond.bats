#!/usr/bin/env bats
# Unit and integration tests for the /review-respond deterministic helper:
#   .claude/skills/review-respond/scripts/review-respond.sh
#
# CLI CONTRACT these tests pin:
#   review-respond.sh <subcommand> [flags]
#
#   threads        --graphql <file> | --rest <file>
#                    -> JSON array of normalized threads (all reviews)
#   select-review  --reviews <file> --threads <file> --author <login> [--review <id>]
#                    -> "<review_id>" | "NONE:no-qualifying-review" | "NONE:review-not-found"
#   commits        --base <sha> [--head <ref>] [--repo-dir <dir>]
#                    -> JSON array of commits | "ERROR:base-missing" | "ERROR:base-not-ancestor" (exit 3)
#   map-threads    --threads <file> --review <id> --commits <file> [--window <n>]
#                    -> {"threads":[...], "unlinked_commits":[...], "commits":[...]}
#   classify       --map <file>
#                    -> same JSON, each thread gains "class", "proposed", optional "suggested"
#   dismissed      --reviews <file> --head <sha> [--timeline <file>] [--review-decision <s>]
#                    -> "NEEDS_LOOK:<login>[,<login>]" | "OK"
#   find-prior     --comments <file> --review <id> --me <login>
#                    -> "<issue_comment_id>" | "NONE"
#   detect-checks  --dir <dir>
#                    -> JSON array [{kind,label,cmd,runner}]
#   parse-test-output --runner <vitest|jest|pytest|bats|phpunit|go>   (log on stdin)
#                    -> {"runner","files","tests_passed","tests_failed","parsed"}
#   render         --input <file>
#                    -> markdown on stdout (exit 0) | "REFUSE:<reason>" (exit 2)
#
#   Exit codes: 0 ok/decision token; 1 usage or malformed input; 2 render refusal;
#   3 git precondition. No subcommand calls gh or the network; only `commits`
#   reads git, read-only.
#
# Fixtures are neutral: github.example.com, acme/widgets, alice (author),
# bob/carol (reviewers). Pure subcommands get inline JSON; `commits` runs
# against a real scratch git repo and `detect-checks` against real scratch
# manifest directories.
#
# Run with: bats tests/review-respond.bats

setup() {
    TEST_HOME="$(mktemp -d)"
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    export RR="$DOTFILES_DIR/.claude/skills/review-respond/scripts/review-respond.sh"

    # Scratch git repos must not see the developer's git config.
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1

    # A PATH holding only bash, to prove the jq guard without uninstalling jq.
    NOJQ_PATH="$TEST_HOME/nojq-bin"
    export NOJQ_PATH
    mkdir -p "$NOJQ_PATH"
    ln -sf "$(command -v bash)" "$NOJQ_PATH/bash"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Fixture builders. Hosts and logins are neutral by rule: github.example.com,
# acme/widgets, alice (PR author), bob and carol (reviewers).
# ---------------------------------------------------------------------------

PR_URL="https://github.example.com/acme/widgets/pull/7"

# `gh api graphql --paginate --slurp` output: an ARRAY of page objects. Four
# thread nodes across two pages; the last node has no comments and is dropped.
_fx_threads_graphql_pages() {
    cat <<'JSON'
[
  {"data":{"repository":{"pullRequest":{"reviewThreads":{
    "pageInfo":{"hasNextPage":true,"endCursor":"c1"},
    "nodes":[
      {"id":"PRRT_1","isResolved":false,"isOutdated":false,"path":"src/a.ts","line":42,"originalLine":40,
       "comments":{"nodes":[{"databaseId":101,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r101",
                              "body":"Nit: rename this","pullRequestReview":{"databaseId":900}}]}},
      {"id":"PRRT_2","isResolved":true,"isOutdated":true,"path":"src/b.ts","line":null,"originalLine":12,
       "comments":{"nodes":[{"databaseId":102,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r102",
                              "body":"Handle the null case","pullRequestReview":{"databaseId":900}}]}}
    ]}}}}},
  {"data":{"repository":{"pullRequest":{"reviewThreads":{
    "pageInfo":{"hasNextPage":false,"endCursor":null},
    "nodes":[
      {"id":"PRRT_3","isResolved":false,"isOutdated":false,"path":"README.md","line":3,"originalLine":3,
       "comments":{"nodes":[{"databaseId":103,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r103",
                              "body":"Typo","pullRequestReview":{"databaseId":901}}]}},
      {"id":"PRRT_4","isResolved":false,"isOutdated":false,"path":"src/c.ts","line":9,"originalLine":9,
       "comments":{"nodes":[]}}
    ]}}}}}
]
JSON
}

# One page object (the non-slurped shape).
_fx_threads_graphql_single() {
    _fx_threads_graphql_pages | jq '.[0]'
}

# `gh api pulls/7/comments --paginate --slurp` output: an array of arrays.
# 201 is a reply to 101 and must be dropped.
_fx_comments_rest_pages() {
    cat <<'JSON'
[
  [
    {"id":101,"pull_request_review_id":900,"path":"src/a.ts","line":42,"original_line":40,
     "commit_id":"bbb","original_commit_id":"aaa","body":"Nit: rename this",
     "html_url":"https://github.example.com/acme/widgets/pull/7#discussion_r101","user":{"login":"bob"}},
    {"id":201,"pull_request_review_id":900,"in_reply_to_id":101,"path":"src/a.ts","line":42,"original_line":40,
     "body":"Done","html_url":"https://github.example.com/acme/widgets/pull/7#discussion_r201","user":{"login":"alice"}}
  ],
  [
    {"id":102,"pull_request_review_id":900,"path":"src/b.ts","line":null,"original_line":12,
     "commit_id":"bbb","original_commit_id":"aaa","body":"Handle the null case",
     "html_url":"https://github.example.com/acme/widgets/pull/7#discussion_r102","user":{"login":"bob"}}
  ]
]
JSON
}

# `pulls/7/reviews` after `jq add`: a flat array. alice is the PR author.
_fx_reviews() {
    cat <<'JSON'
[
  {"id":800,"user":{"login":"alice","type":"User"},"state":"COMMENTED","submitted_at":"2026-10-01T10:00:00Z","commit_id":"aaa0000000000000000000000000000000000000"},
  {"id":900,"user":{"login":"bob","type":"User"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-02T10:00:00Z","commit_id":"aaa0000000000000000000000000000000000000"}
]
JSON
}

# Normalized threads (the `threads` output shape) for select-review tests.
# $1 = review_id, $2 = is_resolved JSON literal (true|false|null)
_fx_norm_thread() {
    jq -n --argjson rid "$1" --argjson res "$2" '{thread_id:"PRRT_x",comment_id:(100+$rid),review_id:$rid,path:"src/a.ts",line:42,original_line:40,is_resolved:$res,is_outdated:false,url:"https://github.example.com/acme/widgets/pull/7#discussion_r101",body:"x"}'
}

_write() {
    # $1 = file name under TEST_HOME; stdin = content
    cat > "$TEST_HOME/$1"
}

# ---------------------------------------------------------------------------
# Skeleton: usage, dispatch, jq guard
# ---------------------------------------------------------------------------

@test "no subcommand prints usage and exits 1" {
    run "$RR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"review-respond.sh <subcommand>"* ]]
}

@test "unknown subcommand exits 1 naming it" {
    run "$RR" frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown subcommand: frobnicate"* ]]
}

@test "unknown flag exits 1 naming it" {
    run "$RR" threads --bogus x
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown argument: --bogus"* ]]
}

@test "a flag without a value exits 1 with a clear message" {
    run "$RR" threads --graphql
    [ "$status" -eq 1 ]
    [[ "$output" == *"--graphql needs a value"* ]]
}

@test "missing jq on PATH exits 1 with a clear message" {
    run bash -c 'PATH="$NOJQ_PATH" bash "$RR" threads --graphql /dev/null'
    [ "$status" -eq 1 ]
    [[ "$output" == *"jq is required"* ]]
}

@test "every contract subcommand is dispatched (not reported as unknown)" {
    [ -x "$RR" ] || {
        echo "helper script missing or not executable: $RR"
        return 1
    }
    local sub
    for sub in threads select-review commits map-threads classify dismissed find-prior detect-checks parse-test-output render; do
        run "$RR" "$sub"
        [[ "$output" != *"unknown subcommand"* ]] || {
            echo "subcommand not wired into dispatch: $sub"
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# threads — GraphQL and REST normalization
# ---------------------------------------------------------------------------

@test "threads --graphql flattens a slurped multi-page response" {
    _fx_threads_graphql_pages | _write pages.json
    run "$RR" threads --graphql "$TEST_HOME/pages.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq 'length')" = "3" ]
    [ "$(echo "$output" | jq -c 'map(.comment_id)')" = "[101,102,103]" ]
    [ "$(echo "$output" | jq -c 'map(.thread_id)')" = '["PRRT_1","PRRT_2","PRRT_3"]' ]
    [ "$(echo "$output" | jq -c 'map(.review_id)')" = "[900,900,901]" ]
    [ "$(echo "$output" | jq -r '.[0].url')" = "$PR_URL#discussion_r101" ]
    [ "$(echo "$output" | jq -r '.[0].body')" = "Nit: rename this" ]
    [ "$(echo "$output" | jq -r '.[0].path')" = "src/a.ts" ]
}

@test "threads --graphql accepts a single response object" {
    _fx_threads_graphql_single | _write single.json
    run "$RR" threads --graphql "$TEST_HOME/single.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.comment_id)')" = "[101,102]" ]
}

@test "threads --graphql maps originalLine to original_line and keeps line null when outdated" {
    _fx_threads_graphql_pages | _write pages.json
    run "$RR" threads --graphql "$TEST_HOME/pages.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.[1] | [.line, .original_line, .is_outdated, .is_resolved]')" = "[null,12,true,true]" ]
    [ "$(echo "$output" | jq -c '.[0] | [.line, .original_line, .is_outdated, .is_resolved]')" = "[42,40,false,false]" ]
}

@test "threads --rest keeps top-level comments only and sets is_resolved null" {
    _fx_comments_rest_pages | _write comments.json
    run "$RR" threads --rest "$TEST_HOME/comments.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.comment_id)')" = "[101,102]" ]
    [ "$(echo "$output" | jq -c 'map(.is_resolved)')" = "[null,null]" ]
    [ "$(echo "$output" | jq -c 'map(.is_outdated)')" = "[false,true]" ]
    [ "$(echo "$output" | jq -c 'map(.review_id)')" = "[900,900]" ]
    [ "$(echo "$output" | jq -c '.[1] | [.line, .original_line]')" = "[null,12]" ]
    [ "$(echo "$output" | jq -r '.[0].url')" = "$PR_URL#discussion_r101" ]
}

@test "threads --rest accepts an already-flat comment array" {
    _fx_comments_rest_pages | jq 'add' | _write flat.json
    run "$RR" threads --rest "$TEST_HOME/flat.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.comment_id)')" = "[101,102]" ]
}

# ---------------------------------------------------------------------------
# select-review
# ---------------------------------------------------------------------------

@test "select-review picks the latest CHANGES_REQUESTED non-author review" {
    _fx_reviews | jq '. + [{"id":901,"user":{"login":"carol","type":"User"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-03T10:00:00Z","commit_id":"aaa"}]' | _write reviews.json
    echo '[]' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "901" ]
}

@test "select-review picks an APPROVED-then-DISMISSED review that still has unresolved threads" {
    _fx_reviews | jq '.[1].state = "DISMISSED" | . + [{"id":901,"user":{"login":"carol","type":"User"},"state":"COMMENTED","submitted_at":"2026-10-03T10:00:00Z","commit_id":"aaa"}]' | _write reviews.json
    { _fx_norm_thread 900 false; _fx_norm_thread 901 true; } | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "select-review ignores the PR author's own reviews" {
    _fx_reviews | jq '. + [{"id":905,"user":{"login":"alice","type":"User"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-07T10:00:00Z","commit_id":"aaa"}]' | _write reviews.json
    echo '[]' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "select-review ignores Bot reviewers and PENDING reviews" {
    _fx_reviews | jq '. + [
        {"id":902,"user":{"login":"widget-bot[bot]","type":"Bot"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-04T10:00:00Z","commit_id":"aaa"},
        {"id":903,"user":{"login":"bob","type":"User"},"state":"PENDING","submitted_at":null,"commit_id":"aaa"}]' | _write reviews.json
    _fx_norm_thread 903 false | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "select-review skips a COMMENTED review whose threads are all resolved" {
    _fx_reviews | jq '. + [{"id":904,"user":{"login":"carol","type":"User"},"state":"COMMENTED","submitted_at":"2026-10-06T10:00:00Z","commit_id":"aaa"}]' | _write reviews.json
    { _fx_norm_thread 904 true; _fx_norm_thread 904 true; } | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "select-review treats null is_resolved as unresolved" {
    _fx_reviews | jq '. + [{"id":904,"user":{"login":"carol","type":"User"},"state":"COMMENTED","submitted_at":"2026-10-06T10:00:00Z","commit_id":"aaa"}]' | _write reviews.json
    _fx_norm_thread 904 null | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "904" ]
}

@test "select-review --review honors an explicit id" {
    _fx_reviews | _write reviews.json
    echo '[]' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice --review 800
    [ "$status" -eq 0 ]
    [ "$output" = "800" ]
}

@test "select-review --review unknown id prints NONE:review-not-found" {
    _fx_reviews | _write reviews.json
    echo '[]' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice --review 123456
    [ "$status" -eq 0 ]
    [ "$output" = "NONE:review-not-found" ]
}

@test "select-review with nothing qualifying prints NONE:no-qualifying-review" {
    _fx_reviews | jq '.[1].state = "COMMENTED"' | _write reviews.json
    _fx_norm_thread 900 true | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "NONE:no-qualifying-review" ]
}

@test "select-review accepts a slurped array-of-arrays reviews file" {
    _fx_reviews | jq '[.]' | _write reviews.json
    echo '[]' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

# ---------------------------------------------------------------------------
# commits — real git in a scratch repo (no mocks)
# ---------------------------------------------------------------------------

_g() { git -C "$REPO" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }

_mkrepo() {
    REPO="$TEST_HOME/repo"
    export REPO
    git init -q "$REPO"
    _g symbolic-ref HEAD refs/heads/main
}

# Stage everything, commit with $1 as the subject, print the new sha.
_commit_all() {
    _g add -A
    _g commit -q -m "$1"
    _g rev-parse HEAD
}

@test "commits lists commits after base in order with short sha, subject and type" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    base="$(_commit_all 'chore: seed')"
    echo one > "$REPO/a.txt"
    c1="$(_commit_all 'fix(core): first change')"
    echo two > "$REPO/README.md"
    c2="$(_commit_all 'feat(api)!: breaking second')"
    echo three > "$REPO/a.txt"
    c3="$(_commit_all 'Tweak things')"
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq 'length')" = "3" ]
    [ "$(echo "$output" | jq -r '.[0].sha')" = "$c1" ]
    [ "$(echo "$output" | jq -r '.[1].sha')" = "$c2" ]
    [ "$(echo "$output" | jq -r '.[2].sha')" = "$c3" ]
    [ "$(echo "$output" | jq -r '.[0].short')" = "$(_g rev-parse --short "$c1")" ]
    [ "$(echo "$output" | jq -c 'map(.subject)')" = '["fix(core): first change","feat(api)!: breaking second","Tweak things"]' ]
    [ "$(echo "$output" | jq -c 'map(.type)')" = '["fix","feat",""]' ]
    [ "$(echo "$output" | jq -r '.[0].files[0].path')" = "a.txt" ]
}

@test "commits honours --head to stop before the branch tip" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    base="$(_commit_all 'chore: seed')"
    echo one > "$REPO/a.txt"
    c1="$(_commit_all 'fix: one')"
    echo two > "$REPO/a.txt"
    _commit_all 'fix: two' >/dev/null
    run "$RR" commits --base "$base" --head main~1 --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.sha)')" = "[\"$c1\"]" ]
}

@test "commits parses single-line and ranged hunk headers" {
    _mkrepo
    seq 1 50 > "$REPO/fifty.txt"
    base="$(_commit_all 'chore: seed')"
    sed -e 's/^20$/twenty/' -e '40d' "$REPO/fifty.txt" > "$REPO/fifty.tmp"
    mv "$REPO/fifty.tmp" "$REPO/fifty.txt"
    _commit_all 'fix: edit 20 and drop 40' >/dev/null
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.[0].files[0].hunks')" = '[{"old_start":20,"old_len":1,"new_start":20,"new_len":1},{"old_start":40,"old_len":1,"new_start":39,"new_len":0}]' ]
}

@test "commits parses a multi-line hunk with both counts" {
    _mkrepo
    seq 1 10 > "$REPO/ten.txt"
    base="$(_commit_all 'chore: seed')"
    { seq 1 2; echo a; echo b; echo c; seq 6 10; } > "$REPO/ten.txt"
    _commit_all 'fix: replace 3-5 with a-c' >/dev/null
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.[0].files[0].hunks')" = '[{"old_start":3,"old_len":3,"new_start":3,"new_len":3}]' ]
}

@test "commits records multiple files per commit" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    base="$(_commit_all 'chore: seed')"
    echo one > "$REPO/a.txt"
    echo two > "$REPO/b.txt"
    _commit_all 'fix: touch two files' >/dev/null
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.[0].files | map(.path) | sort')" = '["a.txt","b.txt"]' ]
    [ "$(echo "$output" | jq -c '.[0].files | map(.hunks | length)')" = '[1,1]' ]
}

@test "commits records a deleted file under its old path with a zero-length new side" {
    _mkrepo
    echo gone > "$REPO/gone.txt"
    echo keep > "$REPO/keep.txt"
    base="$(_commit_all 'chore: seed')"
    _g rm -q gone.txt
    _commit_all 'chore: delete gone' >/dev/null
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.[0].files')" = '[{"path":"gone.txt","hunks":[{"old_start":1,"old_len":1,"new_start":0,"new_len":0}]}]' ]
}

@test "commits excludes merge commits and merged-in side commits" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    base="$(_commit_all 'chore: seed')"
    echo main1 > "$REPO/a.txt"
    m1="$(_commit_all 'fix: on main')"
    _g checkout -q -b side "$base"
    echo side1 > "$REPO/side.txt"
    _commit_all 'feat: on side' >/dev/null
    _g checkout -q main
    _g merge -q --no-ff -m 'Merge branch side' side
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.sha)')" = "[\"$m1\"]" ]
}

@test "commits prints ERROR:base-missing exit 3 for an unknown sha" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    _commit_all 'chore: seed' >/dev/null
    run "$RR" commits --base 0000000000000000000000000000000000000001 --repo-dir "$REPO"
    [ "$status" -eq 3 ]
    [ "$output" = "ERROR:base-missing" ]
}

@test "commits prints ERROR:base-not-ancestor exit 3 after history rewrite" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    base="$(_commit_all 'chore: seed')"
    echo one > "$REPO/a.txt"
    old="$(_commit_all 'fix: reviewed then rewritten')"
    _g reset -q --hard "$base"
    echo one-rewritten > "$REPO/a.txt"
    _commit_all 'fix: rewritten' >/dev/null
    run "$RR" commits --base "$old" --repo-dir "$REPO"
    [ "$status" -eq 3 ]
    [ "$output" = "ERROR:base-not-ancestor" ]
}

@test "commits on an empty range prints []" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    head="$(_commit_all 'chore: seed')"
    run "$RR" commits --base "$head" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = "[]" ]
}

@test "commits handles a path with spaces" {
    _mkrepo
    echo hello > "$REPO/my file.txt"
    base="$(_commit_all 'chore: seed')"
    echo 'hello world' > "$REPO/my file.txt"
    _commit_all 'fix: spaced path' >/dev/null
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.[0].files[0].path')" = "my file.txt" ]
    [ "$(echo "$output" | jq -c '.[0].files[0].hunks')" = '[{"old_start":1,"old_len":1,"new_start":1,"new_len":1}]' ]
}

@test "commits output is unaffected by diff.noprefix and diff.external in the repo config" {
    _mkrepo
    echo seed > "$REPO/a.txt"
    base="$(_commit_all 'chore: seed')"
    echo one > "$REPO/a.txt"
    _commit_all 'fix: one' >/dev/null
    _g config diff.noprefix true
    _g config diff.external /bin/false
    _g config color.ui always
    run "$RR" commits --base "$base" --repo-dir "$REPO"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.[0].files[0].path')" = "a.txt" ]
    [ "$(echo "$output" | jq -c '.[0].files[0].hunks')" = '[{"old_start":1,"old_len":1,"new_start":1,"new_len":1}]' ]
}
