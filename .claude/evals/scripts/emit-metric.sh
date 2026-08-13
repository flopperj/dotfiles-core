#!/usr/bin/env bash
# emit-metric.sh — append a structured metrics event to the project's metrics.jsonl.
#
# Usage: echo '{"event_type":"...","agent":"...","project":"..."}' | bash emit-metric.sh
#
# Emission is best-effort by contract: a pipeline must never block on a metric
# write. jq present => validate + inject timestamp; jq absent => warn on stderr
# and append unvalidated. Callers append `|| true`.
#
# Output: ~/.claude/tasks/<project>/metrics.jsonl
#   <project> = basename of git repo root, else basename of $PWD.

# shellcheck shell=bash

set -euo pipefail

# Read stdin into variable
INPUT="$(cat)"

if [ -z "$INPUT" ]; then
  echo "emit-metric: empty input — nothing to emit" >&2
  exit 1
fi

# Resolve project name from git repo root
PROJECT_NAME=""
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$GIT_ROOT" ]; then
  PROJECT_NAME="$(basename "$GIT_ROOT")"
else
  PROJECT_NAME="$(basename "$PWD")"
fi

METRICS_DIR="$HOME/.claude/tasks/$PROJECT_NAME"
METRICS_FILE="$METRICS_DIR/metrics.jsonl"

mkdir -p "$METRICS_DIR"

if command -v jq &>/dev/null; then
  # --- jq available: validate and enrich ---

  # Validate it is parseable JSON first
  if ! echo "$INPUT" | jq . &>/dev/null; then
    echo "emit-metric: input is not valid JSON — rejecting" >&2
    exit 1
  fi

  # Check required fields
  MISSING=""
  for field in event_type agent project; do
    val="$(echo "$INPUT" | jq -r ".$field // empty")"
    if [ -z "$val" ]; then
      MISSING="$MISSING $field"
    fi
  done

  if [ -n "$MISSING" ]; then
    echo "emit-metric: missing required fields:$MISSING — rejecting" >&2
    exit 1
  fi

  # Inject timestamp if missing
  HAS_TS="$(echo "$INPUT" | jq -r '.timestamp // empty')"
  if [ -z "$HAS_TS" ]; then
    INPUT="$(echo "$INPUT" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {timestamp: $ts}')"
  fi

  # Write compact single line
  echo "$INPUT" | jq -c . >> "$METRICS_FILE"

else
  # --- jq absent: graceful degradation ---
  echo "emit-metric: jq not found, skipping validation" >&2

  # Best-effort timestamp injection: if "timestamp" string not present in input,
  # inject it after the opening brace using bash parameter expansion.
  if [[ "$INPUT" != *'"timestamp"'* ]]; then
    TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    INPUT="${INPUT/\{/\{\"timestamp\":\"$TS\",}"
  fi

  echo "$INPUT" >> "$METRICS_FILE"
fi

exit 0
