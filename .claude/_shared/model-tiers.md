# Agent Model Tier Intent

Canonical tier assignments for `.claude/agents/*.md`. All agents use aliases (`opus`, `sonnet`) rather than pinned model IDs so each tier auto-upgrades as Anthropic releases new models — and so no agent can be stranded if a specific model is withdrawn. `/doctor` Step 6c surfaces drift.

| Agent | Tier | Rationale |
|---|---|---|
| Aristotle | `opus` | First-principles deconstruction is the hardest reasoning step in the kit — it gets the strongest auto-upgrading tier. (Briefly pinned to `claude-fable-5`; reverted to the alias because a pinned ID has no auto-fallback — see [Non-aliased tiers](#non-aliased-tiers).) |
| Optimus | `opus` | Planning quality gates everything downstream — a bad plan cascades into wasted Cyrus cycles, so it gets the strongest auto-upgrading tier. (Same Fable-pin history and revert reason as Aristotle.) |
| Ranger | `opus` | Staff-level review = staff-level analysis. Ranger is chosen precisely when depth matters. |
| Cyrus | `sonnet` | High-throughput TDD loops. Volume and latency sensitivity make Opus uneconomic; Sonnet is sufficient for executing a well-specified Optimus plan. |
| Scout | `sonnet` | Scout's entire differentiation from Ranger is the speed tier. Moving Scout to Opus collapses the `/code-auditor` routing decision into a meaningless choice. |

## Expected alias resolution (as of 2026-06-22)

- `opus` → `claude-opus-4-8` (1M context available; "most capable for complex work")
- `sonnet` → `claude-sonnet-4-6`
- `haiku` → `claude-haiku-4-5`

Verified against the Claude Code `/model` picker on 2026-06-10; unchanged as of 2026-06-22. If Claude Code resolves these aliases to older models on a given machine, `/doctor` reports the drift.

## Non-aliased tiers

Some models are selectable in `/model` but are **not** what the `opus`/`sonnet`/`haiku` aliases resolve to. Agents pin tier *aliases*, so these are only reached by an explicit per-session `/model` choice or an `ANTHROPIC_MODEL` override — never automatically.

- **Fable 5** (`claude-fable-5`) — a distinct tier positioned for "the hardest and longest-running tasks." Not an alias target: an agent reaches it only by an explicit `model: claude-fable-5` pin or a session `/model` override. **No agent pins Fable.** Aristotle and Optimus were briefly pinned to it (v1.11.0) and reverted to the `opus` alias, because:
  - **A pinned model ID has no auto-fallback.** `model: claude-fable-5` means *exactly* that model — not "Fable, else Opus." If Fable is disabled or withdrawn, the pinned agents do **not** fall back to `opus`/Opus 4.8; the spawn errors or falls through to the session model, never to the intended tier. An alias (`opus`) cannot be stranded this way — it always resolves to whatever the platform currently ships for that tier.
  - **Pinning also defeats auto-upgrade** — a pinned agent stays on the frozen ID until manually bumped, the same staleness trap the alias system exists to avoid.

  To deliberately run an agent on Fable, prefer a **session `/model` override** for that run over a permanent frontmatter pin — you get Fable's tuning without stranding the agent if Fable goes away. Only pin a raw ID when an agent genuinely must always use one specific non-aliased model and you accept owning the manual-bump and no-fallback risk.

## Why aliases, not pinned IDs

- **Auto-upgrade** — new Opus/Sonnet versions flow in without touching agent files.
- **Portability** — agent files work across Claude Code versions that may not have the latest model available.
- **Drift signal** — centralizing the expected mapping in one place (this file + `/doctor`) means a silent regression is catchable, not invisible.

The cost is that a specific model ID cannot be guaranteed per invocation. That cost is acceptable because every invocation inherits whatever Anthropic currently ships as the tier's latest — which is the direction we want anyway — and because an alias can never be stranded by a single model being withdrawn. We briefly pinned Aristotle and Optimus to `claude-fable-5` to reach a non-aliased tier and reverted (see [Non-aliased tiers](#non-aliased-tiers)): the auto-upgrade loss and, more importantly, the lack of any fallback when a pinned ID becomes unavailable outweighed Fable's tuning for gated, interactive agents. Reach a non-aliased tier with a session `/model` override instead.

## When to revisit

- A new tier emerges (e.g., a reasoning-specific model distinct from Opus).
- Cost profile of a tier shifts materially enough to change the Sonnet/Opus split.
- A new agent is added and needs to land in the correct tier by default.
