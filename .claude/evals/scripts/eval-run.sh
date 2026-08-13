#!/usr/bin/env bash
# eval-run.sh — score classifier predictions offline against an eval answer key.
#
# Usage:
#   eval-run.sh --set <path> [--predictions <path>] [--min-accuracy <N>] [--warn-only]
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
# Fail-closed rules:
#   - non-numeric --min-accuracy is a hard error (exit 1), even with --warn-only
#   - an unreadable/empty set, or zero scorable records, is a hard error
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

_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --set)          FLAG_set="${2:-}";          shift 2 ;;
            --predictions)  FLAG_predictions="${2:-}";  shift 2 ;;
            --min-accuracy) FLAG_min_accuracy="${2:-}"; shift 2 ;;
            --warn-only)    FLAG_warn_only="true";      shift 1 ;;
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
    [ -n "$FLAG_set" ] || _die "usage: eval-run.sh --set <path> [--predictions <path>] [--min-accuracy <N>] [--warn-only]"
    [ -f "$FLAG_set" ] || _die "set file not found: $FLAG_set"

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
