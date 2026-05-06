---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
user-invocable: true
---

This skill runs an interactive design interview. The user has a plan, design, or proposal
that needs stress-testing. Walk down the decision tree one branch at a time, ensuring every
dependency between decisions is resolved before moving on. The goal is not to critique — it
is to surface assumptions the user has not yet made explicit.

## Process

### 1. Survey the design tree

Before asking the first question, identify the major decision branches in the plan or design.
If a plan file exists (e.g., in `~/.claude/tasks/<project>/plans/`), read it. If the user
referenced a tech spec, PRD, or design doc, read that too.

Map out open decisions in the order they need to be made — earliest dependency first, latest
dependent last. For a feature rollout, that might be: rollback strategy, then rollout
mechanism, then observability, then cleanup. For a schema change, it might be: migration
strategy, then backward compatibility, then validation, then indexing.

If there is no written document, ask the user for a one-paragraph summary and infer the tree
from there before asking anything substantive.

### 2. Ask one question at a time

Never batch questions. Ask one. Wait for the answer. Then decide the next question based on
what you just learned. The point is sequential resolution, not a survey. A list of ten open
questions handed to the user at once is not an interview — it is homework.

Pick the question that unblocks the most downstream decisions. If the rollback strategy
determines what the rollout mechanism can be, ask about rollback first.

### 3. Recommend an answer with each question

Every question must come with your recommended answer and the reasoning behind it.

The user is stress-testing with your help — they need a concrete position to push back on,
not an open-ended prompt. If the user accepts the recommendation, lock the decision and
advance down the tree. If they push back, follow the pushback: revise your understanding,
update the tree, and ask the next question that flows from the new answer.

If your recommendation is wrong, that is a success — the pushback surfaces a constraint the
plan had not captured.

### 4. Explore the codebase before asking

If a question is answerable by reading the code, read the code instead of asking.

Asking the user about something they could discover with `grep` is friction. Examples of
questions to answer yourself before asking the user:
- "What is the existing pattern for X in this repo?"
- "Is there already a helper that does Y?"
- "How does module Z handle this edge case today?"
- "What does the current schema for this table look like?"

Surface what you find — "I looked at the existing implementation and it does X, which means
the question becomes..." — so the user can see your reasoning and correct it if the code is
misleading.

### 5. Lock decisions as they resolve

After each answer, restate the decision in one line: "Decided: we will use a feature flag
with a 1% → 10% → 100% ramp, with a kill-switch toggle in the admin panel."

Maintain a running list of locked decisions visible in the conversation. Before asking a new
question, briefly note which locked decisions it depends on. This keeps the conversation from
looping back to already-resolved branches and gives the user a clear picture of what remains
open.

When all branches of the tree are resolved, summarize the full decision set and ask the user
if they want to capture it as a plan file or PRD (offer `/to-prd` if appropriate).

---

## Example interactions

### Example 1: Stress-testing a feature flag rollout

> User: grill me on my plan to roll out the new tax calculation engine behind a feature flag

**Assistant:** I read the plan doc. Before asking about the rollout ramp, I need to lock the
rollback strategy first — it constrains what the ramp can be.

Question: What is the rollback path if the new engine produces wrong results for 0.5% of
users in the first hour?

My recommendation: the flag should be a kill-switch in the admin panel that immediately falls
back to the old engine for all users, with no code deploy required. This means we need the
old engine to stay hot (no lazy-loading) for the full duration of the rollout.

> User: agreed, kill-switch makes sense. The old engine can stay hot.

Decided: kill-switch in admin panel, old engine stays warm throughout rollout.

Next: I looked at the existing observability setup. There is a `tax_calc_latency_ms` metric
but no per-engine breakdown. We need to be able to compare old vs. new engine error rates
during the ramp. Do we add a `engine_version` tag to the existing metric, or create a
separate metric for the new engine?

My recommendation: tag the existing metric with `engine_version=legacy|v2` — one dashboard,
direct comparison, no metric proliferation.

> User: yes, tag approach. Let's move on.

Decided: `engine_version` tag on `tax_calc_latency_ms`.

Next question: what is the ramp schedule — percentages and time gates between each step?

---

### Example 2: Resolving a schema design fork

> User: grill me on adding a `preferences` column to the `users` table

**Assistant:** I looked at the `users` table schema. It has 23 columns already, some of which
look like they started as single columns and grew into multi-column families (the four
`notification_*` columns, the three `address_*` columns). That pattern suggests we have a
history of schema growth.

Question: should `preferences` be a JSONB column or a separate `user_preferences` table?

My recommendation: a separate `user_preferences` table with one row per preference key. It is
harder to query ad-hoc but avoids the JSONB indexing cost and keeps preferences individually
auditable and individually deleteable — important if any preference could be regulated data.

> User: I see the auditing argument, but we only have three preference keys and I don't think
> that will grow past ten. JSONB is simpler.

That constraint changes things — fewer than ten stable keys is a different design point.
Decided: JSONB column on `users`.

Next: with JSONB, we need a migration strategy for existing rows. I can see from the
migration history that the last three `ALTER TABLE users` migrations used `DEFAULT NULL` with
a subsequent backfill job. Should we follow that pattern here?

My recommendation: yes, same pattern — add the column as nullable with no default, backfill
existing rows to `'{}'::jsonb` in a separate migration, then add the `NOT NULL DEFAULT '{}'`
constraint. Three migrations, safe on a live table.

> User: yes, follow that pattern.

Decided: three-migration approach matching the repo's existing convention.

---

## When NOT to use

If you already have a finalized plan and want a quality pass rather than a design interview,
use `/scout-reviewer` or `/ranger-reviewer` instead — they review completed work. Use
`/grill-me` while you are still in design, when the plan has open questions or untested
assumptions. If you want to turn a resolved conversation into a document, chain to `/to-prd`
at the end of the interview.
