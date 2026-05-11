# Evidence Patterns and Review Heuristics

Use these heuristics to avoid shallow reviews.

## High-value evidence to inspect

- Bootstrap entrypoints such as install scripts, setup commands, make targets, task runners, or shell wrappers.
- README, onboarding docs, architecture notes, and machine-specific instructions.
- Files that define global defaults, local overrides, and OS/shell detection.
- CI workflows, validation commands, tests, linters, or smoke checks.
- Secret-handling patterns, ignored files, templates, and examples.
- Commit diffs that add new dependencies, new environment branches, or new side effects.

## Questions to answer

### Architecture
- Where does the repo define the contract for “supported environments”?
- Which modules are shared versus environment-specific?
- Does the composition model make change safer or more dangerous?

### Portability
- How many assumptions are implicit about OS, shell, package manager, path layout, terminal, fonts, or installed tools?
- Are unsupported environments handled explicitly or left to fail mysteriously?
- Can a new machine be onboarded without forking logic everywhere?

### Safety
- Can bootstrap steps be rerun safely?
- Are destructive actions preceded by checks, backups, prompts, or dry-runs?
- Is failure visible, or does the setup silently continue in a partial state?

### Maintainability
- Is naming predictable?
- Is load order explicit?
- Do docs and file layout help future contributors preserve the design?

## Common strong patterns

- Small bootstrap surface area with delegated modules.
- Explicit layering such as base -> platform -> machine-local overrides.
- Declarative configuration when practical, imperative logic only where needed.
- Documented constraints like “macOS and Linux supported; fish unsupported by design.”
- Validation commands that match the real failure modes.

## Common weak patterns

- Giant all-in-one shell files with mixed concerns.
- Duplicated OS logic in many files.
- One-off aliases, tool installs, or exports scattered with no ownership model.
- Hidden dependencies on personally installed tools or private directories.
- New contributions that only work because the original author already had state on disk.

## How to talk about trade-offs

Use language like:
- "This is a reasonable local optimization, but it weakens portability because..."
- "This looks more sophisticated, but it reduces architectural clarity because..."
- "The repo does not need more abstraction here; it needs a clearer support boundary."
- "This contribution is useful, but it should be isolated behind a platform or tool-specific module."

## Self-review bias

When the reviewer is the author of the code, the highest risk is over-rewarding familiar architecture and under-flagging the safety gaps the author has lived with daily. Counteract it deliberately:

- **Bias safety, validation, and portability scores down by half a point** when the rationale starts with "I know this works." Familiarity is not evidence.
- **Treat warm features as suspect.** A pattern you find elegant is the most likely place to under-flag systemic risk.
- **Look for changes you would block in someone else's PR.** If you'd ask a teammate to add a dry-run, add backup timestamps, or remove a `curl | bash`, you should ask yourself the same.
- **Surface bias explicitly.** If the report omits any concern about an axis you scored ≥4, write one sentence describing what would have to break for that axis to drop a point. Knowing the failure mode is the test that the score is real.

The bias is structural, not situational — it applies on every self-review, not just the rough ones.

The checks above catch **under-investment** (gaps the author can see if prompted). To also catch **misdirected investment** (gaps invisible because the misdirection feels like the work), apply the Hostile-Read Anchors prompts from `rubric.md §8` for every axis scored ≥ 4, and run the Contract Enforcement Audit from `rubric.md §9` to map every documented contract to its enforcer.

## Confidence guidance

Lower confidence when the review lacks:
- bootstrap or install path
- documentation of supported environments
- evidence of validation
- enough context around a patch to understand the surrounding design

When confidence is low, state exactly what you inspected and what remains unknown.
