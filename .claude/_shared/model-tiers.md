# Agent Model Tier Intent

Canonical tier assignments for `.claude/agents/*.md`. Most agents use aliases (`opus`, `sonnet`) rather than pinned model IDs so each tier auto-upgrades as Anthropic releases new models. The two deepest-reasoning agents are an intentional exception — pinned to `claude-fable-5` because Fable is not an alias target and can only be reached by an explicit pin (see [Non-aliased tiers](#non-aliased-tiers)). `/doctor` Step 6c surfaces drift.

| Agent | Tier | Rationale |
|---|---|---|
| Aristotle | `claude-fable-5` (pinned) | First-principles deconstruction is the hardest reasoning step in the kit and the least latency-sensitive (one deep gated turn, not a loop). Fable is positioned for exactly this — "hardest and longest-running tasks." Pinned, not aliased, because Fable is not an `opus`/`sonnet` alias target. |
| Optimus | `claude-fable-5` (pinned) | Planning quality gates everything downstream — a bad plan cascades into wasted Cyrus cycles, so this is the highest-leverage place to spend capability. Gated and interactive, not latency-bound. Pinned for the same reason as Aristotle. |
| Ranger | `opus` | Staff-level review = staff-level analysis. Ranger is chosen precisely when depth matters. Kept on the `opus` alias (auto-upgrades) — review is a verification gate, not a generative reasoning step, so the Fable bet doesn't clearly apply. |
| Cyrus | `sonnet` | High-throughput TDD loops. Volume and latency sensitivity make Opus uneconomic; Sonnet is sufficient for executing a well-specified Optimus plan. |
| Scout | `sonnet` | Scout's entire differentiation from Ranger is the speed tier. Moving Scout to Opus collapses the `/code-auditor` routing decision into a meaningless choice. |

> **Pin tradeoff (Aristotle, Optimus).** Pinning `claude-fable-5` defeats alias auto-upgrade for these two agents: when a newer Opus or Fable lands, they stay on `claude-fable-5` until manually bumped. That is the accepted cost of reaching a non-aliased tier. `/doctor` Step 6c reports the pin as-is; revisit on each model release. If Fable stops being the most-capable long-task tier, re-point these two (back to `opus`, or to the new top tier) in one edit each.

## Expected alias resolution (as of 2026-06-10)

- `opus` → `claude-opus-4-8` (1M context available; "most capable for complex work")
- `sonnet` → `claude-sonnet-4-6`
- `haiku` → `claude-haiku-4-5`

Verified against the Claude Code `/model` picker on 2026-06-10. If Claude Code resolves these aliases to older models on a given machine, `/doctor` reports the drift.

## Non-aliased tiers

Some models are selectable in `/model` but are **not** what the `opus`/`sonnet`/`haiku` aliases resolve to. Agents pin tier *aliases*, so these are only reached by an explicit per-session `/model` choice or an `ANTHROPIC_MODEL` override — never automatically.

- **Fable 5** (`claude-fable-5`) — a distinct tier positioned for "the hardest and longest-running tasks." Not an alias target: an agent does not pick it up by declaring `model: opus`, only by an explicit `model: claude-fable-5` pin (weighed against losing alias auto-upgrade for that agent) or a session `/model` override. **Aristotle and Optimus are pinned to Fable today** (see the table above and the pin-tradeoff note); the remaining agents stay on the `opus`/`sonnet` aliases.

## Why aliases, not pinned IDs

- **Auto-upgrade** — new Opus/Sonnet versions flow in without touching agent files.
- **Portability** — agent files work across Claude Code versions that may not have the latest model available.
- **Drift signal** — centralizing the expected mapping in one place (this file + `/doctor`) means a silent regression is catchable, not invisible.

The cost is that a specific model ID cannot be guaranteed per invocation. That cost is acceptable for most agents because every invocation inherits whatever Anthropic currently ships as the tier's latest — which is the direction we want anyway. The exception is when reaching a non-aliased tier is worth giving up auto-upgrade for: Aristotle and Optimus accept that opposite tradeoff with explicit `claude-fable-5` pins (see the assignment table, the pin-tradeoff note, and [Non-aliased tiers](#non-aliased-tiers)).

## When to revisit

- A new tier emerges (e.g., a reasoning-specific model distinct from Opus).
- Cost profile of a tier shifts materially enough to change the Sonnet/Opus split.
- A new agent is added and needs to land in the correct tier by default.
