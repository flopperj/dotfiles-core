# Changelog

> **How to update:** The pre-commit hook (`scripts/pre-commit.sh`) is auto-installed by `install.sh`. It runs a fast leakage check (`scripts/check-no-leakage.sh`) and re-renders the generated `CLAUDE.md.generated` and `AGENTS.md.generated` files on every commit. Full test/lint suite (`make all`) runs in CI. If you bypass the hook or work in a context where hooks cannot run, keep this file current manually. Each release heading links to the diff on the public mirror.

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
