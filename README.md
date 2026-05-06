# dotfiles-core

Universal Claude Code agent pipeline framework.

## What it is

`dotfiles-core` is a public, opinionated framework for Claude Code. It ships 30+ workflow skills, 5 reasoning agents (Aristotle / Optimus / Cyrus / Ranger / Scout), shared role-guards and responsibility-boundary docs, tested installer, and full-history leakage checking — everything needed to run a production-grade AI-assisted engineering workflow from a standalone install or as the foundation of a company/personal overlay.

## Quickstart

If you have your own overlay repo (recommended for company-specific customization):

```bash
git clone --recurse-submodules https://github.com/<you>/<your-overlay>.git ~/dotfiles
cd ~/dotfiles && bash install.sh
```

To use dotfiles-core standalone (no overlay):

```bash
git clone https://github.com/<you>/dotfiles-core.git ~/dotfiles-core
cd ~/dotfiles-core && bash install.sh
```

After install, restart Claude Code. The full agent pipeline is available.

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

## How to fork as your overlay

1. Create a new private repo (your overlay).
2. Add dotfiles-core as a submodule:
   ```bash
   git submodule add https://github.com/<you>/dotfiles-core.git .claude/dotfiles-core
   ```
3. Write your own `install.sh` that calls `core/install.sh` and then installs overlay-specific content. See `lib-overlays.sh` in `scripts/` for the overlay-fragment registration system.
4. To improve a universal skill: edit in dotfiles-core, push, then bump the submodule pointer in your overlay and commit.

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

Run `make test` before opening a PR. All 166 tests must pass.

## License

MIT — Copyright (c) 2026 dotfiles-core contributors. See [LICENSE](LICENSE).
