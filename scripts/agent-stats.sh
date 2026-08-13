#!/usr/bin/env bash
# agent-stats.sh — Aggregate ~/.claude/tasks/*/metrics.jsonl into a system-level
# summary of agent pipeline health.
#
# Usage:
#   bash scripts/agent-stats.sh [--project <name>] [--days <N>]
#
# Defaults: all projects, last 30 days.
#
# Output is plain text, one section per cohort, designed to be read by humans
# and pasted into reports. No JSON, no colors, no fancy formatting — terminals
# render it consistently and the /agent-stats skill copies it verbatim.
#
# Failure modes:
#   - jq missing: prints a one-line warning and exits 0 (no stats to give).
#   - No metrics files at all: prints "no metrics yet" and exits 0.
#   - Project filter matches nothing: prints "no metrics for <project>" and exits 0.
#
# This script is read-only. It does not modify any metrics files or the
# directory structure. Safe to invoke at any time.
#
# Targets bash 3.2 (macOS system bash): no mapfile/readarray, and empty
# arrays are expanded with the ${arr[@]:-} guard because "${arr[@]}" on an
# empty array trips "unbound variable" under set -u.

# shellcheck shell=bash

set -euo pipefail

PROJECT_FILTER=""
DAYS=30

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT_FILTER="$2"
      shift 2
      ;;
    --days)
      DAYS="$2"
      shift 2
      ;;
    *)
      echo "agent-stats: unknown arg '$1'" >&2
      echo "Usage: $0 [--project <name>] [--days <N>]" >&2
      exit 1
      ;;
  esac
done

TASKS_DIR="$HOME/.claude/tasks"

if ! command -v jq &>/dev/null; then
  echo "agent-stats: jq not found — install jq to use this skill" >&2
  exit 0
fi

if [ ! -d "$TASKS_DIR" ]; then
  echo "No metrics directory found at $TASKS_DIR."
  echo "Run an agent pipeline (Cyrus, ticket-pickup, ticket-swarm) to start emitting metrics."
  exit 0
fi

# Resolve cutoff — events with timestamp >= cutoff are kept.
# date -u -d works on GNU; -v works on BSD/macOS. Try both.
CUTOFF=""
if CUTOFF="$(date -u -d "$DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
elif CUTOFF="$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
else
  echo "agent-stats: cannot compute cutoff date — date command unsupported" >&2
  exit 1
fi

# Collect candidate files
CANDIDATES=()
if [ -n "$PROJECT_FILTER" ]; then
  CANDIDATES=("$TASKS_DIR/$PROJECT_FILTER/metrics.jsonl")
else
  while IFS= read -r _f; do
    CANDIDATES+=("$_f")
  done < <(find "$TASKS_DIR" -name 'metrics.jsonl' 2>/dev/null)
fi

# Materialise events in window
EVENTS_TMP="$(mktemp)"
trap 'rm -f "$EVENTS_TMP"' EXIT INT TERM

for f in "${CANDIDATES[@]:-}"; do
  [ -f "$f" ] || continue
  # Filter by cutoff. jq -c keeps lines compact; --arg passes cutoff string.
  jq -c --arg cutoff "$CUTOFF" 'select(.timestamp >= $cutoff)' "$f" 2>/dev/null >> "$EVENTS_TMP" || true
done

TOTAL_EVENTS="$(wc -l < "$EVENTS_TMP" | tr -d ' ')"

# Header
echo "Agent Stats — last $DAYS days"
if [ -n "$PROJECT_FILTER" ]; then
  echo "Project: $PROJECT_FILTER"
else
  echo "Scope:   all projects"
fi
echo "Cutoff:  $CUTOFF"
echo

if [ "$TOTAL_EVENTS" = "0" ]; then
  echo "No events in window."
  if [ -n "$PROJECT_FILTER" ]; then
    echo "Either the project has not run any agent pipelines recently, or metrics emission failed."
  else
    echo "Run an agent pipeline (Cyrus, ticket-pickup, ticket-swarm) to start emitting metrics."
  fi
  exit 0
fi

echo "Total events: $TOTAL_EVENTS"
echo

# ----------------------------------------------------------------------------
# Pipeline complete — first-pass success rate
# ----------------------------------------------------------------------------
echo "## Pipeline Outcomes"
echo

PIPELINE_STATS="$(jq -s '
  map(select(.event_type == "pipeline_complete"))
  | {
      total: length,
      first_pass: ([.[] | select(.data.first_pass == true)] | length),
      tests_failed: ([.[] | select(.data.tests_passed == false)] | length),
      ci_fix_total: ([.[] | (.data.ci_fix_attempts // 0)] | add // 0),
      avg_duration: (if length == 0 then 0 else ([.[] | (.data.duration_seconds // 0)] | add) / length end),
      by_classification: (
        group_by(.data.classification) |
        map({
          classification: (.[0].data.classification // "unknown"),
          n: length,
          first_pass: ([.[] | select(.data.first_pass == true)] | length)
        })
      ),
      by_agent: (
        group_by(.agent) |
        map({
          agent: .[0].agent,
          n: length,
          first_pass: ([.[] | select(.data.first_pass == true)] | length)
        })
      )
    }
' "$EVENTS_TMP")"

PIPE_TOTAL="$(echo "$PIPELINE_STATS" | jq -r '.total')"

if [ "$PIPE_TOTAL" = "0" ]; then
  echo "No pipeline_complete events yet."
  echo
else
  PIPE_FP="$(echo "$PIPELINE_STATS" | jq -r '.first_pass')"
  PIPE_FAIL="$(echo "$PIPELINE_STATS" | jq -r '.tests_failed')"
  CI_TOTAL="$(echo "$PIPELINE_STATS" | jq -r '.ci_fix_total')"
  AVG_DUR="$(echo "$PIPELINE_STATS" | jq -r '.avg_duration | floor')"

  if [ "$PIPE_TOTAL" -gt 0 ]; then
    PIPE_FP_PCT="$(awk "BEGIN { printf \"%.0f\", ($PIPE_FP / $PIPE_TOTAL) * 100 }")"
  else
    PIPE_FP_PCT="0"
  fi

  echo "Pipelines completed:    $PIPE_TOTAL"
  echo "First-pass success:     $PIPE_FP / $PIPE_TOTAL  (${PIPE_FP_PCT}%)"
  echo "Tests-failed events:    $PIPE_FAIL"
  echo "CI fix attempts (sum):  $CI_TOTAL"
  echo "Avg pipeline duration:  ${AVG_DUR}s"
  echo

  echo "By classification:"
  echo "$PIPELINE_STATS" | jq -r '
    .by_classification[]
    | "  \(.classification | tostring | (. + "                ")[0:14])  \(.n) runs, \(.first_pass)/\(.n) first-pass"
  '
  echo

  echo "By agent:"
  echo "$PIPELINE_STATS" | jq -r '
    .by_agent[]
    | "  \(.agent | tostring | (. + "                          ")[0:26])  \(.n) runs, \(.first_pass)/\(.n) first-pass"
  '
  echo
fi

# ----------------------------------------------------------------------------
# Ticket classification distribution
# ----------------------------------------------------------------------------
echo "## Classification Distribution"
echo

CLASS_TOTAL="$(jq -s 'map(select(.event_type == "ticket_classified")) | length' "$EVENTS_TMP")"

if [ "$CLASS_TOTAL" = "0" ]; then
  echo "No ticket_classified events yet."
  echo
else
  echo "Tickets classified: $CLASS_TOTAL"
  echo
  jq -s '
    map(select(.event_type == "ticket_classified"))
    | group_by(.data.classification)
    | map({classification: (.[0].data.classification // "unknown"), n: length, overrides: ([.[] | select(.data.override != null)] | length)})
    | .[] | "  \(.classification | tostring | (. + "                ")[0:14])  \(.n) tickets, \(.overrides) user overrides"
  ' "$EVENTS_TMP" | tr -d '"'
  echo
fi

# ----------------------------------------------------------------------------
# Swarm runs
# ----------------------------------------------------------------------------
echo "## Swarm Runs"
echo

SWARM_TOTAL="$(jq -s 'map(select(.event_type == "swarm_complete")) | length' "$EVENTS_TMP")"

if [ "$SWARM_TOTAL" = "0" ]; then
  echo "No swarm_complete events yet."
  echo
else
  jq -s '
    map(select(.event_type == "swarm_complete"))
    | {
        runs: length,
        tickets: ([.[] | (.data.tickets_total // 0)] | add // 0),
        completed: ([.[] | (.data.completed // 0)] | add // 0),
        prs: ([.[] | (.data.prs_created // 0)] | add // 0),
        avg_first_pass: (if length == 0 then 0 else ([.[] | (.data.first_pass_rate // 0)] | add) / length end)
      }
    | "Swarm runs:           \(.runs)\nTickets processed:    \(.tickets)\nCompleted:            \(.completed)\nPRs created:          \(.prs)\nAvg first-pass rate:  \(.avg_first_pass | (. * 100 | floor))%"
  ' "$EVENTS_TMP" | tr -d '"'
  echo
fi

# ----------------------------------------------------------------------------
# Health flags — surface signals worth attention
# ----------------------------------------------------------------------------
echo "## Health Flags"
echo

FLAGS=()

if [ "$PIPE_TOTAL" -ge 5 ]; then
  PIPE_FP_PCT_INT="$PIPE_FP_PCT"
  if [ "$PIPE_FP_PCT_INT" -lt 60 ]; then
    FLAGS+=("First-pass rate is ${PIPE_FP_PCT_INT}% (<60%) over $PIPE_TOTAL pipelines — investigate Optimus plan quality or Cyrus retries.")
  fi
fi

if [ "$PIPE_TOTAL" -ge 5 ] && [ "$CI_TOTAL" -gt "$PIPE_TOTAL" ]; then
  FLAGS+=("CI fix attempts ($CI_TOTAL) exceed pipeline count ($PIPE_TOTAL) — Cyrus is hitting CI more than once per pipeline on average.")
fi

if [ "$PIPE_TOTAL" -lt 5 ] && [ "$SWARM_TOTAL" -lt 1 ]; then
  FLAGS+=("Sample size is small ($PIPE_TOTAL pipelines) — trends are not yet meaningful. Re-run after more activity.")
fi

if [ "${#FLAGS[@]}" -eq 0 ]; then
  echo "No flags raised."
else
  for flag in "${FLAGS[@]:-}"; do
    [ -n "$flag" ] || continue
    echo "  - $flag"
  done
fi
echo
