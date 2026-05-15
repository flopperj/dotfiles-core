---
protocol-version: v2
---
# Consult-Instruction Protocol

This document is the single source of truth for the **consult-instruction protocol** —
the versioned contract between `dotfiles-core` and its overlays for referencing
overlay-specific runtime context from core skill files.

## Grammar (today)

A well-formed consult-instruction line matches the following pattern:

```
consult `## <section-name>` in `~/.claude/overlay-context.md`
```

Expressed as a regex for tooling use:

```
consult `## [^`]+` in `~/.claude/overlay-context.md`
```

The path `~/.claude/overlay-context.md` is fixed by design. The indirection
point is single-purpose: every overlay exposes its runtime context at exactly
this path. The section name (`## <section-name>`) is the only variable part.

Full example from a skill file:

```markdown
For company-specific Jira fallback, consult `## Jira fallback` in `~/.claude/overlay-context.md`. If that file is absent, proceed with the primary tool only.
```

## Bilateral contract

The overlay's `scripts/lint-consult-blocks.sh` enforces five properties on every
consult-instruction that appears in any core SKILL.md file:

1. **Presence** — every section named in a consult-instruction must exist as a
   heading in `_shared/overlay-context.md`.
2. **Anti-prose** — references to `overlay-context.md` must use the backticked
   `## Section` form, not free-prose mentions.
3. **Heading-anchored match** — the section name in the consult-instruction must
   match an actual `## Heading` line, not just inline text.
4. **Orphan detection** — a heading in `overlay-context.md` that is not referenced
   by any SKILL.md is flagged as an orphan.
5. **Exact-string heading match** — the match is performed via `grep -Fxq`,
   meaning substring matches and partial-word matches do not pass.

Cite: `scripts/lint-consult-blocks.sh` in the overlay repo.

The core side enforces the complementary property (Step 10, Cohort 2): every
section name referenced in a core SKILL.md must appear in `scripts/consult-vocabulary.txt`.

## Controlled vocabulary

Section names must describe the **runtime decision** the consulting skill is
making, not the **tool or server** that provides the data.

Rule: `## <Capability>` (good) vs `## <Provider> MCP server` (bad).

| Current name | Post-Cohort-2 name | Status | Notes |
|---|---|---|---|
| `## Jira fallback (DAST-Orch MCP)` | `## Jira fallback` | renamed in Cohort 2 | Provider suffix dropped; capability retained |
| `## Jenkins MCP clone URL` | `## Jenkins MCP clone URL` | no change | Already capability-named (the capability is "where to clone Jenkins MCP") |

The machine-readable canonical list lives at `scripts/consult-vocabulary.txt`.

**Audit 2026-05-14:** Confirmed these are the only two consult-instruction sections in core. Both capability-named. Command used: `grep -hoE "consult \`## [^\`]+\`" .claude/skills/*/SKILL.md | sort -u`.

**Capability-naming rule:** A section name is capability-named when it describes
what the consulting skill *decides* or *falls back to*, not which MCP server or
provider supplies the data. Examples:
- `## Jira fallback` — correct (capability)
- `## Jenkins MCP clone URL` — correct (the capability is "where to clone Jenkins MCP"; the URL is the decision output)
- `## DAST-Orch MCP server` — incorrect (provider name, not capability)

**Shared iteration helper:** `scripts/lib-core-symlinks.sh` and `scripts/core-check.sh`
both iterate over `.claude/skills/*/` subdirectories. Decision (Step 3): a shared
helper `_iter_core_skill_dirs` was extracted into `scripts/_lib.sh` to eliminate
the duplicated glob. Both call sites use the helper. Decision recorded here so
future contributors do not re-inline the loop.

## Enforcement evolution

### Today (denylist)

`make check-leakage` runs `scripts/check-no-leakage.sh`, which scans every file
in the repo against a list of company-specific tokens in `scripts/leakage-tokens.txt`.
This catches accidental leakage of overlay-specific identifiers into core.

Weakness: the denylist approach is structurally fragile (see §Why denylist is
structurally weak). For consult-instructions specifically, the section name
`## Jira fallback (DAST-Orch MCP)` contains `DAST-Orch`, a denylist token, which
causes false positives.

### Cohort 1 (denylist + allowlist exemption — SUPERSEDED)

A PROVISIONAL allowlist exemption was added to `check-no-leakage.sh` (Step 4):
any line matching the consult-instruction grammar (`consult \`## …\`` in
`~/.claude/overlay-context.md`) was excluded from token scanning.

This was a band-aid while Cohort 2 built positive enforcement. The allowlist
and the `DAST-Orch` token have both been removed in Cohort 2.

### Cohort 2 (positive grammar — canonical)

`scripts/check-consult-grammar.sh` (Step 10) replaces negative denylist enforcement
with positive grammar enforcement for consult-instructions:

- Every consult-instruction in every core SKILL.md must reference a section name
  listed in `scripts/consult-vocabulary.txt`.
- Any line with the word `consult` + `overlay-context.md` that is not in the
  valid backtick form is a grammar violation.
- Empty vocabulary is a fatal configuration error (exit code 2).
- Wired into `make all` and `scripts/pre-commit.sh`.

**D3 decision (Cohort 2):** `leakage-tokens.txt` is kept as belt-and-suspenders
for free-prose leakage of other company-specific tokens (`mailchimp`, `intuit`,
`turbotax`, `quickbooks`, `cg-tax`, `build.intuit.com`, `@intuit.com`,
`@mailchimp.com`). `DAST-Orch` has been removed from the denylist; grammar
check is its primary enforcement. The PROVISIONAL allowlist sed-pipe is removed.

## Why denylist is structurally weak

**Adversarial token order.** A denylist token like `DAST-Orch` is matched regardless
of context. A legitimate consult-instruction (`consult \`## Jira fallback (DAST-Orch MCP)\``)
triggers the same match as an accidental leakage (`Use the DAST-Orch MCP for Jira`).
The denylist cannot tell these apart without the allowlist band-aid.

**Partial-token near-miss.** A token like `intuit` matches `intuitive`, `inuit`, or
any word containing the substring. Denylist authors must enumerate every variant or
accept false-positive noise. Neither is maintainable at scale.

**Maintenance via grepping the world.** Adding a new overlay-specific identifier
requires updating `leakage-tokens.txt`, re-running the scanner, and verifying that
no existing legitimate mention is newly flagged. Each update is a manual audit.
Positive grammar requires only adding one line to `consult-vocabulary.txt`.

## Versioning

Protocol versions track the consult-instruction contract between core and overlays:

| Version | Description | Shipped with |
|---|---|---|
| v1 | Today's state: implicit grammar, denylist enforcement, no vocabulary file | Initial `PROTOCOL.md` (Cohort 1) |
| v2 | Explicit grammar, positive enforcement via `check-consult-grammar.sh`, capability-named vocabulary | Cohort 2 |

The `protocol-version` frontmatter field in this file is machine-readable. An overlay
lint script that encounters a version it does not understand should fail closed rather
than silently pass. Version increments are non-breaking for overlays that do not read
the grammar check output — bumping the submodule SHA is the opt-in mechanism.
