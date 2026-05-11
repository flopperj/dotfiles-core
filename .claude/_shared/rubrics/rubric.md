# Senior-Plus Dotfiles Review Rubric

Score each category from 1 to 5. Two categories — **portability across machines** and **operational safety** — count double, because for dotfiles those axes are load-bearing: a small portability or safety regression damages the system more than a small documentation or extensibility regression. Total maximum is **45** (5×5 single-weight + 2×10 double-weight).

## 1. Architectural judgment

### 1
Chaotic accumulation of personal tweaks. Responsibilities are mixed together. Changes increase coupling and make future edits harder.

### 2
Some structure exists, but boundaries are weak or inconsistent. Design choices feel reactive rather than intentional.

### 3
Reasonable architecture for an individual-maintained repo. Main responsibilities are separated. Most complexity is understandable.

### 4
Strong system decomposition. Clear layering, extension points, and explicit trade-offs. Complexity is mostly earned.

### 5
Exceptional judgment. The repo feels like a durable operating model: simple where possible, abstract only where justified, and resilient to future change.

## 2. Portability across machines

### 1
Assumes a single machine or environment. Breaks easily across OSes, shells, package managers, or host capabilities.

### 2
Some portability intent, but many hidden assumptions remain. Environment-specific logic is fragile or duplicated.

### 3
Works across a few target environments with understandable constraints. Trade-offs are somewhat documented.

### 4
Strong portability model. Environment detection, overrides, and optional features are isolated and intentional.

### 5
Portability is a first-class design goal. Support boundaries are explicit, failure modes are graceful, and adding a new machine type is low drama.

## 3. Maintainability

### 1
Hard to reason about. Naming, structure, and conventions are inconsistent.

### 2
Readable in parts, but maintenance cost is rising. Too much tacit knowledge is required.

### 3
Maintainer can safely evolve it with some care. Conventions exist and are mostly followed.

### 4
Easy to maintain. Files, naming, and conventions guide future contributions. Most changes are localized.

### 5
Very maintainable. The repo teaches maintainers how to extend it correctly and prevents many classes of accidental damage.

## 4. Operational safety

### 1
Setup and updates are risky. Side effects are poorly controlled and recovery is unclear.

### 2
Some safety awareness, but failure handling, backups, prompts, or idempotency are weak.

### 3
Mostly safe. Common operations are repeatable and obvious footguns are reduced.

### 4
Strong safety model. Installation/update flows are idempotent, observable, and cautious.

### 5
Safety is deeply designed in. The system makes dangerous actions hard and safe actions easy.

## 5. Extensibility

### 1
New contributions tend to sprawl or break assumptions.

### 2
Extensions are possible but often require copying patterns without clear rationale.

### 3
New tools or machine cases can be added with moderate effort.

### 4
Well-designed extension points and contribution patterns. Most growth paths are obvious.

### 5
The repo scales elegantly as a platform for future changes without becoming framework-heavy.

## 6. Documentation and contributor ergonomics

### 1
Little or no documentation. A second engineer would struggle to use or modify the repo.

### 2
Basic setup notes exist, but intent and trade-offs are missing.

### 3
Docs cover main workflows and enough context to contribute.

### 4
Docs clearly explain setup, constraints, philosophy, and safe extension.

### 5
Documentation materially raises team leverage. It explains not just how, but why this system works and where it should not be used.

## 7. Validation and testability

### 1
No clear way to validate changes.

### 2
Validation is ad hoc and mostly manual.

### 3
There is a credible validation path, even if lightweight.

### 4
Validation is consistent and repeatable through tests, linting, dry-runs, or CI.

### 5
Validation is excellent and aligned with risk. Fast feedback protects the system without excessive process.

## 8. Hostile-Read Anchors

The bias-check in `evidence-patterns.md` catches under-investment — gaps that are visible to the author. It does not catch **misdirected investment** — gaps that are invisible because the misdirection feels like the work. The hostile-read anchors close that gap by forcing evidence-anchored answers for every confident score.

### When to apply

For every axis scored **≥ 4**, answer the prompts that apply. Each answer is **1–2 sentences anchored to a specific file, line, or code path** — not abstract self-doubt.

Honest answers that surface real gaps lower the score by 0.5–1 point. That is the design. If a hostile-read answer does not change the score, say why in one sentence (e.g., "weakest claim is X, but the gap is documented and bounded — no score change").

### The three prompts

**Prompt A — applied to every axis ≥ 4:**
> *What is the weakest claim I am making here, and what specific evidence would falsify it?*

The answer must name a file or behavior. "It feels solid" is not an answer.

**Prompt B — applied to every axis ≥ 4 on a metric the author personally invested in:**
> *Is my investment measuring what I think it's measuring, or am I counting the work-product instead of the user-visible behavior?*

Examples of misdirected investment to watch for: a lint script that runs on changed lines only (counts compliance, not coverage); a "comprehensive check" that audits a fraction of the installed surface (counts presence, not completeness); a "migration complete" claim that left sentinels behind (counts the PR, not the system state).

**Prompt C — applied to every axis ≥ 4 where validation or enforcement is claimed:**
> *Where does the documented contract diverge from the enforced contract? Walk the code path, not the narrative.*

The answer must trace at least one path from the documented promise (README, SKILL.md, CHANGELOG, commit message) to the line of code that enforces it. If the trace ends at a partial enforcement, that is a LEAKY contract — record it in the Contract Enforcement Audit (§9).

### Output requirement

The answers appear in the final report under a new section titled **"Hostile-read answers"**, immediately after the Scorecard table. Each answer is anchored to a specific evidence artifact (file:line, command output, commit SHA).

*Illustration (synthetic):* A repo claims "all config files are validated on commit." Prompt A answer: "Weakest claim is completeness — `pre-commit.sh:44-71` only validates `*.json`; `*.yaml` files are unchecked. This would fail if a bad YAML was introduced." One sentence, file + line, falsifiable.

## 9. Contract Enforcement Audit

This is a cross-axis check. It does not replace any of the 7 axes; it scores **the gap between what the repo's documented contracts promise and what the executed code enforces.** The most common staff-trap is a system whose narrative runs one rigor-level ahead of its enforcement — this check catches that gap.

### Procedure

1. **Inventory documented contracts.** Scan README, SKILL.md files, CHANGELOG.md, and recent commit messages for claims about what the system enforces. Examples of claim language: "comprehensive check", "bilateral lint", "drift guard", "no half-render", "structural linter", "migration complete", "validates every installed surface". Each claim is a contract.
2. **Map each contract to its enforcer.** Name the file and approximate line range that implements the check. If no enforcer exists, record the enforcer as `(none — decorative)`.
3. **Score the gap per contract:**
   - **TIGHT** — the code enforces every case the contract describes. No known bypass.
   - **LEAKY** — the code enforces the common case but has known or likely bypasses (partial coverage, substring matching where structural matching is implied, only-changed-lines mode where "full lint" is claimed, fresh-install paths where "every install" is claimed).
   - **DECORATIVE** — the contract is documented but the enforcement is symbolic (commented-out code, a rule listed in a doc with no script behind it, a sentinel pattern that the runtime never reads).
4. **Score the axis impact.** Identify which of the 7 axes each contract belongs to (most enforcement claims map to validation or operational safety; documentation claims map to docs; architectural claims may map to architecture or maintainability).

### Output requirement

Include the following table in the final report under a section titled **"Contract Enforcement Audit"**, immediately after the Hostile-Read Answers section:

```
| Contract (claim text or paraphrase) | Source (file:line or commit) | Enforcer (file:line) | Status | Axis affected |
|---|---|---|---|---|
```

Every contract in the inventory appears in the table. Empty cells are not allowed — if the enforcer is `(none)`, that is itself the finding.

### Axis cap rule

**Any contract that is LEAKY or DECORATIVE caps the affected axis at 4, regardless of other evidence.** This applies even if the axis's other dimensions would justify 5. Record the cap explicitly in the Scorecard rationale:

> "validation: capped at 4 — `check.sh:32-58` enforces ~25% of installed surface (LEAKY)"

The cap is the mechanism that makes the audit load-bearing. Without it, the table is a comment block; with it, the evaluator cannot claim 5 on an axis whose contract is unenforced.

### Interaction with existing verdict overrides

The axis cap from this section stacks with the existing verdict overrides above:

- A LEAKY validation contract caps validation at 4 (this section).
- An axis ≤ 2 still caps the verdict at **solid senior** (existing override rule).
- The axis cap from this section is applied **before** computing the weighted total — so the doubling of portability/safety reflects the capped score.

## Computing the weighted total

Multiply the **portability** and **operational safety** scores by 2 before summing. The other five categories sum at face value.

```
total = architectural_judgment
      + 2 × portability
      + maintainability
      + 2 × operational_safety
      + extensibility
      + documentation
      + validation
```

Maximum is 45. A repo that scores 4 across the board lands at 36 (5×4 + 2×4 + 2×4) — the doubling makes a low portability or safety score genuinely costly, which is the intent.

## Interpreting totals

Use totals as a guide, not a substitute for judgment. Bands are equal-width (9 points each) and align with the verdict words used in `SKILL.md`.

| Total (out of 45) | Verdict |
|---|---|
| 9-17 | **below senior bar** |
| 18-26 | **solid senior** |
| 27-35 | **approaching staff** |
| 36-44 | **staff-caliber** |
| 45 | **principal-leaning** |

## Verdict overrides

Cap the verdict — regardless of total — when any single axis fails badly:

- **Any axis ≤ 2** → cap at **solid senior**. A weighted total can hide a critical hole; the cap surfaces it.
- **Portability or operational safety = 1** → cap at **below senior bar**. Dotfiles with a serious portability or safety regression are not senior-caliber, no matter how strong the documentation or architecture is.
- **No tests, no validation strategy, and no dry-run** → cap at **solid senior**. Validation is the floor for staff-and-above signal.

State any active cap explicitly in the verdict line ("approaching staff by total, capped at solid senior because operational safety = 2").
