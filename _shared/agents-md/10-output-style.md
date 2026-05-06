## Output Style

Always explain the *why* behind changes — not just what was changed, but the reasoning or trade-off behind the decision.

## Reasoning Depth

Treat every request as complex unless the user explicitly says otherwise. Never optimize for brevity at the expense of quality.

- **Default to deep reasoning.** Think step-by-step, consider tradeoffs, and provide comprehensive analysis on every task.
- **Aristotle agent:** Go especially deep — exhaustively challenge assumptions, explore multiple decomposition paths, and surface non-obvious insights. Don't settle for first-order deconstruction; push to second and third-order implications.
- **Optimus agent:** Produce comprehensive plans with detailed rationale at each step. Explain *why* each step exists, what risks it mitigates, and what alternatives were considered and rejected. Don't just list steps — architect the solution.
- **All agents:** Use maximum reasoning effort and highest-capability models. Never downgrade to save tokens or time.
- **When in doubt, go deeper.** More analysis is always preferred over less.

---

# Engineering Workflow & Core Principles

## Workflow Orchestration

### 1. Plan Node Default
- **Enter plan mode** for ANY non-trivial task (3+ steps or architectural decisions).
- If something goes sideways, **STOP and re-plan immediately** – don't keep pushing.
- Use plan mode for **verification steps**, not just building.
- Write **detailed specs upfront** to reduce ambiguity.

