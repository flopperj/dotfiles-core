---
name: smart-statusline
description: "Install a Claude Code statusline that shows model name, session cost, a 10-block context usage bar, and color-coded warnings (/compact prompts at 30%, urgency at 90%). Use when the user types /smart-statusline, asks to set up a statusline, wants to see context usage in their terminal, asks how full their context window is, wants cost tracking in Claude Code, or says things like 'show me context percentage', 'set up my statusline', or 'I want to see how much context I have left'."
user-invocable: true
---

# Claude Code Statusline

> **Just installed this skill? Say: "install my statusline"** — Claude will set everything up automatically.



Installs a statusline script for Claude Code that shows at a glance:
- **Model name** — which Claude model is active
- **Session cost** — running USD total for the session
- **Context bar** — 10-block progress bar (each block = 10% of context window)
- **Color-coded warnings** — green → orange → red as context fills up

Example output:
```
Sonnet 4.6  $0.42  ████░░░░░░  38% — run /compact now
```

Color thresholds:
- **Green** (0–29%) — plenty of room
- **Yellow** (30%) — consider `/compact`
- **Orange** (31–89%) — run `/compact` now
- **Red** (90%+) — start a new session

## Installation

Two things are needed: the script file and a `settings.json` entry.

### Step 1: Copy the script

The script is bundled at `scripts/statusline-command.sh` relative to this SKILL.md. Copy it to `~/.claude/`:

```bash
cp <skill-dir>/scripts/statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

If you're installing via `npx @dev-devsuccess/skills`, the skill directory will be at `~/.claude/skills/smart-statusline/` (global) or `.claude/skills/smart-statusline/` (project).

### Step 2: Add to settings.json

Add the `statusLine` key to your Claude Code `settings.json`. For **global** (all projects):

```json
// ~/.claude/settings.json
{
  "statusLine": {
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

For **project-scoped** (just this repo), add to `.claude/settings.json` in your project root instead.

### Step 3: Verify

Open Claude Code — the statusline should appear immediately. If it doesn't show, check that `jq` is installed (`brew install jq` on macOS, `apt install jq` on Linux).

## When Claude installs this

If the user asks you to install the statusline for them:

1. Find the skill directory — check `~/.claude/skills/smart-statusline/` (global install) or `.claude/skills/smart-statusline/` (project install)
2. Copy the script: `cp <skill-dir>/scripts/statusline-command.sh ~/.claude/statusline-command.sh`
3. Read the user's `~/.claude/settings.json` (create it if missing), add the `statusLine` block, write it back
4. Confirm: "Statusline installed — reopen Claude Code to see it. Once you've confirmed it's working, I can remove the `statusline` skill directory (`<skill-dir>`) since it's no longer needed — the script and settings.json are all that's required going forward."
5. After the user confirms it's working, clean up: `rm -rf <skill-dir>`

Use the project-scoped `.claude/settings.json` if the user is working in a specific repo and says so. Default to global `~/.claude/settings.json` otherwise.

## Requirements

- `jq` — JSON parsing in the script (`brew install jq` / `apt install jq`)
- Claude Code with statusline support (any recent version)
- Bash

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
