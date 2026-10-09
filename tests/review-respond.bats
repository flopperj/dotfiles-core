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
    # The newest review is placed first so that only submitted_at, not input
    # order, can make it the pick.
    _fx_reviews | jq '[{"id":901,"user":{"login":"carol","type":"User"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-03T10:00:00Z","commit_id":"aaa"}] + .' | _write reviews.json
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
    # GitHub reports submitted_at null for a PENDING review; this fixture dates
    # it after bob's so that only the state filter, not the sort key, excludes it.
    _fx_reviews | jq '. + [
        {"id":902,"user":{"login":"widget-bot[bot]","type":"Bot"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-04T10:00:00Z","commit_id":"aaa"},
        {"id":903,"user":{"login":"bob","type":"User"},"state":"PENDING","submitted_at":"2026-10-05T10:00:00Z","commit_id":"aaa"}]' | _write reviews.json
    _fx_norm_thread 903 false | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "900" ]
}

@test "select-review with only bot and PENDING reviews prints NONE:no-qualifying-review" {
    _fx_reviews | jq '.[1].state = "COMMENTED" | . + [
        {"id":902,"user":{"login":"widget-bot[bot]","type":"Bot"},"state":"CHANGES_REQUESTED","submitted_at":"2026-10-04T10:00:00Z","commit_id":"aaa"},
        {"id":903,"user":{"login":"bob","type":"User"},"state":"PENDING","submitted_at":null,"commit_id":"aaa"}]' | _write reviews.json
    { _fx_norm_thread 900 true; _fx_norm_thread 903 false; } | jq -s '.' | _write threads.json
    run "$RR" select-review --reviews "$TEST_HOME/reviews.json" --threads "$TEST_HOME/threads.json" --author alice
    [ "$status" -eq 0 ]
    [ "$output" = "NONE:no-qualifying-review" ]
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

# ---------------------------------------------------------------------------
# map-threads and classify
# ---------------------------------------------------------------------------

# Threads for two reviews (900 is the one under test) and five commits:
#   aaa1111 fix   src/a.ts @40      -> overlaps thread 101 (orig 40, line 42)
#   bbb2222 docs  README.md @3      -> only touches review 901's thread: unlinked
#   ccc3333 fix   src/b.ts @12,0    -> insertion anchored at 12: overlaps 102
#   ddd4444 chore src/a.ts src/b.ts src/z.ts @1 -> touches 101/102, no overlap
#   eee5555 feat  src/unrelated.ts  -> unlinked
_fx_map_threads() {
    cat <<'JSON'
[
  {"thread_id":"PRRT_1","comment_id":101,"review_id":900,"path":"src/a.ts","line":42,"original_line":40,"is_resolved":false,"is_outdated":false,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r101","body":"Nit: rename this"},
  {"thread_id":"PRRT_2","comment_id":102,"review_id":900,"path":"src/b.ts","line":null,"original_line":12,"is_resolved":false,"is_outdated":true,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r102","body":"Handle the null case"},
  {"thread_id":"PRRT_3","comment_id":103,"review_id":901,"path":"README.md","line":3,"original_line":3,"is_resolved":false,"is_outdated":false,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r103","body":"Typo"},
  {"thread_id":"PRRT_4","comment_id":104,"review_id":900,"path":"src/c.ts","line":100,"original_line":100,"is_resolved":false,"is_outdated":false,"url":"https://github.example.com/acme/widgets/pull/7#discussion_r104","body":"Untouched"}
]
JSON
}

_fx_map_commits() {
    cat <<'JSON'
[
  {"sha":"aaa1111aaa1111aaa1111aaa1111aaa1111aaa11","short":"aaa1111","subject":"fix(core): fix a","type":"fix",
   "files":[{"path":"src/a.ts","hunks":[{"old_start":40,"old_len":1,"new_start":40,"new_len":2}]}]},
  {"sha":"bbb2222bbb2222bbb2222bbb2222bbb2222bbb22","short":"bbb2222","subject":"docs: update readme","type":"docs",
   "files":[{"path":"README.md","hunks":[{"old_start":3,"old_len":1,"new_start":3,"new_len":1}]}]},
  {"sha":"ccc3333ccc3333ccc3333ccc3333ccc3333ccc33","short":"ccc3333","subject":"fix(b): null case","type":"fix",
   "files":[{"path":"src/b.ts","hunks":[{"old_start":12,"old_len":0,"new_start":13,"new_len":3}]}]},
  {"sha":"ddd4444ddd4444ddd4444ddd4444ddd4444ddd44","short":"ddd4444","subject":"chore: format everything","type":"chore",
   "files":[{"path":"src/a.ts","hunks":[{"old_start":1,"old_len":1,"new_start":1,"new_len":1}]},
            {"path":"src/b.ts","hunks":[{"old_start":1,"old_len":1,"new_start":1,"new_len":1}]},
            {"path":"src/z.ts","hunks":[{"old_start":1,"old_len":1,"new_start":1,"new_len":1}]}]},
  {"sha":"eee5555eee5555eee5555eee5555eee5555eee55","short":"eee5555","subject":"feat: unrelated","type":"feat",
   "files":[{"path":"src/unrelated.ts","hunks":[{"old_start":1,"old_len":1,"new_start":1,"new_len":1}]}]}
]
JSON
}

# One thread (review 900, comment 101) and one commit aaa1111 with one hunk on
# the same path, for pinning the overlap rule one parameter at a time.
# $1 path  $2 line (json)  $3 original_line (json)  $4-$7 old_start old_len new_start new_len
_map_case() {
    jq -n --arg p "$1" --argjson line "$2" --argjson ol "$3" \
        '[{thread_id:"PRRT_1",comment_id:101,review_id:900,path:$p,line:$line,original_line:$ol,is_resolved:false,is_outdated:($line==null),url:"https://github.example.com/acme/widgets/pull/7#discussion_r101",body:"x"}]' \
        > "$TEST_HOME/threads.json"
    jq -n --arg p "$1" --argjson os "$4" --argjson ol "$5" --argjson ns "$6" --argjson nl "$7" \
        '[{sha:"aaa1111aaa1111aaa1111aaa1111aaa1111aaa11",short:"aaa1111",subject:"fix: one",type:"fix",files:[{path:$p,hunks:[{old_start:$os,old_len:$ol,new_start:$ns,new_len:$nl}]}]}]' \
        > "$TEST_HOME/commits.json"
}

# A classify input with one thread and the given touching/overlapping lists
# over a fixed commits index: fix1 and fix2 are fixes, docs1 docs, chore1 chore.
_fx_map() {
    jq -n --argjson t "$1" --argjson o "$2" '{
      threads: [{thread_id:"PRRT_1",comment_id:101,review_id:900,path:"src/a.ts",line:42,original_line:40,
                 is_resolved:false,is_outdated:false,url:"https://github.example.com/acme/widgets/pull/7#discussion_r101",body:"x",
                 touching:$t,overlapping:$o}],
      unlinked_commits: [],
      commits: [
        {sha:"f1",short:"fix1",subject:"fix: first",type:"fix"},
        {sha:"f2",short:"fix2",subject:"fix: second",type:"fix"},
        {sha:"d1",short:"docs1",subject:"docs: readme",type:"docs"},
        {sha:"c1",short:"chore1",subject:"chore: deps",type:"chore"}]}'
}

_run_map() {
    run "$RR" map-threads --threads "$TEST_HOME/threads.json" --review 900 --commits "$TEST_HOME/commits.json" "$@"
}

@test "map-threads ignores threads from other reviews" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads | map(.comment_id)')" = "[101,102,104]" ]
}

@test "map-threads: a commit on another path does not touch" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[] | select(.comment_id == 104) | [.touching, .overlapping]')" = "[[],[]]" ]
}

@test "map-threads keeps touching and overlapping in commit order" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[] | select(.comment_id == 101) | [.touching, .overlapping]')" = '[["aaa1111","ddd4444"],["aaa1111"]]' ]
    [ "$(echo "$output" | jq -c '.threads[] | select(.comment_id == 102) | [.touching, .overlapping]')" = '[["ccc3333","ddd4444"],["ccc3333"]]' ]
}

@test "map-threads: overlap on original_line within window" {
    _map_case src/a.ts null 40 45 1 45 1
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0].overlapping')" = '["aaa1111"]' ]
}

@test "map-threads: overlap on current line via new-side range" {
    _map_case src/a.ts 42 10 60 1 40 3
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0].overlapping')" = '["aaa1111"]' ]
}

@test "map-threads: a hunk just outside the window touches but does not overlap" {
    _map_case src/a.ts null 40 46 1 46 1
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.threads[0].touching, .threads[0].overlapping]')" = '[["aaa1111"],[]]' ]
}

@test "map-threads --window 0 is exact" {
    _map_case src/a.ts null 40 41 1 41 1
    _run_map --window 0
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0].overlapping')" = '[]' ]
    _map_case src/a.ts null 40 40 1 40 1
    _run_map --window 0
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0].overlapping')" = '["aaa1111"]' ]
}

@test "map-threads: zero-length deletion hunk (old_len 0) still overlaps its anchor line" {
    _map_case src/b.ts null 12 12 0 13 3
    _run_map --window 0
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0].overlapping')" = '["aaa1111"]' ]
}

@test "map-threads: a null line never overlaps on the new side" {
    _map_case src/a.ts null 400 1 1 1 1
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.threads[0].touching, .threads[0].overlapping]')" = '[["aaa1111"],[]]' ]
}

@test "map-threads: unlinked_commits are commits touching no thread path" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.unlinked_commits')" = '["bbb2222","eee5555"]' ]
}

@test "map-threads carries a commits index for later steps" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    _run_map
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.commits | map(.short)')" = '["aaa1111","bbb2222","ccc3333","ddd4444","eee5555"]' ]
    [ "$(echo "$output" | jq -c '.commits[0] | keys')" = '["sha","short","subject","type"]' ]
}

@test "map-threads rejects a non-numeric --window" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    _run_map --window five
    [ "$status" -eq 1 ]
    [[ "$output" == *"--window must be a non-negative integer"* ]]
}

@test "classify: no touching commit gives untouched with needs_discussion" {
    _fx_map '[]' '[]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0] | [.class, .proposed]')" = '["untouched",{"outcome":"needs_discussion","detail":""}]' ]
    [ "$(echo "$output" | jq -c '.threads[0] | has("suggested")')" = "false" ]
}

@test "classify: exactly one overlapping commit gives candidate with proposed fixed and that sha" {
    _fx_map '["fix1","docs1"]' '["fix1"]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0] | [.class, .proposed]')" = '["candidate",{"outcome":"fixed","sha":"fix1","detail":"fix: first"}]' ]
}

@test "classify: two overlapping commits give ambiguous, never fixed" {
    _fx_map '["fix1","fix2"]' '["fix1","fix2"]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0] | [.class, .proposed]')" = '["ambiguous",{"outcome":"ambiguous"}]' ]
}

@test "classify: touching but none overlapping gives ambiguous" {
    _fx_map '["fix1"]' '[]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.threads[0].class')" = "ambiguous" ]
    [ "$(echo "$output" | jq -r '.threads[0].proposed.outcome')" = "ambiguous" ]
    [ "$(echo "$output" | jq -r '.threads[0].suggested')" = "fix1" ]
}

@test "classify: ambiguous with one non-docs candidate sets suggested but keeps class ambiguous" {
    _fx_map '["docs1","fix1","chore1"]' '["docs1","fix1","chore1"]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0] | [.class, .proposed.outcome, .suggested]')" = '["ambiguous","ambiguous","fix1"]' ]
}

@test "classify: ambiguous with two non-docs candidates sets no suggested" {
    _fx_map '["fix1","fix2","docs1"]' '["fix1","fix2","docs1"]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.threads[0] | [.class, has("suggested")]')" = '["ambiguous",false]' ]
}

@test "classify: suggestion considers overlapping commits only when any overlap" {
    _fx_map '["fix1","fix2","docs1"]' '["docs1","fix2"]' | _write map.json
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.threads[0].suggested')" = "fix2" ]
}

@test "classify preserves unlinked_commits and the commits index" {
    _fx_map_threads | _write threads.json
    _fx_map_commits | _write commits.json
    "$RR" map-threads --threads "$TEST_HOME/threads.json" --review 900 --commits "$TEST_HOME/commits.json" > "$TEST_HOME/map.json"
    run "$RR" classify --map "$TEST_HOME/map.json"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.unlinked_commits')" = '["bbb2222","eee5555"]' ]
    [ "$(echo "$output" | jq -c '.commits | length')" = "5" ]
    [ "$(echo "$output" | jq -c '.threads | map(.class)')" = '["candidate","candidate","untouched"]' ]
}

@test "classify never emits outcome fixed for an ambiguous or untouched thread" {
    local i=0 spec
    for spec in \
        '[] []' \
        '["fix1"] []' \
        '["fix1","fix2"] ["fix1","fix2"]' \
        '["docs1","fix1"] ["docs1","fix1"]' \
        '["fix1","fix2","docs1"] ["fix1","fix2","docs1"]' \
        '["docs1","chore1"] ["docs1","chore1"]' \
        '["docs1","chore1"] []' \
        '["fix1","docs1"] ["fix1"]' ; do
        # shellcheck disable=SC2086
        set -- $spec
        _fx_map "$1" "$2" > "$TEST_HOME/map-$i.json"
        i=$((i + 1))
    done
    [ "$i" -eq 8 ]
    local f violations=0 verdict
    for f in "$TEST_HOME"/map-*.json; do
        verdict="$("$RR" classify --map "$f" | jq -r '
            [.threads[] | select((.class == "ambiguous" or .class == "untouched") and .proposed.outcome == "fixed")] | length')"
        [ "$verdict" = "0" ] || violations=$((violations + 1))
    done
    [ "$violations" -eq 0 ]
}

# ---------------------------------------------------------------------------
# dismissed and find-prior
# ---------------------------------------------------------------------------

HEAD_SHA="ccc0000000000000000000000000000000000000"

# Reviews where bob's APPROVED review 900 was dismissed by a push.
_fx_reviews_dismissed() {
    _fx_reviews | jq '.[1].state = "DISMISSED"'
}

# A re-approval by $1 at commit $2 submitted at $3 (id 910).
_review_approved() {
    jq -n --arg login "$1" --arg sha "$2" --arg at "$3" \
        '{id:910,user:{login:$login,type:"User"},state:"APPROVED",submitted_at:$at,commit_id:$sha}'
}

# GraphQL timeline (single response object) with one ReviewDismissedEvent per
# "login:previousState" argument, all created at 2026-10-05T12:00:00Z.
_fx_timeline() {
    local nodes='[]' spec login state
    for spec in "$@"; do
        login="${spec%%:*}"
        state="${spec#*:}"
        nodes="$(jq -c --arg login "$login" --arg state "$state" \
            '. + [{createdAt:"2026-10-05T12:00:00Z",previousReviewState:$state,review:{databaseId:900,author:{login:$login}}}]' <<<"$nodes")"
    done
    jq -n --argjson nodes "$nodes" '{data:{repository:{pullRequest:{timelineItems:{nodes:$nodes}}}}}'
}

_run_dismissed() {
    run "$RR" dismissed --reviews "$TEST_HOME/reviews.json" --head "$HEAD_SHA" "$@"
}

@test "dismissed: dismissed approval with no re-approval at head gives NEEDS_LOOK:bob" {
    _fx_reviews_dismissed | _write reviews.json
    _fx_timeline bob:APPROVED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:bob" ]
}

@test "dismissed: re-approval at head after the dismissal gives OK" {
    { _fx_reviews_dismissed; _review_approved bob "$HEAD_SHA" 2026-10-06T10:00:00Z; } | jq -s '.[0] + [.[1]]' | _write reviews.json
    _fx_timeline bob:APPROVED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "dismissed: a re-approval at an older commit does not clear" {
    { _fx_reviews_dismissed; _review_approved bob bbb0000000000000000000000000000000000000 2026-10-06T10:00:00Z; } | jq -s '.[0] + [.[1]]' | _write reviews.json
    _fx_timeline bob:APPROVED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:bob" ]
}

@test "dismissed: an approval at head submitted before the dismissal does not clear" {
    { _fx_reviews_dismissed; _review_approved bob "$HEAD_SHA" 2026-10-04T10:00:00Z; } | jq -s '.[0] + [.[1]]' | _write reviews.json
    _fx_timeline bob:APPROVED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:bob" ]
}

@test "dismissed: a re-approval by someone else does not clear the dismissed reviewer" {
    { _fx_reviews_dismissed; _review_approved carol "$HEAD_SHA" 2026-10-06T10:00:00Z; } | jq -s '.[0] + [.[1]]' | _write reviews.json
    _fx_timeline bob:APPROVED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:bob" ]
}

@test "dismissed: dismissed CHANGES_REQUESTED is ignored on the timeline path" {
    _fx_reviews_dismissed | _write reviews.json
    _fx_timeline carol:CHANGES_REQUESTED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "dismissed: two uncleared reviewers are listed sorted" {
    _fx_reviews_dismissed | _write reviews.json
    _fx_timeline carol:APPROVED bob:APPROVED | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:bob,carol" ]
}

@test "dismissed: timeline accepts slurped pages" {
    _fx_reviews_dismissed | _write reviews.json
    _fx_timeline bob:APPROVED | jq '[.]' | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json"
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:bob" ]
}

@test "dismissed: an empty timeline gives OK even with a DISMISSED review in REST" {
    _fx_reviews_dismissed | _write reviews.json
    _fx_timeline | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json" --review-decision REVIEW_REQUIRED
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "dismissed fallback: DISMISSED review and decision REVIEW_REQUIRED gives NEEDS_LOOK:unknown" {
    _fx_reviews_dismissed | _write reviews.json
    _run_dismissed --review-decision REVIEW_REQUIRED
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:unknown" ]
}

@test "dismissed fallback: decision APPROVED gives OK" {
    _fx_reviews_dismissed | _write reviews.json
    _run_dismissed --review-decision APPROVED
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "dismissed fallback: no DISMISSED review gives OK" {
    _fx_reviews | _write reviews.json
    _run_dismissed --review-decision REVIEW_REQUIRED
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "dismissed fallback: a timeline file holding null behaves like no timeline" {
    _fx_reviews_dismissed | _write reviews.json
    echo 'null' | _write timeline.json
    _run_dismissed --timeline "$TEST_HOME/timeline.json" --review-decision REVIEW_REQUIRED
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:unknown" ]
}

@test "dismissed fallback: an omitted --review-decision counts as not approved" {
    _fx_reviews_dismissed | _write reviews.json
    _run_dismissed
    [ "$status" -eq 0 ]
    [ "$output" = "NEEDS_LOOK:unknown" ]
}

# issues/7/comments --paginate --slurp: array of arrays.
#   5001 alice, marker 900            5002 carol, marker 900 (not me)
#   5003 alice, marker 901            5004 alice, marker 900 but no 🤖 prefix
#   5005 alice, marker 900, later     5006 alice, marker 9001 (must not match 900)
_fx_issue_comments() {
    cat <<'JSON'
[
  [
    {"id":5001,"user":{"login":"alice"},"created_at":"2026-10-05T13:00:00Z","body":"🤖 **Review round: Bob** ([review 900](https://github.example.com/acme/widgets/pull/7#pullrequestreview-900))\n\nHead is now `ccc0000`.\n\n<!-- review-respond review=900 -->"},
    {"id":5002,"user":{"login":"carol"},"created_at":"2026-10-05T13:05:00Z","body":"🤖 something else\n\n<!-- review-respond review=900 -->"},
    {"id":5003,"user":{"login":"alice"},"created_at":"2026-10-05T13:10:00Z","body":"🤖 **Review round: Carol**\n\n<!-- review-respond review=901 -->"}
  ],
  [
    {"id":5004,"user":{"login":"alice"},"created_at":"2026-10-05T13:15:00Z","body":"**Review round: Bob**\n\n<!-- review-respond review=900 -->"},
    {"id":5005,"user":{"login":"alice"},"created_at":"2026-10-06T09:00:00Z","body":"🤖 **Review round: Bob** (updated)\n\n<!-- review-respond review=900 -->"},
    {"id":5006,"user":{"login":"alice"},"created_at":"2026-10-06T09:30:00Z","body":"🤖 **Review round: Bob**\n\n<!-- review-respond review=9001 -->"}
  ]
]
JSON
}

# Keep only the comment ids given, preserving the array-of-arrays shape.
_only_ids() {
    jq --argjson ids "$1" 'map(map(select(.id as $i | $ids | index($i) != null)))'
}

_run_find_prior() {
    run "$RR" find-prior --comments "$TEST_HOME/comments.json" --review 900 --me alice
}

@test "find-prior returns my marked comment for the review" {
    _fx_issue_comments | _only_ids '[5001]' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "5001" ]
}

@test "find-prior ignores another user's comment carrying the marker" {
    _fx_issue_comments | _only_ids '[5002]' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "NONE" ]
}

@test "find-prior ignores my comment for a different review id" {
    _fx_issue_comments | _only_ids '[5003, 5006]' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "NONE" ]
}

@test "find-prior matches my marked comment without the 🤖 prefix" {
    # The gate lets the user post without the marker prefix; a re-run must
    # still find that comment or it would post a duplicate.
    _fx_issue_comments | _only_ids '[5004]' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "5004" ]
}

@test "find-prior returns the latest when there are duplicates" {
    # Pages reversed so the latest comment comes first in input order and only
    # the created_at sort can pick it.
    _fx_issue_comments | _only_ids '[5005, 5001]' | jq 'reverse' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "5005" ]
}

@test "find-prior picks my comment out of the full mixed set" {
    _fx_issue_comments | jq 'reverse' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "5005" ]
}

@test "find-prior with none prints NONE" {
    echo '[[]]' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "NONE" ]
}

@test "find-prior accepts a flat comment array" {
    _fx_issue_comments | _only_ids '[5001]' | jq 'add' | _write comments.json
    _run_find_prior
    [ "$status" -eq 0 ]
    [ "$output" = "5001" ]
}

# ---------------------------------------------------------------------------
# detect-checks — real scratch manifest directories
# ---------------------------------------------------------------------------

_proj() {
    PROJ="$TEST_HOME/proj"
    mkdir -p "$PROJ"
    export PROJ
}

_pkg() {
    # $1 = scripts object (JSON)
    jq -n --argjson s "$1" '{name:"widgets",private:true,scripts:$s}' > "$PROJ/package.json"
}

_run_detect() {
    run "$RR" detect-checks --dir "$PROJ"
}

@test "detect-checks: npm package with test/lint/typecheck scripts" {
    _proj
    _pkg '{"test":"vitest run","lint":"eslint . --ext .ts","typecheck":"tsc --noEmit --skipLibCheck"}'
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[{"kind":"test","label":"vitest","cmd":"npm run test","runner":"vitest"},{"kind":"lint","label":"eslint","cmd":"npm run lint","runner":null},{"kind":"typecheck","label":"`tsc --noEmit --skipLibCheck`","cmd":"npm run typecheck","runner":null}]' ]
}

@test "detect-checks: pnpm lockfile switches the runner prefix" {
    _proj
    _pkg '{"test":"vitest run"}'
    : > "$PROJ/pnpm-lock.yaml"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.[0].cmd')" = "pnpm run test" ]
}

@test "detect-checks: yarn and bun lockfiles switch the prefix too" {
    _proj
    _pkg '{"test":"jest"}'
    : > "$PROJ/yarn.lock"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.[0].cmd')" = "yarn test" ]
    rm "$PROJ/yarn.lock"
    : > "$PROJ/bun.lockb"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.[0].cmd')" = "bun run test" ]
}

@test "detect-checks: tsc script body becomes the backticked label" {
    _proj
    _pkg '{"type-check":"tsc -p tsconfig.json"}'
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[{"kind":"typecheck","label":"`tsc -p tsconfig.json`","cmd":"npm run type-check","runner":null}]' ]
}

@test "detect-checks: env wrappers are skipped when labelling and the runner is inferred" {
    _proj
    _pkg '{"test":"cross-env CI=true vitest run --coverage","lint":"node scripts/lint.js"}'
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map([.label, .runner])')" = '[["vitest","vitest"],["lint",null]]' ]
}

@test "detect-checks: a test script with no known runner reports runner null" {
    _proj
    _pkg '{"test":"node --test"}'
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.[0] | [.label, .runner]')" = '["test",null]' ]
}

@test "detect-checks: Makefile test and lint targets" {
    _proj
    printf '.PHONY: test lint\n\ntest:\n\tDOTFILES_DIR=$(PWD) bats tests/*.bats\n\nlint:\n\tshellcheck scripts/*.sh\n' > "$PROJ/Makefile"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[{"kind":"test","label":"bats","cmd":"make test","runner":"bats"},{"kind":"lint","label":"make lint","cmd":"make lint","runner":null}]' ]
}

@test "detect-checks: Makefile target names must match exactly" {
    _proj
    printf 'test-unit:\n\tgo test ./...\nlinting:\n\ttrue\ncheck-leakage:\n\ttrue\n' > "$PROJ/Makefile"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[]' ]
}

@test "detect-checks: Makefile check target maps to lint only without a lint target" {
    _proj
    printf 'test:\n\tpytest -q\ncheck:\n\truff check .\n' > "$PROJ/Makefile"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map([.kind, .cmd, .runner])')" = '[["test","make test","pytest"],["lint","make check",null]]' ]
    printf 'test:\n\tpytest -q\nlint:\n\truff check .\ncheck:\n\truff check .\n' > "$PROJ/Makefile"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.cmd)')" = '["make test","make lint"]' ]
}

@test "detect-checks: composer phpunit and phpstan" {
    _proj
    printf '{"scripts":{"test":"phpunit --testdox","lint":"phpcs --standard=PSR12 src","phpstan":"phpstan analyse"}}\n' > "$PROJ/composer.json"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[{"kind":"test","label":"phpunit","cmd":"composer test","runner":"phpunit"},{"kind":"lint","label":"phpcs","cmd":"composer lint","runner":null},{"kind":"typecheck","label":"phpstan","cmd":"composer phpstan","runner":null}]' ]
}

@test "detect-checks: composer array-valued scripts and psalm" {
    _proj
    printf '{"scripts":{"test":["@php vendor/bin/phpunit"],"psalm":"psalm --no-cache"}}\n' > "$PROJ/composer.json"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map([.kind, .label, .runner])')" = '[["test","phpunit","phpunit"],["typecheck","psalm",null]]' ]
}

@test "detect-checks: pyproject with ruff and mypy" {
    _proj
    printf '[project]\nname = "widgets"\n\n[tool.ruff]\nline-length = 100\n\n[tool.mypy]\nstrict = true\n' > "$PROJ/pyproject.toml"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[{"kind":"test","label":"pytest","cmd":"python3 -m pytest","runner":"pytest"},{"kind":"lint","label":"ruff","cmd":"ruff check .","runner":null},{"kind":"typecheck","label":"mypy","cmd":"mypy .","runner":null}]' ]
}

@test "detect-checks: the pytest command uses python3 and leaves the summary rule intact" {
    _proj
    printf '[pytest]\ntestpaths = tests\n' > "$PROJ/pytest.ini"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.[0].cmd')" = "python3 -m pytest" ]
}

@test "detect-checks: pytest.ini alone yields only the test command" {
    _proj
    printf '[pytest]\ntestpaths = tests\n' > "$PROJ/pytest.ini"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.kind)')" = '["test"]' ]
}

@test "detect-checks: setup.cfg counts only with a [tool:pytest] section" {
    _proj
    printf '[metadata]\nname = widgets\n' > "$PROJ/setup.cfg"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[]' ]
    printf '[metadata]\nname = widgets\n[tool:pytest]\naddopts = -q\n' > "$PROJ/setup.cfg"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.kind)')" = '["test"]' ]
}

@test "detect-checks: go.mod" {
    _proj
    printf 'module example.com/acme/widgets\n\ngo 1.22\n' > "$PROJ/go.mod"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[{"kind":"test","label":"go","cmd":"go test ./...","runner":"go"},{"kind":"lint","label":"go vet","cmd":"go vet ./...","runner":null}]' ]
}

@test "detect-checks: empty dir prints []" {
    _proj
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '[]' ]
}

@test "detect-checks: package.json wins over Makefile for the test kind" {
    _proj
    _pkg '{"test":"vitest run"}'
    printf 'test:\n\tbats tests\nlint:\n\tshellcheck scripts/*.sh\n' > "$PROJ/Makefile"
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map([.kind, .cmd])')" = '[["test","npm run test"],["lint","make lint"]]' ]
}

@test "detect-checks: output is always ordered test, lint, typecheck" {
    _proj
    _pkg '{"typecheck":"tsc --noEmit","lint":"eslint .","test":"jest"}'
    _run_detect
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c 'map(.kind)')" = '["test","lint","typecheck"]' ]
}

# ---------------------------------------------------------------------------
# parse-test-output — inline runner logs on stdin
# ---------------------------------------------------------------------------

_parse() {
    # $1 = runner; log on stdin
    run bash -c '"$RR" parse-test-output --runner "$1"' _ "$1"
}

@test "parse-test-output vitest all passing" {
    _parse vitest <<'LOG'
 RUN  v3.1.1 /work/widgets

 ✓ src/a.test.ts (12 tests) 34ms
 ✓ src/b.test.ts (7 tests) 12ms

 Test Files  159 passed (159)
      Tests  2753 passed (2753)
   Start at  10:00:00
   Duration  12.34s (transform 1.2s, setup 0ms, collect 3.4s, tests 7.1s)
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"vitest","files":159,"tests_passed":2753,"tests_failed":0,"parsed":true}' ]
}

@test "parse-test-output vitest with failures sets tests_failed" {
    _parse vitest <<'LOG'
 Test Files  1 failed | 158 passed (159)
      Tests  3 failed | 2750 passed (2753)
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"vitest","files":159,"tests_passed":2750,"tests_failed":3,"parsed":true}' ]
}

@test "parse-test-output strips ANSI colour codes" {
    printf ' \033[2mTest Files\033[22m  \033[1;32m159 passed\033[39;22m (159)\n      \033[2mTests\033[22m  \033[1;32m2753 passed\033[39;22m (2753)\n' > "$TEST_HOME/vitest.log"
    _parse vitest < "$TEST_HOME/vitest.log"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.files, .tests_passed, .tests_failed, .parsed]')" = '[159,2753,0,true]' ]
}

@test "parse-test-output survives non-UTF-8 bytes in the log under a UTF-8 locale" {
    # BSD sed exits 1 ("illegal byte sequence") on \xff under a UTF-8 locale,
    # which under set -e ended the script with no JSON at all; BSD grep then
    # treats a log holding an invalid byte as binary and matches nothing.
    printf 'PASS src/a.test.ts\n  renders \xff\xfe garbage\nTest Suites: 1 passed, 1 total\nTests:       2 passed, 2 total\n' > "$TEST_HOME/jest-bytes.log"
    run bash -c 'LC_ALL=C.UTF-8 "$RR" parse-test-output --runner jest < "$1"' _ "$TEST_HOME/jest-bytes.log"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    [ "$(echo "$output" | jq -c '[.files, .tests_passed, .tests_failed, .parsed]')" = '[1,2,0,true]' ]
    printf 'Test Suites: 1 passed, 1 total\nTests: \xff\xfe 2 passed, 2 total\n' > "$TEST_HOME/jest-bytes2.log"
    run bash -c 'LC_ALL=C.UTF-8 "$RR" parse-test-output --runner jest < "$1"' _ "$TEST_HOME/jest-bytes2.log"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed, .parsed]')" = '[2,0,true]' ]
}

@test "parse-test-output jest" {
    _parse jest <<'LOG'
PASS src/a.test.ts
FAIL src/b.test.ts
  ● renders › shows the thing

Test Suites: 1 failed, 11 passed, 12 total
Tests:       2 failed, 118 passed, 120 total
Snapshots:   0 total
Time:        4.2 s
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"jest","files":12,"tests_passed":118,"tests_failed":2,"parsed":true}' ]
    _parse jest <<'LOG'
Test Suites: 12 passed, 12 total
Tests:       120 passed, 120 total
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.files, .tests_passed, .tests_failed]')" = '[12,120,0]' ]
}

@test "parse-test-output pytest passed and failed" {
    _parse pytest <<'LOG'
============================= test session starts ==============================
collected 122 items

tests/test_a.py ....F.                                                   [ 50%]
tests/test_b.py .....F                                                   [100%]

========================= 120 passed, 2 failed in 3.21s ========================
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"pytest","files":null,"tests_passed":120,"tests_failed":2,"parsed":true}' ]
    _parse pytest <<'LOG'
=================== 2 failed, 120 passed, 1 skipped in 1.20s ===================
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed]')" = '[120,2]' ]
    _parse pytest <<'LOG'
============================== 50 passed in 0.50s ==============================
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed]')" = '[50,0]' ]
}

@test "parse-test-output pytest quiet mode: bare summary line without the = rule" {
    _parse pytest <<'LOG'
..                                                                       [100%]
2 passed in 0.01s
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed, .parsed]')" = '[2,0,true]' ]
    _parse pytest <<'LOG'
.F.                                                                      [100%]
1 failed, 2 passed in 0.02s
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed, .parsed]')" = '[2,1,true]' ]
    _parse pytest <<'LOG'
3 passed, 1 skipped, 2 warnings in 0.30s
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed]')" = '[3,0]' ]
}

@test "parse-test-output bats pretty and TAP fallback" {
    _parse bats <<'LOG'
 ✓ first thing
 ✓ second thing
 ✗ third thing
   (in test file tests/x.bats, line 9)

3 tests, 1 failure
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"bats","files":null,"tests_passed":2,"tests_failed":1,"parsed":true}' ]
    _parse bats <<'LOG'
 ✓ only thing

1 test, 0 failures
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed]')" = '[1,0]' ]
    _parse bats <<'LOG'
1..3
ok 1 first thing
not ok 2 second thing
# (in test file tests/x.bats, line 9)
ok 3 third thing
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed, .parsed]')" = '[2,1,true]' ]
}

@test "parse-test-output phpunit OK and failure forms" {
    _parse phpunit <<'LOG'
PHPUnit 10.5.0 by Sebastian Bergmann and contributors.

.........................                                         25 / 25 (100%)

Time: 00:00.123, Memory: 8.00 MB

OK (25 tests, 60 assertions)
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"phpunit","files":null,"tests_passed":25,"tests_failed":0,"parsed":true}' ]
    _parse phpunit <<'LOG'
FAILURES!
Tests: 25, Assertions: 60, Failures: 2.
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed]')" = '[23,2]' ]
    _parse phpunit <<'LOG'
ERRORS!
Tests: 25, Assertions: 60, Errors: 1, Failures: 2.
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '[.tests_passed, .tests_failed]')" = '[22,3]' ]
}

@test "parse-test-output go" {
    _parse go <<'LOG'
ok  	example.com/acme/widgets/pkg/a	0.012s
ok  	example.com/acme/widgets/pkg/b	(cached)
--- FAIL: TestThing (0.00s)
FAIL	example.com/acme/widgets/pkg/c	0.100s
LOG
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -c '.')" = '{"runner":"go","files":2,"tests_passed":null,"tests_failed":1,"parsed":true}' ]
}

@test "parse-test-output unrecognised log gives parsed false and null counts" {
    local runner
    for runner in vitest jest pytest bats phpunit go; do
        _parse "$runner" <<'LOG'
nothing to see here
LOG
        [ "$status" -eq 0 ] || return 1
        [ "$(echo "$output" | jq -c '.')" = "{\"runner\":\"$runner\",\"files\":null,\"tests_passed\":null,\"tests_failed\":null,\"parsed\":false}" ] || {
            echo "unexpected for $runner: $output"
            return 1
        }
    done
}

@test "parse-test-output rejects an unknown runner" {
    _parse mocha <<'LOG'
  12 passing (1s)
LOG
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown runner: mocha"* ]]
}

# ---------------------------------------------------------------------------
# render — golden shape, refusals, escaping
# ---------------------------------------------------------------------------

_fx_render_input() {
    cat <<'JSON'
{
  "pr_url": "https://github.example.com/acme/widgets/pull/79",
  "review": {"id": 900, "reviewer_name": "Bob"},
  "head": {"short": "4bfe659"},
  "needs_look": true,
  "rows": [
    {"comment_id": 101, "title": "Image search misconfig escapes fail-soft", "outcome": "fixed", "sha": "651eb74", "detail": ""},
    {"comment_id": 102, "title": "Supersede rule depends on completion order", "outcome": "fixed", "sha": "7126064", "detail": "outcomes keep line order"},
    {"comment_id": 103, "title": "Weak test assertions", "outcome": "fixed", "sha": "51423a4", "detail": ""}
  ],
  "also_found": [
    {"text": "the image search base URLs were missing the `/imagesearch` path", "shas": ["4a4adea"]},
    {"text": "`request_id` is now forwarded", "shas": ["19231d6"]}
  ],
  "testing": {"cwd": "app/", "checks": [
    {"kind": "test", "label": "vitest", "status": "passed", "files": 159, "tests_passed": 2753, "parsed": true},
    {"kind": "lint", "label": "eslint", "status": "passed"},
    {"kind": "typecheck", "label": "`tsc --noEmit --skipLibCheck`", "status": "passed"}
  ]}
}
JSON
}

_fx_render_golden() {
    cat <<'MD'
🤖 **Review round: Bob** ([review 900](https://github.example.com/acme/widgets/pull/79#pullrequestreview-900))

Head is now `4bfe659`. The push dismissed the approval, so this needs another look.

| Comment | Outcome |
|---|---|
| [Image search misconfig escapes fail-soft](https://github.example.com/acme/widgets/pull/79#discussion_r101) | Fixed in `651eb74` |
| [Supersede rule depends on completion order](https://github.example.com/acme/widgets/pull/79#discussion_r102) | Fixed in `7126064`: outcomes keep line order |
| [Weak test assertions](https://github.example.com/acme/widgets/pull/79#discussion_r103) | Fixed in `51423a4` |

**Also found:** the image search base URLs were missing the `/imagesearch` path (`4a4adea`). `request_id` is now forwarded (`19231d6`).

**Testing at `4bfe659`** (from `app/`): vitest 159 files / **2,753 tests passed**; eslint and `tsc --noEmit --skipLibCheck` clean.

<!-- review-respond review=900 -->
MD
}

# Render the golden input transformed by the jq filter $1; output in $output.
_render_with() {
    _fx_render_input | jq "$1" | _write input.json
    run "$RR" render --input "$TEST_HOME/input.json"
}

@test "render golden: exemplar-shaped input renders byte-for-byte" {
    _fx_render_input | _write input.json
    _fx_render_golden | _write expected.md
    "$RR" render --input "$TEST_HOME/input.json" > "$TEST_HOME/out.md"
    cmp "$TEST_HOME/out.md" "$TEST_HOME/expected.md"
}

@test "render: needs_look false omits the dismissal clause" {
    _render_with '.needs_look = false'
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '3p')" = 'Head is now `4bfe659`.' ]
}

@test "render: wont_fix and needs_discussion cells" {
    _render_with '.rows = [
        {comment_id:101,title:"A",outcome:"wont_fix",detail:"by design"},
        {comment_id:102,title:"B",outcome:"needs_discussion",detail:""},
        {comment_id:103,title:"C",outcome:"needs_discussion",detail:"needs product input"},
        {comment_id:104,title:"D",outcome:"wont_fix",detail:""}]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"| [A](https://github.example.com/acme/widgets/pull/79#discussion_r101) | Won't fix: by design |"* ]]
    [[ "$output" == *"#discussion_r102) | Needs discussion |"* ]]
    [[ "$output" == *"#discussion_r103) | Needs discussion: needs product input |"* ]]
    [[ "$output" == *"#discussion_r104) | Won't fix |"* ]]
}

@test "render: empty also_found omits the section" {
    _render_with '.also_found = []'
    [ "$status" -eq 0 ]
    [[ "$output" != *"Also found"* ]] || return 1
    # The table's last row is line 9; one blank line and then the Testing line follow.
    [ "$(echo "$output" | sed -n '10,11p')" = "$(printf '\n**Testing at `4bfe659`** (from `app/`): vitest 159 files / **2,753 tests passed**; eslint and `tsc --noEmit --skipLibCheck` clean.')" ]
}

@test "render: pipe and brackets in a title are escaped" {
    _render_with '.rows[0].title = "Handle a|b [x] case"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'| [Handle a\|b \[x\] case](https://github.example.com/acme/widgets/pull/79#discussion_r101) | Fixed in `651eb74` |'* ]]
}

@test "render: newline in a detail collapses to a space and markup is neutralised" {
    _render_with '.rows[0].detail = "line one\nline two | three <!-- hidden"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'| Fixed in `651eb74`: line one line two \| three  hidden |'* ]]
}

@test "render: reviewer_name is sanitized (comment opener, pipe, newline)" {
    # reviewer_name comes from users/<login> .name, which the reviewer controls;
    # an unclosed <!-- there would hide the whole body up to the trailing marker.
    _render_with '.review.reviewer_name = "Bob <!-- x | y\nz"'
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '1p')" = '🤖 **Review round: Bob  x \| y z** ([review 900](https://github.example.com/acme/widgets/pull/79#pullrequestreview-900))' ]
}

@test "render: also_found text is sanitized" {
    _render_with '.also_found[0].text = "hidden <!-- comment | here"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Also found:** hidden  comment \| here (`4a4adea`). `request_id` is now forwarded (`19231d6`).'* ]]
}

@test "render: testing.cwd is sanitized" {
    _render_with '.testing.cwd = "a|b <!-- c/"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Testing at `4bfe659`** (from `a\|b  c/`): vitest 159 files'* ]]
}

@test "render: check labels are sanitized in the Testing line" {
    _render_with '.testing.checks[1].label = "eslint <!-- x | y" | .testing.checks[0].label = "vitest\nrun"'
    [ "$status" -eq 0 ]
    [[ "$output" == *': vitest run 159 files / **2,753 tests passed**; eslint  x \| y and `tsc --noEmit --skipLibCheck` clean.'* ]]
}

@test "render: failed check refuses with REFUSE:checks-failed and exit 2" {
    _render_with '.testing.checks[1].status = "failed"'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:checks-failed:eslint" ]
}

@test "render: a check with a missing status is not treated as passed" {
    _render_with '.testing.checks[2] |= del(.status)'
    [ "$status" -eq 2 ]
    [ "$output" = 'REFUSE:checks-failed:`tsc --noEmit --skipLibCheck`' ]
}

@test "render: ambiguous row refuses" {
    _render_with '.rows[1].outcome = "ambiguous"'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:unresolved-ambiguous:102" ]
}

@test "render: fixed row without sha refuses" {
    _render_with '.rows[0].sha = null'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:fixed-without-sha:101" ]
    _render_with '.rows[2].sha = ""'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:fixed-without-sha:103" ]
}

@test "render: unknown outcome refuses" {
    _render_with '.rows[1].outcome = "tightened"'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:unknown-outcome:102" ]
}

@test "render: empty rows refuses" {
    _render_with '.rows = []'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:empty-rows" ]
}

@test "render: a failing check is reported before any row problem" {
    _render_with '.testing.checks[0].status = "failed" | .rows[0].outcome = "ambiguous"'
    [ "$status" -eq 2 ]
    [ "$output" = "REFUSE:checks-failed:vitest" ]
}

@test "render: unparsed test count renders 'passed (count not reported)'" {
    _render_with '.testing.checks[0] = {kind:"test",label:"vitest",status:"passed",files:null,tests_passed:null,parsed:false}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Testing at `4bfe659`** (from `app/`): vitest passed (count not reported); eslint and `tsc --noEmit --skipLibCheck` clean.'* ]]
}

@test "render: no checks renders the explicit no-command sentence" {
    _render_with '.testing.checks = [] | .testing.cwd = "."'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Testing at `4bfe659`**: no test, lint, or typecheck command detected.'* ]]
}

@test "render: cwd '.' or empty omits the from-clause" {
    _render_with '.testing.cwd = "."'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Testing at `4bfe659`**: vitest 159 files'* ]]
    _render_with 'del(.testing.cwd)'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Testing at `4bfe659`**: vitest 159 files'* ]]
}

@test "render: files null drops the files clause" {
    _render_with '.testing.checks[0].files = null | .testing.checks[0].tests_passed = 42'
    [ "$status" -eq 0 ]
    [[ "$output" == *': vitest **42 tests passed**; eslint and'* ]]
}

@test "render: go-style counts with null tests_passed render files passed" {
    _render_with '.testing.checks[0] = {kind:"test",label:"go",status:"passed",files:3,tests_passed:null,parsed:true}'
    [ "$status" -eq 0 ]
    [[ "$output" == *': go 3 files passed; eslint and'* ]]
}

@test "render: non-test checks list with Oxford-free and" {
    _render_with '.testing.checks = [.testing.checks[0], {kind:"lint",label:"eslint",status:"passed"}]'
    [ "$status" -eq 0 ]
    [[ "$output" == *'; eslint clean.'* ]]
    _render_with '.testing.checks += [{kind:"lint",label:"stylelint",status:"passed"}]'
    [ "$status" -eq 0 ]
    [[ "$output" == *'; eslint, `tsc --noEmit --skipLibCheck` and stylelint clean.'* ]]
}

@test "render: two test checks produce two clauses" {
    _render_with '.testing.checks = [.testing.checks[0], {kind:"test",label:"bats",status:"passed",files:null,tests_passed:12,parsed:true}]'
    [ "$status" -eq 0 ]
    [[ "$output" == *': vitest 159 files / **2,753 tests passed**; bats **12 tests passed**.'* ]]
}

@test "render: output begins with the 🤖 prefix and ends with the marker line" {
    _fx_render_input | _write input.json
    "$RR" render --input "$TEST_HOME/input.json" > "$TEST_HOME/out.md"
    [ "$(head -c 5 "$TEST_HOME/out.md")" = "🤖 " ]
    [ "$(tail -n 1 "$TEST_HOME/out.md")" = "<!-- review-respond review=900 -->" ]
    [ "$(tail -c 1 "$TEST_HOME/out.md" | od -An -tx1 | tr -d ' \n')" = "0a" ]
    [ "$(tail -c 2 "$TEST_HOME/out.md" | od -An -tx1 | tr -d ' \n')" != "0a0a" ]
}

@test "render: sections are separated by exactly one blank line" {
    _fx_render_input | _write input.json
    "$RR" render --input "$TEST_HOME/input.json" > "$TEST_HOME/out.md"
    [ "$(grep -c '^$' "$TEST_HOME/out.md")" = "5" ]
    [[ "$(tr '\n' '~' < "$TEST_HOME/out.md")" != *"~~~"* ]] || return 1
}

@test "render: three-digit count has no comma, seven-digit has two" {
    _render_with '.testing.checks[0].tests_passed = 999'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**999 tests passed**'* ]]
    _render_with '.testing.checks[0].tests_passed = 1000'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**1,000 tests passed**'* ]]
    _render_with '.testing.checks[0].tests_passed = 1234567 | .testing.checks[0].files = 2048'
    [ "$status" -eq 0 ]
    [[ "$output" == *'vitest 2,048 files / **1,234,567 tests passed**'* ]]
}

@test "render: also_found with two shas lists both" {
    _render_with '.also_found = [{text:"renamed the helper", shas:["aaa1111","bbb2222"]}]'
    [ "$status" -eq 0 ]
    [[ "$output" == *'**Also found:** renamed the helper (`aaa1111`, `bbb2222`).'* ]]
}
