---
name: doctor
description: "Validate the full dotfiles setup: symlinks, CLI tools, MCP servers, plugins, and agent health. Use when the user types /doctor, starts a prompt with 'Doctor', or asks to 'check my setup', 'validate my dotfiles', 'is everything working', 'run diagnostics', or 'health check'."
user-invocable: true
---

# Doctor — Dotfiles Diagnostic Skill

Run a comprehensive health check of the dotfiles installation.

## Steps

### Step 1 — Locate the dotfiles directory

Determine the dotfiles repo location:
1. If `~/.claude/CLAUDE.md` is a symlink, resolve its parent's parent to find the repo root.
2. Fall back to `~/dotfiles`.
3. If neither exists, report and stop.

### Step 2 — Run `install.sh --check`

Execute `install.sh --check` from the dotfiles directory. This validates:
- Core symlinks (`~/.aliases.local`, `~/.claude/CLAUDE.md`)
- All Claude agent symlinks (`~/.claude/agents/`)
- All Claude skill symlinks (`~/.claude/skills/`)
- All Cursor agent mirrors (`~/.cursor/agents/` — same source as Claude agents)
- All Cursor skill mirrors (`~/.cursor/skills/` — same source as Claude skills)
- Cursor config symlinks (`hooks.json`, `mcp.json`, hook scripts)
- Stale/broken symlinks across both `~/.claude/` and `~/.cursor/`
- CLI tool availability (`claude`, `gh`, `git`, `jq`)
- Last install timestamp

Capture the full output and present it to the user.

### Step 3 — Plugin sync check

Compare the **union** of declared plugins against `~/.claude/settings.json` `enabledPlugins`. Declared plugins come from two sources:

- `<core>/plugins.txt` (universal plugins shipped by dotfiles-core; in overlay installs the path is `<dotfiles>/.claude/dotfiles-core/plugins.txt`)
- `<dotfiles>/.claude/plugins.txt` (overlay-specific plugins; only present in overlay installs)

Procedure:
1. Resolve the core path:
   - If `<dotfiles>/.claude/dotfiles-core/plugins.txt` exists → use it (overlay install).
   - Else if `<dotfiles>/plugins.txt` exists → use it (standalone core install).
   - Else → no core plugins to declare.
2. Read overlay's `<dotfiles>/.claude/plugins.txt` if present.
3. Build the declared-plugins set as the **union** of both files (skip blank lines and `#`-prefixed comments).
4. Read `~/.claude/settings.json` and extract the `enabledPlugins` keys.
5. Report:
   - Plugins in declared-set but not enabled in settings → "Not installed"
   - Plugins enabled in settings but not in declared-set → "Not tracked"
   - Plugins in both → "OK"

When listing OK plugins, annotate the source: `frontend-design@claude-plugins-official (core)`, `mcds-web-plugin@devassist-plugins-registry (overlay)`. This makes it obvious which file to edit if the user wants to remove or change a plugin.

### Step 4 — Settings template drift check

If `<dotfiles>/.claude/settings.json.template` exists:
1. Read the template and `~/.claude/settings.json`.
2. Compare the top-level keys (ignoring `mcpServers` values which contain secrets).
3. Report any keys present in the template but missing from settings, or vice versa.

### Step 5 — Agent memory status

For each agent in `<dotfiles>/.claude/agents/*.md`:
1. Extract the agent name from the filename.
2. Check if `~/.claude/agent-memory/<name>/MEMORY.md` exists.
3. Report: "Has memory" or "No memory yet" for each agent.

### Step 6 — Skill prerequisites (optional)

Check for external tools required by optional skills. Report as INFO-level (not blocking):

| Tool | Required by | Check |
|---|---|---|
| `gcloud` ADC | google-docs, google-drive | `test -f ~/.config/gcloud/application_default_credentials.json` |
| `mmdc` | mermaid-diagrams | `command -v mmdc` |
| `python3` | mc-lint | `command -v python3` |
| `uv` | jenkins-mcp | `command -v uv` |
| `jenkins-mcp` config | briefing, ranger, scout, cyrus (CI diagnosis) | Check `~/.claude.json` for `mcpServers.jenkins-mcp` key |
| Google Calendar MCP | briefing (SCHEDULE section) | Check if `mcp__claude_ai_Google_Calendar__list_events` appears in available tools (cloud MCP — cannot be checked via file; report INFO only) |
| Slack MCP | briefing (COMMS section) | Check if `mcp__claude_ai_Slack__slack_search_public_and_private` appears in available tools (cloud MCP — cannot be checked via file; report INFO only) |

For each missing tool, report: `INFO: {tool} not found — required by {skill} (optional)`

For cloud MCPs (Google Calendar, Slack), report: `INFO: Google Calendar MCP — cloud integration, availability varies per session. Enables SCHEDULE section in /briefing.` and `INFO: Slack MCP — cloud integration, availability varies per session. Enables COMMS section in /briefing.`

### Step 6b — Jenkins MCP status (optional)

Claude Code reads MCP servers from `~/.claude.json` (registered via `claude mcp add`), **not** from `~/.claude/settings.json`. Check `~/.claude.json` for jenkins-mcp registration.

If `~/.claude.json` contains an `mcpServers.jenkins-mcp` entry:
1. Verify `uv` is installed: `command -v uv`
2. Verify the `--directory` path in the MCP config exists (extract from args in `~/.claude.json`)
3. Verify `JENKINS_USER` and `JENKINS_TOKEN` are available from **either** the `~/.claude.json` `env` block **or** the shell environment (check both — credentials in either location are sufficient since child processes inherit shell env vars)
4. Check `~/.cursor/mcp.json` for a matching `mcpServers.jenkins-mcp` entry (Cursor parity check)
5. Report:
   - All OK: `INFO: Jenkins MCP configured and prerequisites present`
   - Missing `uv`: `WARN: Jenkins MCP configured but uv not found — install with: curl -LsSf https://astral.sh/uv/install.sh | sh`
   - Missing directory: `WARN: Jenkins MCP directory not found at {path}<!-- BEGIN OVERLAY-FRAGMENT: doctor-jenkins-clone-url --> <!-- END OVERLAY-FRAGMENT: doctor-jenkins-clone-url -->`. For the company-specific clone target, consult `## Jenkins MCP clone URL` in `~/.claude/overlay-context.md`. If that file is absent, proceed with the primary log message only.
   - Missing credentials: `WARN: Jenkins MCP missing JENKINS_USER or JENKINS_TOKEN (not found in ~/.claude.json env block or shell environment)`
   - Missing Cursor config: `INFO: Jenkins MCP not configured in ~/.cursor/mcp.json — Cursor agents will not have Jenkins access`

If no `mcpServers.jenkins-mcp` entry exists in `~/.claude.json`:
- Report: `INFO: Jenkins MCP not registered in Claude Code — run install.sh or: claude mcp add jenkins-mcp -s user ...`

### Step 6c — Agent model tier resolution

Agents use the `opus` and `sonnet` aliases in their `model:` frontmatter. An agent *may* instead be intentionally pinned to a raw model ID to reach a non-aliased tier (e.g. `claude-fable-5`) — none are today, but the check below handles it if one ever is. Tier intent, expected alias resolution, and which agents (if any) are pinned all live in `<dotfiles>/.claude/_shared/model-tiers.md` — the source of truth.

Check:
1. Read `<dotfiles>/.claude/_shared/model-tiers.md` and extract both the agent tier table and the expected alias resolution block (the `opus → claude-opus-…`, `sonnet → claude-sonnet-…` lines). Use whatever IDs, pins, and date the doc currently states — it is the source of truth; do not hardcode a version here.
2. For each agent file in `<dotfiles>/.claude/agents/*.md`, read the `model:` frontmatter field and confirm it matches the tier the doc assigns that agent — an **alias** (`opus`/`sonnet`/`haiku`) for aliased agents, or the **exact pinned ID** for agents the doc marks `(pinned)`.
3. If an agent's frontmatter does not match the documented tier, report: `WARN: {agent} declares model: {actual} but model-tiers.md expects {expected}`. A pinned ID that matches the doc's pin is NOT drift — do not warn on it.
4. Check `~/.claude/settings.json` and the `ANTHROPIC_MODEL` env var for any top-level `model` override. If present, report: `INFO: model override detected: {source}={value}`.
5. Alias-to-model resolution cannot be probed without an API call. Surface the expected mapping so the user can verify manually via `/model`.

Report: `INFO: Agent model tiers validated against _shared/model-tiers.md. Expected: <the alias→model mappings as stated in that doc>. Verify with /model if unsure.`

### Step 7 — Submodule health (if submodule present)

Check whether `dotfiles-core` is initialized and properly pinned.

#### 7a — Submodule init check

```bash
git -C {dotfiles-dir} submodule status .claude/dotfiles-core 2>/dev/null
```

If the submodule line starts with `-` → **BROKEN: `.claude/dotfiles-core` submodule not initialized. Run: `git submodule update --init --recursive`**

If absent → Skip rest of Step 7 (submodule not declared in this overlay).

#### 7b — SHA match check

The submodule HEAD must match the SHA committed in the overlay's tree:

```bash
# SHA committed in overlay (what git tracks)
committed_sha=$(git -C {dotfiles-dir} ls-tree HEAD .claude/dotfiles-core | awk '{print $3}')
# Current submodule HEAD
current_sha=$(git -C {dotfiles-dir}/.claude/dotfiles-core rev-parse HEAD 2>/dev/null)
```

If they differ → **WARN: submodule HEAD (`{current_sha}`) differs from pinned SHA (`{committed_sha}`). Run: `git submodule update`**

If match → `ok  submodule dotfiles-core @ {short_sha}`

#### 7c — Core-owned symlinks resolve into submodule path

For each of `~/.claude/skills/forge`, `~/.claude/skills/grill-me`, `~/.claude/skills/to-prd`:

```bash
readlink ~/.claude/skills/forge
```

Expected: resolves to a path containing `.claude/dotfiles-core/`. If it resolves to the overlay's own in-tree copy or is missing → **WARN: {skill} symlink does not resolve through submodule — re-run install.sh**

#### 7d — Rendered file freshness

Re-render CLAUDE.md and AGENTS.md from fragments and diff against `~/.claude/CLAUDE.md`:

```bash
# Source lib-overlays.sh from core submodule
source {dotfiles-dir}/.claude/dotfiles-core/scripts/lib-overlays.sh

# Re-render core-only view to temp
concat_fragments /tmp/doctor-claude-check.md {dotfiles-dir}/.claude/dotfiles-core/_shared/claude-md

# Compare
diff /tmp/doctor-claude-check.md ~/.claude/CLAUDE.md
```

If diff is non-empty → **WARN: CLAUDE.md is stale (fragments diverged). Re-run install.sh to regenerate.**

If identical (or overlay adds extra content that makes it a superset) → `ok  CLAUDE.md freshness check`

#### 7e — Overlay fragment application check

If `{dotfiles-dir}/.claude/overlay-fragments.yaml` exists, verify each registered fragment's target file contains its sentinel markers:

```bash
# For each fragment in overlay-fragments.yaml, grep target for BEGIN/END sentinels
```

Missing sentinel → **WARN: fragment `{name}` sentinel not found in `{target}` — re-run install-overlay.sh**

### Step 8 — Summary

Present a summary:
- Total checks run
- Issues found (with severity: BROKEN, WARN, INFO)
- Suggested fix commands for any issues

If everything passes, say: "All systems healthy."

If everything passes and there are no BROKEN or WARN issues, append: `Tip: Run /briefing for a situation report of your current work.`
