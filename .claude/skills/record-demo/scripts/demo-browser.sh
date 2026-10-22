#!/usr/bin/env bash
# Claude's own Chrome instance for background demos: separate persistent profile,
# DevTools on localhost:${DEMO_CDP_PORT:-9333}, and flags that keep rendering when the window is
# covered or minimized, so the user can keep working while Claude drives it.
#
# Usage:
#   demo-browser.sh start [url]   # background launch (never steals focus)
#   demo-browser.sh login [url]   # foreground launch so the user can sign in
#   demo-browser.sh status
#   demo-browser.sh stop
#
# The DevTools port is unauthenticated: any local process can drive this browser
# (and its signed-in sessions) while it runs. Stop it when the demo is done.
set -euo pipefail

PROFILE="$HOME/Library/Application Support/claude-demo-chrome"
PORT=${DEMO_CDP_PORT:-9333}
CHROME="/Applications/Google Chrome.app"

running() { curl -s -m 2 "http://127.0.0.1:$PORT/json/version" >/dev/null; }

launch() {
  local url=${2:-about:blank}
  if running; then echo "already running on :$PORT"; return; fi
  mkdir -p "$PROFILE"
  # DEMO_SCALE=2 renders at 2x on a 1x display, so the screencast stream itself is 2x.
  # -n: new instance alongside the user's Chrome. -g: don't activate.
  open $1 -na "$CHROME" --args \
    --user-data-dir="$PROFILE" --remote-debugging-port=$PORT \
    --remote-debugging-address=127.0.0.1 \
    --no-first-run --no-default-browser-check \
    --disable-backgrounding-occluded-windows --disable-renderer-backgrounding \
    --disable-background-timer-throttling \
    --window-size=1280,900 ${DEMO_SCALE:+--force-device-scale-factor=$DEMO_SCALE} "$url"
  for _ in $(seq 1 40); do running && { echo "running on :$PORT (profile: $PROFILE)"; return; }; sleep 0.25; done
  echo "Chrome did not open DevTools on :$PORT" >&2; exit 1
}

case "${1:-}" in
  start) launch -g "${2:-}" ;;
  login) launch -F "${2:-}" ;;
  status) running && echo "running on :$PORT" || { echo "not running"; exit 1; } ;;
  stop) pkill -f -- "--user-data-dir=$PROFILE" && echo stopped || echo "not running" ;;
  *) sed -n '2,13p' "$0" >&2; exit 2 ;;
esac
