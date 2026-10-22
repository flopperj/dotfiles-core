#!/usr/bin/env bash
# Record a region of the screen (usually the browser window) to a raw .mov.
#
# Usage:
#   record.sh check                      # verify Screen Recording permission
#   record.sh start <x> <y> <w> <h> <workdir>
#   record.sh mark <workdir> <label>     # timestamp a step (seconds since start)
#   record.sh stop <workdir>
#
# Coordinates are screen points (what window.screenX/outerWidth report), not
# Retina pixels. State lives in <workdir>: raw.mov, pid, started_at, marks.tsv.
set -euo pipefail

cmd=${1:-}
shift || true

case "$cmd" in
  check)
    tmp=$(mktemp -t record-demo-check).png
    if screencapture -x -R0,0,8,8 "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      rm -f "$tmp"
      echo "ok"
    else
      rm -f "$tmp"
      echo "denied: grant Screen Recording to the Claude app in System Settings → Privacy & Security → Screen Recording, then restart Claude" >&2
      exit 1
    fi
    ;;

  start)
    [ "$#" -eq 5 ] || { echo "usage: record.sh start <x> <y> <w> <h> <workdir>" >&2; exit 2; }
    x=$1 y=$2 w=$3 h=$4 dir=$5
    mkdir -p "$dir"
    [ -f "$dir/pid" ] && kill -0 "$(cat "$dir/pid")" 2>/dev/null && { echo "already recording (pid $(cat "$dir/pid"))" >&2; exit 1; }
    rm -f "$dir/raw.mov" "$dir/marks.tsv"
    # -v video, -C cursor, -k click highlights, -x no sound.
    nohup screencapture -v -C -k -x -R"$x,$y,$w,$h" "$dir/raw.mov" >"$dir/screencapture.log" 2>&1 &
    echo $! >"$dir/pid"
    python3 -c 'import time; print(time.time())' >"$dir/started_at"
    sleep 1
    kill -0 "$(cat "$dir/pid")" 2>/dev/null || { echo "screencapture exited early:" >&2; cat "$dir/screencapture.log" >&2; exit 1; }
    echo "recording pid $(cat "$dir/pid") → $dir/raw.mov"
    ;;

  mark)
    [ "$#" -ge 2 ] || { echo "usage: record.sh mark <workdir> <label>" >&2; exit 2; }
    dir=$1; shift
    now=$(python3 -c 'import time; print(time.time())')
    start=$(cat "$dir/started_at")
    printf '%.1f\t%s\n' "$(python3 -c "print($now - $start)")" "$*" | tee -a "$dir/marks.tsv"
    ;;

  stop)
    [ "$#" -eq 1 ] || { echo "usage: record.sh stop <workdir>" >&2; exit 2; }
    dir=$1
    pid=$(cat "$dir/pid")
    # SIGINT makes screencapture finalize the file (SIGTERM/KILL leave it unplayable).
    kill -INT "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    rm -f "$dir/pid"
    [ -s "$dir/raw.mov" ] || { echo "no recording written; see $dir/screencapture.log" >&2; exit 1; }
    ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$dir/raw.mov" | xargs printf 'stopped: %s (%.1fs)\n' "$dir/raw.mov"
    ;;

  *)
    sed -n '2,10p' "$0" >&2
    exit 2
    ;;
esac
