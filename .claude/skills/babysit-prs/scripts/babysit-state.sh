#!/usr/bin/env bash
# babysit-state.sh — per-run JSON state store for the /babysit-prs skill.
#
# Pure state-store CLI: JSON/args in, JSON/values out. No network I/O — the
# SKILL.md Actor prose owns all gh/Slack/git calls; this script only reads and
# writes the run's state file. All writes are atomic (write-temp-then-rename),
# so a single-writer-per-tick caller needs no locking.
#
# State home:  ~/.claude/tasks/<project>/babysit-prs/
#   <project>  = basename(git toplevel || pwd), overridable via $BABYSIT_PROJECT
#   <run_id>.json  — one file per run
#   latest.json    — symlink to the active run's file
#
# The on-disk shape is documented (and fixture-tested) in ../data/state-schema.json.
#
# Subcommands:
#   state-init  --run-id <id> [--flags <str>] [--my-login <login>] [--targets <str>]
#       Create <run_id>.json (run-level fields, empty .prs) + latest.json symlink.
#   state-load  --targets <str>
#       Resume-match: print the run_id of the most-recent run file whose
#       .targets exactly matches; exit non-zero if none match.
#   state-read-pr  --run-id <id> --pr <n>
#       Print the per-PR record JSON on stdout; exit non-zero if absent.
#   state-write-pr --run-id <id> --pr <n> --record <json>
#       Store/replace the per-PR record (round-trips verbatim).
#   state-set-run  --run-id <id> --set <dotpath=value> [--set ...]
#       Set run-level fields by dotted path (e.g. slack.channel_id=C123).
#
# shellcheck shell=bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

_project() {
    # Same convention as metrics.jsonl / obligations.yaml. Overridable in tests.
    if [ -n "${BABYSIT_PROJECT:-}" ]; then
        printf '%s\n' "$BABYSIT_PROJECT"
        return 0
    fi
    basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

_state_dir() {
    printf '%s/.claude/tasks/%s/babysit-prs\n' "$HOME" "$(_project)"
}

_run_file() {
    printf '%s/%s.json\n' "$(_state_dir)" "$1"
}

_die() {
    echo "babysit-state: $*" >&2
    exit 1
}

_require_jq() {
    command -v jq >/dev/null 2>&1 || _die "jq is required but not found on PATH"
}

# ---------------------------------------------------------------------------
# Atomic write: render JSON to a temp file in the same dir, fsync-ish, rename.
# rename(2) within a directory is atomic, so a concurrent reader sees either the
# old or the new complete file — never a partial write. The temp file is removed
# on any error via the trap, leaving no strays.
# ---------------------------------------------------------------------------
_atomic_write() {
    # $1 = destination path, stdin = content
    local dest="$1" dir tmp
    dir="$(dirname "$dest")"
    mkdir -p "$dir"
    tmp="$(mktemp "$dir/.babysit-state.XXXXXX")"
    # Ensure the temp file never lingers if we die before the rename.
    trap 'rm -f "$tmp"' RETURN
    cat >"$tmp"
    # Refuse to commit empty content. A producer that fails mid-pipe (e.g. a jq
    # compile error upstream) yields an empty stdin; without this guard the
    # `mv` would atomically replace valid state with a 0-byte file, silently
    # breaking the "reader always sees a complete file" invariant. Fail closed:
    # leave the existing dest untouched and error out. (jq always emits at least
    # a trailing newline for real output, so a non-empty file here is genuine.)
    if [ ! -s "$tmp" ]; then
        _die "refusing to write empty content to $dest (upstream producer failed)"
    fi
    mv -f "$tmp" "$dest"
}

# Normalize a targets string to a canonical, order-independent form so that
# "482 491" and "491 482" resume-match the same run.
_canon_targets() {
    # Split on whitespace, drop empties, sort, join with single spaces.
    printf '%s\n' "$1" | tr -s '[:space:]' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//'
}

# ---------------------------------------------------------------------------
# Simple long-flag parser: sets FLAG_<name> shell vars. --set is multi-valued
# and collected into the SET_KV array.
# ---------------------------------------------------------------------------
FLAG_run_id=""
FLAG_flags=""
FLAG_my_login=""
FLAG_targets=""
FLAG_pr=""
FLAG_record=""
SET_KV=()

_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --run-id)   FLAG_run_id="${2:-}";   shift 2 ;;
            --flags)    FLAG_flags="${2:-}";     shift 2 ;;
            --my-login) FLAG_my_login="${2:-}";  shift 2 ;;
            --targets)  FLAG_targets="${2:-}";   shift 2 ;;
            --pr)       FLAG_pr="${2:-}";        shift 2 ;;
            --record)   FLAG_record="${2:-}";    shift 2 ;;
            --set)      SET_KV+=("${2:-}");      shift 2 ;;
            *) _die "unknown argument: $1" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_state_init() {
    _parse_args "$@"
    [ -n "$FLAG_run_id" ] || _die "state-init requires --run-id"

    local file started canon
    file="$(_run_file "$FLAG_run_id")"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    canon="$(_canon_targets "$FLAG_targets")"

    jq -n \
        --arg run_id   "$FLAG_run_id" \
        --arg started  "$started" \
        --arg flags    "$FLAG_flags" \
        --arg my_login "$FLAG_my_login" \
        --arg targets  "$canon" \
        '{
            run_id:   $run_id,
            started:  $started,
            flags:    $flags,
            my_login: $my_login,
            slack:    { channel_id: null, last_seen_ts: null, enabled: false },
            targets:  $targets,
            prs:      {}
        }' | _atomic_write "$file"

    # (Re)point latest.json at this run. Use a relative link so the symlink
    # survives if the tasks tree is relocated wholesale.
    local dir
    dir="$(_state_dir)"
    ln -sfn "$FLAG_run_id.json" "$dir/latest.json"
}

cmd_state_load() {
    _parse_args "$@"
    local dir want
    dir="$(_state_dir)"
    want="$(_canon_targets "$FLAG_targets")"
    [ -d "$dir" ] || _die "no state dir yet"

    # Walk run files newest-first by mtime; print the first whose canonicalized
    # .targets equals the requested set.
    local f candidate mt best_mt="" best_id=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        candidate="$(jq -r '.targets // ""' "$f" 2>/dev/null || echo "")"
        candidate="$(_canon_targets "$candidate")"
        if [ "$candidate" = "$want" ]; then
            mt="$(_mtime "$f")"
            if [ -z "$best_mt" ] || [ "$mt" -gt "$best_mt" ]; then
                best_mt="$mt"
                best_id="$(jq -r '.run_id' "$f")"
            fi
        fi
    done < <(find "$dir" -maxdepth 1 -type f -name '*.json' ! -name 'latest.json' 2>/dev/null)

    [ -n "$best_id" ] || _die "no matching run for targets: $want"
    printf '%s\n' "$best_id"
}

# Portable mtime-as-epoch (GNU vs BSD stat).
#
# Cannot rely on `stat -f %m || stat -c %Y`: on GNU/Linux `stat -f` is valid
# (it means --file-system) and exits 0, so the `||` fallback never fires and we
# get the verbose filesystem block instead of an mtime. Detect GNU explicitly —
# only GNU coreutils stat has --version.
_mtime() {
    if stat --version >/dev/null 2>&1; then
        stat -c %Y "$1" 2>/dev/null || echo 0   # GNU
    else
        stat -f %m "$1" 2>/dev/null || echo 0    # BSD/macOS
    fi
}

cmd_state_read_pr() {
    _parse_args "$@"
    [ -n "$FLAG_run_id" ] || _die "state-read-pr requires --run-id"
    [ -n "$FLAG_pr" ]     || _die "state-read-pr requires --pr"

    local file
    file="$(_run_file "$FLAG_run_id")"
    [ -f "$file" ] || _die "no such run: $FLAG_run_id"

    # Emit the record only if present; a miss is a non-zero exit, never a
    # fabricated record.
    local record
    record="$(jq -c --arg pr "$FLAG_pr" '.prs[$pr] // empty' "$file")"
    [ -n "$record" ] || _die "no record for PR $FLAG_pr in run $FLAG_run_id"
    printf '%s\n' "$record"
}

cmd_state_write_pr() {
    _parse_args "$@"
    [ -n "$FLAG_run_id" ] || _die "state-write-pr requires --run-id"
    [ -n "$FLAG_pr" ]     || _die "state-write-pr requires --pr"
    [ -n "$FLAG_record" ] || _die "state-write-pr requires --record"

    local file
    file="$(_run_file "$FLAG_run_id")"
    [ -f "$file" ] || _die "no such run: $FLAG_run_id"

    # Validate the incoming record is JSON before we touch the file.
    printf '%s' "$FLAG_record" | jq -e '.' >/dev/null 2>&1 \
        || _die "--record is not valid JSON"

    # Store the record verbatim under .prs[<pr>] (replace, not deep-merge, so a
    # record round-trips byte-for-byte). Atomic write keeps the file always
    # valid on disk.
    jq --arg pr "$FLAG_pr" --argjson record "$FLAG_record" \
        '.prs[$pr] = $record' "$file" | _atomic_write "$file"
}

cmd_state_set_run() {
    _parse_args "$@"
    [ -n "$FLAG_run_id" ] || _die "state-set-run requires --run-id"
    [ "${#SET_KV[@]}" -gt 0 ] || _die "state-set-run requires at least one --set key=value"

    local file
    file="$(_run_file "$FLAG_run_id")"
    [ -f "$file" ] || _die "no such run: $FLAG_run_id"

    # Build one jq program applying every dotted-path assignment. Values are
    # typed: true/false/null and bare integers become JSON scalars; everything
    # else is a string.
    local kv key val prog=""
    for kv in "${SET_KV[@]}"; do
        case "$kv" in
            *=*) key="${kv%%=*}"; val="${kv#*=}" ;;
            *)   _die "malformed --set (want key=value): $kv" ;;
        esac
        [ -n "$key" ] || _die "empty key in --set: $kv"
        # The key is interpolated RAW into the jq program below, so it must be a
        # safe dotted path (alnum/underscore segments joined by '.') — nothing
        # else. Reject any key with a jq metacharacter (e.g. '(', '|', spaces)
        # BEFORE building the program: a malformed key makes jq fail to compile,
        # emit empty stdout, and (absent this guard + the _atomic_write guard)
        # truncate the state file. Fail closed, touch nothing. Values are always
        # injected as typed literals (below), never raw, so only keys need this.
        case "$key" in
            *[!a-zA-Z0-9._]* | .* | *. | *..*)
                _die "invalid --set key (want a dotted path like slack.channel_id): $key" ;;
        esac
        local jqval
        case "$val" in
            true|false|null)                 jqval="$val" ;;
            ''|*[!0-9]*)                      jqval="$(printf '%s' "$val" | jq -R '.')" ;;
            *)                               jqval="$val" ;;  # all-digits -> number
        esac
        prog="${prog}.${key} = ${jqval} | "
    done
    prog="${prog%| }"

    # Compute the new document and validate it is non-empty valid JSON BEFORE
    # letting it reach the atomic rename — mirrors cmd_state_write_pr's
    # validate-before-write discipline. On any jq failure, the state file is
    # left byte-identical. (_atomic_write also refuses empty content as a
    # second line of defense.)
    local updated
    updated="$(jq "$prog" "$file")" || _die "state-set-run: jq failed to apply --set program"
    printf '%s' "$updated" | jq -e '.' >/dev/null 2>&1 \
        || _die "state-set-run: produced invalid JSON; state left unchanged"
    printf '%s\n' "$updated" | _atomic_write "$file"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
    _require_jq
    [ "$#" -ge 1 ] || _die "usage: babysit-state.sh <state-init|state-load|state-read-pr|state-write-pr|state-set-run> [args]"
    local sub="$1"; shift
    case "$sub" in
        state-init)     cmd_state_init "$@" ;;
        state-load)     cmd_state_load "$@" ;;
        state-read-pr)  cmd_state_read_pr "$@" ;;
        state-write-pr) cmd_state_write_pr "$@" ;;
        state-set-run)  cmd_state_set_run "$@" ;;
        *) _die "unknown subcommand: $sub" ;;
    esac
}

main "$@"
