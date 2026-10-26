// Playwright helper for demo choreography in Claude's demo Chrome (demo-browser.sh).
//
// The visible cursor is NOT drawn in the page. A CDP screencast delivers frames
// unevenly (and the video is later resampled to a fixed frame rate), so a cursor
// drawn in the page snaps. Instead this helper drives the real mouse and keyboard
// (so hover, focus and click handlers fire) and logs what it did as timestamped
// events. composite.py draws the cursor and click ripples on a constant-30fps
// timeline afterwards, and autotrim.py uses the same log to decide what to cut.
// Captions stay in the page: they change rarely, so frame pacing doesn't matter.
//
// Times in the log are epoch seconds from Date.now(). The screencast's frame
// timestamps are on the same clock: a DOM change lands in a frame ~6-11 ms after
// Node sends it (measured), well under one 30fps frame.
//
// Usually run through run.mjs, which passes the helper to a choreography module:
//   export default async function (d) {
//     await d.caption('Search for an entity');
//     await d.clickEl(d.page.getByRole('searchbox'));
//     await d.type('arrow');
//     await d.pending(() => d.page.waitForSelector('.results'));  // sped up in the edit
//     await d.hold(1500);                                          // never cut
//   }
//
// Locators inside iframes work as-is (Playwright reports their boxes relative to
// the main viewport): d.page.frameLocator('iframe').locator('…'), or
// d.frame('about:srcdoc').locator('…') for an editor canvas rendered in a srcdoc iframe.
import { chromium } from 'playwright-core';
import fs from 'node:fs';

export const sleep = ms => new Promise(r => setTimeout(r, ms));
const now = () => Date.now() / 1000;

// Sine ease-in-out: peak speed is only ~1.6x the average, so a fast glide still reads
// as motion at 30fps. (Cubic peaks at 3x: ~100-180px per frame, which looks like a jump.)
// composite.py replays the same curve, named in the event log.
const ease = t => -(Math.cos(Math.PI * t) - 1) / 2;
// Glide duration scales with distance: 400ms for short hops, 800ms across the screen.
const glideMs = dist => Math.min(800, Math.max(400, 250 + dist * 0.55));

// Same arrow as composite.py, for the dry-run preview only.
const PREVIEW_CURSOR = `<svg width="33" height="46" viewBox="-1 0 14 18" style="overflow:visible;filter:drop-shadow(0 2px 3px rgba(0,0,0,.45))"><path d="M.5 1.2v15.7l4.9-4.45 6.4-.08z" fill="#671DC9" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;

/**
 * @param {string} urlFragment  picks the tab whose URL contains it
 * @param {{eventsFile?: string, isPreviewEnabled?: boolean, start?: {x:number,y:number}, cdpUrl?: string}} opts
 *   isPreviewEnabled: draw a live cursor in the page so someone watching the window can
 *   follow along. The screencast captures it, so use it for dry runs only.
 */
export async function connect(urlFragment, { eventsFile, isPreviewEnabled = false, start, cdpUrl = `http://127.0.0.1:${process.env.DEMO_CDP_PORT || 9333}` } = {}) {
  const browser = await chromium.connectOverCDP(cdpUrl);
  const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().includes(urlFragment));
  if (!page) throw new Error(`no tab with URL containing ${urlFragment}`);
  // Never page.bringToFront(): it activates the Chrome window and steals the user's
  // focus. Focus emulation makes the page behave as focused (focus/blur, :focus
  // styles, caret) while the window stays in the background.
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: true });

  // CSS viewport + page zoom. Browser page zoom (Cmd +/-) changes innerWidth: at 75% a
  // 1280px-wide capture is a 1707 CSS px viewport. zoom = lockWidth / innerWidth, where
  // lockWidth is the CSS width screencast.mjs pins with Emulation.setDeviceMetricsOverride
  // (choreo.sh passes it as DEMO_LOCK_WIDTH, i.e. innerWidth at 100% zoom). That ratio does
  // not depend on the device scale factor. outerWidth/innerWidth is unreliable (window
  // chrome, DevTools docks), so without DEMO_LOCK_WIDTH the fallback is
  // devicePixelRatio / DEMO_DSF (default 2, the screencast's deviceScaleFactor), because
  // page zoom multiplies devicePixelRatio.
  const lockWidth = +process.env.DEMO_LOCK_WIDTH || 0, dsf = +process.env.DEMO_DSF || 2;
  const measureViewport = () => page.evaluate(() => ({ width: innerWidth, height: innerHeight, devicePixelRatio: devicePixelRatio }))
    .then(v => ({ ...v, zoom: +(lockWidth ? lockWidth / v.width : v.devicePixelRatio / dsf).toFixed(4) }));
  const viewport = await measureViewport();
  let pos = start ?? { x: viewport.width / 2, y: viewport.height / 2 };
  // All times are epoch seconds. composite.py and autotrim.py read this file.
  const events = {
    version: 3, ease: 'inOutSine', start: pos, viewport: { ...viewport },
    zoom: viewport.zoom, devicePixelRatio: viewport.devicePixelRatio,
    // Timestamped CSS viewport history; a new entry is appended whenever it changes
    // (e.g. the zoom is changed mid-run). composite.py picks the entry in force at each time.
    viewports: [{ t: now(), ...viewport }],
    moves: [], clicks: [], keys: [], captions: [], scrolls: [], pending: [], holds: [], marks: [],
  };
  await page.mouse.move(pos.x, pos.y);

  // (Re)install the caption box and, in preview mode, the live cursor. Called before
  // every use, so it survives navigations and SPA re-renders that wipe <body>.
  const ensureOverlay = () => page.evaluate(([isPreviewEnabled, svg]) => {
    if (document.getElementById('__demo')) return;
    const root = document.createElement('div');
    root.id = '__demo';
    root.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647';
    root.innerHTML = `<div id="__demo_cap" style="position:absolute;left:50%;bottom:28px;transform:translateX(-50%);max-width:70%;padding:10px 18px;border-radius:10px;background:rgba(10,10,10,.9);color:#fff;font:600 16px/1.3 system-ui;opacity:0;transition:opacity .2s"></div>`;
    if (isPreviewEnabled) root.insertAdjacentHTML('beforeend', `<div id="__demo_cur" style="position:absolute;left:0;top:0;transition:transform 45ms linear">${svg}</div>`);
    (document.body ?? document.documentElement).appendChild(root);
  }, [isPreviewEnabled, PREVIEW_CURSOR]).catch(() => {});

  const previewAt = (x, y) => isPreviewEnabled && page.evaluate(([x, y]) => {
    const c = document.getElementById('__demo_cur');
    if (c) c.style.transform = `translate(${x - 3.5}px, ${y - 3}px)`;
  }, [x, y]).catch(() => {});

  const previewRipple = (x, y) => isPreviewEnabled && page.evaluate(([x, y]) => {
    const r = document.createElement('div');
    r.style.cssText = `position:absolute;left:${x - 30}px;top:${y - 30}px;width:60px;height:60px;border-radius:50%;background:#671DC948;border:3px solid #671DC9;box-sizing:border-box`;
    document.getElementById('__demo')?.appendChild(r);
    r.animate([{ transform: 'scale(.05)', opacity: 1, easing: 'cubic-bezier(.33,1,.68,1)' }, { transform: 'scale(.97)', opacity: 1, offset: .7 }, { transform: 'scale(1)', opacity: 0 }], { duration: 420 }).onfinish = () => r.remove();
  }, [x, y]).catch(() => {});

  await ensureOverlay();
  await previewAt(pos.x, pos.y);

  // Visible part of a locator's box in main-viewport CSS px, or null if off-screen.
  const visibleBox = async locator => {
    const b = await locator.boundingBox();
    if (!b) return null;
    const x0 = Math.max(0, b.x), y0 = Math.max(0, b.y);
    const x1 = Math.min(viewport.width, b.x + b.width), y1 = Math.min(viewport.height, b.y + b.height);
    return x1 - x0 >= 4 && y1 - y0 >= 4 ? { box: b, x0, y0, x1, y1 } : null;
  };

  const stableBox = async locator => {
    let prev = null;
    for (let i = 0; i < 40; i++) {
      const b = await locator.boundingBox();
      if (b && prev && Math.abs(b.x - prev.x) < 0.5 && Math.abs(b.y - prev.y) < 0.5) return b;
      prev = b;
      await sleep(50);
    }
    return prev;
  };

  // Re-measure before every action; log (and adopt) a new viewport if it changed.
  const sampleViewport = async () => {
    const v = await measureViewport().catch(() => null);
    if (!v || (v.width === viewport.width && v.height === viewport.height && v.devicePixelRatio === viewport.devicePixelRatio)) return;
    Object.assign(viewport, v);
    events.viewports.push({ t: now(), ...v });
  };

  const api = {
    page, browser, events, viewport, sampleViewport,
    get position() { return { ...pos }; },

    /** The first frame whose URL contains `fragment`, e.g. d.frame('about:srcdoc'). */
    frame(fragment) {
      const f = page.frames().find(f => f !== page.mainFrame() && f.url().includes(fragment));
      if (!f) throw new Error(`no frame with URL containing ${fragment}`);
      return f;
    },

    /** Show `text` in the caption box (empty hides it) and wait `holdMs`. */
    async caption(text, holdMs = 500) {
      await ensureOverlay();
      await page.evaluate(t => {
        const c = document.getElementById('__demo_cap');
        if (!c) return;
        if (t) c.textContent = t;
        c.style.opacity = t ? 1 : 0;
      }, text);
      events.captions.push({ t: now(), text });
      await sleep(holdMs);
    },

    /** Glide to (x, y) in viewport CSS px. Real mouse events follow in ~40ms steps, so
     *  hover states fire on the way; the logged path is the ideal curve. */
    async moveTo(x, y) {
      await sampleViewport();
      const dist = Math.hypot(x - pos.x, y - pos.y);
      if (dist < 1) return;
      const ms = glideMs(dist);
      const from = pos, t0 = Date.now();
      events.moves.push({ t0: t0 / 1000, t1: (t0 + ms) / 1000, from, to: { x, y } });
      for (let el = 0; el < ms; el = Date.now() - t0) {
        const e = ease(el / ms);
        const px = from.x + (x - from.x) * e, py = from.y + (y - from.y) * e;
        await page.mouse.move(px, py);
        previewAt(px, py);
        await sleep(35);
      }
      await page.mouse.move(x, y);
      previewAt(x, y);
      pos = { x, y };
      // Don't let the next action start before the logged glide has finished.
      const left = t0 + ms - Date.now();
      if (left > 0) await sleep(left);
    },

    /** Glide to (x, y), pause briefly, click. */
    async click(x, y, { settleMs = 450 } = {}) {
      await api.moveTo(x, y);
      await sleep(120);
      events.clicks.push({ t: now(), x, y });
      previewRipple(x, y);
      await page.mouse.down(); await sleep(50); await page.mouse.up();
      await sleep(settleMs);
    },

    /** Bring a locator into view (smooth scroll, works inside iframes) and return a
     *  point inside its visible part. `at` is a fraction of the box, default centre. */
    async pointOf(locator, { at = { x: 0.5, y: 0.5 }, timeout = 10000 } = {}) {
      locator = locator.first();
      await sampleViewport();
      await locator.waitFor({ state: 'visible', timeout });
      let vis = await visibleBox(locator);
      const b = vis?.box;
      const isFullyInView = b && b.y >= 0 && b.y + b.height <= viewport.height && b.x >= 0 && b.x + b.width <= viewport.width;
      if (!isFullyInView) {
        const t0 = now();
        await locator.evaluate(el => el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' }));
        await stableBox(locator);
        events.scrolls.push({ t0, t1: now() });
        vis = await visibleBox(locator);
      }
      if (!vis) throw new Error(`element is not visible in the viewport: ${locator}`);
      const { box, x0, y0, x1, y1 } = vis;
      const clamp = (v, a, z) => Math.min(z - 2, Math.max(a + 2, v));
      return {
        x: Math.round(clamp(box.x + box.width * at.x, x0, x1)),
        y: Math.round(clamp(box.y + box.height * at.y, y0, y1)),
      };
    },

    async hoverEl(locator, opts) { const p = await api.pointOf(locator, opts); await api.moveTo(p.x, p.y); },
    async clickEl(locator, opts = {}) { const p = await api.pointOf(locator, opts); await api.click(p.x, p.y, opts); },

    /** Scroll whatever is under the cursor by dy CSS px with wheel events (smoothly). */
    async scroll(dy, ms = 600) {
      await sampleViewport();
      const t0 = now(), steps = Math.max(1, Math.round(ms / 30));
      let done = 0;
      for (let i = 1; i <= steps; i++) {
        const target = dy * ease(i / steps);
        await page.mouse.wheel(0, target - done);
        done = target;
        await sleep(30);
      }
      events.scrolls.push({ t0, t1: now() });
    },

    /** Type into the focused element (any frame) with real key events. */
    async type(text, perKeyMs = 70) {
      const t0 = now();
      await page.keyboard.type(text, { delay: perKeyMs });
      events.keys.push({ t0, t1: now() });
    },
    async press(key) {
      const t0 = now();
      await page.keyboard.press(key);
      events.keys.push({ t0, t1: now() });
    },

    /** Await something slow (network, an agent reply, a spinner). The span is sped up
     *  in the edit, not cut, so viewers still see that it was loading. */
    async pending(fnOrPromise, label = 'pending') {
      const t0 = now();
      try { return await (typeof fnOrPromise === 'function' ? fnOrPromise() : fnOrPromise); }
      finally { events.pending.push({ t0, t1: now(), label }); }
    },

    /** Keep the current view on screen for `ms` (e.g. to read a result); never cut. */
    async hold(ms) {
      const t0 = now();
      await sleep(ms);
      events.holds.push({ t0, t1: now() });
    },

    mark(label) { events.marks.push({ t: now(), label }); },

    save() { if (eventsFile) fs.writeFileSync(eventsFile, JSON.stringify(events, null, 1)); },
  };
  return api;
}
