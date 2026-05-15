# dotfiles-core

Universal Claude Code agent pipeline framework.

## What it is

`dotfiles-core` is a public, opinionated framework for Claude Code. It ships 30+ workflow skills, 5 reasoning agents (Aristotle / Optimus / Cyrus / Ranger / Scout), shared role-guards and responsibility-boundary docs, tested installer, and full-history leakage checking — everything needed to run a production-grade AI-assisted engineering workflow from a standalone install or as the foundation of a company/personal overlay.

## Prerequisites

- **Claude Code CLI** (`claude` command on `$PATH`). Install: `curl -fsSL https://claude.ai/install.sh | bash`, or visit [claude.ai/install](https://claude.ai/install). The installer can do this for you if `claude` isn't found.
- **bash 3.2+** (macOS default; Linux default).
- **git 2.x+** with submodule support.
- **macOS or Linux**. Windows isn't tested; WSL likely works but is unverified.
- Optional, only for some skills/tooling: `bats` (running tests), `shellcheck` (linting), `gh` (used by `/pr-create-from-commits` and similar).

## Quickstart

There are two equally-supported install paths. Pick whichever matches your use case.

> **A note on URLs.** This repo is mirrored to multiple Git hosts. Replace `<repo-url>` in the commands below with the URL of whichever mirror you have access to — for example, an internal Git host inside your company, or a public GitHub mirror. The installer behaves identically regardless of source.

### Option 1 — Standalone install

Use this when you want to run `dotfiles-core` directly without building your own overlay. Good for evaluating, learning the framework, or using it as-is.

```bash
git clone <repo-url> ~/dotfiles-core
cd ~/dotfiles-core && bash install.sh
```

### Option 2 — Overlay install

Use this when you want to layer your own customizations (aliases, personal skills, machine-specific MCP config, secrets handling) on top of `dotfiles-core`. The overlay owns *your* customizations; `dotfiles-core` is consumed via git submodule and updates independently. See [How to create your own overlay](#how-to-create-your-own-overlay) below for the one-time setup.

```bash
git clone --recurse-submodules https://github.com/<you>/<your-overlay>.git ~/dotfiles
cd ~/dotfiles && bash install.sh
```

The `--recurse-submodules` flag is **required** for overlay installs — without it, the `dotfiles-core` submodule is empty and the installer halts with a clear error. If you forgot:

```bash
cd ~/dotfiles
git submodule update --init --recursive
bash install.sh
```

## What the installer does

Both install paths create symlinks under `~/.claude/`:

- `~/.claude/skills/<each-skill>/` → skills inside the cloned repo (or, for overlay installs, into the submodule for universal skills and into the overlay for overlay-specific ones).
- `~/.claude/agents/<each-agent>.md` → reasoning agent files.
- `~/.claude/_shared/` → shared role-guards and responsibility-boundary docs.
- `~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md` → rendered from numbered fragments at install time.

The installer also installs two universal Claude Code plugins from the official Anthropic marketplace, declared in `plugins.txt` at the repo root:

- `frontend-design@claude-plugins-official` — production-grade frontend interface guidance
- `playwright@claude-plugins-official` — browser automation and testing

Plugin install is idempotent and gracefully skips if the `claude` CLI is unavailable. Overlays may layer additional plugins via their own `.claude/plugins.txt`; the two lists are union-installed.

The installer is **idempotent** — re-run it any time. It detects existing symlinks, prompts before overwriting non-symlink files, and reports what changed.

## Verify the install

```bash
bash install.sh --check     # reports symlink health without modifying anything
```

Then restart Claude Code, run `claude`, and try a slash command:

```
/forge
```

If `/forge` (and other commands like `/briefing`, `/doctor`, `/code-auditor`) appear in the slash-command menu, the install succeeded.

## First steps

Once installed, try one of these to see the framework in action:

- **`/forge`** — five-stage pipeline from rough idea to built and tested code.
- **`/grill-me <plan>`** — relentless interview to stress-test a design.
- **`/code-auditor`** — complexity-aware code review on your current branch.
- **`/doctor`** — full health check of the install.
- **`/briefing`** — session-start situation report (works best with Jira/GitHub configured).

## Troubleshooting

- **`install.sh` says "dotfiles-core installer not found"** (overlay path) → run `git submodule update --init --recursive` from the overlay root, then re-run `bash install.sh`.
- **Slash commands don't appear** → restart Claude Code. The CLI loads skills at session start, not while a session is running.
- **`make test` fails with `DOTFILES_DIR not set`** → use `make test`, not raw `bats`. The Makefile injects `DOTFILES_DIR` for the test environment.
- **Pre-commit hook rejects a commit citing leakage** → check `scripts/leakage-tokens.txt`. The check is intentional; if your commit references a forbidden token, rename it.
- **Symlink collision warning** → `install.sh` backs up existing non-symlink files to `<file>.bak.<timestamp>` before linking. Inspect and delete the backup once you're sure.

## Uninstall

```bash
bash install.sh --check     # list what was installed
# Then manually remove the symlinks under ~/.claude/ that point into your clone:
find ~/.claude -maxdepth 3 -type l -lname "*dotfiles-core*" -delete
# Or, more aggressively (removes all dotfiles-core-managed symlinks):
rm ~/.claude/{CLAUDE,AGENTS,DoD}.md
rm -rf ~/.claude/{_shared,skills,agents}
# Finally, drop the clone itself:
rm -rf ~/dotfiles-core   # or your overlay directory
```

## Architecture — three-repo model

```
┌─────────────────────────────────────────────┐
│  dotfiles-core (this repo — public, MIT)    │
│  30+ universal skills, 5 reasoning agents   │
│  _shared/, scripts/, tests/, install.sh     │
└──────────────────┬──────────────────────────┘
                   │ git submodule
        ┌──────────┴──────────┐
        │                     │
┌───────▼──────┐     ┌────────▼────────┐
│  company     │     │  personal       │
│  overlay     │     │  overlay        │
│              │     │                 │
│  company-    │     │  personal       │
│  specific    │     │  aliases,       │
│  skills,     │     │  skills, etc.   │
│  aliases,    │     │                 │
│  MCP config  │     │                 │
└──────────────┘     └─────────────────┘
```

Universal improvements land in core. Overlays adopt them via explicit submodule pointer-bump commits. Company secrets and private tooling never touch core.

## How to create your own overlay

An overlay is your personal or company-specific repo that consumes `dotfiles-core` as a git submodule and adds whatever else you need.

### One-time setup

1. **Create a new repo** on your GitHub (private or public — your call). Clone it locally:

   ```bash
   git clone https://github.com/<you>/<your-overlay>.git ~/dotfiles
   cd ~/dotfiles
   ```

2. **Add `dotfiles-core` as a submodule** at `.claude/dotfiles-core/` (replace `<repo-url>` with whichever mirror you use — see [the URL note](#quickstart) above):

   ```bash
   git submodule add <repo-url> .claude/dotfiles-core
   ```

3. **Author a thin `install.sh` orchestrator** that delegates to core, then runs your overlay-specific steps:

   ```bash
   cat > install.sh <<'EOF'
   #!/usr/bin/env bash
   set -euo pipefail
   DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

   # 1. Run dotfiles-core installer (universal skills, agents, _shared/)
   bash "$DOTFILES_DIR/.claude/dotfiles-core/install.sh" "$@"

   # 2. Run your overlay-specific install steps
   if [ -f "$DOTFILES_DIR/scripts/install-overlay.sh" ]; then
     source "$DOTFILES_DIR/scripts/install-overlay.sh"
   fi

   echo "Done."
   EOF
   chmod +x install.sh
   ```

4. **Add overlay-specific content** alongside the submodule. Examples:
   - `.aliases.local` — shell aliases for your environment
   - `.claude/skills/<your-skill>/` — overlay-only skills (not in core)
   - `.claude/skill-fragments/<core-skill>/` + `.claude/overlay-fragments.yaml` — inject overlay-specific content into core skills via the [`lib-overlays.sh`](scripts/lib-overlays.sh) fragment system
   - `scripts/install-overlay.sh` — your overlay-specific install steps (Cursor mirroring, MCP server registration, machine-detection, etc.)

5. **Commit, push, install**:

   ```bash
   git add -A && git commit -m "Initial overlay setup"
   git push -u origin main
   bash install.sh
   ```

### Day-2: improving a universal skill

When you want to improve a skill that lives in `dotfiles-core`:

1. Edit the skill **inside the submodule** (use `/core-edit <skill>` in Claude Code — it scripts the cd-into-submodule, edit, commit, push, and pointer-bump dance):
2. Or do it manually:
   ```bash
   cd ~/dotfiles/.claude/dotfiles-core
   git checkout main
   # edit the skill, run tests, commit, push to dotfiles-core
   git push
   cd ~/dotfiles
   git add .claude/dotfiles-core
   git commit -m "chore(submodule): bump dotfiles-core to <new SHA>"
   git push
   bash install.sh
   ```

The submodule SHA pin is intentional — your overlay records exactly which version of `dotfiles-core` it consumes. Pull updates from upstream `dotfiles-core` whenever you choose, not automatically.

## Skills — 30+ universal workflow skills

| Skill | What it does |
|---|---|
| `/agent-stats` | Aggregate agent pipeline metrics: first-pass rate, classification distribution, health flags |
| `/aristotle-deconstructor` | First-principles deconstruction pipeline (Aristotle → Optimus → Cyrus) |
| `/briefing` | Session-start situation report: sprint status, open PRs, CI, calendar, Slack signals |
| `/code-auditor` | Complexity-aware PR review router — auto-routes to Scout or Ranger |
| `/core-edit` | Edit a skill inside dotfiles-core from within an overlay repo |
| `/create-jira-ticket` | Create Jira tickets (Stories, Bugs, Tasks, Epics) via Atlassian MCP |
| `/create-tech-spec` | Generate a technical specification or design document |
| `/cyrus-tdd-engineer` | TDD implementation agent — Red-Green-Refactor with 80%+ coverage |
| `/doctor` | Health check: validates symlinks, CLI tools, MCP servers, plugins |
| `/dotfiles-sync` | Pull dotfiles updates and re-run install.sh |
| `/forge` | Five-stage sense-making + build pipeline (grill-me → PRD → plan → implement) |
| `/google-docs` | Create, read, and edit Google Docs with Markdown conversion |
| `/google-drive` | Search, upload, download, and share Google Drive files |
| `/grill-me` | Relentless interview to stress-test a plan or design |
| `/lessons-review` | Surface cross-project lessons; gate promotion to system-wide guidance |
| `/mermaid-diagrams` | Convert Mermaid syntax to PNG via mmdc |
| `/metrics-emit` | Library skill — structured metrics event schema for pipeline skills |
| `/obligations` | Cross-session reminders: create, view, cancel, and evaluate |
| `/optimus-planner` | Detailed execution plan before implementation begins |
| `/pr-create-from-commits` | Create a PR from recent commits with template auto-detection |
| `/ranger-reviewer` | Staff-level PR review with confidence scoring (Opus-tier) |
| `/review-context` | Generate a per-project llms.txt for reviewer context |
| `/scout-reviewer` | PR review with parallel analysis and confidence scoring (Sonnet-tier) |
| `/self-evaluate` | Self-evaluate the dotfiles repo (overlay or core) for health and engineering quality |
| `/smart-compact` | Topic-aware /compact — choose what survives the context summary |
| `/smart-statusline` | Terminal statusline: model, cost, context usage bar |
| `/swarm-retro` | Analyze swarm runs for misclassifications and improvement opportunities |
| `/team-lead` | Domain coordinator for ticket-swarm (not user-invocable) |
| `/ticket-pickup` | Fetch a Jira ticket, enrich with codebase context, route to pipeline |
| `/ticket-swarm` | Batch-process Jira tickets with parallel agent pipelines |
| `/to-prd` | Synthesize conversation context into a structured PRD |

## Agents — 5 reasoning agents

| Agent | Role |
|---|---|
| **Aristotle** | First-principles deconstructor — strips assumptions before planning begins |
| **Optimus** | Planner — produces detailed, step-sequenced execution plans |
| **Cyrus** | TDD engineer — implements with strict Red-Green-Refactor discipline |
| **Ranger** | Staff-level reviewer — deep analysis, Opus-tier, approval-gated |
| **Scout** | PR reviewer — parallel analysis, confidence scoring, Sonnet-tier |

Each agent carries a role-guard block (generated by `scripts/role-guard-gen.sh`) that enforces strict boundaries: Cyrus never architects, Ranger never implements, Aristotle never plans.

## Shared infrastructure

- `_shared/role-guards/` — per-agent role-guard fragments, spliced into agent files by `role-guard-gen.sh`
- `_shared/responsibility-boundaries.md` — canonical boundary table consumed by all 5 agents
- `_shared/agents-md/` — numbered fragments concatenated into AGENTS.md at install time
- `scripts/check-no-leakage.sh` — enforced via pre-commit hook and CI
- `scripts/lib-overlays.sh` — overlay-fragment registration and concatenation library
- `agent-memory-seeds/` — starter MEMORY.md files for each reasoning agent

## Contributing

PRs welcome. The pre-commit hook runs `scripts/check-no-leakage.sh` on every commit. The token list lives in `scripts/leakage-tokens.txt` — any commit adding a token from that list is rejected. Keep contributions universal.

Run `make test` before opening a PR. All 183 tests must pass.

## License

MIT — Copyright (c) 2026 dotfiles-core contributors. See [LICENSE](LICENSE).
