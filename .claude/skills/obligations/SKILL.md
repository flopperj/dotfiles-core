---
name: obligations
description: "Create, view, cancel, and evaluate cross-session obligations. Use when the user types /obligations, says 'remind me', 'watch this', 'nudge me', 'track this', 'show my obligations', 'cancel obligation', or asks to set up a recurring check on a PR or Jira ticket."
user-invocable: true
---

## Overview

Obligations are commitments the system makes to check a condition and take an action across session boundaries. Unlike in-session reminders, obligations persist in `~/.claude/tasks/<project>/obligations.yaml` and survive conversation resets. The `/briefing` skill evaluates all active obligations at session start; this skill manages their full lifecycle — create, view, cancel, evaluate, and garbage-collect.

Resolve `<project>` as: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`

---

## Data Model

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique ID: `ob-YYYYMMDD-NNN` |
| `name` | string | Human-readable name (e.g., `nudge-reviewer-pr-482`) |
| `created` | ISO 8601 | When the obligation was created |
| `created_by` | string | `user`, `policy`, or `briefing` |
| `condition.type` | string | `gh_query`, `jql`, `compound`, `time` |
| `condition.query` | string | The query to execute |
| `condition.predicate` | string | The condition to check against query results |
| `action.type` | string | `notify`, `invoke_skill`, `approve_then_invoke` |
| `action.message` | string | Message to display when condition is met |
| `gate` | string | `autonomous`, `notify`, `approve` |
| `expiry.type` | string | `date`, `condition`, `count` |
| `expiry.value` | string | Expiry value (ISO date, condition expression, or integer count) |
| `cooldown` | string | Duration string (e.g., `24h`, `1h`) |
| `max_fires` | integer or null | Max times this obligation can fire; null = unlimited |
| `fired_count` | integer | How many times it has fired |
| `last_fired` | ISO 8601 or null | Last fire timestamp |
| `status` | string | `active`, `expired`, `resolved`, `cancelled` |
| `dedup_key` | string or null | Only the newest obligation with this key fires |

**Fully populated example:**

```yaml
- id: "ob-20260413-001"
  name: "check-pr-482-review"
  created: "2026-04-13T09:00:00"
  created_by: "user"
  condition:
    type: "gh_query"
    query: "gh pr view 482 --json reviewDecision"
    predicate: "reviewDecision == 'REVIEW_REQUIRED' OR reviewDecision is null"
  action:
    type: "notify"
    message: "PR #482 still waiting for review. Nudge reviewer?"
  gate: "notify"
  expiry:
    type: "date"
    value: "2026-04-16T00:00:00"
  cooldown: "24h"
  max_fires: 3
  fired_count: 0
  last_fired: null
  status: "active"
  dedup_key: "pr-482-review-check"
```

---

## Creating Obligations

When the user asks to create an obligation in natural language:

1. **Parse the intent** — identify the target (PR, Jira ticket, generic), the condition (status check, review state, time-based), the action (notify, suggest), and timing constraints.
2. **Generate the obligation struct** with sensible defaults:
   - `gate: "notify"` — show the user, don't auto-act
   - `cooldown: "24h"` — avoid spamming
   - `max_fires: 3` — auto-expire after 3 notifications
   - `expiry: { type: "date", value: "+3d" }` — 3 days from now (resolve to absolute ISO datetime)
   - `status: "active"`, `fired_count: 0`, `last_fired: null`
3. **Resolve the file path** — `~/.claude/tasks/<project>/obligations.yaml`
4. **Read existing file** (if present) — load current obligation list to check for existing IDs
5. **Generate a unique ID** — `ob-YYYYMMDD-NNN` where NNN is the next sequential integer for today (001, 002, …)
6. **Append the new obligation** and write the file back
7. **Confirm** — show the created obligation with its ID, condition summary, expiry, and cooldown

### Examples

**"Remind me to check PR #482 tomorrow if it hasn't been reviewed"**

```yaml
- id: "ob-20260413-001"
  name: "check-pr-482-review"
  condition:
    type: "gh_query"
    query: "gh pr view 482 --json reviewDecision"
    predicate: "reviewDecision == 'REVIEW_REQUIRED' OR reviewDecision is null"
  action:
    type: "notify"
    message: "PR #482 still waiting for review. Nudge reviewer?"
  gate: "notify"
  expiry: { type: "date", value: "2026-04-16T00:00:00" }
  cooldown: "24h"
  max_fires: 3
```

**"Watch PROJ-1234 and tell me when it's Done"**

```yaml
- id: "ob-20260413-002"
  name: "watch-proj-1234-done"
  condition:
    type: "jql"
    query: "key = PROJ-1234 AND status = 'Done'"
    predicate: "result_count > 0"
  action:
    type: "notify"
    message: "PROJ-1234 has been moved to Done!"
  gate: "notify"
  expiry: { type: "date", value: "2026-04-20T00:00:00" }
  cooldown: "1h"
  max_fires: 1
```

**"Nudge me daily if my sprint has unstarted tickets"**

```yaml
- id: "ob-20260413-003"
  name: "sprint-unstarted-nudge"
  condition:
    type: "jql"
    query: "assignee = currentUser() AND sprint in openSprints() AND status = 'To Do'"
    predicate: "result_count > 0"
  action:
    type: "notify"
    message: "{count} sprint tickets still in To Do. Consider swarming them."
  gate: "notify"
  expiry: { type: "condition", value: "result_count == 0" }
  cooldown: "24h"
  max_fires: null
```

---

## Viewing Obligations

When the user asks to see obligations ("show my obligations", "what am I tracking", "obligations list"):

1. Resolve the file path and read `obligations.yaml`
2. Filter to `status: active` only
3. Render in this format:

```
Active obligations (2):
  1. [ob-20260413-001] Check PR #482 review status — next eval: tomorrow (0/3 fired)
     Condition: PR #482 reviewDecision == REVIEW_REQUIRED
  2. [ob-20260413-002] Watch PROJ-1234 for Done — next eval: next briefing (1/1 fired)
     Condition: PROJ-1234 status == Done

  -> cancel 1 = Remove obligation 1
  -> cancel all = Remove all obligations
  -> check = Evaluate all obligations now
```

If no active obligations exist, show: `No active obligations.`

---

## Cancelling Obligations

When the user asks to cancel ("cancel obligation 1", "remove the PR #482 reminder", "cancel all"):

1. **Resolve the target** — by index number (from view list), by ID (`ob-20260413-001`), by name fragment (`pr-482`), or the keyword `all`
2. **Set `status: cancelled`** on the matched obligation(s) — do not delete, keep for audit trail
3. **Write the updated file**
4. **Confirm** — "Cancelled obligation ob-20260413-001 (check-pr-482-review)."

---

## Evaluating Obligations

The evaluation loop is called by both `/obligations check` and the `/briefing` skill. For each obligation where `status == active`:

1. **Check expiry:**
   - `type: date` — if `expiry.value` < now → set `status: expired`, skip
   - `type: count` — if `fired_count >= max_fires` → set `status: expired`, skip
   - `type: condition` — evaluate the expiry expression; if met → set `status: resolved`, skip

2. **Check cooldown:**
   - If `last_fired` is set and `last_fired + cooldown > now` → skip (still cooling down)

3. **Check dedup:**
   - If another obligation with the same `dedup_key` exists with a newer `created` date → skip this one (superseded)

4. **Evaluate the condition:**
   - `gh_query` — run the `gh` CLI command, parse JSON output, check predicate against result
   - `jql` — run via MCP: primary `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql`<!-- BEGIN OVERLAY-FRAGMENT: obligations-jql-fallback-tool --> <!-- END OVERLAY-FRAGMENT: obligations-jql-fallback-tool -->; check predicate against `result_count`. For company-specific Jira fallback tool name, consult `## Jira fallback (DAST-Orch MCP)` in `~/.claude/overlay-context.md`. If that file is absent, proceed with the primary tool only.
   - `compound` — evaluate all sub-conditions; all must be true for the obligation to fire
   - `time` — check if `condition.after` < now

5. **If condition is met:**
   - `gate: notify` → display `action.message` inline
   - `gate: approve` → display message and ask for confirmation before invoking any action
   - `gate: autonomous` → invoke the action immediately without prompting
   - Increment `fired_count`, set `last_fired` to now

6. **Staleness check:**
   - After firing, check if the inverse condition is now met (e.g., PR was merged, ticket is Done) → set `status: resolved`

7. **Write back** — persist updated `fired_count`, `last_fired`, and `status` to the YAML file

**Error handling:** If a condition query fails (MCP unavailable, `gh` error), skip that obligation and note: `Could not evaluate obligation {name}: {error}`. Do not mark it expired or resolved on failure.

---

## Garbage Collection

On each evaluation pass and when `/obligations` is invoked directly:

- Identify obligations with `status` in (`expired`, `resolved`, `cancelled`) that are older than 7 days (`created` < now - 7d)
- Move them to an `archive` list at the bottom of `obligations.yaml` — store only `id` and `name`, not the full struct
- Leave `obligations.yaml` in place even if only archived items remain (preserves audit trail)

```yaml
archive:
  - id: "ob-20260406-001"
    name: "check-pr-475-review"
```

---

## Future Enhancement — RemoteTrigger

This section documents a planned Phase 2 integration. Do not implement it yet.

When an obligation needs to fire outside of active sessions, a corresponding RemoteTrigger can be registered alongside it. The RemoteTrigger's prompt would re-invoke `/obligations check` for that specific obligation ID. On trigger execution, the obligation condition is re-evaluated before any action is taken — the obligation file remains the source of truth; the RemoteTrigger is only the alarm clock. If the obligation has been cancelled or expired before the trigger fires, evaluation exits cleanly with no action. This pattern decouples the scheduling mechanism from the obligation logic and keeps the YAML file authoritative.
