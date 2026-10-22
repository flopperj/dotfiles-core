#!/usr/bin/env bash
# Trim a raw recording down to the kept segments and encode a PR-ready MP4.
#
# Usage: finish.sh <raw.mov> <out.mp4> <segments>
#   segments: comma-separated start-end seconds, each optionally sped up:
#             "0-12.5,14-40@4,41-55"  (14–40s plays at 4x; gaps are cut)
#             use "all" to keep the whole recording.
#
# Output: H.264 / yuv420p / 30fps / no audio / faststart, max 1280px wide (MAX_W),
# re-encoded with stronger compression until it is under 10 MB (the upload limit).
set -euo pipefail

[ "$#" -eq 3 ] || { sed -n '2,10p' "$0" >&2; exit 2; }
in=$1 out=$2 segs=$3
limit=$((10 * 1024 * 1024))
max_w=${MAX_W:-1280}            # MAX_W=2560 keeps a 2x capture at full resolution
crfs=${CRFS:-26 30 34 38}       # tried in order until the file is under the limit

if [ "$segs" = "all" ]; then
  dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$in")
  segs="0-$dur"
fi

filter="" labels="" i=0
IFS=',' read -ra parts <<<"$segs"
for p in "${parts[@]}"; do
  range=${p%@*}
  speed=1
  [[ "$p" == *@* ]] && speed=${p#*@}
  start=${range%-*} end=${range#*-}
  filter+="[0:v]trim=start=${start}:end=${end},setpts=(PTS-STARTPTS)/${speed}[v$i];"
  labels+="[v$i]"
  i=$((i + 1))
done
filter+="${labels}concat=n=${i}:v=1:a=0,fps=30,scale='min(${max_w},iw)':-2,format=yuv420p[out]"

for crf in $crfs; do
  ffmpeg -hide_banner -loglevel error -y -i "$in" -filter_complex "$filter" -map "[out]" \
    -c:v libx264 -preset slow -crf "$crf" -movflags +faststart -an "$out"
  size=$(stat -f%z "$out")
  if [ "$size" -lt "$limit" ]; then
    dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$out")
    printf '%s  %.1fs  %.1f MB  (crf %s)\n' "$out" "$dur" "$(echo "$size / 1048576" | bc -l)" "$crf"
    exit 0
  fi
done
echo "still over 10 MB at crf 38; cut more or speed up idle segments" >&2
exit 1
