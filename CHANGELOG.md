# Changelog

> **How to update:** The pre-commit hook (`scripts/pre-commit.sh`) is auto-installed by `install.sh`. It runs a fast leakage check (`scripts/check-no-leakage.sh`) and re-renders the generated `CLAUDE.md.generated` and `AGENTS.md.generated` files on every commit. Full test/lint suite (`make all`) runs in CI. If you bypass the hook or work in a context where hooks cannot run, keep this file current manually. Each release heading links to the diff on the public mirror.

## v1.14.0 — 2026-07-06 (babysit-prs)

### Added

- `/babysit-prs` skill (`.claude/skills/babysit-prs/`) — a `/loop`-driven orchestrator that watches open PRs and, behind escalating typed opt-in flags (`--review-only` default, `--fix`, `--approve`, `--merge`), reviews / fixes / approves / merges them behind a reversibility × blast-radius gate. One tick per invocation; `/loop` owns cadence. No companion agent: it composes `/code-auditor` → Scout/Ranger for review and Cyrus for fixes, owning only the scheduling, gating, and I/O glue. Internally split into a read-only **Watcher** (target resolution, one `gh pr view` per PR, transition/CI classification) and an in-session **Actor** (the only half that mutates); every accept/hold/settle/stop decision is a call to the tested `babysit-gate.sh`, never re-derived in prose. Safety posture: merging a teammate's PR you did not name is structurally impossible (foreign authorship is high blast-radius; merge requires blast-radius `!= high`), and every safety-relevant comparison fails **closed** on absent/non-numeric input.
- `.claude/skills/babysit-prs/scripts/babysit-gate.sh` — the pure-function decision core (`decide`, `merge-gate`, `blast-radius`, `flake-tick`, `fingerprint`, `converged?`, `settle?`, `rearm?`, `auto-approve?`, `defer?`, `stop?`): JSON/args in → token on stdout, exit 0, no side effects.
- `.claude/skills/babysit-prs/scripts/babysit-state.sh` — per-run JSON state store; atomic write-temp-then-rename that refuses to commit empty content; single-writer per tick.
- `.claude/skills/babysit-prs/data/state-schema.json` — documents and round-trip-fixtures the per-run state shape.
- `tests/babysit-{gate,state,routing}.bats` — 124 tests, auto-discovered by `make test`. Adversarial coverage includes the fail-open regression (non-numeric/absent safety input → HOLD/high-blast, never ALLOW), line-independent fingerprints, per-name flake keying, a state-corruption regression (a malformed `--set` key leaves the state file byte-identical), and the octal-leading-zero fail-open (a stringified `"0450"` size must gate as `high:size`, not slip through as `low`).

### Changed

- `Makefile` — `make lint` now shellchecks skill-local scripts (`.claude/skills/*/scripts/*.sh`) in addition to repo-root `scripts/*.sh`; the nested glob no-ops cleanly when a skill ships none. Skill scripts back consequential actions, so they are gated by CI rather than a manual reminder.
- `_shared/claude-md/10-agent-routing.md`, `_shared/claude-md/20-trigger-skills.md` — name-prefix (`Babysit, ...`) and trigger-phrase routing rows for the new skill, regenerated into `.claude/CLAUDE.md.generated` in lockstep.

### Fixed

- `.claude/skills/babysit-prs/scripts/babysit-gate.sh` — forced base-10 in the two `$(( ))` arithmetic sites (`_blast_radius` churn, `flake-tick` counter). A digit-only but leading-zero size string (e.g. `"0450"`) previously read as **octal** (296 decimal, under the 400 threshold when the true value 450 is over it), silently failing the size veto **open** to `low` — or crashing on an invalid octal literal like `"0800"`. Both violated the gate's fail-closed contract. Found by Ranger on the pre-merge pass and verified by execution before and after the fix.

## v1.13.0 — 2026-06-22 (revert Fable pins to opus alias)

### Changed

- `.claude/agents/aristotle-deconstructor.md`, `.claude/agents/optimus-planner.md` — reverted `model: claude-fable-5` (pinned in v1.11.0) back to the `opus` alias. A pinned raw model ID has **no auto-fallback**: if `claude-fable-5` is disabled or withdrawn, the pinned agents do not fall back to `opus`/Opus 4.8 — the spawn errors or falls through to the session model, never to the intended tier. An alias can never be stranded that way (it always resolves to whatever the platform currently ships for the tier), and it keeps auto-upgrade. Net: both deepest-reasoning agents are back on the strongest auto-upgrading tier with no stranding risk.
- `.claude/_shared/model-tiers.md` — table moves Aristotle/Optimus back to `opus`; dropped the pin-tradeoff note; rewrote the "Non-aliased tiers" Fable entry to explain *why no agent pins it* (the no-auto-fallback + auto-upgrade-loss reasoning) and to recommend a session `/model` override over a permanent pin when Fable's tuning is genuinely wanted; refreshed the alias-resolution date stamp. Doctor Step 6c logic is unchanged — it remains pin-aware and forward-safe, it just finds zero pinned agents now.
- `.claude/skills/doctor/SKILL.md` — Step 6c prose reworded so the pin mechanism is described conditionally ("if any agent is pinned…") rather than asserting present-tense that pinned agents exist, since the revert leaves zero. The validation logic is unchanged.

## v1.12.0 — 2026-06-10 (comment marker + token economy)

### Added

- `_shared/agents-md/20-task-orchestration.md` § "Token Economy" — a new Core-Principles-adjacent section making the kit's implicit cost discipline explicit so every skill/agent inherits it: scope before exploring (a one-line constraint rules out wide token-burning investigation; this is also *why* Optimus plans before Cyrus builds), batch/parallelize independent agent calls rather than serializing follow-ups (each subagent call re-sends its prompt + re-reads context — `code-auditor`'s 3-agent fan-out is the model), prefer targeted edits over regenerating unchanged output, route work to the cheapest sufficient model tier (links `model-tiers.md`), and weigh subagent offload against its per-call re-send cost. Distilled from the transferable ~3 of 23 tactics in a Claude-usage-reduction article (the rest were claude.ai consumer-product advice already covered by `/handoff`, `/smart-compact`, `/smart-statusline`, `/schedule`, and the skills-load-on-demand architecture).

- `_shared/agents-md/20-task-orchestration.md` § "Automated Comment Marker — 🤖 prefix" — a canonical global rule: every comment an agent posts on the user's behalf (Jira issue comments, GitHub PR review/inline/general comments, GitHub issue comments) is prefixed with `🤖 `, even when the user approved the exact text — approval makes the content theirs, authorship is still the agent. One carve-out: omit only on explicit user instruction ("post as me, no robot prefix"). Explicitly scoped to *comments* — commit messages, PR titles, PR bodies, and Slack posts follow their own separate conventions. Replaces the previous state where the 🤖 marker was sprinkled only into the example comment strings of `ticket-pickup`/`ticket-swarm` (Jira-only, unenforced).
- `tests/automated-comment-marker.bats` (13 cases) — guards the canonical rule's presence in the fragment + generated AGENTS.md, its Jira/GitHub coverage and "unless instructed" carve-out, that all six posting surfaces (ticket-pickup, ticket-swarm, scout/ranger skills, scout/ranger agents) reference it, and that the autonomous Jira pings still carry the inline prefix. Per Ranger's self-review of this change: the four reviewer-surface assertions check the operative `🤖 ` prefix *instruction* (not just the section-name citation) so a regression that kept the heading but dropped the rule fails the suite — verified via a mutation test; the generated-file check asserts a body line as well as the heading; and the in-section emoji grep is scoped so it can't pass on an unrelated future occurrence.

### Changed

- `.claude/skills/scout-reviewer/SKILL.md`, `.claude/skills/ranger-reviewer/SKILL.md`, `.claude/agents/scout-reviewer.md`, `.claude/agents/ranger-reviewer.md` — the comment-posting steps and gate rules now require the `🤖 ` prefix on every posted PR comment and approval message (visible in the draft the user approves), citing the canonical AGENTS.md rule. Previously these GitHub paths had no marker at all.
- `.claude/skills/ticket-pickup/SKILL.md`, `.claude/skills/ticket-swarm/SKILL.md` — the inline 🤖 voice note now points at the canonical AGENTS.md rule as the source of the requirement, rather than implying it's a skill-local convention.
- `_shared/agents-md/20-task-orchestration.md` — clarified (per Ranger's review) that `/code-auditor` routes to Scout/Ranger but never posts to GitHub itself, so the prefix is applied by the delegated reviewer, not the auditor — resolving a contradiction with code-auditor's own "never post to GitHub" role guard.

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
