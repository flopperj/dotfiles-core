# Changelog

> **How to update:** The pre-commit hook (`scripts/pre-commit.sh`) is auto-installed by `install.sh`. It runs a fast leakage check (`scripts/check-no-leakage.sh`) and re-renders the generated `CLAUDE.md.generated` and `AGENTS.md.generated` files on every commit. A pre-push gate (`scripts/pre-push.sh`, also auto-installed) scans every outgoing commit's tree and metadata before it leaves the machine. CI runs lint, consult-grammar, and the test suite (including synthetic-token leakage mechanism tests) on every PR; the company-token scan is a separate step that runs only when guard data is present on the runner. If you bypass the hooks or work in a context where hooks cannot run, keep this file current manually. Each release heading links to the diff on the public mirror.

## v1.19.0 — 2026-09-09 (portable export of the reasoning pipeline)

### Added

- **`scripts/export-skills.sh <target> [--check] [--owner-team …] [--owner-slack …]`** — renders self-contained copies of the nine reasoning-pipeline skills (`aristotle-deconstructor`, `optimus-planner`, `cyrus-tdd-engineer`, `forge`, `grill-me`, `to-prd`, `code-auditor`, `scout-reviewer`, `ranger-reviewer`) into a plain `skills/<name>/SKILL.md` repository for skills CLIs that cannot install `~/.claude/agents`, workflows, `_shared/`, or `evals/`. Agent definitions ship as `skills/<name>/agent.md` with a *Launching the agent* section (registered subagent → `general-purpose` fallback primed with `agent.md` → inline) and a `scripts/install-agent.sh` registration helper. Shared assets (turn-cap doc, handoff schemas, review heuristics, `code-auditor-score.js`) are duplicated per skill so single-skill installs work. SKILL.md frontmatter gains a `metadata:` block (`domain`, `status`, `bundle`, `tags`, `tools`, `mcp_servers`, optional owner fields). A README table is maintained between `REASONING PIPELINE TABLE` sentinels. `--check` exits 1 on drift.
- **`scripts/check-portable-refs.sh <skills-dir>`** — self-containment gate for an exported bundle: forbids core-only paths and export markers, requires every `/skill` reference to resolve to a bundle skill or be covered by the "optional external skills" paragraph, and verifies relative links resolve. Also guards against nested `SKILL.md` files (the CLI registers each one as a skill).
- **`scripts/templates/install-agent.sh`** — copied into every agent-backed exported skill; installs `agent.md` to `~/.claude/agents/<name>.md` (or `./.claude/agents/` with `--project`), refusing to overwrite a differing file without `--force`.
- **`.claude/_shared/portable/`** — `launch.md`, `bundle-notes.md`, `agent-notes.md` templates inserted into exported files.
- **Export markers** — `<!-- BEGIN CORE-ONLY -->` … `<!-- END CORE-ONLY -->` (dropped on export) and `<!-- PORTABLE-ONLY … -->` (unwrapped on export). Applied to the metrics-emit sections in `optimus-planner/SKILL.md` and `agents/cyrus-tdd-engineer.md`, the Cursor-hook paragraphs in `cyrus-tdd-engineer/SKILL.md`, the metric mentions in `_shared/agent-turn-cap-warning.md`, and the failure-handling lead-in in `code-auditor/SKILL.md`. Core rendering is unchanged (HTML comments).
- Makefile targets `export-skills` / `check-export` (`TARGET=…`, `EXPORT_ARGS=…`); `scripts/templates/*.sh` added to `LINT_FILES`.
- `tests/export-skills.bats` — 45 tests (21 in the initial cut, extended in the review follow-ups): CLI surface, render shape, metadata, idempotency and `--check` drift (including the missing-dir case), self-containment via `check-portable-refs.sh`, byte-identity of shipped assets, agent frontmatter preservation, inserted sections, README sentinel behaviour, and `install-agent.sh` semantics.
- README — "Publishing to a team skills repo" section.

### Notes

- The `metrics-emit` library skill is deliberately **not** exported: its only consumer (`/agent-stats`) is not part of the bundle, so emission instructions are stripped rather than guarded.

### Fixed (review follow-up)

- **`check-portable-refs.sh` no longer passes vacuously.** An empty resolved skill list is an error, not "clean (0 skills)"; a non-bundle `/skill` token is excused only when that exact token or its namespace wildcard (`/mc-*`, `/create-*`, …) literally appears in the file's optional-skills paragraph. Forbidden list gains the unqualified "Follow CLAUDE.md error handling defaults" phrase and `ob-[0-9]` obligation ids.
- **`export-skills.sh`:** an unterminated `CORE-ONLY` block aborts the render instead of truncating the file; `--check` also detects executable-bit drift on shipped scripts; the two-line "Follow CLAUDE.md error handling / defaults." wrap in the reviewer agents is rewritten robustly; `managed via dotfiles` is anchored so `dotfiles-core` survives; `EXPORT_SKILLS_CORE_DIR` lets tests render from a scratch copy.
- **Rendered bundle:** every `agent.md` is told to end completed runs with `<<task-complete>>` (the instruction previously lived only in the maintainer's global AGENTS.md); `review-heuristics.md` ships with every skill that cites it (cyrus, scout, ranger, code-auditor); `SKILL_DIR` resolution is spelled out; the fallback brief restates `disallowedTools` and the agent notes tell the agent to self-enforce them; per-skill *Requires* lists replace the all-nine sibling boilerplate; Optimus's memory step is qualified as registered-mode only; the shipped `auditor-composite.json` `$comment` cites `workflows/code-auditor-score.js`.
- **Canonical docs:** `agent-turn-cap-warning.md` and `cyrus-tdd-engineer/SKILL.md` now say Cyrus `maxTurns` is 300 (was 100); forge's private obligation id is `CORE-ONLY`.
- **`install-agent.sh`:** `name:` is sanitized (`^[A-Za-z0-9][A-Za-z0-9_-]*$`, whitespace/quotes stripped); `--project` resolves the git root instead of `$PWD`.
- Re-review follow-up: `Requires` lists name only skills a SKILL.md actually invokes (reviewers → `cyrus-tdd-engineer`; `grill-me` → `to-prd`; `forge` drops the transitive `cyrus-tdd-engineer`); the missing-sibling rule says earlier steps still run; the agent-notes memory bullet renders only for agents declaring `memory:`; launch text qualifies tool restrictions and memory as conditional.
- Tests assert diagnostic messages, not just exit codes, on every error path (`--check` drift kinds, usage errors, unterminated marker, clean-run positive control).
- Portability: no `sed -i` in `export-skills.sh` (BSD/GNU flag syntax differs; CI runs on Linux).
- `tests/export-skills.bats`: 45 tests, with a real-tree snapshot guard (`setup_file`/`teardown_file`) and coverage for every path above.

## v1.18.1 — 2026-09-09 (pipeline_complete emit contract: first_pass/classification)

### Fixed

- **Emitter drift produced a false 50% first-pass rate in `/agent-stats`.** `pipeline_complete` events from the Cyrus agent omitted `first_pass` and `classification`, and the aggregator counted a missing `first_pass` as a miss. Both sides fixed:
  - `.claude/agents/cyrus-tdd-engineer.md` — `first_pass` (derived `tests_passed && ci_fix_attempts == 0`) and `classification` (explicit `null` on direct invocations) are now required emit fields.
  - `.claude/skills/optimus-planner/SKILL.md` — direct-invocation emit includes `classification: null`.
  - `.claude/skills/ticket-pickup/SKILL.md` — `first_pass` wording aligned to the canonical rule, retry-awareness kept as the better-information case.
  - `.claude/skills/metrics-emit/SKILL.md` — documents both fields as required on `pipeline_complete`, with the derivation rule and the legacy-only consumer fallback.
  - `scripts/agent-stats.sh` — `def fp:` jq predicate derives `first_pass` for legacy events missing the field (explicit `first_pass: false` respected; explicit `null` treated as absent, documented at the decision site), applied to totals and both breakdowns.

### Added

- `scripts/agent-stats.sh` — health flag for contradictory emits (`first_pass: true` with `tests_passed: false`), fail-closed per the numeric-gate convention.
- `tests/agent-stats.bats` — four new tests: derivation from `tests_passed`/`ci_fix_attempts` (including the `By agent:` breakdown line), explicit-`false` no-override, and contradiction-flag positive/negative cases.

## v1.18.0 — 2026-09-02 (peer-toned, block-anchored reviewer comments)

### Changed

- **Reviewer comment defaults flipped** (Scout and Ranger). Behavior changes visible on every review:
  - **Tone: peer is now the default voice** — short, question-led, no restated context, no A/B prescription. Explanatory survives as the opt-in for authors with fewer than 10 contributions; ambiguous or unavailable author signal resolves to peer instead of deferring to the user. Minimal (bot authors) unchanged.
  - **Density budget** — a default comment body is at most two sentences, with prohibitions on restated context, A/B prescription menus, and positives padding. Blocking findings whose mechanism needs more room may exceed the ceiling (actionable beats terse).
  - **Anchoring: comments anchor to the affected block, not a single line** — the contiguous changed-line run plus its smallest enclosing syntactic construct, clamped to the `@@` hunk. Ranges crossing a hunk edge are truncated to the edge; single-line becomes the fallback shape. The four hard anchor constraints and the 422-fails-whole-review warning are kept verbatim.
- `.claude/agents/ranger-reviewer.md` / `.claude/agents/scout-reviewer.md` — posting sections updated to block-range anchoring with a pointer to the SKILL.md § ANCHOR-CONSTRAINTS contract; `.claude/skills/code-auditor/SKILL.md` descriptive prose updated to the new defaults (sentinel pointers unchanged).

### Added

- `.claude/_shared/reviewer-blocks/` — canonical home for the four reviewer contract blocks (`tone-calibration`, `anchor-constraints`, `findings-critique`, `verify-then-draft`) that were previously hand-synced byte-identical copies in both reviewer SKILL.md files. Spliced by the new `scripts/reviewer-blocks-gen.sh` (modeled on `role-guard-gen.sh`, multi-directive-per-file), enforced by drift tests per the existing generator convention — no hook call.
- `tests/reviewer-shared-blocks.bats` — fragment existence, generator idempotence/drift, cross-reviewer parity, fragment fidelity, directive presence.
- `tests/reviewer-tone-anchor-defaults.bats` — semantic guards for the peer default, density budget, affected-block anchoring, clamp rule, and the hard-constraint/422-warning regression guard.

## v1.17.0 — 2026-08-25 (multi-repo ticket decomposition)

### Added

- `.claude/skills/ticket-pickup/scripts/repo-registry.sh` — sole name→checkout oracle for the `## Repo registry` section in `~/.claude/overlay-context.md` (user-maintained overlay data; core never writes it). `list` and `resolve <name>` subcommands with resolution-time validation and distinct exit codes (not found / stale entry / no registry / malformed entry). Registry content is data, never executed. Covered by `tests/repo-registry.bats`.
- `multi_repo_split` metrics event — `.claude/evals/schemas/multi-repo-split-event.schema.json`, catalog entry in the metrics-emit skill, `event_type` enum addition in `metrics-event.schema.json`, and `tests/multi-repo-split-event.bats`. Emitted on both the decomposition-gate and notice paths so false positives are measurable. Consumed for real: `scripts/agent-stats.sh` gains a "Multi-Repo Splits" output section (gate/notice counts, notice-vs-gate false-positive ratio, gate-choice distribution; covered in `tests/agent-stats.bats`), and the swarm-retro quantitative step reads the same signal. `final_order` semantics (cancel/only/single emit the proposed order; differs only on reorder) and the gate-menu-to-enum mapping are pinned identically in the schema, the catalog, and the emit site.
- `tests/merge-order-format.bats` — parses the canonical Merge order example straight out of the pr-create-from-commits SKILL.md, keeping the documented sentinel block and entry-line grammar a tested contract.

### Changed

- `.claude/skills/ticket-pickup/SKILL.md` — three additions: Step 2.4 resolves a cold `repo:<name>` label to a checkout via the registry helper; Step 3 enrichment becomes registry-scoped, tagging each code reference with the repo it actually resolves in; Step 3.5 detects multi-repo scope from that resolution evidence, gates decomposition into per-repo Jira sub-tasks (notice-only when no registry exists), and hands confirmed splits to the unchanged swarm path.
- `.claude/skills/ticket-swarm/SKILL.md` — branch setup resolves `repo:<name>` labels to absolute checkout paths via the registry helper (blocked-ticket convention on any lookup failure); the three dispatch lists and the dry-run report gain a `Repo root:` line. When a resolved repo root differs from the cwd, branch creation uses plain `git -C` commands — the cwd-bound `newbranch` overlay alias is reserved for unlabeled tickets (same guard added to ticket-pickup Step 5.5).
- `.claude/skills/create-jira-ticket/SKILL.md` — new automation-only "Batch mode: repo-split sub-tasks": sequential creation with `repo:<name>` labels, pairwise `blocks` links added only after all creations succeed, Task+`Relates` fallback for projects without a Sub-task type, and clean-stop on any failure (never reports a partial batch as success). Tool list gains `createIssueLink`, `getIssueLinkTypes`, `getJiraProjectIssueTypesMetadata`.
- `.claude/skills/pr-create-from-commits/SKILL.md` — sentinel-delimited, machine-parseable "Merge order" PR-body section for repo-split sub-task PRs (informational only), plus a best-effort plain-language merge-order comment on the parent ticket after PR creation.
- `.claude/skills/overlay-init/SKILL.md` — the add-context route documents the canonical `## Repo registry` entry format as a known section.
- `scripts/consult-vocabulary.txt` — new `## Repo registry` entry.
- `README.md` — skill-table rows updated for create-jira-ticket, pr-create-from-commits, ticket-pickup, and ticket-swarm.

## v1.16.0 — 2026-08-13 (ADK workflow conversion + eval gates)

> Retroactive entry: this release was tagged at the PR #25 merge without a
> changelog entry; recorded 2026-08-25 when the gap was found during the
> v1.17.0 release.

### Added

- Typed handoff schemas for the agent pipeline (`aristotle-to-optimus.json`, `optimus-to-cyrus.json`, `auditor-composite.json`, `swarm-context.json`) with schema-contract tests, plus real-object validation in `tests/workflows`.
- Classifier answer key + conformance runner under `.claude/evals/`, with a ratcheting CI gate and eval-accuracy gating for swarm-retro memory promotion.
- Saved workflows: code-auditor scoring (`code-auditor-score`) and team-lead wave execution (`team-lead-waves`); staged-chain workflow conversion.

### Fixed

- Stats health gate fails closed on non-numeric input; metrics emit valid JSON on the bash 3.2 jq-absent path; install links workflow schemas and checks them in core-check; `parallel()` documented as taking thunk arrays; `<<task-complete>>` sentinel scoped to prose-orchestrated calls.

## v1.15.2 — 2026-07-29 (shape CI + mirror history scrub)

### Added

- `scripts/check-leakage-shapes.sh` — secret-free structural leakage scan for public CI and fork PRs: flags in-tree `leakage-tokens.txt`, `dotfiles-guard/` material, and corporate email shapes in `.claude/` publication surfaces without embedding company-specific token values.
- `tests/leakage-shapes.bats` — coverage for the shape scan.
- `make check-leakage-shapes` — Makefile target wired into `.github/workflows/lint.yml` as an always-on CI step.

### Changed

- `scripts/scrub-mirror-history.sh` — gains a `push` subcommand for force-pushing scrubbed bare mirrors; audit output lists release tags to re-apply.
- `PROTOCOL.md` — documents the shape scan as the fork-PR coverage layer alongside the structurally skipped company-token scan.

### Ops

- Public mirror history rewritten to remove `scripts/leakage-tokens.txt` from all commits (`git filter-repo` + force-push). Fork owners may need to rebase.

## v1.15.1 — 2026-07-29 (publication-gate follow-ups)

### Added

- `scripts/scrub-mirror-history.sh` — audit/scrub helper for removing `scripts/leakage-tokens.txt` from the public mirror's git history (`audit` and `scrub` subcommands; scrub requires `git-filter-repo` and a manual force-push).

### Changed

- `scripts/lib-core-symlinks.sh` — `_install_git_hook` resolves the real gitdir via `git rev-parse --git-dir`, so pre-commit and pre-push hooks install in submodule worktrees (`.git` is a file) as well as standalone clones.
- `tests/test_helper.bash` — pins synthetic `LEAKAGE_*` guard fixtures in every test so migration/content leakage checks run on CI instead of silently skipping.
- `tests/install-precommit-hook.bats` — fixtures use real git repos; submodule gitdir install is tested explicitly.

### Fixed

- `scripts/role-guard-gen.sh` — empty `_tmpfiles` array no longer triggers an unbound-variable error on exit when no fragments were written.

## v1.15.0 — 2026-07-29 (externalized leakage gate)

### Added

- `scripts/pre-push.sh` — a publication-set leakage gate, installed as the `pre-push` git hook by `install.sh` via `_install_git_hook`. Where the pre-commit check scans only the working tree (early warning), the pre-push gate scans every outgoing commit in the pushed range — each commit's **full tree** plus its **metadata** (author/committer identity and commit message) — so a token buried in an intermediate commit, or in a commit message, can never reach a remote even if a later commit removed it from the tree.
- External token-data contract — the token list no longer lives in this repo. It is materialized outside every working tree at `${XDG_CONFIG_HOME:-~/.config}/dotfiles-guard/leakage-tokens.txt` by an overlay installer, alongside a `company-context` marker file. Semantics are fail-closed: marker present but list missing (or empty) is a hard configuration error, never a silent pass; marker absent means the machine carries no company context and the checks skip cleanly.
- `tests/pre-push-hook.bats` — coverage for the publication-set gate, exercising the mechanism entirely on synthetic tokens.
- `.github/workflows/lint.yml` — the company-token scan is now a **structurally skipped** step on runners without the guard data: a visible "skipped" status in the run, never a silent green. Lint, the consult-grammar check, and the synthetic-token test suite still run everywhere.

### Changed

- `scripts/check-no-leakage.sh` — reads the external token list instead of an in-tree file; output is content-free (file/line references only — matched content is withheld by design, because the checker's own output is a publication channel); gains a `--commits` mode that reads commit SHAs from stdin and scans each commit's tree and metadata (used by the pre-push gate); fails closed with a distinct exit code when the company-context marker exists but the list is missing or has no effective tokens.
- `tests/leakage-check.bats` — rewritten on synthetic tokens pointed at fixture list/marker files, so the detection mechanism is fully testable in public CI without the real token data.

### Removed

- The in-tree token list (`scripts/leakage-tokens.txt`) and the per-file scan exclusions it required — the list's own presence in the tree was the leak the check existed to prevent.

## v1.14.2 — 2026-07-16

### Added

- `.claude/agents/optimus-planner.md` — reuse-vs-duplication planning discipline. A new **Pre-Plan Investigation Step D (Reuse audit)** greps the codebase for an existing helper/util/service that covers each capability *before* planning to write a new one, and a new plan-template **Section 4a (Reuse & Consolidation)** carries the findings forward: existing code to call, extend-don't-fork targets, justified new shared code (with a mandated shared location), and pre-existing duplication to flag as follow-up. 4a is in the always-include set and stays even in short-form plans (a one-file change is where a stray duplicate slips in). Optimus can flag a too-narrow helper for Cyrus to **generalize or modularize**, with **KISS as the explicit ceiling** — the minimal change that closes the actual gap, never a framework for hypothetical callers.
- `.claude/agents/cyrus-tdd-engineer.md` — a new **"Search Before You Build — Reuse Over Duplication"** rule (check plan §4a → grep the repo → reuse / extend / justified-write-new) with a one-sentence justification requirement mirroring the existing mocking-justification pattern, a **KISS-capped** extend/generalize branch, a **Self-Verification checklist** line, and a **parallel-mode note** covering the gap where two same-wave Cyrus agents can't see each other's in-flight helpers (new shared code goes to §4a's designated location; suspected collisions surface for between-wave dedup). Root cause addressed: each agent sees only its own task, so nobody was responsible for asking "does this already exist?" — the fix lives in Optimus (plan for reuse) and Cyrus (check before building), mirroring the existing `frontend-design` annotate-then-act pattern. Aristotle intentionally untouched (strategic role, never names file paths).

### Changed

- `.claude/agents/optimus-planner.md`, `.claude/skills/optimus-planner/SKILL.md` — Plan Critique check #4 renamed **"Boundary fit & reuse"** (folded reuse into the existing check rather than adding a sixth, keeping the "five staff-grade checks" count in sync across the agent file and the skill's verbatim critique block); an unjustified new utility is now an explicit ❌. An unjustified new helper is scored as the duplicate it will become at implementation time.

## v1.14.1 — 2026-07-15

### Added

- `_shared/agents-md/20-task-orchestration.md` § "Code Comments" — a new rule forbidding **agent-pipeline vocabulary** from leaking into shipped product source. Comments, code identifiers, log strings, and JSX in shipped files must not reference the internal planning pipeline: agent names (Aristotle/Optimus/Cyrus/Scout/Ranger), plan step numbers (`Step 3`, `Step 4a`), assumption/risk IDs (`A9`, `A10`, `risk R6`), or wave/handoff/gate framing. A bare ticket key (`// PROJ-1234:`) stays fine. These tokens are build-time scaffolding, not facts about the code, and mean nothing to a future reader who never saw the plan — the same class of problem as narrative comments, one step more opaque. Regenerated into `.claude/AGENTS.md.generated` in lockstep. (#20)
- `.claude/agents/cyrus-tdd-engineer.md`, `.claude/agents/optimus-planner.md` — role-tuned copies of the rule placed where leaks originate: Cyrus strips/rewrites leaked tokens from Optimus snippets before committing (snippets are copied into real files verbatim), and Optimus keeps `Step N` / risk-ID / agent-name framing in plan prose and structure, never inside a code block. (#20)
- `.claude/agents/scout-reviewer.md`, `.claude/agents/ranger-reviewer.md` — a new review flag alongside "Narrative comments" so both reviewers catch the leak at PR time, with the same severity model (Suggestion by default, escalate to Important if pervasive). `code-auditor` intentionally left untouched — it's a pure router that produces no findings and inherits the rule by delegating to Scout/Ranger. (#20)

### Fixed

- `.claude/skills/babysit-prs/scripts/babysit-state.sh` — `_mtime` now uses a platform-correct `stat` directive so the babysit state store reads modification times correctly across BSD/macOS and GNU/Linux `stat` flavors, rather than silently failing on one. (#19)

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
