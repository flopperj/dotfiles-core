# Agent Model Tier Intent

Canonical tier assignments for `.claude/agents/*.md`. Uses aliases (`opus`, `sonnet`) rather than pinned model IDs so each tier auto-upgrades as Anthropic releases new models. `/doctor` Step 6c surfaces drift.

| Agent | Tier | Rationale |
|---|---|---|
| Aristotle | `opus` | Deep reasoning is the job — first-principles deconstruction demands maximum capability. |
| Optimus | `opus` | Planning quality gates everything downstream; ambiguous plans cost more than Opus does. |
| Ranger | `opus` | Staff-level review = staff-level analysis. Ranger is chosen precisely when depth matters. |
| Cyrus | `sonnet` | High-throughput TDD loops. Volume and latency sensitivity make Opus uneconomic; Sonnet is sufficient for executing a well-specified Optimus plan. |
| Scout | `sonnet` | Scout's entire differentiation from Ranger is the speed tier. Moving Scout to Opus collapses the `/code-auditor` routing decision into a meaningless choice. |

## Expected alias resolution (as of 2026-04-20)

- `opus` → `claude-opus-4-7`
- `sonnet` → `claude-sonnet-4-6`
- `haiku` → `claude-haiku-4-5`

If Claude Code resolves these aliases to older models on a given machine, `/doctor` reports the drift.

## Why aliases, not pinned IDs

- **Auto-upgrade** — new Opus/Sonnet versions flow in without touching agent files.
- **Portability** — agent files work across Claude Code versions that may not have the latest model available.
- **Drift signal** — centralizing the expected mapping in one place (this file + `/doctor`) means a silent regression is catchable, not invisible.

The cost is that a specific model ID cannot be guaranteed per invocation. That cost is acceptable because every invocation inherits whatever Anthropic currently ships as the tier's latest — which is the direction we want anyway.

## When to revisit

- A new tier emerges (e.g., a reasoning-specific model distinct from Opus).
- Cost profile of a tier shifts materially enough to change the Sonnet/Opus split.
- A new agent is added and needs to land in the correct tier by default.
