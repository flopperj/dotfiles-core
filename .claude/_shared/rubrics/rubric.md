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
