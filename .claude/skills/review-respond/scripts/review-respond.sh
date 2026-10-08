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

cmd_commits() {
    _parse_args "$@"
    [ -n "$FLAG_base" ] || _die "--base is required"
    local head="${FLAG_head:-HEAD}" dir="${FLAG_repo_dir:-.}"
    [ -d "$dir" ] || _die "--repo-dir: no such directory: $dir"
    _die "not implemented: commits ($head)"
}

cmd_map_threads() {
    _parse_args "$@"
    _require_file --threads "$FLAG_threads"
    _require_file --commits "$FLAG_commits"
    [ -n "$FLAG_review" ] || _die "--review is required"
    local window="${FLAG_window:-5}"
    case "$window" in
        ''|*[!0-9]*) _die "--window must be a non-negative integer" ;;
    esac
    _die "not implemented: map-threads"
}

cmd_classify() {
    _parse_args "$@"
    _require_file --map "$FLAG_map"
    _die "not implemented: classify"
}

cmd_dismissed() {
    _parse_args "$@"
    _require_file --reviews "$FLAG_reviews"
    [ -n "$FLAG_head" ] || _die "--head is required"
    [ -z "$FLAG_timeline" ] || _require_file --timeline "$FLAG_timeline"
    _die "not implemented: dismissed (${FLAG_review_decision:-no decision})"
}

cmd_find_prior() {
    _parse_args "$@"
    _require_file --comments "$FLAG_comments"
    [ -n "$FLAG_review" ] || _die "--review is required"
    [ -n "$FLAG_me" ] || _die "--me is required"
    _die "not implemented: find-prior"
}

cmd_detect_checks() {
    _parse_args "$@"
    [ -n "$FLAG_dir" ] || _die "--dir is required"
    [ -d "$FLAG_dir" ] || _die "--dir: no such directory: $FLAG_dir"
    _die "not implemented: detect-checks"
}

cmd_parse_test_output() {
    _parse_args "$@"
    case "$FLAG_runner" in
        vitest|jest|pytest|bats|phpunit|go) ;;
        '') _die "--runner is required" ;;
        *) _die "unknown runner: $FLAG_runner" ;;
    esac
    _die "not implemented: parse-test-output"
}

cmd_render() {
    _parse_args "$@"
    _require_file --input "$FLAG_input"
    _die "not implemented: render"
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
