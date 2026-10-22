// Drive a tab in the demo browser (demo-browser.sh, or any browser on DEMO_CDP_PORT) without touching the
// user's mouse, keyboard, or focus: all input is synthetic, sent over DevTools.
//
// Usage: node drive.mjs <url-fragment> <command> [args...]
//   goto <url>
//   click <selector>
//   type <selector> <text> [delay-ms=45]     real key events, so React sees them
//   press <selector> <key>                   e.g. Enter
//   eval <js-expression | @file.js>          prints the result as JSON
//   wait <js-expression> [timeout-s=180]     until the expression is truthy
//   scroll <selector>                        smooth-scroll it to the centre
//   scroll-text <regex>                      same, for the deepest element whose text
//                                            matches, searching every frame (e.g. an
//                                            editor canvas in an about:srcdoc iframe)
//   shot <out.png>                           screenshot of the viewport
//   aria [selector=body] [frame-fragment]    accessibility snapshot, for picking locators
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const [frag, cmd, ...args] = process.argv.slice(2);
if (!frag || !cmd) { console.error(fs.readFileSync(new URL(import.meta.url)).toString().split('\n').slice(1, 17).join('\n')); process.exit(2); }

const browser = await chromium.connectOverCDP(`http://127.0.0.1:${process.env.DEMO_CDP_PORT || 9333}`);
const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url().includes(frag));
if (!page) { console.error(`no tab with URL containing ${frag}`); process.exit(1); }
const js = s => (s.startsWith('@') ? fs.readFileSync(s.slice(1), 'utf8') : s);

switch (cmd) {
  case 'goto': await page.goto(args[0], { waitUntil: 'domcontentloaded' }); break;
  case 'click': await page.locator(args[0]).first().click(); break;
  case 'type': await page.locator(args[0]).first().pressSequentially(args[1], { delay: +(args[2] ?? 45) }); break;
  case 'press': await page.locator(args[0]).first().press(args[1]); break;
  case 'eval': console.log(JSON.stringify(await page.evaluate(js(args[0])))); break;
  case 'wait': await page.waitForFunction(js(args[0]), null, { timeout: +(args[1] ?? 180) * 1000, polling: 1000 }); break;
  case 'scroll': await page.locator(args[0]).first().evaluate(e => e.scrollIntoView({ behavior: 'smooth', block: 'center' })); break;
  case 'scroll-text': {
    let hit = null;
    // Child frames first: the thing being demoed (e.g. an email canvas) usually lives in
    // an iframe, while the main frame's chat often quotes the same text.
    for (const f of [...page.frames().slice(1), page.mainFrame()]) {
      hit = await f.evaluate(src => {
        const re = new RegExp(src, 'i');
        const els = [...document.querySelectorAll('body *')].filter(e => re.test(e.textContent) && ![...e.children].some(c => re.test(c.textContent)));
        const e = els.at(-1);
        if (!e) return null;
        e.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return e.textContent.trim().slice(0, 120);
      }, args[0]).catch(() => null);
      if (hit) break;
    }
    if (!hit) { console.error(`no element matching /${args[0]}/ in any frame`); process.exit(1); }
    console.log(JSON.stringify(hit));
    break;
  }
  case 'shot': await page.screenshot({ path: args[0] }); break;
  case 'aria': {
    const frame = args[1] ? page.frames().find(f => f.url().includes(args[1])) : page.mainFrame();
    if (!frame) { console.error(`no frame with URL containing ${args[1]}`); process.exit(1); }
    console.log(await frame.locator(args[0] ?? 'body').first().ariaSnapshot({ timeout: 15000 }));
    break;
  }
  default: console.error(`unknown command ${cmd}`); process.exit(2);
}
process.exit(0);
