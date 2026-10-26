// Record a tab in the demo browser (demo-browser.sh, or any browser on DEMO_CDP_PORT) via the DevTools
// screencast. Works while the window is covered or minimized. Locks the page to
// a fixed viewport so every take has the same size.
//
// Usage: node screencast.mjs <url-fragment> <out-dir> [width=1280] [height=800]
//   Runs until SIGINT/SIGTERM, then writes <out-dir>/NNNNN.jpg + times.txt
//   (epoch seconds per frame) + urls.tsv (time<TAB>url on each navigation).
//   Start it in the background; prints "recording" once the first frame lands.
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const [frag, out, w = '1280', h = '800'] = process.argv.slice(2);
if (!frag || !out) { console.error('usage: screencast.mjs <url-fragment> <out-dir> [width] [height]'); process.exit(2); }
fs.mkdirSync(out, { recursive: true });
for (const f of fs.readdirSync(out)) if (/^\d+\.jpg$/.test(f)) fs.rmSync(`${out}/${f}`);

const browser = await chromium.connectOverCDP(`http://127.0.0.1:${process.env.DEMO_CDP_PORT || 9333}`);
const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().includes(frag));
if (!page) { console.error(`no tab with URL containing ${frag}`); process.exit(1); }

const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setDeviceMetricsOverride', { width: +w, height: +h, deviceScaleFactor: 2, mobile: false });

// Written before the screencast starts: frames can stream (and the take can end)
// before Page.startScreencast's reply arrives, which once left no meta.json at all.
fs.writeFileSync(`${out}/meta.json`, JSON.stringify({ width: +w, height: +h }));
const times = [];
const urls = [[Date.now() / 1000, page.url()]];
page.on('framenavigated', f => { if (f === page.mainFrame()) urls.push([Date.now() / 1000, f.url()]); });

let n = 0;
cdp.on('Page.screencastFrame', ({ data, metadata, sessionId }) => {
  cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  fs.writeFileSync(`${out}/${String(n++).padStart(5, '0')}.jpg`, Buffer.from(data, 'base64'));
  times.push(metadata.timestamp);
  if (n === 1) console.log('recording');
});
// Ask for device pixels (2x) so text stays crisp; without max* Chrome sends CSS-pixel frames.
// The stream is capped at the window's real pixel size, so on a 1x display start the
// browser with DEMO_SCALE=2 (demo-browser.sh) to get true 2x frames.
await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 85, maxWidth: +w * 2, maxHeight: +h * 2 });
// Screencast only emits on repaint; nudge one so a static page still gets a first frame.
await page.evaluate(() => { document.documentElement.style.outline = '0 solid transparent'; });

const stop = async () => {
  await cdp.send('Page.stopScreencast').catch(() => {});
  times.push(Date.now() / 1000); // hold the last frame until stop
  fs.copyFileSync(`${out}/${String(n - 1).padStart(5, '0')}.jpg`, `${out}/${String(n).padStart(5, '0')}.jpg`);
  fs.writeFileSync(`${out}/times.txt`, times.join('\n'));
  fs.writeFileSync(`${out}/urls.tsv`, urls.map(u => u.join('\t')).join('\n'));
  await cdp.send('Emulation.clearDeviceMetricsOverride').catch(() => {});
  console.log(`stopped: ${n + 1} frames, ${(times.at(-1) - times[0]).toFixed(1)}s`);
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
setInterval(() => {}, 1 << 30);
