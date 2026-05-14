---
name: self-evaluate
description: self-evaluate this dotfiles repository (overlay or dotfiles-core) for health and engineering quality — structure, bootstrap, portability, maintainability, safety, docs, tests, and CI. use only in a dotfiles-family workspace when the user wants an honest self-assessment, a sanity check that the setup is in solid shape, pre-flight before sharing changes, or senior-plus bar feedback on their own dotfiles work.
user-invocable: true
---

# Self-evaluate (dotfiles)

## Scope — overlay or core, never anything else

This skill runs in **two modes**, auto-detected at step 0:

- **Overlay mode** — workspace is the company overlay repo (contains `.claude/dotfiles-core/` as a submodule).
- **Core mode** — workspace is the standalone `dotfiles-core` repo (contains `scripts/lib-core-symlinks.sh` and `scripts/lib-core-seeds.sh` at root, no submodule).

**Install behavior:**

- **Overlay install** (`overlay/install.sh`): the overlay's `scripts/lib-symlinks.sh` skip-list excludes this skill from `~/.claude/skills/` and `~/.cursor/skills/` and actively removes any pre-existing global symlink. Overlay users invoke the skill exclusively in-tree.
- **Standalone-core install** (`dotfiles-core/install.sh`): core's `scripts/lib-core-symlinks.sh` auto-discovers all skill directories via a glob with no skip-list, so `~/.claude/skills/self-evaluate/` is created and points at the in-tree core copy. This is intentional — a standalone-core session must be able to reach the skill at all. When an overlay install runs on top later, its cleanup removes the global symlink and restores the repo-local-only invariant.

The skill's step-0 pre-condition refuses to run on any workspace lacking `install.sh` at root, and rule 4 of the detection block refuses on any workspace where neither marker set matches. Together they gate global discoverability so the skill never produces false invocations on unrelated projects, even those that happen to have their own `install.sh`.

**When to use:** Open the **overlay** or **dotfiles-core** repo as the workspace (e.g. PR review, contribution assessment). Do **not** invoke this skill for other workspaces or external repos — suggest a generic review approach or the appropriate project skill instead.

**Purpose:** Self-evaluate to ensure the dotfiles setup is in **solid shape** — evidence-backed judgment on whether the system is maintainable, portable, and safe to rely on over time.

Treat the work as **your own** dotfiles to stress-test: optimize for long-term operability, portability, maintainability, and honest gaps — not for impressing an external reviewer.

**Mode-specific behavior:** Steps 3 (submodule health) and 4 (overlay-context wiring) only apply in overlay mode. In core mode they are explicitly **skipped** and recorded as "not applicable in core mode" in the Contract Enforcement Audit, so a future reader can see they were considered, not forgotten. All other steps (architecture, portability, safety, tests, docs, validation) apply identically in both modes; the rubric and weighted total are unchanged.

## Review modes

Choose the narrowest mode that fits the request.

1. **Repo review**
   Use when assessing the full dotfiles repo. Inspect architecture, layout, install/bootstrap flow, docs, tests, validation, CI, risk controls, and portability.
2. **Contribution review**
   Use when assessing a patch, diff, PR description, commit series, or a small set of changed files. Judge whether the change improves or harms the overall system.
3. **Gap-to-next-level review**
   Use when the user wants feedback framed for senior, senior staff, staff, principal, or similar levels. Describe what is solid now, what is missing, and what would materially change the signal.

## Operating stance

- Default to a **senior-plus bar**. Avoid nitpicks unless they point to a broader systems issue.
- Prefer **evidence over taste**. Separate objective risk from personal preference.
- **Portability and operational safety carry double weight in the rubric.** Verdict overrides in `references/rubric.md` cap the result when either axis scores low — for dotfiles those two axes are load-bearing.
- **Self-review bias check.** If you wrote this code, your default is to over-reward familiar architecture and under-flag the safety gaps you live with daily. Bias your scoring one half-point harder on safety, validation, and portability than feels comfortable, and explain in the rationale why a familiar pattern still earned its score.
- Be tech-stack agnostic. Do not assume bash, zsh, nix, chezmoi, stow, macOS, or Linux unless the repo shows it.
- Reward deliberate trade-offs. A simpler design with explicit constraints can score higher than a clever but fragile one.
- Penalize hidden coupling, unowned complexity, irreversible machine mutations, weak failure modes, and documentation that does not help another engineer succeed.

## 0. Detect mode (deterministic — do not skip)

**Pre-condition:** `install.sh` must exist at the workspace root. If not, this is not a dotfiles workspace — refuse with a clear message and suggest `/code-auditor` or a generic review instead.

The skill picks **core mode** or **overlay mode** before any other step. Precedence is fixed; do not improvise.

1. **Explicit user flag wins.**
   - `--core` → mode is **core**. The core marker files must be reachable at either `scripts/lib-core-symlinks.sh` (workspace root — standalone-core session) **or** `.claude/dotfiles-core/scripts/lib-core-symlinks.sh` (submodule path — overlay session, cross-tree audit). If neither is reachable, refuse with a message naming both candidate paths.
   - `--overlay` → mode is **overlay**. The workspace must contain `.claude/dotfiles-core/`; if not, refuse — no overlay is reachable from a standalone-core checkout using `--overlay`. Explicit flags override every other signal below.

2. **Overlay markers.** If `.claude/dotfiles-core/` exists (submodule populated) OR `.claude/_shared/overlay-context.md` exists, the workspace is the overlay → mode is **overlay**.

3. **Core markers.** If `scripts/lib-core-symlinks.sh` AND `scripts/lib-core-seeds.sh` both exist at the workspace root, the workspace is standalone core → mode is **core**.

4. **No match → refuse.** If neither marker set matches and no flag was passed, refuse politely and state which markers were checked. Suggest a generic review approach (Scout, Ranger, or `/code-auditor`) instead.

**Conflict handling:**
- **Flag wins over cwd.** `--core` from an overlay session is the cross-tree audit path: the skill scores the dotfiles-core submodule at `.claude/dotfiles-core/` rather than the overlay root. In this case, score the submodule's **contents** — not the overlay's wiring to it. Steps 3 and 4 stay skipped even though the workspace context could supply them; that data belongs in a separate overlay-mode audit.
- `--overlay` from a standalone-core session: refuse — no overlay is reachable from a core-only checkout.
- Both overlay AND core markers at the same root: impossible in practice; if encountered, rule 2 wins (overlay) by precedence.

**Report the detected mode explicitly** in the report header — for example: `**Mode:** Overlay (auto-detected)`, `**Mode:** Core (auto-detected)`, or `**Mode:** Core (--core flag override)`. Future readers must see which lens the skill applied.

## Review workflow

1. Identify the evidence surface.
   - Full repo: inspect top-level structure, install/bootstrap entrypoints, environment detection, package or tool managers, shell/editor/tool configs, docs, tests, and CI.
   - Contribution: inspect the changed files **and** the unchanged neighborhood around them. Score the *delta*, not the post-state — a small fix to a 3/5 area is qualitatively different from the same fix to a 5/5 area. Run `git diff <base>...HEAD --stat` to scope, then read each modified file plus its closest dependency (sourced library, called function, test that should cover it).
2. Infer the system model.
   - How is the repo meant to be installed?
   - How does it adapt across machines, shells, operating systems, or contexts?
   - Where are responsibilities separated versus entangled?
3. **Check dotfiles-core submodule health** — **overlay mode only**. Skip in core mode and record "not applicable in core mode" under Contract Enforcement Audit.
   - Submodule initialized: `git submodule status .claude/dotfiles-core` — if the line starts with `-`, the submodule is not initialized (blocker).
   - Submodule pin is committed: compare `git ls-tree HEAD .claude/dotfiles-core` SHA against the submodule HEAD. If they differ, the pointer is stale or drifted behind — flag as a portability risk.
   - Core-owned symlinks resolve through the submodule path (`readlink ~/.claude/skills/forge` contains `dotfiles-core`). If they resolve to in-tree overlay copies when the submodule is populated, the installer has a regression.
4. **Check overlay-context.md wiring** — **overlay mode only**. Skip in core mode and record "not applicable in core mode" under Contract Enforcement Audit. (In core mode, every skill that consults overlay-context.md does so against a path that is only populated by an overlay installer; verifying that wiring lives with the overlay, not core.)
   - The file provides company-specific runtime facts to universal core skills. Verify it exists, is non-empty, and is symlinked to `~/.claude/overlay-context.md` post-install.
   - For each of the affected core skills (briefing, ticket-swarm, ticket-pickup, obligations, pr-create-from-commits, doctor), verify the resolved SKILL.md references `~/.claude/overlay-context.md` in a consult-instruction. If the consult-instruction is missing, the skill will silently ignore company-specific behavior. Flag as a maintainability gap.
5. Score the work using the rubric in `references/rubric.md`.
   - **For every axis you score ≥ 4, answer the Hostile-Read Anchors prompts (rubric §8).** Anchor each answer to a specific file, line, or code path. Honest answers that surface a real gap lower the score by 0.5–1 point.
   - **Run the Contract Enforcement Audit (rubric §9).** Inventory the documented contracts (README, SKILL.md files, CHANGELOG, recent commits), map each to its enforcer, and score TIGHT/LEAKY/DECORATIVE. A LEAKY or DECORATIVE contract caps the affected axis at 4.
6. Call out risks using the heuristics in `references/evidence-patterns.md`.
7. Produce a decision-oriented output using the report structure below.
8. When the repo or patch is incomplete, say what is missing and lower confidence instead of pretending certainty.

## What strong work looks like

Favor signals like these:

- Clear layering between bootstrap, machine detection, shared defaults, machine-local overrides, and optional features.
- Idempotent setup flows that can be rerun safely.
- Explicit support boundaries for OS, shell, editor, terminal, and secrets handling.
- Minimal hidden state and minimal assumptions about the host machine.
- Good failure messages, dry-run capability, validation, or rollback-friendly design.
- Docs that help a second engineer understand intent, trade-offs, and safe extension points.
- Changes that increase leverage for future contributors instead of adding one-off tweaks.

## Red flags

Escalate findings like these:

- Bootstrapping mutates a machine without checks, prompts, backups, or idempotency.
- OS- or shell-specific logic is scattered instead of isolated.
- New tools are added without lifecycle, ownership, or portability reasoning.
- Secrets, tokens, hostnames, or personal assumptions leak into tracked config.
- Dotfile load order is implicit and fragile.
- The repo cannot explain how to test or validate changes.
- Docs say what to do but not why the design is safe or extensible.
- A contribution optimizes the author's workflow while making the system harder for future maintainers.
- **(Overlay mode only)** The dotfiles-core submodule pointer is stale or behind the committed SHA — two installations from the same overlay commit will produce different skill versions.
- **(Overlay mode only)** A core skill's SKILL.md no longer contains the consult-instruction for `~/.claude/overlay-context.md` — company-specific behavior is silently skipped without the referencing line.
- **(Overlay mode only)** A section referenced by a consult-instruction has been renamed in `_shared/overlay-context.md` without updating the instruction — the instruction points at a section that no longer exists, silently returning empty context.
- **(Core mode only)** `lib-overlays.sh`'s `concat_fragments` helper changed shape without bumping a coordinated overlay — downstream overlay installers that depend on the fragment-render contract will silently produce a different `~/.claude/CLAUDE.md`. Core is consumed as a submodule; an unannounced contract change is a stealth break for every overlay pinned to the bumped SHA.
- **(Core mode only)** A universal skill or agent was added to `.claude/skills/` or `.claude/agents/` without a corresponding update to `lib-core-symlinks.sh`'s symlink loop — the new asset ships in the submodule but never reaches `~/.claude/` in a fresh install.

## Report structure

Use this structure unless the user requested another format.

# Dotfiles self-evaluation

**Mode:** *Overlay* | *Core* — state which was auto-detected at step 0. Steps 3 and 4 only contribute findings in overlay mode; in core mode, the Contract Enforcement Audit table records them as "not applicable in core mode" rather than omitting them silently.

## Executive summary
- 2 to 5 bullets.
- State overall quality, confidence, and whether the setup currently reads as solid for senior-plus.

## Overall verdict
Choose one of the five verdicts in `references/rubric.md`. Bands and verdict-override rules are defined there:
- **below senior bar**
- **solid senior**
- **approaching staff**
- **staff-caliber**
- **principal-leaning**

State the weighted total and any active cap explicitly: e.g. *"approaching staff (32/45), capped at solid senior because operational safety = 2"*.

## Scorecard
Include a 1-5 score and short rationale for each axis. The two **bold** axes count double in the weighted total — see `references/rubric.md`.

| Category | Score (1-5) | Rationale |
|---|---:|---|
| architectural judgment |  |  |
| **portability across machines** |  |  |
| maintainability |  |  |
| **operational safety** |  |  |
| extensibility |  |  |
| documentation and contributor ergonomics |  |  |
| validation and testability |  |  |

State the weighted total under the table: `Total: N/45 (= arch + 2×port + maint + 2×safety + ext + docs + valid)`.

## Hostile-read answers
For each axis scored ≥ 4, list the answers to the rubric §8 prompts. Each answer is 1–2 sentences anchored to specific evidence. If an honest answer dropped the score, the new score is reflected in the Scorecard above and the drop is noted here.

## Contract Enforcement Audit
Produce the contract → enforcer → status table from rubric §9. Record any axis caps applied as a result (e.g., "validation capped at 4 — `check.sh:32-58` LEAKY").

## Evidence
Group observations under:
- strengths
- concerns
- unknowns that limit confidence

## Confidence
Required, not optional. State explicitly:
- **Score:** high | medium | low
- **What I reviewed:** the files / commands / signals you actually inspected.
- **What I did not review:** files or signals deliberately skipped, and why.
- **What would change my verdict:** specific evidence that would move the score up or down.

A senior-plus reviewer knows what they don't know. Surfacing the gap is part of the job.

## Senior-plus assessment
Use these subheads:
- **What already signals senior+**
- **What blocks stronger senior/staff signal**
- **What would most improve the principal signal**

## Priority recommendations
List the 3 to 7 changes with the highest leverage. For each recommendation include:
- why it matters
- expected impact
- rough implementation direction

## Contribution verdict
When reviewing a patch or PR, add:
- **merge as-is**, **merge with follow-ups**, or **rework before merge**
- a brief explanation tied to system impact

## Per-axis delta (contribution mode only)
For each axis the patch touches, state how the change shifts the score. Format:

```
- operational safety: 3 → 4. Replaced .bak overwrite with timestamped backup.
- validation:        4 → 4. New test covers the new path; no regression.
- portability:       4 → 4. No change.
```

Score the *delta*, not the post-state. A small fix to a 3/5 axis is qualitatively different from the same fix to a 5/5 axis — surface that.

## Level framing guidance
Use these interpretations when writing the assessment.

- **Senior**: reliable, maintainable, clear ownership boundaries, sensible defaults, fewer footguns.
- **Staff / senior staff**: strong system decomposition, higher leverage patterns, better extension points, explicit trade-offs, robust portability model.
- **Principal and beyond**: coherent philosophy, long-term operability, risk-managed automation, excellent documentation as a force multiplier, and decisions that scale to many future changes and environments.

Do not treat “principal” as “more complexity.” Often the strongest principal signal is reducing complexity while increasing adaptability and safety.

## Review behavior rules

- Distinguish **taste**, **local optimization**, and **systemic risk**.
- Do not over-reward novelty. Reward boring, durable design.
- Do not assume lack of tests means poor work if the repo offers another credible validation strategy; explain the trade-off.
- If the repo is intentionally personal rather than team-scaled, judge whether it is honest and well-contained rather than pretending it should be an enterprise platform.
- When evidence is thin, give a provisional assessment and say what additional files or signals would change the verdict.

## Resources

- `references/rubric.md` — scoring anchors, weighted total formula, bands, and verdict-override rules.
- `references/evidence-patterns.md` — heuristics, evidence to inspect, common strong and weak patterns.
- `references/rubric.md §8` — Hostile-Read Anchors. Required for every axis scored ≥ 4.
- `references/rubric.md §9` — Contract Enforcement Audit. Required for every review. Axis-capping is part of the scoring formula.
