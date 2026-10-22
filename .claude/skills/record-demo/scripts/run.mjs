// Run a demo choreography against a tab in Claude's demo Chrome.
//
// Usage: node run.mjs <url-fragment> <choreography.mjs> [events.json] [--preview]
//   choreography.mjs default-exports `async function (d)`, where d is the cursor.mjs
//   helper (d.page is the Playwright Page).
//   events.json  where to write the cursor/caption/pending log (composite.py, autotrim.py)
//   --preview    draw a live cursor in the page so someone watching can follow it. The
//                screencast would capture it, so only use it for dry runs.
// The events log is written even if the choreography throws, and the error is printed
// with the step that failed; exit status is 1 in that case.
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { connect } from './cursor.mjs';

const args = process.argv.slice(2);
const isPreviewEnabled = args.includes('--preview');
const [frag, choreo, eventsFile] = args.filter(a => a !== '--preview');
if (!frag || !choreo) { console.error('usage: run.mjs <url-fragment> <choreography.mjs> [events.json] [--preview]'); process.exit(2); }

const { default: run } = await import(pathToFileURL(path.resolve(choreo)).href);
if (typeof run !== 'function') { console.error(`${choreo} must default-export async function (d)`); process.exit(2); }

const d = await connect(frag, { eventsFile, isPreviewEnabled });
let status = 0;
try {
  await run(d);
} catch (e) {
  console.error(`choreography failed: ${e.message}`);
  status = 1;
} finally {
  d.save();
}
const ev = d.events;
console.log(`done: ${ev.moves.length} glides, ${ev.clicks.length} clicks, ${ev.captions.length} captions, ${ev.pending.length} pending spans`);
// Disconnect without closing Claude's demo Chrome.
process.exit(status);
