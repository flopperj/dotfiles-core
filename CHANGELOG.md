# Changelog

> **How to update:** The pre-commit hook (`scripts/pre-commit.sh`) is auto-installed by `install.sh`. It runs a fast leakage check (`scripts/check-no-leakage.sh`) and re-renders the generated `CLAUDE.md.generated` and `AGENTS.md.generated` files on every commit. Full test/lint suite (`make all`) runs in CI. If you bypass the hook or work in a context where hooks cannot run, keep this file current manually. Each release heading links to the diff on the public mirror.

## v1.12.0 — 2026-06-10 (automated comment marker)

### Added

- `_shared/agents-md/20-task-orchestration.md` § "Automated Comment Marker — 🤖 prefix" — a canonical global rule: every comment an agent posts on the user's behalf (Jira issue comments, GitHub PR review/inline/general comments, GitHub issue comments) is prefixed with `🤖 `, even when the user approved the exact text — approval makes the content theirs, authorship is still the agent. One carve-out: omit only on explicit user instruction ("post as me, no robot prefix"). Explicitly scoped to *comments* — commit messages, PR titles, PR bodies, and Slack posts follow their own separate conventions. Replaces the previous state where the 🤖 marker was sprinkled only into the example comment strings of `ticket-pickup`/`ticket-swarm` (Jira-only, unenforced).
- `tests/automated-comment-marker.bats` (13 cases) — guards the canonical rule's presence in the fragment + generated AGENTS.md, its Jira/GitHub coverage and "unless instructed" carve-out, that all six posting surfaces (ticket-pickup, ticket-swarm, scout/ranger skills, scout/ranger agents) reference it, and that the autonomous Jira pings still carry the inline prefix.

### Changed

- `.claude/skills/scout-reviewer/SKILL.md`, `.claude/skills/ranger-reviewer/SKILL.md`, `.claude/agents/scout-reviewer.md`, `.claude/agents/ranger-reviewer.md` — the comment-posting steps and gate rules now require the `🤖 ` prefix on every posted PR comment and approval message (visible in the draft the user approves), citing the canonical AGENTS.md rule. Previously these GitHub paths had no marker at all.
- `.claude/skills/ticket-pickup/SKILL.md`, `.claude/skills/ticket-swarm/SKILL.md` — the inline 🤖 voice note now points at the canonical AGENTS.md rule as the source of the requirement, rather than implying it's a skill-local convention.

## v1.11.0 — 2026-06-10 (review heuristics)

### Added

- `.claude/skills/code-auditor/references/review-heuristics.md` — canonical, narrowly-scoped reference for a few test/review heuristics shared by Scout, Ranger, and Cyrus: the four lies of a green diff (test asserts a mock was called not the result; dead code wired in nowhere; placeholder behind a type contract; type/contract error the happy-mock hides), the "test only code you own" filter, scope-feedback-to-the-diff, mechanical-invariant enforcement, and re-evaluating harness complexity on model upgrades. Distilled from Anthropic/OpenAI/Huntley harness research (via the `crodrigues3/harness` evaluator) and re-expressed for this kit's stack and idiom; provenance noted in the doc header.

### Changed

- `.claude/agents/ranger-reviewer.md`, `.claude/agents/scout-reviewer.md` — the Testing checklist now carries a one-line-per-archetype summary of the four lies of a green diff, framed as **correctness** findings (so they survive confidence filtering rather than being dropped as coverage nits), each pointing at the canonical reference.
- `.claude/agents/cyrus-tdd-engineer.md` — new "Test Only Code You Own" section after the Mocking Decision, reconciled with the 80% coverage threshold (wrapper pass-through lines don't earn their keep), cross-linked to the mocking tree, self-verification checklist, and the canonical reference.
- `.claude/skills/code-auditor/SKILL.md` — routing-handoff section now points reviewers at the shared `review-heuristics.md` (the auditor routes, it does not apply them).
- `.claude/agents/aristotle-deconstructor.md`, `.claude/agents/optimus-planner.md` — pinned `model: claude-fable-5` (was the `opus` alias). Fable 5 is positioned for "the hardest and longest-running tasks," which fits the two deepest-reasoning, least-latency-sensitive agents: first-principles deconstruction (Aristotle) and execution planning (Optimus), where plan quality gates everything downstream. These are explicit pins, not aliases, because Fable is not an `opus`/`sonnet` alias target — the accepted tradeoff is that these two no longer auto-upgrade and must be re-pointed manually on future model releases. Ranger, Cyrus, and Scout stay on their `opus`/`sonnet` aliases.
- `.claude/_shared/model-tiers.md` — refreshed the stale "Expected alias resolution" block (was dated 2026-04-20, `opus → claude-opus-4-7`) to 2026-06-10 reality verified against the `/model` picker: `opus → claude-opus-4-8`, `sonnet → claude-sonnet-4-6`, `haiku → claude-haiku-4-5`. Moved Aristotle and Optimus to a pinned `claude-fable-5` tier in the assignment table with rationale + an explicit pin-tradeoff note (auto-upgrade lost, revisit each release), and documented Fable 5 under "Non-aliased tiers" as a selectable tier reached only by pin or session override. No Mythos tier exists in the picker; none was added.
- `.claude/skills/doctor/SKILL.md` — Step 6c no longer hardcodes a model version (it pointed at `claude-opus-4-7`) and now understands pinned-ID tiers: it validates aliased agents against the alias and pinned agents against the exact ID the doc marks `(pinned)`, treating a matching pin as intentional rather than drift.

## v1.10.0 — 2026-06-09 (performance-review)

### Added

- `/performance-review` skill (`.claude/skills/performance-review/SKILL.md`) — a company-agnostic engine that drafts an honest, evidence-backed performance self-review into a Google Doc with every Jira ticket / PR / repo hyperlinked. Two modes (year-end retrospective verdict; mid-year forward-looking checkpoint) and calibrates the rating recommendation to the user's role/level and stated audience. Reads company specifics (fiscal calendar, Jira cloudId, GitHub host, template doc, rating ladder) from `~/.claude/performance-review.yaml`, with built-in defaults if absent — same core/overlay split as `policies.yaml` for `/briefing`.
- `references/honesty-bar.md` — the eight rules (verify every ticket, shipped-vs-built language, honest metrics, audience-altitude jargon stripping, initiative-vs-ownership, level-calibrated self-rating, promotion angle, section consistency) plus the pre-submit audit checklist that make a self-review survive calibration scrutiny.
- `references/evidence-engine.md`, `references/google-docs-linking.md`, `references/config-defaults.md` — the exact Jira/GitHub gathering commands, the Docs-API run-coalescing / link-bleed gotchas, and the YAML schema with graceful fallbacks.

### Fixed

- `scripts/check-no-leakage.sh`, `scripts/check-consult-grammar.sh` — replaced `mapfile` (a bash 4+ builtin) with portable `while-read` loops. `mapfile` crashed under the repo's target macOS stock bash 3.2, which blocked every commit since both hooks run from `scripts/pre-commit.sh`.

## v1.9.0 — 2026-06-09 (overlay tooling)

### Added

- `/overlay-init` skill (`.claude/skills/overlay-init/SKILL.md`) — scaffolds a new dotfiles-core overlay and configures existing ones. Routes a bare invocation to scaffolding and `add-skill` / `add-fragment` / `add-context` to the configure sub-generators. The `add-context` route writes the overlay half of the bilateral consult-instruction contract and machine-checks the precise core-side gap (the `consult-vocabulary.txt` entry plus a core SKILL.md consult-line), routing the core-side change to `/core-edit` without auto-editing core.
- `scripts/new-overlay.sh` — deterministic scaffold engine: `new-overlay.sh <target-dir> [overlay-name] [--force] [--core-url <url>]`. No-clobber guard, `origin`-derived submodule URL with a local-path guard (errors to `--core-url`), metacharacter-safe `awk` token substitution (`{{OVERLAY_NAME}}` + `{{CORE_URL}}`), `--force` idempotency, `git init` + `git submodule add` + stage (no auto-commit), and a non-destructive final `bash install.sh --check`.
- `scripts/overlay-skeleton/` — the constant overlay skeleton committed once as gate-covered `.template` fixtures (with a `dotclaude/` rename) so they stay invisible to the consult-grammar and leakage scanners by construction; the engine copies them rather than generating the orchestrator per-overlay.
- `tests/new-overlay.bats` (9-case matrix, offline local bare-repo submodule fixture) and `tests/overlay-skeleton.bats` (fixture well-formedness + a self-verifying gate-safety guard).

### Changed

- `scripts/lib-overlays.sh` — `apply_manifest` now treats an **absent** manifest as an optional no-op (`return 0`), mirroring `concat_fragments`' optional-overlay-dir contract. A present-but-malformed manifest, or a declared fragment whose source is missing, still errors.
- `README.md` — "How to create your own overlay" rewritten: `/overlay-init` is now the primary path; the hand-authored heredoc `install.sh` step is removed and the manual fallback points at the shipped `scripts/overlay-skeleton/install.sh.template` fixture (single source of truth).
- `_shared/claude-md/20-trigger-skills.md` — added the `/overlay-init` trigger-routing row (regenerates `CLAUDE.md.generated`).

### Fixed

- `.gitignore` — ignore `.claude/scheduled_tasks.lock`, a Claude Code runtime artifact that should never be committed.

## Unreleased — v1.4.0 (Cohort 1: protocol-invisible hygiene)

### Added

- `PROTOCOL.md` — single source of truth for the consult-instruction grammar, bilateral overlay contract, enforcement evolution path (Cohort 1 PROVISIONAL → Cohort 2 positive grammar), and design rationale. Includes 16 shape-lint assertions in `tests/protocol-artifact.bats`.
- `scripts/_lib.sh` — new `_iter_core_skill_dirs` helper that replaces the duplicated doubled-slash glob in both `lib-core-symlinks.sh` and `core-check.sh`. Six assertions in `tests/skills-iteration.bats`.
- `.github/workflows/lint.yml` — GitHub Actions CI for the public mirror: runs `make all` (lint + check-leakage + bats tests) on every PR and push to `main`/`master`.
- `scripts/lib-core-symlinks.sh` — `_install_precommit_hook` function; auto-installs `scripts/pre-commit.sh` → `.git/hooks/pre-commit` during `install.sh`. Idempotent; skips submodule worktrees where `.git` is a file, not a directory; backs up existing regular-file hooks (husky, lefthook, hand-written) before symlinking. Six assertions in `tests/install-precommit-hook.bats`.

### Changed

- `scripts/lib-core-symlinks.sh`, `scripts/core-check.sh` — skill-dir iteration now delegates to `_iter_core_skill_dirs` (no behavior change; cosmetic path normalization).

### Fixed

- Doubled-slash glob `"$core_dir/.claude/skills/"/*/ ` in `lib-core-symlinks.sh:94` and `core-check.sh:36` — trailing slash inside the quoted segment produced `…/skills//*/ ` on some shells. Now produced by the helper via proper concatenation.

### Removed

- `scripts/lib-symlinks.sh`, `scripts/lib-seeds.sh`, `scripts/check.sh` — zero-consumer dead code (un-prefixed overlay forks never wired into `install.sh`; `check.sh` superseded by `core-check.sh`). Deleting `check.sh` silences 14 pre-existing SC2088 shellcheck warnings.

## v1.3.0 — 2026-05-14

- `/self-evaluate` skill: runtime mode detection picks core or overlay rubric automatically. Standalone-core sessions can self-audit during bootstrap; overlay sessions retain `--core` flag.
- `/handoff` skill: cross-session reasoning trails — capture typed rejections and next intent for the next session.
- Rubric: §8 Hostile-Read Anchors + §9 Contract Enforcement Audit. Verifiers check the artifact against itself; TIGHT/LEAKY/DECORATIVE contract status with axis-cap-at-4 rule for LEAKY/DECORATIVE.
- README: skills table updated with `/self-evaluate` row.
- Bug fixes: backup collision-safe suffix counter; seed backup before `--reseed` overwrite; core-check resolves symlink target before freshness check.
