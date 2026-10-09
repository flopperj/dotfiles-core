#!/usr/bin/env bash
# review-respond.sh — the deterministic core of the /review-respond skill.
#
# The SKILL.md prose owns every gh call, every judgment call (thread titles,
# also-found wording) and the approval gate. This script owns every DECISION:
# which review to answer, which commits touch which thread, what may be called
# "Fixed", whether a push dismissed an approval, whether a prior summary exists,
# which checks to run, what the runner logs say, and how the comment renders.
# Nothing here calls gh or the network. Only `commits` reads git, read-only.
# jq is required.
#
# Subcommands:
#   threads        --graphql <file> | --rest <file>
#                    -> JSON array of normalized threads (all reviews)
#   select-review  --reviews <file> --threads <file> --author <login> [--review <id>]
#                    -> "<review_id>" | "NONE:no-qualifying-review" | "NONE:review-not-found"
#   commits        --base <sha> [--head <ref>] [--repo-dir <dir>]
#                    -> JSON array of commits | "ERROR:base-missing" | "ERROR:base-not-ancestor" (exit 3)
#   map-threads    --threads <file> --review <id> --commits <file> [--window <n>]
#                    -> {"threads":[...with touching/overlapping...], "unlinked_commits":[...], "commits":[...]}
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
# Exit codes: 0 ok/decision token; 1 usage or malformed input; 2 render refusal;
# 3 git precondition.
#
# Normalized thread shape (output of `threads`, input to everything after):
#   {"thread_id","comment_id","review_id","path","line","original_line",
#    "is_resolved","is_outdated","url","body"}
# From the REST fallback is_resolved is null (unknown) and is_outdated is
# (line == null); downstream code treats null is_resolved as unresolved so the
# fallback fails toward "still needs an answer", never toward silence.
#
# shellcheck shell=bash

set -euo pipefail

_die() {
    echo "review-respond: $*" >&2
    exit 1
}

_usage() {
    cat >&2 <<'USAGE'
usage: review-respond.sh <subcommand> [flags]

  threads            --graphql <file> | --rest <file>
  select-review      --reviews <file> --threads <file> --author <login> [--review <id>]
  commits            --base <sha> [--head <ref>] [--repo-dir <dir>]
  map-threads        --threads <file> --review <id> --commits <file> [--window <n>]
  classify           --map <file>
  dismissed          --reviews <file> --head <sha> [--timeline <file>] [--review-decision <s>]
  find-prior         --comments <file> --review <id> --me <login>
  detect-checks      --dir <dir>
  parse-test-output  --runner <vitest|jest|pytest|bats|phpunit|go>   (log on stdin)
  render             --input <file>
USAGE
    exit 1
}

_require_jq() {
    command -v jq >/dev/null 2>&1 || _die "jq is required but not found on PATH"
}

# ---------------------------------------------------------------------------
# Long-flag parser. Every flag takes a value and sets FLAG_<name>.
# ---------------------------------------------------------------------------
FLAG_graphql=""
FLAG_rest=""
FLAG_reviews=""
FLAG_threads=""
FLAG_author=""
FLAG_review=""
FLAG_base=""
FLAG_head=""
FLAG_repo_dir=""
FLAG_commits=""
FLAG_window=""
FLAG_map=""
FLAG_timeline=""
FLAG_review_decision=""
FLAG_comments=""
FLAG_me=""
FLAG_dir=""
FLAG_runner=""
FLAG_input=""

_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --graphql|--rest|--reviews|--threads|--author|--review|--base|--head|\
            --repo-dir|--commits|--window|--map|--timeline|--review-decision|\
            --comments|--me|--dir|--runner|--input)
                [ "$#" -ge 2 ] || _die "flag $1 needs a value"
                ;;
            *) _die "unknown argument: $1" ;;
        esac
        case "$1" in
            --graphql)         FLAG_graphql="$2" ;;
            --rest)            FLAG_rest="$2" ;;
            --reviews)         FLAG_reviews="$2" ;;
            --threads)         FLAG_threads="$2" ;;
            --author)          FLAG_author="$2" ;;
            --review)          FLAG_review="$2" ;;
            --base)            FLAG_base="$2" ;;
            --head)            FLAG_head="$2" ;;
            --repo-dir)        FLAG_repo_dir="$2" ;;
            --commits)         FLAG_commits="$2" ;;
            --window)          FLAG_window="$2" ;;
            --map)             FLAG_map="$2" ;;
            --timeline)        FLAG_timeline="$2" ;;
            --review-decision) FLAG_review_decision="$2" ;;
            --comments)        FLAG_comments="$2" ;;
            --me)              FLAG_me="$2" ;;
            --dir)             FLAG_dir="$2" ;;
            --runner)          FLAG_runner="$2" ;;
            --input)           FLAG_input="$2" ;;
        esac
        shift 2
    done
}

_require_file() {
    # $1 = flag name, $2 = path
    [ -n "$2" ] || _die "$1 is required"
    [ -f "$2" ] || _die "$1: no such file: $2"
}

# ---------------------------------------------------------------------------
# Shared jq definitions.
# `gh api --paginate --slurp` yields an array of pages (REST: array of arrays;
# GraphQL: array of response objects), while a single call yields one page.
# Every reader accepts both so a caller never has to remember which it saved.
# ---------------------------------------------------------------------------
JQ_DEFS='
def pages: if type == "array" then . else [.] end;
def flat: if type == "array" then [.[] | if type == "array" then .[] else . end] else [.] end;
'

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_threads() {
    _parse_args "$@"
    if [ -n "$FLAG_graphql" ]; then
        _require_file --graphql "$FLAG_graphql"
        jq "$JQ_DEFS"'
            pages
            | map(.data.repository.pullRequest.reviewThreads.nodes // []) | add // []
            | map(select(((.comments.nodes // []) | length) > 0))
            | map(. as $t | .comments.nodes[0] as $c
                  | {thread_id: $t.id,
                     comment_id: $c.databaseId,
                     review_id: $c.pullRequestReview.databaseId,
                     path: $t.path,
                     line: $t.line,
                     original_line: $t.originalLine,
                     is_resolved: $t.isResolved,
                     is_outdated: $t.isOutdated,
                     url: $c.url,
                     body: $c.body})' "$FLAG_graphql"
    elif [ -n "$FLAG_rest" ]; then
        _require_file --rest "$FLAG_rest"
        jq "$JQ_DEFS"'
            flat
            | map(select(.in_reply_to_id == null))
            | map({thread_id: null,
                   comment_id: .id,
                   review_id: .pull_request_review_id,
                   path: .path,
                   line: .line,
                   original_line: .original_line,
                   is_resolved: null,
                   is_outdated: (.line == null),
                   url: .html_url,
                   body: .body})' "$FLAG_rest"
    else
        _die "threads needs --graphql <file> or --rest <file>"
    fi
}

cmd_select_review() {
    _parse_args "$@"
    _require_file --reviews "$FLAG_reviews"
    if [ -n "$FLAG_review" ]; then
        jq -r "$JQ_DEFS"'
            flat
            | if any(.[]; (.id | tostring) == $id) then $id else "NONE:review-not-found" end' \
            --arg id "$FLAG_review" "$FLAG_reviews"
        return 0
    fi
    _require_file --threads "$FLAG_threads"
    [ -n "$FLAG_author" ] || _die "--author is required"
    # A review qualifies when it still asks for something: CHANGES_REQUESTED, or
    # any of its threads not known to be resolved (null = unknown, so the REST
    # fallback counts as unresolved). Author, bot and pending reviews never do.
    jq -r "$JQ_DEFS"'
        ($threads[0] | flat) as $ts
        | flat
        | map(select((.user.login // "") != $author
                     and (.user.type // "") != "Bot"
                     and .state != "PENDING"))
        | map(. as $r
              | select($r.state == "CHANGES_REQUESTED"
                       or any($ts[]; (.review_id | tostring) == ($r.id | tostring)
                                     and .is_resolved != true)))
        | if length == 0 then "NONE:no-qualifying-review"
          else (max_by(.submitted_at // "") | .id | tostring) end' \
        --arg author "$FLAG_author" --slurpfile threads "$FLAG_threads" "$FLAG_reviews"
}

# One `git show -U0` per commit, parsed into {path, hunks}. Diff output is pinned
# against the user's config: explicit a/ b/ prefixes (diff.noprefix,
# diff.mnemonicPrefix), --no-ext-diff (difftastic and friends), --no-color,
# --no-renames so a rename is a delete plus an add and every block carries
# ---/+++ lines with identical header paths. git appends a TAB to the ---/+++
# path when it contains a space, so that is stripped. Paths git C-quotes
# (quotes, backslashes, control characters) are left as printed.
JQ_COMMIT='
def hunk:
  capture("^@@ -(?<os>[0-9]+)(,(?<ol>[0-9]+))? \\+(?<ns>[0-9]+)(,(?<nl>[0-9]+))? @@")
  | {old_start: (.os | tonumber), old_len: ((.ol // "1") | tonumber),
     new_start: (.ns | tonumber), new_len: ((.nl // "1") | tonumber)};
def depath: sub("\t$"; "");
def header_path:
  ltrimstr("diff --git ") | . as $r | ($r | length) as $n
  | if ($n >= 5) and ((($n - 5) % 2) == 0) then
      ((($n - 5) / 2) | floor) as $k | (2 + $k) as $a | (5 + $k) as $b
      | if ($r[0:2] == "a/") and ($r[$a:$b] == " b/") and ($r[2:$a] == $r[$b:])
        then $r[2:$a] else null end
    else null end;
[inputs] as $lines
| reduce $lines[] as $l ({files: [], cur: null, minus: null, in_header: false};
    if ($l | startswith("diff --git ")) then
      (if .cur != null then .files += [.cur] else . end)
      | .cur = {path: ($l | header_path), hunks: []} | .minus = null | .in_header = true
    elif .in_header and ($l | startswith("--- ")) then
      .minus = ($l | ltrimstr("--- ") | depath)
    elif .in_header and ($l | startswith("+++ ")) then
      ($l | ltrimstr("+++ ") | depath) as $plus
      | .cur.path = (if $plus == "/dev/null" then (.minus | ltrimstr("a/"))
                     else ($plus | ltrimstr("b/")) end)
    elif ($l | startswith("@@ ")) then
      .in_header = false | .cur.hunks += [($l | hunk)]
    else . end)
| (if .cur != null then .files += [.cur] else . end)
| {sha: $sha, short: $short, subject: $subject,
   type: ([$subject | capture("^(?<t>[a-z]+)(\\(.*\\))?!?:")] | .[0].t // ""),
   files: (.files | map(select(.path != null)))}
'

cmd_commits() {
    _parse_args "$@"
    [ -n "$FLAG_base" ] || _die "--base is required"
    local head="${FLAG_head:-HEAD}" dir="${FLAG_repo_dir:-.}"
    [ -d "$dir" ] || _die "--repo-dir: no such directory: $dir"
    if ! git -C "$dir" cat-file -e "${FLAG_base}^{commit}" 2>/dev/null; then
        printf 'ERROR:base-missing\n'
        exit 3
    fi
    git -C "$dir" rev-parse --verify --quiet "${head}^{commit}" >/dev/null \
        || _die "--head: not a commit: $head"
    if ! git -C "$dir" merge-base --is-ancestor "$FLAG_base" "$head"; then
        printf 'ERROR:base-not-ancestor\n'
        exit 3
    fi
    local sha short subject
    {
        while IFS=$'\x1f' read -r sha short subject; do
            [ -n "$sha" ] || continue
            git -C "$dir" -c core.quotepath=false --no-pager show -U0 --format= \
                --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ \
                --inter-hunk-context=0 "$sha" \
              | jq -R -n --arg sha "$sha" --arg short "$short" --arg subject "$subject" "$JQ_COMMIT"
        done < <(git -C "$dir" --no-pager log --first-parent --no-merges --reverse \
                    --format='%H%x1f%h%x1f%s' "${FLAG_base}..${head}")
    } | jq -s '.'
}

# Thread line numbers are in the coordinates of the commit the reviewer drafted
# against, which can predate the review's own commit_id, so hunk overlap is
# windowed (default 5 lines each side). A miss lands in `ambiguous`, which the
# gate resolves by hand — the safe direction.
cmd_map_threads() {
    _parse_args "$@"
    _require_file --threads "$FLAG_threads"
    _require_file --commits "$FLAG_commits"
    [ -n "$FLAG_review" ] || _die "--review is required"
    local window="${FLAG_window:-5}"
    case "$window" in
        ''|*[!0-9]*) _die "--window must be a non-negative integer" ;;
    esac
    jq "$JQ_DEFS"'
        ($commits[0] | flat) as $cs
        | ($window | tonumber) as $w
        | def near($s; $n; $L):
            ($L != null) and (($s - $w) <= $L) and ($L <= ($s + ([$n, 1] | max) - 1 + $w));
          (flat | map(select((.review_id | tostring) == $review))) as $ts
        | ($ts | map(.path) | unique) as $paths
        | {
            threads: ($ts | map(. as $t
                | ($cs | map(select(any(.files[]; .path == $t.path)))) as $touching
                | ($touching | map(select(
                      any(.files[] | select(.path == $t.path) | .hunks[];
                          near(.old_start; .old_len; $t.original_line)
                          or near(.new_start; .new_len; $t.line))))) as $overlapping
                | $t + {touching: ($touching | map(.short)),
                        overlapping: ($overlapping | map(.short))})),
            unlinked_commits: ($cs
                | map(select(all(.files[]; .path as $p | any($paths[]; . == $p) | not)))
                | map(.short)),
            commits: ($cs | map({sha: .sha, short: .short, subject: .subject, type: .type}))
          }' \
        --arg review "$FLAG_review" --arg window "$window" \
        --slurpfile commits "$FLAG_commits" "$FLAG_threads"
}

# Policy only. "Fixed" is proposed solely when exactly one commit overlaps the
# thread; anything less certain is `ambiguous` and must be chosen by a person.
# Housekeeping commits (docs/chore/style/ci) touch many files, so when they
# leave exactly one substantive candidate it is offered as `suggested` — a
# default for the gate, never a change of class.
cmd_classify() {
    _parse_args "$@"
    _require_file --map "$FLAG_map"
    jq '
        (.commits // []) as $cs
        | def commit($short): ([$cs[] | select(.short == $short)] | .[0]);
          def housekeeping($short): (commit($short).type // "") as $ty
            | any(("docs", "chore", "style", "ci"); . == $ty);
          .threads |= map(
            if (.touching | length) == 0 then
              . + {class: "untouched", proposed: {outcome: "needs_discussion", detail: ""}}
            elif (.overlapping | length) == 1 then
              . + {class: "candidate",
                   proposed: {outcome: "fixed", sha: .overlapping[0],
                              detail: (commit(.overlapping[0]).subject // "")}}
            else
              (if (.overlapping | length) > 0 then .overlapping else .touching end) as $cands
              | ([$cands[] | select(housekeeping(.) | not)]) as $substantive
              | . + {class: "ambiguous", proposed: {outcome: "ambiguous"}}
              | if ($substantive | length) == 1 then . + {suggested: $substantive[0]} else . end
            end)' "$FLAG_map"
}

# REST shows a dismissed review only as state DISMISSED, without the state it
# had before, so "the push dismissed an approval" needs the GraphQL timeline
# (ReviewDismissedEvent.previousReviewState). Without a timeline — or with a
# file holding null from a failed call — the answer degrades to
# NEEDS_LOOK:unknown whenever any review is DISMISSED and the PR is not approved.
cmd_dismissed() {
    _parse_args "$@"
    _require_file --reviews "$FLAG_reviews"
    [ -n "$FLAG_head" ] || _die "--head is required"
    local have_timeline="false"
    if [ -n "$FLAG_timeline" ]; then
        _require_file --timeline "$FLAG_timeline"
        if [ "$(jq -r 'if . == null then "null" else "present" end' "$FLAG_timeline")" = "present" ]; then
            have_timeline="true"
        fi
    fi
    if [ "$have_timeline" = "true" ]; then
        jq -r "$JQ_DEFS"'
            ($reviews[0] | flat) as $rs
            | pages
            | map(.data.repository.pullRequest.timelineItems.nodes // []) | add // []
            | map(select(.previousReviewState == "APPROVED"))
            | map(. as $e | ($e.review.author.login // "") as $login
                  | select($login != "")
                  | select(any($rs[]; (.user.login // "") == $login
                                      and .state == "APPROVED"
                                      and .commit_id == $head
                                      and (.submitted_at // "") > $e.createdAt) | not)
                  | $login)
            | unique
            | if length == 0 then "OK" else "NEEDS_LOOK:" + join(",") end' \
            --arg head "$FLAG_head" --slurpfile reviews "$FLAG_reviews" "$FLAG_timeline"
    else
        jq -r "$JQ_DEFS"'
            flat
            | if ($decision != "APPROVED") and any(.[]; .state == "DISMISSED")
              then "NEEDS_LOOK:unknown" else "OK" end' \
            --arg decision "$FLAG_review_decision" "$FLAG_reviews"
    fi
}

# Idempotency: a prior summary is recognised only by the exact hidden marker
# rendered at the end of every body, posted by me. The 🤖 prefix is not part
# of the match because the gate may post without it. Fuzzy text matching
# could overwrite a teammate's or an unrelated comment.
cmd_find_prior() {
    _parse_args "$@"
    _require_file --comments "$FLAG_comments"
    [ -n "$FLAG_review" ] || _die "--review is required"
    [ -n "$FLAG_me" ] || _die "--me is required"
    jq -r "$JQ_DEFS"'
        flat
        | map(select((.user.login // "") == $me
                     and ((.body // "") | contains($marker))))
        | if length == 0 then "NONE"
          else (sort_by([(.created_at // ""), .id]) | last | .id | tostring) end' \
        --arg me "$FLAG_me" --arg marker "<!-- review-respond review=${FLAG_review} -->" "$FLAG_comments"
}

# Candidate emitters for detect-checks. Each prints zero or more
# {kind,label,cmd,runner} objects; the caller keeps the first per kind in
# manifest order. `runner` is limited to what parse-test-output can read, so
# an unknown runner is null and the Testing line says "count not reported"
# instead of guessing.
JQ_RUNNER_OF='
def runner_of($body):
  if ($body | test("\\bvitest\\b")) then "vitest"
  elif ($body | test("\\bjest\\b")) then "jest"
  elif ($body | test("\\bpytest\\b")) then "pytest"
  elif ($body | test("\\bbats\\b")) then "bats"
  elif ($body | test("\\bphpunit\\b")) then "phpunit"
  elif ($body | test("\\bgo test\\b")) then "go"
  else null end;
'

_dc_package_json() {
    local dir="$1" pm
    [ -f "$dir/package.json" ] || return 0
    if [ -f "$dir/pnpm-lock.yaml" ]; then pm="pnpm run"
    elif [ -f "$dir/yarn.lock" ]; then pm="yarn"
    elif [ -f "$dir/bun.lockb" ] || [ -f "$dir/bun.lock" ]; then pm="bun run"
    else pm="npm run"
    fi
    jq -c "$JQ_RUNNER_OF"'
        def known: ["vitest","jest","mocha","ava","tap","eslint","biome","prettier","stylelint",
                    "tsc","tsd","vue-tsc","oxlint","xo","standard"];
        def words: gsub("^\\s+|\\s+$"; "") | split(" ") | map(select(. != ""));
        def unwrap:
          if length > 0 and ((.[0] | test("^[A-Za-z_][A-Za-z0-9_]*=")) or (.[0] | IN("npx", "bunx", "cross-env")))
          then .[1:] | unwrap else . end;
        def label_for($name; $body):
          ($body | words | unwrap) as $w | ($w[0] // "") as $first
          | if $first == "tsc" then "`" + ($w | join(" ")) + "`"
            elif ($first | IN(known[])) then $first
            else $name end;
        (.scripts // {}) as $s
        | [ (if ($s.test | type) == "string" then {kind: "test", name: "test"} else empty end),
            (if ($s.lint | type) == "string" then {kind: "lint", name: "lint"} else empty end),
            (["typecheck", "type-check", "tsc", "check-types"]
               | map(select(($s[.] | type) == "string")) | .[0] // empty
               | {kind: "typecheck", name: .}) ]
        | .[]
        | . as $c | $s[$c.name] as $body
        | {kind: $c.kind, label: label_for($c.name; $body), cmd: ($pm + " " + $c.name),
           runner: (if $c.kind == "test" then runner_of($body) else null end)}' \
        --arg pm "$pm" "$dir/package.json"
}

_dc_makefile() {
    local dir="$1" target recipe
    [ -f "$dir/Makefile" ] || return 0
    local have_lint="false"
    grep -qE '^lint[[:space:]]*:' "$dir/Makefile" && have_lint="true"
    while IFS=$'\t' read -r target recipe; do
        [ -n "$target" ] || continue
        case "$target" in
            test)
                jq -c -n "$JQ_RUNNER_OF"'
                    runner_of($recipe) as $r
                    | {kind: "test", label: ($r // "make test"), cmd: "make test", runner: $r}' \
                    --arg recipe "$recipe" ;;
            lint)
                jq -c -n '{kind: "lint", label: "make lint", cmd: "make lint", runner: null}' ;;
            typecheck)
                jq -c -n '{kind: "typecheck", label: "make typecheck", cmd: "make typecheck", runner: null}' ;;
            check)
                [ "$have_lint" = "true" ] \
                    || jq -c -n '{kind: "lint", label: "make check", cmd: "make check", runner: null}' ;;
        esac
    done < <(awk '
        /^(test|lint|typecheck|check)[[:space:]]*:/ {
            cur = $0; sub(/[[:space:]]*:.*/, "", cur); seen[cur] = 1; next
        }
        /^\t/ { if (cur != "") recipe[cur] = recipe[cur] " " $0; next }
        { cur = "" }
        END { for (t in seen) { r = recipe[t]; gsub(/\t/, " ", r); print t "\t" r } }
    ' "$dir/Makefile")
}

_dc_composer() {
    local dir="$1"
    [ -f "$dir/composer.json" ] || return 0
    jq -c '
        def body: if type == "array" then join(" ") else . end;
        def tool($b): (["phpunit","pest","phpcs","php-cs-fixer","phpstan","psalm","phplint"]
                       | map(select(. as $t | $b | test("\\b" + $t + "\\b"))) | .[0]);
        (.scripts // {}) as $s
        | [ (if $s.test != null then {kind: "test", name: "test"} else empty end),
            (["lint", "phpcs"] | map(select($s[.] != null)) | .[0] // empty | {kind: "lint", name: .}),
            (["phpstan", "psalm"] | map(select($s[.] != null)) | .[0] // empty | {kind: "typecheck", name: .}) ]
        | .[]
        | . as $c | ($s[$c.name] | body) as $b
        | {kind: $c.kind, label: (tool($b) // $c.name), cmd: ("composer " + $c.name),
           runner: (if $c.kind == "test" and ($b | test("\\bphpunit\\b")) then "phpunit" else null end)}' \
        "$dir/composer.json"
}

_dc_python() {
    local dir="$1"
    local py="$dir/pyproject.toml"
    if [ -f "$py" ] || [ -f "$dir/pytest.ini" ] || [ -f "$dir/tox.ini" ] \
        || { [ -f "$dir/setup.cfg" ] && grep -qE '^\[tool:pytest\]' "$dir/setup.cfg"; }; then
        jq -c -n '{kind: "test", label: "pytest", cmd: "python3 -m pytest", runner: "pytest"}'
    fi
    if { [ -f "$py" ] && grep -qE '^\[tool\.ruff' "$py"; } || [ -f "$dir/ruff.toml" ]; then
        jq -c -n '{kind: "lint", label: "ruff", cmd: "ruff check .", runner: null}'
    fi
    if { [ -f "$py" ] && grep -qE '^\[tool\.mypy' "$py"; } || [ -f "$dir/mypy.ini" ]; then
        jq -c -n '{kind: "typecheck", label: "mypy", cmd: "mypy .", runner: null}'
    fi
}

_dc_go() {
    local dir="$1"
    [ -f "$dir/go.mod" ] || return 0
    jq -c -n '{kind: "test", label: "go", cmd: "go test ./...", runner: "go"}'
    jq -c -n '{kind: "lint", label: "go vet", cmd: "go vet ./...", runner: null}'
}

cmd_detect_checks() {
    _parse_args "$@"
    [ -n "$FLAG_dir" ] || _die "--dir is required"
    [ -d "$FLAG_dir" ] || _die "--dir: no such directory: $FLAG_dir"
    {
        _dc_package_json "$FLAG_dir"
        _dc_makefile "$FLAG_dir"
        _dc_composer "$FLAG_dir"
        _dc_python "$FLAG_dir"
        _dc_go "$FLAG_dir"
    } | jq -s '
        . as $all
        | ["test", "lint", "typecheck"]
        | map(. as $k | ($all | map(select(.kind == $k)) | .[0]) // empty)'
}

# parse-test-output helpers. Each reads the ANSI-stripped log file $1 and sets
# P_FILES / P_PASSED / P_FAILED ("" = unknown) and P_PARSED.
_num_before() {
    # $1 = text, $2 = word -> the number right before "<word>" in text, or ""
    printf '%s' "$1" | grep -oE "[0-9]+ $2" | tail -1 | grep -oE '^[0-9]+' || true
}

_pt_vitest() {
    local tf tl
    tf="$(grep -E '^[[:space:]]*Test Files[[:space:]]' "$1" | tail -1 || true)"
    tl="$(grep -E '^[[:space:]]*Tests[[:space:]]+[0-9]' "$1" | tail -1 || true)"
    P_FILES="$(printf '%s' "$tf" | grep -oE '\([0-9]+\)' | tail -1 | tr -d '()' || true)"
    [ -n "$P_FILES" ] || P_FILES="$(_num_before "$tf" passed)"
    P_PASSED="$(_num_before "$tl" passed)"
    P_FAILED="$(_num_before "$tl" failed)"
}

_pt_jest() {
    local sl tl
    sl="$(grep -E '^Test Suites:' "$1" | tail -1 || true)"
    tl="$(grep -E '^Tests:' "$1" | tail -1 || true)"
    P_FILES="$(_num_before "$sl" total)"
    P_PASSED="$(_num_before "$tl" passed)"
    P_FAILED="$(_num_before "$tl" failed)"
}

# The summary is "=== N passed, M failed in 1.2s ===" normally and a bare
# "N passed, M failed in 1.2s" under -q; pytest always lists failed and passed
# before any other count, so a bare line starts with one of them.
_pt_pytest() {
    local line
    line="$(grep -E '^(=+ .*)?[0-9]+ (passed|failed)' "$1" | tail -1 || true)"
    P_FILES=""
    P_PASSED="$(_num_before "$line" passed)"
    P_FAILED="$(_num_before "$line" failed)"
    [ -z "$P_FAILED" ] || [ -n "$P_PASSED" ] || P_PASSED=0
}

_pt_bats() {
    local line total ok nok
    line="$(grep -E '^[0-9]+ tests?, [0-9]+ failures?' "$1" | tail -1 || true)"
    P_FILES=""
    if [ -n "$line" ]; then
        total="$(printf '%s' "$line" | grep -oE '^[0-9]+')"
        P_FAILED="$(printf '%s' "$line" | grep -oE '[0-9]+ failure' | grep -oE '^[0-9]+')"
        P_PASSED=$((total - P_FAILED))
        return 0
    fi
    ok="$(grep -cE '^ok ' "$1" || true)"
    nok="$(grep -cE '^not ok ' "$1" || true)"
    if [ "$((ok + nok))" -gt 0 ]; then
        P_PASSED="$ok"
        P_FAILED="$nok"
    else
        P_PASSED=""
        P_FAILED=""
    fi
}

_pt_phpunit() {
    local ok line total failures errors
    P_FILES=""
    ok="$(grep -oE 'OK \([0-9]+ tests?' "$1" | tail -1 || true)"
    if [ -n "$ok" ]; then
        P_PASSED="$(printf '%s' "$ok" | grep -oE '[0-9]+')"
        P_FAILED=0
        return 0
    fi
    line="$(grep -E '^Tests: [0-9]+' "$1" | tail -1 || true)"
    if [ -n "$line" ]; then
        total="$(printf '%s' "$line" | grep -oE 'Tests: [0-9]+' | grep -oE '[0-9]+')"
        failures="$(printf '%s' "$line" | grep -oE 'Failures: [0-9]+' | grep -oE '[0-9]+' || true)"
        errors="$(printf '%s' "$line" | grep -oE 'Errors: [0-9]+' | grep -oE '[0-9]+' || true)"
        P_FAILED=$(( ${failures:-0} + ${errors:-0} ))
        P_PASSED=$((total - P_FAILED))
        return 0
    fi
    P_PASSED=""
    P_FAILED=""
}

_pt_go() {
    local ok fails
    ok="$(grep -cE '^ok[[:space:]]' "$1" || true)"
    fails="$(grep -cE '^FAIL[[:space:]]' "$1" || true)"
    P_PASSED=""
    if [ "$((ok + fails))" -gt 0 ]; then
        P_FILES="$ok"
        P_FAILED="$fails"
    else
        P_FILES=""
        P_FAILED=""
    fi
}

cmd_parse_test_output() {
    _parse_args "$@"
    case "$FLAG_runner" in
        vitest|jest|pytest|bats|phpunit|go) ;;
        '') _die "--runner is required" ;;
        *) _die "unknown runner: $FLAG_runner" ;;
    esac
    # Not `local`: the EXIT trap runs after this function has returned.
    PT_LOG="$(mktemp)"
    trap 'rm -f "$PT_LOG"' EXIT
    sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' > "$PT_LOG"
    P_FILES=""; P_PASSED=""; P_FAILED=""
    "_pt_$FLAG_runner" "$PT_LOG"
    # A summary that names a passed count but no failed count means zero failed.
    [ -z "$P_PASSED" ] || [ -n "$P_FAILED" ] || P_FAILED=0
    local parsed="false"
    if [ -n "$P_PASSED" ] || [ -n "$P_FILES" ]; then parsed="true"; fi
    jq -n --arg r "$FLAG_runner" --arg files "$P_FILES" --arg p "$P_PASSED" --arg f "$P_FAILED" \
        --argjson parsed "$parsed" '
        def num: if . == "" then null else tonumber end;
        {runner: $r, files: ($files | num), tests_passed: ($p | num), tests_failed: ($f | num), parsed: $parsed}'
}

# render is where two promises are enforced mechanically rather than by prose:
# a failed check can never be dropped from the Testing line (the whole body is
# refused), and a row can never say "Fixed" without a commit behind it. The
# body starts with the 🤖 marker and ends with a hidden review marker that
# find-prior matches on. Defined through a heredoc because the Won't-fix cell
# needs a literal apostrophe; read with the builtin so loading the script runs
# no external command before the jq guard (read returns 1 at EOF, hence || true).
JQ_RENDER=""
IFS= read -r -d '' JQ_RENDER <<'JQ' || true
def commas: tostring | if length <= 3 then . else (.[0:length-3] | commas) + "," + .[length-3:] end;
def clean: tostring | gsub("\r"; "") | gsub("\n"; " ") | gsub("<!--"; "") | gsub("\\|"; "\\|");
def clean_title: clean | gsub("\\["; "\\[") | gsub("\\]"; "\\]");
def oxford: if length == 0 then "" elif length == 1 then .[0]
            else (.[0:length-1] | join(", ")) + " and " + .[length-1] end;
def with_detail($d): if $d != "" then ": " + $d else "" end;
def cell:
  ((.detail // "") | clean) as $d
  | if .outcome == "fixed" then "Fixed in `" + .sha + "`" + with_detail($d)
    elif .outcome == "wont_fix" then "Won't fix" + with_detail($d)
    else "Needs discussion" + with_detail($d) end;
def test_clause:
  if .parsed == true and .tests_passed != null then
    .label + " " + (if .files != null then (.files | commas) + " files / " else "" end)
      + "**" + (.tests_passed | commas) + " tests passed**"
  elif .parsed == true and .files != null then .label + " " + (.files | commas) + " files passed"
  else .label + " passed (count not reported)" end;

. as $in
| ($in.rows // []) as $rows
| ($in.testing.checks // []) as $checks
| ($in.review.id | tostring) as $rid
| ($in.head.short | tostring) as $short
| ($in.pr_url // "") as $pr
| (first($checks[] | select(.status != "passed") | .label | tostring) // null) as $failed
| (first($rows[]
     | if .outcome == "ambiguous" then "REFUSE:unresolved-ambiguous:" + (.comment_id | tostring)
       elif .outcome == "fixed" and ((.sha // "") == "") then "REFUSE:fixed-without-sha:" + (.comment_id | tostring)
       elif .outcome == "fixed" or .outcome == "wont_fix" or .outcome == "needs_discussion" then empty
       else "REFUSE:unknown-outcome:" + (.comment_id | tostring) end) // null) as $row_refusal
| if $failed != null then "REFUSE:checks-failed:" + $failed
  elif ($rows | length) == 0 then "REFUSE:empty-rows"
  elif $row_refusal != null then $row_refusal
  else
    (["🤖 **Review round: " + ($in.review.reviewer_name // "" | tostring) + "** ([review " + $rid
      + "](" + $pr + "#pullrequestreview-" + $rid + "))"]) as $header
    | (["Head is now `" + $short + "`."
        + (if $in.needs_look == true then " The push dismissed the approval, so this needs another look." else "" end)]) as $head
    | (["| Comment | Outcome |", "|---|---|"]
       + ($rows | map("| [" + (.title | clean_title) + "](" + $pr + "#discussion_r" + (.comment_id | tostring)
                      + ") | " + cell + " |"))) as $table
    | (($in.also_found // []) | if length == 0 then [] else
         ["**Also found:** " + (map(.text + " (" + (.shas | map("`" + . + "`") | join(", ")) + ").") | join(" "))] end) as $also
    | ("**Testing at `" + $short + "`**"
       + (if (($in.testing.cwd // "") != "") and ($in.testing.cwd != ".") then " (from `" + $in.testing.cwd + "`)" else "" end)) as $prefix
    | (if ($checks | length) == 0 then [$prefix + ": no test, lint, or typecheck command detected."]
       else
         (([$checks[] | select(.kind == "test") | test_clause])
          + ([$checks[] | select(.kind != "test") | .label] | if length == 0 then [] else [oxford + " clean"] end)) as $clauses
         | [$prefix + ": " + ($clauses | join("; ")) + "."]
       end) as $testing
    | (["<!-- review-respond review=" + $rid + " -->"]) as $marker
    | [$header, $head, $table, $also, $testing, $marker]
      | map(select(length > 0) | join("\n")) | join("\n\n")
  end
JQ

cmd_render() {
    _parse_args "$@"
    _require_file --input "$FLAG_input"
    local out
    out="$(jq -r "$JQ_RENDER" "$FLAG_input")"
    case "$out" in
        REFUSE:*)
            printf '%s\n' "$out"
            exit 2 ;;
    esac
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
    _require_jq
    [ "$#" -ge 1 ] || _usage
    local sub="$1"; shift
    case "$sub" in
        threads)            cmd_threads "$@" ;;
        select-review)      cmd_select_review "$@" ;;
        commits)            cmd_commits "$@" ;;
        map-threads)        cmd_map_threads "$@" ;;
        classify)           cmd_classify "$@" ;;
        dismissed)          cmd_dismissed "$@" ;;
        find-prior)         cmd_find_prior "$@" ;;
        detect-checks)      cmd_detect_checks "$@" ;;
        parse-test-output)  cmd_parse_test_output "$@" ;;
        render)             cmd_render "$@" ;;
        *) _die "unknown subcommand: $sub" ;;
    esac
}

main "$@"
