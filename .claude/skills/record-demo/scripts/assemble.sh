#!/usr/bin/env bash
# Turn DevTools screencast frames into a constant-30fps raw video, optionally
# with a URL caption bar stacked on top. The output feeds finish.sh like raw.mov.
#
# Usage: assemble.sh <frames-dir> <out.mp4> [url]
#   frames-dir: NNNNN.jpg frames + times.txt (one epoch-seconds timestamp per frame),
#               either raw from screencast.mjs or uniform 30fps from composite.py
#   url:        caption text; omit for no caption bar
# Video time 0 = the first line of times.txt.
set -euo pipefail

[ "$#" -ge 2 ] || { sed -n '2,9p' "$0" >&2; exit 2; }
dir=$1 out=$2 url=${3:-}
here=$(cd "$(dirname "$0")" && pwd)

if [ -f "$dir/uniform_fps" ]; then
  # Uniform frames (composite.py) are read 1:1 as an image sequence. Going through a
  # concat list with per-frame durations makes fps=30 repeat and skip frames, which
  # shows up as the cursor stalling then jumping.
  inp=(-framerate "$(cat "$dir/uniform_fps")" -start_number 0 -i "$dir/%05d.jpg")
else
  # Raw screencast frames: each frame is held until the next one arrived (screencast
  # only sends frames on repaint, so gaps are real stillness).
  python3 - "$dir" <<'PY'
import os, sys
d = sys.argv[1]
ts = [float(t) for t in open(f"{d}/times.txt").read().split()]
frames = sorted(f for f in os.listdir(d) if f.endswith(".jpg"))
with open(f"{d}/concat.txt", "w") as f:
    for i, name in enumerate(frames):
        dur = (ts[i + 1] - ts[i]) if i + 1 < len(ts) else 0.5
        f.write(f"file '{name}'\nduration {max(dur, 0.001):.4f}\n")
    f.write(f"file '{frames[-1]}'\n")
PY
  inp=(-f concat -safe 0 -i "$dir/concat.txt")
fi

# Output size = the last frame's (the first can predate the viewport lock).
jpgs=("$dir"/*.jpg); last=${jpgs[${#jpgs[@]}-1]}
read -r w h < <(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$last" | tr ',' ' ')
# Viewport width in CSS px (from screencast.mjs), so the caption's text size matches the page.
vw=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['width'])" "$dir/meta.json" 2>/dev/null || echo $((w / 2)))
fit="scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"
if [ -n "$url" ]; then
  bin="$dir/.caption"
  [ -x "$bin" ] || swiftc -O -o "$bin" "$here/caption.swift"
  # Caption is laid out at the page's CSS width and rendered at the frames' pixel density.
  "$bin" "$url" "$vw" "$(python3 -c "print($w / $vw)")" "$dir/caption.png"
  # The caption image must loop at 30fps too: at ffmpeg's default 25fps, vstack emits a
  # mixed-rate stream that duplicates and drops frames.
  ffmpeg -hide_banner -loglevel error -y "${inp[@]}" -loop 1 -framerate 30 -i "$dir/caption.png" \
    -filter_complex "[0:v]${fit},fps=30[p];[1:v]scale=${w}:-2[c];[c][p]vstack=shortest=1,fps=30,format=yuv420p" \
    -r 30 -c:v libx264 -preset veryfast -crf 18 "$out"
else
  ffmpeg -hide_banner -loglevel error -y "${inp[@]}" \
    -vf "${fit},fps=30,format=yuv420p" -r 30 -c:v libx264 -preset veryfast -crf 18 "$out"
fi
ffprobe -v error -show_entries stream=width,height -show_entries format=duration -of compact=p=0:nk=1 "$out" | paste -sd' ' - | xargs printf "$out %s\n"
