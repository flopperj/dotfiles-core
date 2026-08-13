#!/usr/bin/env bash
# eval-run.sh — score classifier predictions offline against an eval answer key.
#
# Usage:
#   eval-run.sh --set <path> [--predictions <path>] [--min-accuracy <N>] [--warn-only|--ratchet]
#
# The set is JSONL; each record carries at least {"id","expected"} (full record
# shape: id, summary, description, files_touched, expected, rationale, source).
# Predictions are JSONL records of {"id","predicted"}; when --predictions is
# omitted, each set record's own "predicted" field is used instead.
#
# The runner NEVER invokes an LLM — producing predictions is a separate,
# human- or agent-driven step. It prints per-case PASS/FAIL lines plus an
# accuracy summary, and exits 0 iff accuracy >= --min-accuracy (default 100).
#
# --warn-only decouples the exit code from the threshold, never the report:
# the same full report and accuracy number are printed, a WARN line is added
# on a miss, and the exit code is 0.
#
# --ratchet derives the mode MECHANICALLY from the set's own record count
# (non-empty lines): count < 30 -> warn-only; count >= 30 -> blocking. There
# is no human toggle — the flag cannot be combined with --warn-only, and the
# arm taken plus the count that decided it are always printed.
#
# Fail-closed rules:
#   - non-numeric --min-accuracy is a hard error (exit 1), even with --warn-only
#   - an unreadable/empty set, or zero scorable records, is a hard error
#   - a --ratchet count that cannot be determined from the set file is a hard
#     error — an unreadable set must never silently mean warn-only
#   - a case with no prediction counts as FAIL — never silently skipped
#   - malformed JSONL records are skipped with a stderr warning and counted
#     in the summary
#
# shellcheck shell=bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Tunable constant — the default accuracy threshold (percent). 100 means any
# miss fails: the set is an answer key, so full conformance is the default bar.
# Callers (e.g. the CI ratchet) override via --min-accuracy.
# ---------------------------------------------------------------------------
MIN_ACCURACY_DEFAULT=100

# ---------------------------------------------------------------------------
# Tunable constant — the ratchet's blocking threshold (record count). Below
# this the eval reports but never fails CI; at or above it the exit code
# gates. 30 is pinned by the plan (12 is the seed floor, 30 the gate floor).
# ---------------------------------------------------------------------------
RATCHET_THRESHOLD=30

_die() {
    echo "eval-run: $*" >&2
    exit 1
}

_require_jq() {
    command -v jq >/dev/null 2>&1 || _die "jq is required but not found on PATH"
}

# ---------------------------------------------------------------------------
# Long-flag parser. Sets FLAG_<name> shell vars; --warn-only is a boolean switch.
# ---------------------------------------------------------------------------
FLAG_set=""
FLAG_predictions=""
FLAG_min_accuracy=""
FLAG_warn_only="false"
FLAG_ratchet="false"

_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --set)          FLAG_set="${2:-}";          shift 2 ;;
            --predictions)  FLAG_predictions="${2:-}";  shift 2 ;;
            --min-accuracy) FLAG_min_accuracy="${2:-}"; shift 2 ;;
            --warn-only)    FLAG_warn_only="true";      shift 1 ;;
            --ratchet)      FLAG_ratchet="true";        shift 1 ;;
            *) _die "unknown argument: $1" ;;
        esac
    done
}

# Validate a value is a non-empty digit string BEFORE any -gt/-ge comparison.
# Under set -e, `[ "$x" -ge N ]` on a non-numeric $x is silently treated as
# false inside an `if`, skipping the veto — the gate would fail OPEN. Digit-only
# is not yet decimal-safe (leading zeros read as octal in $(( ))); callers
# force base-10 with 10# at the arithmetic site.
_require_digits() {
    # $1 = name for the error message, $2 = value
    case "$2" in
        ''|*[!0-9]*) _die "$1 must be a non-negative integer, got: '${2}'" ;;
    esac
}

# Print the ratchet's case count: non-empty lines in the set file. Returns
# nonzero when the count cannot be determined (e.g. unreadable file). Note
# grep -c prints "0" and exits 1 on an empty file (zero matches) — that is a
# real count, not a failure; a read error (exit 2) prints nothing to stdout.
_count_records() {
    local count=""
    if count="$(grep -c . "$1" 2>/dev/null)"; then
        printf '%s' "$count"
        return 0
    fi
    if [ "$count" = "0" ]; then
        printf '%s' "$count"
        return 0
    fi
    return 1
}

# Temp file for the id -> predicted lookup built from --predictions.
# bash 3.2 has no associative arrays, so the join is file-based.
TMP_LOOKUP=""
_cleanup() {
    [ -n "$TMP_LOOKUP" ] && rm -f "$TMP_LOOKUP"
    return 0
}
trap _cleanup EXIT

# Build the lookup file (one "id<TAB>predicted" row per valid prediction).
# Malformed prediction lines are skipped with a warning.
_build_prediction_lookup() {
    local pred_file="$1"
    TMP_LOOKUP="$(mktemp)"
    local line id predicted lnum=0
    while IFS= read -r line || [ -n "$line" ]; do
        lnum=$((lnum + 1))
        [ -n "$line" ] || continue
        if ! id="$(printf '%s' "$line" | jq -er '.id' 2>/dev/null)" \
            || ! predicted="$(printf '%s' "$line" | jq -er '.predicted' 2>/dev/null)"; then
            echo "eval-run: WARNING: skipping malformed prediction line $lnum" >&2
            continue
        fi
        printf '%s\t%s\n' "$id" "$predicted" >> "$TMP_LOOKUP"
    done < "$pred_file"
}

# Resolve the prediction for a case: from the lookup file when --predictions
# was given, else from the set record's own "predicted" field. Empty when none.
_prediction_for() {
    local id="$1" record="$2"
    if [ -n "$TMP_LOOKUP" ]; then
        awk -F '\t' -v id="$id" '$1 == id { print $2; exit }' "$TMP_LOOKUP"
    else
        printf '%s' "$record" | jq -r '.predicted // empty' 2>/dev/null
    fi
}

# ===========================================================================
# The single run: score every case, print the report, gate on the threshold.
# ===========================================================================
cmd_run() {
    _parse_args "$@"
    [ -n "$FLAG_set" ] || _die "usage: eval-run.sh --set <path> [--predictions <path>] [--min-accuracy <N>] [--warn-only|--ratchet]"
    [ -f "$FLAG_set" ] || _die "set file not found: $FLAG_set"

    # The mechanical ratchet: derive warn-only vs blocking from the set's own
    # record count. Fail-closed — an indeterminable count is a hard error,
    # never a silent warn-only default, and there is no human toggle (the
    # flag combination that would provide one is rejected).
    if [ "$FLAG_ratchet" = "true" ]; then
        [ "$FLAG_warn_only" = "false" ] \
            || _die "--ratchet and --warn-only cannot be combined: the ratchet derives the mode mechanically from the set's record count"
        local count
        if ! count="$(_count_records "$FLAG_set")"; then
            _die "ratchet: cannot determine case count from set file: $FLAG_set"
        fi
        _require_digits "ratchet case count" "$count"
        # Force base-10 (see the --min-accuracy note below).
        count=$(( 10#$count ))
        if [ "$count" -ge "$RATCHET_THRESHOLD" ]; then
            printf 'ratchet: %d cases >= %d -> blocking (exit code gates)\n' "$count" "$RATCHET_THRESHOLD"
        else
            FLAG_warn_only="true"
            printf 'ratchet: %d cases < %d -> warn-only (non-blocking)\n' "$count" "$RATCHET_THRESHOLD"
        fi
    fi

    local min_accuracy="${FLAG_min_accuracy:-$MIN_ACCURACY_DEFAULT}"
    _require_digits "--min-accuracy" "$min_accuracy"
    # Force base-10: a leading-zero digit string ("049") is otherwise read as
    # octal by $(( )) — an invalid literal here, a silently smaller value in
    # comparisons elsewhere.
    min_accuracy=$(( 10#$min_accuracy ))

    if [ -n "$FLAG_predictions" ]; then
        [ -f "$FLAG_predictions" ] || _die "predictions file not found: $FLAG_predictions"
        _build_prediction_lookup "$FLAG_predictions"
    fi

    local scored=0 correct=0 malformed=0 lnum=0
    local line id expected predicted
    while IFS= read -r line || [ -n "$line" ]; do
        lnum=$((lnum + 1))
        [ -n "$line" ] || continue
        if ! id="$(printf '%s' "$line" | jq -er '.id' 2>/dev/null)" \
            || ! expected="$(printf '%s' "$line" | jq -er '.expected' 2>/dev/null)"; then
            malformed=$((malformed + 1))
            echo "eval-run: WARNING: skipping malformed set record at line $lnum" >&2
            continue
        fi
        predicted="$(_prediction_for "$id" "$line")"
        scored=$((scored + 1))
        if [ -z "$predicted" ]; then
            # Fail-closed: an unpredicted case is a miss, not a skip — an
            # empty predictions file must never score 100%.
            printf 'FAIL %s (expected=%s predicted=(none))\n' "$id" "$expected"
        elif [ "$predicted" = "$expected" ]; then
            correct=$((correct + 1))
            printf 'PASS %s (expected=%s predicted=%s)\n' "$id" "$expected" "$predicted"
        else
            printf 'FAIL %s (expected=%s predicted=%s)\n' "$id" "$expected" "$predicted"
        fi
    done < "$FLAG_set"

    if [ "$scored" -eq 0 ]; then
        _die "no scorable records in set: $FLAG_set ($malformed malformed skipped)"
    fi

    # Counts are internally derived, but the accuracy division is a gate input:
    # validate anyway so a future refactor cannot fail open.
    _require_digits "scored count" "$scored"
    _require_digits "correct count" "$correct"
    local accuracy=$(( 10#$correct * 100 / 10#$scored ))

    printf 'cases: %d scored, %d malformed skipped\n' "$scored" "$malformed"
    printf 'accuracy: %d%% (%d/%d)\n' "$accuracy" "$correct" "$scored"

    if [ "$accuracy" -ge "$min_accuracy" ]; then
        printf 'RESULT: PASS (accuracy %d%% >= min %d%%)\n' "$accuracy" "$min_accuracy"
        return 0
    fi
    if [ "$FLAG_warn_only" = "true" ]; then
        printf 'WARN: accuracy %d%% < min %d%% (warn-only: exit 0)\n' "$accuracy" "$min_accuracy"
        return 0
    fi
    printf 'RESULT: FAIL (accuracy %d%% < min %d%%)\n' "$accuracy" "$min_accuracy"
    return 1
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
    _require_jq
    cmd_run "$@"
}

main "$@"
