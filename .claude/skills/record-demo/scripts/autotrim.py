#!/usr/bin/env python3
"""Plan the edit for a choreographed recording and print a finish.sh segment list.

usage: autotrim.py <frames-dir> <events.json> [--marks marks.tsv] [--no-auto-pending]

<frames-dir> is the RAW screencast output (screencast.mjs), not the composited frames:
its frames contain only what the page painted, so cursor motion (drawn later by
composite.py) can't be mistaken for UI change. The cursor's own activity comes
straight from the events log, which is exact. Video time 0 = the first line of
<frames-dir>/times.txt, which is also where composite.py and assemble.sh start.

Every 1/30s slot of the recording is classed, highest priority first:
  action   glides, clicks + ripple, typing, scrolls, d.hold(), caption reading time.
           Kept at 1x, so a cut or speed change never lands mid-glide or mid-ripple.
  pending  d.pending() spans (and fast-start/fast-end marks). Sped up, never cut.
  change   the page repainted visibly (with a short lead-in and a tail to see the
           result). Kept at 1x; a change run longer than AUTO_PENDING_S with no
           action is treated as loading/streaming and sped up after its first 0.5s.
  static   nothing moves. Cut when longer than MIN_GAP_S. Cutting a static run is
           seamless: the frames on both sides are identical, cursor included.
"""
import json, math, os, sys
import numpy as np
from PIL import Image

FPS = 30
DIFF_LEVEL, MIN_CHANGED_PX = 18, 6     # on a 320px-wide grey thumbnail; a text caret
                                       # blink (~1px wide) stays under MIN_CHANGED_PX
CHANGE_LEAD_S, CHANGE_TAIL_S = 0.2, 0.7
ACTION_LEAD_S, ACTION_TAIL_S = 0.25, 0.15
CLICK_TAIL_S = 0.5                     # ripple (420ms) plus a beat
MIN_GAP_S = 0.4                        # shorter static runs are kept (avoid choppy cuts)
AUTO_PENDING_S, AUTO_PENDING_KEEP_S = 1.5, 0.5
OPENING_S, CLOSING_S = 0.6, 1.0        # establishing shot before the first action; final hold
PENDING_TARGET_S, MAX_SPEED = 1.2, 8   # a pending span plays in ~1.2s, at most 8x


def caption_read_s(text):
    return 0.3 if not text else min(3.5, max(1.2, 0.8 + 0.045 * len(text)))


def changed_pixels(frames_dir, files):
    """Per source frame: number of visibly changed thumbnail pixels vs the previous frame."""
    prev, out = None, []
    for f in files:
        im = Image.open(f"{frames_dir}/{f}")
        im.draft("L", (im.width // 4, im.height // 4))  # fast DCT-domain downscale for JPEG
        im = im.convert("L")
        im = im.resize((320, max(1, round(320 * im.height / im.width))), Image.BILINEAR)
        a = np.asarray(im, dtype=np.int16)
        if prev is None or prev.shape != a.shape:
            out.append(10**6 if prev is not None else 0)
        else:
            out.append(int((np.abs(a - prev) > DIFF_LEVEL).sum()))
        prev = a
    return out


def main():
    args = sys.argv[1:]
    is_auto_pending = "--no-auto-pending" not in args
    args = [a for a in args if a != "--no-auto-pending"]
    marks_file = None
    if "--marks" in args:
        i = args.index("--marks")
        marks_file = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    frames_dir, events_file = args
    ev = json.load(open(events_file))
    times = [float(t) for t in open(f"{frames_dir}/times.txt").read().split()]
    files = sorted(f for f in os.listdir(frames_dir) if f.endswith(".jpg"))
    T0, T1 = times[0], times[-1]
    n = int(math.ceil((T1 - T0) * FPS)) + 1
    slot = lambda t: min(n, max(0, int(round((t - T0) * FPS))))

    ACTION, PENDING, CHANGE, STATIC = 3, 2, 1, 0
    cls = np.full(n, STATIC, dtype=np.int8)

    def paint(t0, t1, c):
        a, b = slot(t0), slot(t1)
        cls[a:b] = np.maximum(cls[a:b], c)

    # Visual change from the raw frames. A frame at time t shows a change that
    # happened just before it.
    px = changed_pixels(frames_dir, files)
    for t, p in zip(times[1:], px[1:]):
        if p >= MIN_CHANGED_PX:
            paint(t - CHANGE_LEAD_S, t + CHANGE_TAIL_S, CHANGE)

    # Explicit pending spans.
    pending = [(p["t0"], p["t1"]) for p in ev.get("pending", [])]
    if marks_file:
        start = None
        for line in open(marks_file):
            if "\t" not in line:
                continue
            epoch, label = line.rstrip("\n").split("\t", 1)
            if label == "fast-start":
                start = float(epoch)
            elif label == "fast-end" and start is not None:
                pending.append((start, float(epoch)))
                start = None
    for a, b in pending:
        paint(a, b, PENDING)

    # Cursor and keyboard activity, captions, holds: always kept at 1x.
    action_starts = []
    for m in ev.get("moves", []):
        paint(m["t0"] - ACTION_LEAD_S, m["t1"] + ACTION_TAIL_S, ACTION); action_starts.append(m["t0"])
    for c in ev.get("clicks", []):
        paint(c["t"] - ACTION_LEAD_S, c["t"] + CLICK_TAIL_S, ACTION); action_starts.append(c["t"])
    for k in ev.get("keys", []) + ev.get("scrolls", []) + ev.get("holds", []):
        paint(k["t0"] - ACTION_LEAD_S, k["t1"] + ACTION_TAIL_S, ACTION); action_starts.append(k["t0"])
    for c in ev.get("captions", []):
        paint(c["t"], c["t"] + caption_read_s(c["text"]), ACTION); action_starts.append(c["t"])

    # Opening and closing: a short establishing shot, then a final hold.
    first = min(action_starts, default=T0)
    paint(max(T0, first - OPENING_S), first, ACTION)
    last = max([i for i in range(n) if cls[i] != STATIC], default=0)
    paint(T0 + last / FPS, T0 + last / FPS + CLOSING_S, ACTION)

    # Runs -> (start_slot, end_slot, speed or None to cut).
    runs, i = [], 0
    while i < n:
        j = i
        while j < n and cls[j] == cls[i]:
            j += 1
        runs.append([i, j, int(cls[i])])
        i = j

    plan = []   # (a, b, speed) in slots; speed 0 = cut
    for k, (a, b, c) in enumerate(runs):
        dur = (b - a) / FPS
        if c == STATIC:
            is_edge = k == 0 or k == len(runs) - 1
            plan.append((a, b, 0 if (dur > MIN_GAP_S or is_edge) else 1))
        elif c == PENDING:
            plan.append((a, b, min(MAX_SPEED, max(1, round(dur / PENDING_TARGET_S, 1)))))
        elif c == CHANGE and is_auto_pending and dur > AUTO_PENDING_S:
            keep = round(AUTO_PENDING_KEEP_S * FPS)
            plan.append((a, a + keep, 1))
            rest = (b - a - keep) / FPS
            plan.append((a + keep, b, min(MAX_SPEED, max(1, round(rest / PENDING_TARGET_S, 1)))))
        else:
            plan.append((a, b, 1))

    # Merge neighbours with the same speed; drop cuts.
    segs = []
    for a, b, s in plan:
        if s == 0 or b <= a:
            continue
        if segs and segs[-1][1] == a and segs[-1][2] == s:
            segs[-1][1] = b
        else:
            segs.append([a, b, s])

    fmt = lambda s: ("" if s == 1 else f"@{s:g}")
    print(",".join(f"{a / FPS:.3f}-{b / FPS:.3f}{fmt(s)}" for a, b, s in segs))
    out_s = sum((b - a) / FPS / s for a, b, s in segs)
    sped = sum((b - a) / FPS for a, b, s in segs if s > 1)
    print(f"# raw {(T1 - T0):.1f}s -> {out_s:.1f}s: {len(segs)} segments, "
          f"{sum(1 for a, b, s in plan if s == 0)} static gaps cut, {sped:.1f}s of pending sped up",
          file=sys.stderr)


if __name__ == "__main__":
    main()
