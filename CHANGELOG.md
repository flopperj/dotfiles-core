# Changelog

> **How to update:** The pre-commit hook (`scripts/pre-commit.sh`) is auto-installed by `install.sh`. It runs a fast leakage check (`scripts/check-no-leakage.sh`) and re-renders the generated `CLAUDE.md.generated` and `AGENTS.md.generated` files on every commit. Full test/lint suite (`make all`) runs in CI. If you bypass the hook or work in a context where hooks cannot run, keep this file current manually. Each release heading links to the diff on the public mirror.

## Unreleased — v1.9.0 (overlay tooling)

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
