---
name: record-demo
description: >-
  Record a demo video of a feature being exercised in the browser, trim it, save it as demo_<slug>.mp4, and embed it in a PR description's "🎥 Demo" section so reviewers can see it was tested locally. Records in the background by default, so the user can keep working: scriptable demos are planned, written as a Playwright choreography, and recorded with a smooth on-video cursor, click rings and captions, with dead time cut automatically. Records before/after pairs, and proves the "before" shows the problem before recording anything. Use when the user asks to "record a demo", "make a demo video for the PR", "add a demo to the PR", "record a before and after", "screen-record this", or invokes /record-demo. Args: PR URL, plus what to demonstrate. macOS only.
user-invocable: true
---

# Record a PR demo

Adapted from San'Quan Prioleau's `record-demo` skill (MIT, see `LICENSE`).

Three recording paths. **Prefer C**, then A: neither takes focus, moves the real cursor, or needs the browser on screen, so the user keeps working while you record.

- **C. Choreographed (default):** plan the demo, write it as a Playwright choreography, and record it with one command (`choreo.sh`). The video shows a smooth cursor, click rings and captions, and dead time is cut automatically. Use it whenever the steps can be scripted.
- **A. Background, step by step:** driven one command at a time over DevTools (`drive.mjs`) and recorded with the DevTools screencast (`screencast.mjs`), with manual marks and trims. Use it for one-off steps not worth scripting, or when choreography keeps failing on the page.
- **B. Screen capture (fallback):** the user's own Chrome window, recorded with `screencapture`. Use it only when the demo needs a window or session the other paths can't reach. The window must stay in front and uncovered for the whole take.

For company-specific demo targets, consult `## Demo recording targets` in `~/.claude/overlay-context.md`. If that file is absent, proceed with the generic steps only.

## Setup

`S=~/.claude/skills/record-demo/scripts` (run `.sh` with `bash`, `.mjs` with `node`). Work dir: `D=<scratchpad>/demo-<slug>`. Output dir: `OUT=${DEMO_OUT_DIR:-$HOME/Desktop/🎥 Demos}`. Final file: `$OUT/demo_<slug>.mp4` (lowercase `demo_`, hyphenated slug, e.g. `demo_edit-agent-streaming-reply.mp4`; a pair adds `-before` / `-after`). Default size **1280×800**.

Run the preflight first. It changes nothing and prints the fix for each gap:

```bash
bash $S/preflight.sh [url-fragment]
```

- The dotfiles installer installs `ffmpeg` with Homebrew (`brew.txt`). If it's still missing, start `brew install ffmpeg` at once, in the background (it can take many minutes), and keep planning while it runs.
- Python needs numpy and Pillow. Put them in a virtualenv at `~/.cache/record-demo-venv` rather than the system Python; the scripts use it automatically when it exists (preflight prints the commands). `DEMO_PYTHON` overrides it. For the manual commands below, `PY=${DEMO_PYTHON:-$HOME/.cache/record-demo-venv/bin/python}`.
- `npm i` in `$S` installs the pinned `playwright-core` once. It writes no lockfile (`$S/.npmrc`).

### Which browser

Every script talks to one browser over DevTools on `127.0.0.1:${DEMO_CDP_PORT:-9333}`. Two ways to get one:

- **Attach (preferred when available).** If the project already launches a signed-in automation browser that exposes a DevTools port (a dev launcher, a test harness), set `DEMO_CDP_PORT` to that port and skip `demo-browser.sh`. There's no sign-in step, and you never handle the user's credentials.
- **Own profile.** `bash $S/demo-browser.sh start "<url>"` launches a separate Chrome with its own persistent profile, in the background, never activated. If the page shows a login screen, run `demo-browser.sh login "<url>"`, which opens the window in front, and ask the user to sign in. Poll in the background for the target element (`node $S/drive.mjs <frag> eval "!!document.querySelector('…')"` every 3s). Never type credentials yourself. If the user closed the window, `stop`, then `login` again.

The DevTools port is unauthenticated: any local process can drive that browser and its signed-in sessions while it runs. Stop a browser you started (`demo-browser.sh stop`) when the demo is done; leave an attached one to its owner.

**One driver at a time.** A second script driving or recording the same browser (another session, a subagent, a leftover background run) corrupts both takes: stray typing, extra frames, a missing `meta.json`. Preflight checks for one; never leave a run going after reporting.

## 1. Plan, and prove it on screen

Write a short test plan before any code: the goal in one line, then numbered steps, each with the result a viewer should see (e.g. "Search 'arrow' → the list filters as you type"). Keep it to what proves the PR works; 4–8 steps is typical. Confirm it with the user in one line along with the slug, unless they already spelled it out.

**For a before/after pair, run the steps on both builds before recording either.** The "before" (the deployed build, or the base branch) must actually show the problem, and the "after" must show it fixed. If the "before" already behaves correctly, stop and tell the user what you saw: the premise of the change may be wrong, and a video of two identical takes proves nothing. Check the outcome at its source (reload, open the saved record in a second tab, read the stored value), not just what the page claims.

## 2. Script (path C)

Write the plan as a choreography module in `$D/demo.mjs`, with the plan as its header comment. Start from `examples/entitease.mjs`. It default-exports `async function (d)`; `d` is the `cursor.mjs` helper:

| Call | Does |
|---|---|
| `d.caption(text, holdMs)` | shows a caption at the bottom of the page (`''` hides it) |
| `d.clickEl(locator)` / `d.hoverEl(locator)` | waits for the element, scrolls it into view, glides to it, clicks or hovers |
| `d.click(x, y)` / `d.moveTo(x, y)` | the same at page coordinates |
| `d.type(text, perKeyMs)` / `d.press(key)` | real key events into the focused element |
| `d.scroll(dy)` | wheel scroll at the cursor |
| `d.frame(urlFragment)` | the first frame whose URL contains it, to build locators in (e.g. `'about:srcdoc'`) |
| `d.hold(ms)` | a pause viewers need (reading a result); never cut |
| `d.pending(fn or promise)` | a wait on loading, network or an agent reply; sped up in the edit, never cut |
| `d.page` | the Playwright `Page` for anything else |

- Use locators (`getByRole`, `page.locator(...)`), never hard-coded coordinates. Pick them from `node $S/drive.mjs <frag> aria [selector] [frame-fragment]`, which prints the accessibility tree, instead of guessing.
- Wrap every wait on the app in `d.pending(...)`, e.g. `await d.pending(() => page.getByText('Done').waitFor({ timeout: 240000 }))`, so the edit speeds it up instead of keeping it at 1×.
- Use `d.hold(...)` after each visible result so it stays on screen long enough to read.
- Avoid steps with real side effects (Save, Send, Publish) unless the demo is about them.
- For a pair, write one choreography and read what differs from `process.env` (e.g. `DEMO_URL`), so both takes run the same steps.

Locator traps that cost dry runs:
- `getByRole('button', { name: 'View' })` also matches "View all", "Preview" and the like: pass `{ exact: true }`, and scope to a container.
- `getByText(/…/)` happily matches hidden copies (a collapsed panel, an offscreen template). Filter with `.filter({ visible: true })` or wait for `state: 'visible'`.
- In a rich-text or block editor, one click often only selects the block. Double-click to enter it, then place the caret with the keyboard (`Meta+ArrowDown` for the end); `End` may scroll the canvas instead.

## 3. Dry run, then record (path C)

```bash
bash $S/choreo.sh <url-fragment> $D/demo.mjs $D --dry-run    # live cursor in the page, no recording
bash $S/choreo.sh <url-fragment> $D/demo.mjs $D "$OUT/demo_<slug>.mp4"
```

- Repeat the dry run until it passes: fix selectors and waits from the error, which names the failing step. Reload the page between attempts (`node $S/drive.mjs <frag> goto "<url>"`).
- `choreo.sh` records the screencast, runs the choreography (`run.mjs`), and stops. Then `composite.py` draws the cursor and click rings onto a constant 30fps timeline, `assemble.sh` adds the URL bar, `autotrim.py` plans the edit, and `finish.sh` encodes.
- It stops recording if the choreography fails and keeps the frames. Omit the output path to stop after `$D/raw.mp4` and `$D/segments.txt`. Pass `--segments` to override the edit, and `--no-url-bar` or `--size WxH` as needed.
- For a pair, give each take its own work dir (`$D/before`, `$D/after`) so neither overwrites the other's frames.

How it stays smooth:
- **The cursor is never drawn in the page while recording.** `cursor.mjs` logs every glide and click with timestamps (`events.json`), and `composite.py` draws them afterwards: an arrow cursor plus a ring that grows on each click. The screencast delivers frames unevenly, so a cursor drawn in the page would snap between positions; drawn afterwards it moves smoothly whatever the capture did. Only the dry run shows a live cursor.
- **Page zoom is supported.** `cursor.mjs` logs positions in CSS px and records the viewport, `zoom` and `devicePixelRatio` in `events.json`, plus a `viewports` history that gains an entry whenever the viewport changes. `composite.py` derives `S = frame_width / CSS viewport width` per time and prints S and the derived zoom.
- **Glides use sine ease-in-out at 400–800ms by distance.** A cubic curve peaks at 3× the average speed and reads as a jump.
- **The browser is never brought to the front.** `cursor.mjs` uses focus emulation instead of `page.bringToFront()`, which would steal the user's focus.

How the edit works (`autotrim.py`, reading the raw frames plus `events.json`):
- **Kept at 1×:** glides, clicks and their rings, typing, scrolls, holds, caption reading time, and visible page changes.
- **Sped up to play in about 1.2s (max 8×):** `d.pending()` spans, plus unmarked page activity over 1.5s with no action (spinners, streaming), after its first 0.5s.
- **Cut:** static stretches longer than 0.4s.
- Cuts never land inside a glide or a ring. On pages that animate constantly, everything quiet would get sped up: rerun the plan with `"$PY" $S/autotrim.py $D/frames $D/events.json --no-auto-pending` and pass its output to `choreo.sh --segments`.

Crisp video: on a 1x display the DevTools screencast is capped at the window's physical pixel size. Start your own browser with `DEMO_SCALE=2` for true 2560×1600 frames, and keep the resolution at encode time with `MAX_W=2560 CRFS="20 23 26 30" bash $S/choreo.sh …`. `MAX_W` (default 1280) is the final width and `CRFS` (default `26 30 34 38`) the CRF ladder, tried in order until the file fits under 10 MB. A 51s take was 3.3 MB at crf 20.

**Cursor or ring looks offset:** compare the `S=` that `composite.py` printed with `frame_width / CSS viewport width` (1920 / 1280 = 1.5 at 100% zoom). If they differ, check `viewport`/`viewports` in `events.json`, then re-composite from the kept frames without re-recording: `"$PY" $S/composite.py $D/frames $D/events.json $D/comp`, then `assemble.sh`.

## A. Background, step by step

```bash
node $S/drive.mjs <frag> type 'textarea[placeholder="Ask anything..."]' "<prompt>" 40
node $S/drive.mjs <frag> click 'button[aria-label="Send message"]'
node $S/drive.mjs <frag> wait "!document.querySelector('button[aria-label=\"Stop\"]')" 240
node $S/drive.mjs <frag> scroll-text "Early-bird\\s+buyer"   # searches iframes first
node $S/drive.mjs <frag> shot $D/check.png                   # look before/after
```

- All input is synthetic over DevTools; the user's mouse and keyboard are untouched. `type` sends real key events, so React state updates with no setter hacks.
- `eval` runs only in the main frame. For content in an iframe, use `scroll-text`, `aria … <frame-fragment>`, or a small Playwright script over `page.frames()`.
- To verify a claimed visual change, read computed styles; don't trust a description. "Slightly dimmer" once turned out to be `rgb(255,255,255)` → `rgb(245,245,245)`, which nobody can see. Tell the user.

Record:

```bash
mkdir -p $D && (nohup node $S/screencast.mjs <frag> $D/frames 1280 800 > $D/screencast.log 2>&1 & echo $! > $D/pid)
until grep -q recording $D/screencast.log; do sleep 0.5; done
# … stage the "before" view, then drive the steps; mark each one:
python3 -c "import time,sys; print(f'{time.time():.2f}\t'+sys.argv[1])" "<step>" >> $D/marks.tsv
# … hold the final state ~3s, then:
kill -INT $(cat $D/pid)
bash $S/assemble.sh $D/frames $D/raw.mp4 "$(head -1 $D/frames/urls.tsv | cut -f2)"
```

- `screencast.mjs` locks the page to the viewport size, writes `NNNNN.jpg` + `times.txt` + `urls.tsv` + `meta.json`, and holds the last frame until stopped.
- `assemble.sh` builds a constant-30fps video with a browser-style URL bar on top, rendered by `caption.swift`. Omit the URL argument to skip it.
- Marks are epoch seconds; subtract the first line of `times.txt` to get video time.

## B. Screen capture (fallback)

- `bash $S/record.sh check`. If it's denied, the user must enable **System Settings → Privacy & Security → Screen Recording** for the process running Claude Code (the CLI binary, not a desktop UI app); the grant may need redoing after updates. `open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"` opens the pane.
- `stage-window.sh` and `chrome-js.sh` also need **Automation → Google Chrome** for that process (`-1743` means it's missing). `chrome-js.sh` also needs Chrome → **View → Developer → Allow JavaScript from Apple Events**. To type with it, use the React-safe value setter plus an `input` event, one character every ~45ms.

```bash
bash $S/record.sh start $(bash $S/stage-window.sh "<url-fragment>") $D   # zsh: inline $(…), don't store the rect in $VAR
bash $S/record.sh mark $D "<step>"
bash $S/record.sh stop $D      # → $D/raw.mov
```

- `stage-window.sh` un-minimizes, focuses and sizes the window.
- Watch for system pop-ups covering the window. Gray traffic lights mean the window lost focus; cut before that.

## Trim (A and B; C trims automatically)

The raw video is mostly dead air between tool calls. Find where the screen changes:

```bash
ffmpeg -hide_banner -i $D/raw.mp4 -vf "scale=400:-1,select='gt(scene,0.003)',showinfo" -f null - 2>&1 \
  | grep -o 'pts_time:[0-9.]*' | cut -d: -f2 | awk '{printf "%.1f ", $1}'
```

Combine those times with the marks (typing often falls below the scene threshold). Keep ~0.5s before to ~2.5s after each change, run typing at `@1.5`, and speed waits up with `@6`–`@8`:

```bash
bash $S/finish.sh $D/raw.mp4 "$OUT/demo_<slug>.mp4" "0.5-4,5-13.8@1.5,13.8-43.5@6,43.5-50,63-67.5"
```

`finish.sh` encodes H.264 at max 1280px wide, recompressing until the file is under 10 MB (the upload limit).

## Check the video

Spot-check the start, the key moment and the last frame (`-sseof -0.2`): tile them with `hstack`/`vstack` and Read the result. Watch the *after* frame for regressions the change introduced (e.g. removing a highlight once left dark text on a dark background) and report them. Then send the mp4 to the user.

## Upload and embed in the PR

The `gh` CLI can't upload attachments, so use GitHub's web uploader from a browser already signed in to GitHub (a browser-control tool), then edit the body with `gh`:

1. Open the PR's Conversation tab and find the file input inside the **new comment** form, not the description editor.
2. Copy the mp4 into `$D/` and upload that copy; browser upload tools refuse paths outside the session's folders. Never click the attach button: it opens a native picker.
3. After ~5s, take the asset URL (`https://<github-host>/user-attachments/assets/<uuid>`) out of the comment field. Clear the field (`value=''` plus an `input` event) and leave the comment **unsubmitted**.
4. `gh pr view <url> --json body -q .body > $D/body.md`, with the host as a literal (`GH_HOST=<host>` or a full PR URL). In the `🎥 Demo` section (any heading level), replace the placeholder or the previous asset URL with the new bare URL on its own line; for a pair, label the lines **Before** and **After**. With no Demo section, add `### 🎥 Demo` above "Steps to test" (or at the end).
5. Show the user the diff. Unless they already asked you to update the description, wait for a yes. Then `gh pr edit <url> --body-file $D/body.md`.
6. Reload the page and confirm the description's `video` element exists and its `currentSrc` contains the new asset id.

If the upload fails, give the user the file path and the exact body edit to make by drag-and-drop.

## Notes

- One demo per PR (or one pair); replace the old URL rather than stacking videos, unless asked.
- Never record secrets: tokens in request headers, auth panels, credential files. Scroll past them or cut the segment.
- Stop every background process you started before reporting: the screencast, a browser you launched, a dev server.
