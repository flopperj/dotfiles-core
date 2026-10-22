#!/usr/bin/env bash
# Record a Playwright choreography end to end in Claude's demo Chrome:
# screencast -> run.mjs -> stop -> composite.py (cursor) -> assemble.sh (URL bar)
# -> autotrim.py (edit plan) -> finish.sh (<10 MB mp4).
#
# Usage: choreo.sh <url-fragment> <choreography.mjs> <work-dir> [out.mp4] [options]
#   --dry-run       run the choreography with a live cursor drawn in the page, no recording
#   --size WxH      viewport to lock while recording (default 1280x800)
#   --no-url-bar    skip the URL caption bar
#   --segments S    use this finish.sh segment list instead of autotrim's
# Without out.mp4 it stops after writing <work-dir>/raw.mp4 and segments.txt.
# Start the browser first: demo-browser.sh start "<url>".
set -euo pipefail

usage() { sed -n '2,13p' "$0" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
pos=() dry=0 size=1280x800 urlbar=1 segs=""
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) dry=1 ;;
    --size) size=$2; shift ;;
    --no-url-bar) urlbar=0 ;;
    --segments) segs=$2; shift ;;
    -h|--help) usage ;;
    *) pos+=("$1") ;;
  esac
  shift
done
[ "${#pos[@]}" -ge 3 ] || usage
frag=${pos[0]} choreo=${pos[1]} D=${pos[2]} out=${pos[3]:-}
mkdir -p "$D"
py=${DEMO_PYTHON:-python3}

if [ "$dry" = 1 ]; then
  DEMO_LOCK_WIDTH=${size%x*} exec node "$here/run.mjs" "$frag" "$choreo" "$D/events-dry.json" --preview
fi

rm -rf "$D/frames" "$D/comp"
node "$here/screencast.mjs" "$frag" "$D/frames" "${size%x*}" "${size#*x}" > "$D/screencast.log" 2>&1 &
rec=$!
trap 'kill -INT $rec 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do grep -q recording "$D/screencast.log" && break; kill -0 $rec 2>/dev/null || break; sleep 0.25; done
grep -q recording "$D/screencast.log" || { cat "$D/screencast.log" >&2; exit 1; }
sleep 0.4   # let the viewport lock settle before the choreography measures the page

status=0
DEMO_LOCK_WIDTH=${size%x*} node "$here/run.mjs" "$frag" "$choreo" "$D/events.json" || status=$?
sleep 0.3
kill -INT $rec; wait $rec || true; trap - EXIT
cat "$D/screencast.log"
[ "$status" = 0 ] || { echo "choreography failed; frames kept in $D/frames" >&2; exit "$status"; }

"$py" "$here/composite.py" "$D/frames" "$D/events.json" "$D/comp"
url=""
[ "$urlbar" = 1 ] && url=$(head -1 "$D/frames/urls.tsv" | cut -f2)
bash "$here/assemble.sh" "$D/comp" "$D/raw.mp4" "$url"
[ -n "$segs" ] || segs=$("$py" "$here/autotrim.py" "$D/frames" "$D/events.json")
echo "$segs" > "$D/segments.txt"
echo "segments: $segs"
[ -z "$out" ] || bash "$here/finish.sh" "$D/raw.mp4" "$out" "$segs"
