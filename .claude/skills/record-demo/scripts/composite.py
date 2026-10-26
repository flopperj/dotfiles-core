#!/usr/bin/env python3
"""Resample screencast frames to a constant 30fps and draw the demo cursor on top.

usage: composite.py <frames-dir> <events.json> <out-dir>

Screencast frames arrive unevenly (only on repaint, with gaps while the machine is
busy), so a cursor drawn in the page snaps. Here each output frame holds the latest
screencast frame at or before its time, and the cursor is drawn at the position
interpolated from the logged path (cursor.mjs) for that exact time, so its motion is
smooth whatever the capture did. Clicks get a ring that grows out of the click point.

<out-dir> gets NNNNN.jpg + times.txt + meta.json + uniform_fps, the layout
assemble.sh reads (uniform_fps makes it read the frames 1:1 as an image sequence).
"""
import bisect, json, math, os, shutil, sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from PIL import Image, ImageDraw, ImageFilter

FPS = 30
FILL, OUTLINE = (0x67, 0x1D, 0xC9), (255, 255, 255)   # #671DC9
CURSOR_SCALE = 2.7                  # Figma arrow is ~12x16 CSS px; outline + shadow scale with it
RIPPLE_RADIUS, RIPPLE_MS = 30, 420  # click circle grows from the click point to 30 CSS px
RIPPLE_RING, RIPPLE_FILL_ALPHA = 3, 72   # opaque 3 CSS px ring around a ~28% fill
RIPPLE_FADE_FROM = 0.7               # fully opaque until 70% of the animation, then fades
PRESS_MS = 160                      # cursor dips slightly on click
# Figma-style arrow, tip at the hotspot (CSS px at scale 1).
ARROW = [(0.5, 1.2), (0.5, 16.9), (5.4, 12.45), (11.8, 12.37)]


def in_out_sine(t):
    return -(math.cos(math.pi * t) - 1) / 2


EASINGS = {"inOutSine": in_out_sine}   # module-level so the worker processes can pickle it


def ease_fn(name):
    if name not in EASINGS:
        raise SystemExit(f"unknown easing {name!r} in the events log")
    return EASINGS[name]


class Compositor:
    def __init__(self, src, ev, size, S):
        self.src, self.ev, self.size, self.S = src, ev, size, S
        self.ease = ease_fn(ev.get("ease"))
        self.moves = sorted(ev["moves"], key=lambda m: m["t0"])
        self.sprites = {}
        # (t, S) steps from the CSS-viewport history; S_at(t) is the entry in force at t.
        self.s_steps = []

    def S_at(self, t):
        s = self.S
        for ts, v in self.s_steps:
            if ts <= t:
                s = v
            else:
                break
        return s

    def cursor_pos(self, t):
        pos = self.ev["start"]
        for m in self.moves:
            if t < m["t0"]:
                break
            k = min(1.0, (t - m["t0"]) / max(1e-6, m["t1"] - m["t0"]))
            e = self.ease(k)
            pos = {"x": m["from"]["x"] + (m["to"]["x"] - m["from"]["x"]) * e,
                   "y": m["from"]["y"] + (m["to"]["y"] - m["from"]["y"]) * e}
        return pos

    def make_sprite(self, scale):
        """RGBA arrow: white outline, #671DC9 fill, soft drop shadow; supersampled."""
        SS, pad = 8, 10
        k = self.S * scale
        w, h = int((12 + 2 * pad) * k), int((18 + 2 * pad) * k)
        big = (w * SS, h * SS)
        pts = [((x + pad) * k * SS, (y + pad) * k * SS) for x, y in ARROW]
        shape = Image.new("RGBA", big, (0, 0, 0, 0))
        d = ImageDraw.Draw(shape)
        stroke = max(1, round(1.6 * k * SS))
        d.polygon(pts, fill=OUTLINE + (255,))
        d.line(pts + [pts[0]], fill=OUTLINE + (255,), width=stroke * 2, joint="curve")
        for p in pts:  # round the outline's corners
            d.ellipse([p[0] - stroke, p[1] - stroke, p[0] + stroke, p[1] + stroke], fill=OUTLINE + (255,))
        inner = Image.new("L", big, 0)
        ImageDraw.Draw(inner).polygon(pts, fill=255)
        inner = inner.filter(ImageFilter.MinFilter(max(3, (round(0.5 * k * SS) // 2) * 2 + 1)))
        shape.paste(Image.new("RGBA", big, FILL + (255,)), (0, 0), inner)
        alpha = shape.split()[3]
        shadow = Image.new("RGBA", big, (0, 0, 0, 0))
        shadow.paste(Image.new("RGBA", big, (0, 0, 0, 120)), (0, round(1.5 * k * SS)), alpha)
        shadow = shadow.filter(ImageFilter.GaussianBlur(2.2 * k * SS))
        shadow.alpha_composite(shape)
        return shadow.resize((w, h), Image.LANCZOS), (pad * k, pad * k)  # + hotspot offset

    def sprite_for(self, scale):
        key = (round(self.S, 4), round(scale, 2))
        if key not in self.sprites:
            self.sprites[key] = self.make_sprite(scale)
        return self.sprites[key]

    @staticmethod
    def paste(img, layer, x, y):
        """alpha_composite that clips at the frame edges (PIL rejects negative offsets)."""
        sx, sy = max(0, -x), max(0, -y)
        dx, dy = max(0, x), max(0, y)
        w = min(layer.width - sx, img.width - dx)
        h = min(layer.height - sy, img.height - dy)
        if w > 0 and h > 0:
            img.alpha_composite(layer, (dx, dy), (sx, sy, sx + w, sy + h))

    def draw_ripples(self, img, t):
        S = self.S
        for c in self.ev["clicks"]:
            age = (t - c["t"]) * 1000
            if not 0 <= age < RIPPLE_MS:
                continue
            k = age / RIPPLE_MS
            r = max(1.0, RIPPLE_RADIUS * (1 - (1 - k) ** 3) * S)   # ease-out growth
            fade = 1.0 if k < RIPPLE_FADE_FROM else (1 - k) / (1 - RIPPLE_FADE_FROM)
            R = math.ceil(RIPPLE_RADIUS * S) + 4
            SS = 4   # supersample so the thin ring stays crisp and round
            big = Image.new("RGBA", (2 * R * SS, 2 * R * SS), (0, 0, 0, 0))
            cx = cy = (R + (c["x"] * S) % 1) * SS   # keep the sub-pixel centre
            rr, ring = r * SS, max(1, round(RIPPLE_RING * S * SS))
            d = ImageDraw.Draw(big)
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=FILL + (round(RIPPLE_FILL_ALPHA * fade),))
            if rr > ring:   # draw the ring as its own annulus so it isn't blended with the fill
                ring_mask = Image.new("L", big.size, 0)
                md = ImageDraw.Draw(ring_mask)
                md.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=round(255 * fade))
                md.ellipse([cx - rr + ring, cy - rr + ring, cx + rr - ring, cy + rr - ring], fill=0)
                big.paste(Image.new("RGBA", big.size, FILL + (round(255 * fade),)), (0, 0), ring_mask)
            layer = big.resize((2 * R, 2 * R), Image.LANCZOS)
            self.paste(img, layer, math.floor(c["x"] * S) - R, math.floor(c["y"] * S) - R)

    def press_scale(self, t):
        for c in self.ev["clicks"]:
            age = (t - c["t"]) * 1000
            if 0 <= age < PRESS_MS:
                return 1 - 0.18 * math.sin(math.pi * age / PRESS_MS)
        return 1.0

    def load(self, name):
        im = Image.open(f"{self.src}/{name}").convert("RGB")
        if im.size != self.size:   # e.g. the first frame, captured before the viewport lock
            im.thumbnail(self.size, Image.LANCZOS)
            canvas = Image.new("RGB", self.size)
            canvas.paste(im, ((self.size[0] - im.width) // 2, (self.size[1] - im.height) // 2))
            im = canvas
        return im.convert("RGBA")

    def render(self, job):
        """Render output frames [n0, n1); each item is (n, t, source-frame-name)."""
        out, items = job
        cache_name, cache_img = None, None
        for n, t, name in items:
            self.S = self.S_at(t)
            if name != cache_name:
                cache_img, cache_name = self.load(name), name
            img = cache_img.copy()
            self.draw_ripples(img, t)
            p = self.cursor_pos(t)
            sp, (hx, hy) = self.sprite_for(CURSOR_SCALE * self.press_scale(t))
            self.paste(img, sp, round(p["x"] * self.S - hx), round(p["y"] * self.S - hy))
            img.convert("RGB").save(f"{out}/{n:05d}.jpg", quality=92)
        return len(items)


def _render(args):
    comp, job = args
    return comp.render(job)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    src, events_file, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".jpg"):
            os.remove(f"{out}/{f}")
    ev = json.load(open(events_file))
    ev.setdefault("clicks", [])
    meta = json.load(open(f"{src}/meta.json"))
    times = [float(t) for t in open(f"{src}/times.txt").read().split()]
    files = sorted(f for f in os.listdir(src) if f.endswith(".jpg"))
    if len(files) != len(times):
        sys.exit(f"{src}: {len(files)} frames but {len(times)} timestamps")

    # Output size = the most common frame size (the first frame can predate the
    # viewport lock); S = source pixels per CSS px. Events are logged in the
    # page's CSS viewport, which is wider than the window when the page is
    # zoomed out, so scale by that width when the events record it.
    sizes = Counter(Image.open(f"{src}/{f}").size for f in files[:: max(1, len(files) // 50)] + files[-1:])
    size = sizes.most_common(1)[0][0]
    # With a timestamped viewport history (cursor.mjs v3) S follows it, so a zoom
    # change mid-run stays aligned; otherwise the single recorded viewport, then meta.
    css_width = (ev.get("viewport") or {}).get("width") or meta["width"]
    S = size[0] / css_width
    history = sorted((v for v in ev.get("viewports", []) if v.get("width")), key=lambda v: v["t"])
    if history:
        S = size[0] / history[0]["width"]   # before the first sample

    t_start, t_end = times[0], times[-1]
    n_out = max(1, int((t_end - t_start) * FPS)) + 1    # last frame lands on (or just before) t_end
    items = []
    for n in range(n_out):
        t = t_start + n / FPS
        i = min(len(files) - 1, max(0, bisect.bisect_right(times, t + 1e-6) - 1))
        items.append((n, t, files[i]))

    comp = Compositor(src, ev, size, S)
    comp.s_steps = [(v["t"], size[0] / v["width"]) for v in history]
    workers = max(1, min(8, (os.cpu_count() or 2) - 1))
    chunk = math.ceil(len(items) / workers)
    jobs = [(comp, (out, items[k:k + chunk])) for k in range(0, len(items), chunk)]
    with ProcessPoolExecutor(workers) as pool:
        done = sum(pool.map(_render, jobs))

    with open(f"{out}/times.txt", "w") as f:
        f.write("\n".join(f"{t_start + n / FPS:.4f}" for n in range(n_out)))
    with open(f"{out}/uniform_fps", "w") as f:
        f.write(str(FPS))
    shutil.copy(f"{src}/meta.json", f"{out}/meta.json")
    if os.path.exists(f"{src}/urls.tsv"):
        shutil.copy(f"{src}/urls.tsv", f"{out}/urls.tsv")
    lock_width = meta["width"]   # window/lock width = CSS width at 100% page zoom
    uniq = list(dict.fromkeys(round(size[0] / v["width"], 4) for v in history)) or [round(S, 4)]
    zooms = ", ".join(f"{lock_width * s / size[0]:.0%}" for s in uniq)
    print(f"composited {done} frames at {FPS}fps ({(n_out - 1) / FPS:.1f}s, {size[0]}x{size[1]}, "
          f"S={', '.join(f'{s:g}' for s in uniq)}, css viewport {css_width}px, derived page zoom {zooms})")


if __name__ == "__main__":
    main()
