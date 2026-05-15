---
name: briefing
description: "Session-start situation report: Jira sprint status, open PRs, failing CI, stale reviews, today's calendar, Slack signals, and suggested actions. Use when the user types /briefing, /sitrep, starts a prompt with 'Sitrep', or asks 'what needs my attention', 'what's my status', 'morning briefing', 'show me my dashboard', 'what should I work on', or 'catch me up'."
user-invocable: true
---

<!-- shape: checklist-v1 -->

# Briefing — Session-Start Situation Report

Query Jira, GitHub, Google Calendar, and Slack, merge the results, and render a prioritized situation report of what needs the user's attention right now. This skill queries and presents — it does NOT act. All actions come from the user typing the suggested commands.

## When to Use

- The user types `/briefing`, `/sitrep`, or starts a prompt with `Sitrep, ...`.
- The user asks "what needs my attention?", "what's my status?", "morning briefing", "show me my dashboard", "what should I work on?", or "catch me up".
- The user is starting a work session and wants a quick orientation across Jira / GitHub / Calendar / Slack / CI / obligations.
- A scheduled job (`/schedule` or future `RemoteTrigger`) fires `/briefing` to produce a recurring morning situation report.

> Briefing is read-only. It queries and renders; the user decides what to act on. If the user wants the briefing AND wants something fixed, they invoke a downstream skill (Scout to review a PR, Cyrus to fix CI, Pickup to start a ticket, etc.) — briefing surfaces the suggested commands but never runs them.

## Workflow

The four-stage flow is **Gather → Enrich → Compose → Present**:

- **Gather** (Steps 1, 1b, 1c, 2): run Jira / Calendar / Slack / GitHub queries in parallel.
- **Enrich** (Step 2.5): if any PRs have failing CI and Jenkins MCP is available, fetch failure details.
- **Compose** (Step 3): derive signals from the raw query results and prioritize.
- **Present** (Step 4): render the briefing in the canonical output format.

### Step 1 — Query Jira (via MCP)

Run all four Jira queries in parallel using the primary MCP tool. If the primary fails, retry each with the fallback tool. If both fail, skip Jira and note the degradation.

**Primary tool:** `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql`

For company-specific Jira fallback, consult `## Jira fallback` in `~/.claude/overlay-context.md`. If that file is absent, proceed with the primary tool only.

<!-- BEGIN OVERLAY-FRAGMENT: briefing-jira-fallback-tool -->
<!-- END OVERLAY-FRAGMENT: briefing-jira-fallback-tool -->

Run these queries:

| Query | JQL |
|---|---|
| Sprint tickets | `assignee = currentUser() AND sprint in openSprints() ORDER BY priority ASC, status ASC` |
| Recently assigned | `assignee = currentUser() AND created >= -48h ORDER BY created DESC` |
| P0/P1 items | `assignee = currentUser() AND status in ("In Progress", "To Do") AND priority in ("Highest", "High") ORDER BY priority ASC` |
| In Progress tickets | `assignee = currentUser() AND status = "In Progress" ORDER BY updated ASC` |

Fields to request: `summary`, `status`, `priority`, `issuetype`, `created`, `updated`, `sprint`
Max results per query: 25

### Step 1b — Query Google Calendar (via MCP)

**Prerequisite check:** Before calling any Google Calendar MCP tools, check if `mcp__claude_ai_Google_Calendar__list_events` is listed in your available tools (visible in the system prompt). If no `mcp__claude_ai_Google_Calendar__*` tools appear, the MCP is not connected — skip this step entirely and proceed without calendar data.

Run this query in parallel with Steps 1, 2, and 1c:

~~~
mcp__claude_ai_Google_Calendar__list_events(
  startTime="<today>T00:00:00",
  endTime="<tomorrow>T00:00:00",
  orderBy="startTime",
  pageSize=50
)
~~~

Replace `<today>` and `<tomorrow>` with ISO 8601 date strings for the current date and the next day.

**Fields to extract per event:**
- `summary` (event title)
- `start.dateTime` or `start.date` (all-day events use `date`, timed events use `dateTime`)
- `end.dateTime` or `end.date`
- `attendees` (list, look for `responseStatus` of the current user)
- `status` (confirmed, tentative, cancelled)
- `hangoutLink` or `conferenceData` (meeting link, if present)
- `location` (physical or virtual)

**Filter out:**
- Events with `status == "cancelled"`
- All-day events that are informational (holidays, OOO markers from others) — keep only all-day events where the user is an attendee
- Declined events (where the current user's `responseStatus == "declined"`)

**Performance budget:** Calendar query should complete in <3 seconds. A single `list_events` call with a 24-hour window is sufficient — no pagination needed for a single day.

### Step 1c — Query Slack (via MCP)

**Prerequisite check:** Before calling any Slack MCP tools, check if `mcp__claude_ai_Slack__slack_search_public_and_private` is listed in your available tools (visible in the system prompt). If no `mcp__claude_ai_Slack__*` tools appear, the MCP is not connected — skip this step entirely and proceed without Slack data.

Run these queries in parallel with Steps 1, 1b, and 2. All three Slack queries can also run in parallel with each other.

**Query 1 — @mentions (overnight):**

~~~
mcp__claude_ai_Slack__slack_search_public_and_private(
  query="to:me after:<16h_ago_unix_timestamp>",
  sort="timestamp",
  sort_dir="desc",
  limit=20,
  include_context=false,
  response_format="concise"
)
~~~

Replace `<16h_ago_unix_timestamp>` with the Unix timestamp for 16 hours before the current time. This captures overnight activity since the user's last likely session.

**Query 2 — DM activity (overnight):**

~~~
mcp__claude_ai_Slack__slack_search_public_and_private(
  query="to:me after:<16h_ago_unix_timestamp>",
  channel_types="im,mpim",
  sort="timestamp",
  sort_dir="desc",
  limit=10,
  include_context=false,
  response_format="concise"
)
~~~

This specifically targets direct messages and group DMs. Results may overlap with Query 1 — deduplicate by message timestamp in Step 3.

**Query 3 — Thread replies (overnight):**

~~~
mcp__claude_ai_Slack__slack_search_public_and_private(
  query="to:me is:thread after:<16h_ago_unix_timestamp>",
  sort="timestamp",
  sort_dir="desc",
  limit=10,
  include_context=false,
  response_format="concise"
)
~~~

This surfaces threads where someone replied and mentioned the user.

**Fields to extract per message:**
- `channel.name` or `channel.id` (where the message was posted)
- `user` or `username` (who sent the message)
- `text` (message content — truncate to ~80 chars for the briefing)
- `ts` (timestamp — for deduplication and age calculation)
- `permalink` (direct link to the message)
- `thread_ts` (if the message is a thread reply)

**Deduplication:** Messages that appear in multiple queries (e.g., a DM that is also an @mention) should be deduplicated by `ts` + `channel.id`. Keep the first occurrence.

**Performance budget:** All three Slack queries should complete in <5 seconds total. The `concise` response format and `include_context=false` minimize token usage.

### Step 2 — Query GitHub (via `gh` CLI)

Run both GitHub queries. If `gh` fails, see Graceful Degradation.

```bash
# My open PRs
gh pr list --author @me --state open \
  --json number,title,createdAt,reviewDecision,statusCheckRollup,isDraft,url \
  --limit 25

# PRs where I am a requested reviewer
gh pr list --search "review-requested:@me" --state open \
  --json number,title,createdAt,url \
  --limit 10
```

#### Comment-monitoring queries (Phase 1)

These queries add visibility into PR comment activity. They run after the initial `gh pr list --author @me` returns PR numbers.

```bash
# Unresolved review threads on my PRs (batched GraphQL)
# Batch up to 10 PRs per query using GraphQL aliases.
# Build the query dynamically from PR numbers returned by --author @me above.
# Example for PRs #101, #102, #103:
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pr101: pullRequest(number: 101) {
        number
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
      pr102: pullRequest(number: 102) {
        number
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
      pr103: pullRequest(number: 103) {
        number
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
    }
  }
'
# Construct one query per batch of 10 PRs from the --author @me result set.
# Total API calls: ceil(N/10) where N = number of open PRs (max 25 = 3 calls).
# For each PR, count nodes where isResolved == false. That is the unresolved thread count.
```

```bash
# PRs where I am @mentioned in comments (single search query)
gh search prs --mentions @me --state open --repo {owner}/{repo} \
  --json number,title,url,author --limit 20
# This returns PRs where any comment mentions the current user.
# Filter out PRs already in the --author @me set (self-mentions on own PRs are noise).
# Remaining PRs = someone else's PR where I was mentioned.
```

### Step 2.5 — Jenkins CI Enrichment (optional)

When Step 2 reveals PRs with failing CI (`statusCheckRollup` contains FAILURE or ERROR), attempt to fetch failure details from the Jenkins MCP server.

**Prerequisite check:** Before calling any Jenkins MCP tools, check if `mcp__jenkins-mcp__get_build_errors` is listed in your available tools (visible in the system prompt). If no `mcp__jenkins-mcp__*` tools appear, the MCP is not configured — skip this step entirely and proceed to Step 3 with the existing `gh pr checks` data.

**For each PR with failing CI** (parallelize across PRs):

1. **Resolve the build:** Call `mcp__jenkins-mcp__get_multibranch_branch` with the PR's branch name to get the latest build URL and number.
2. **Fetch error context:** Call `mcp__jenkins-mcp__get_build_errors` with the resolved build. This is the primary diagnosis tool — it extracts up to 200 lines around ERROR/Exception/FAILED patterns from the build log. It is token-efficient and should be preferred over fetching full logs.
3. **Fetch test results (if applicable):** Call `mcp__jenkins-mcp__get_test_results` to get JUnit test report data (`passCount`, `failCount`, `skipCount`, and individual failure details). This provides structured test failure information that may be clearer than raw log parsing.
4. **Extract from the MCP responses:**
   - **Failure type**: test failure, compilation error, lint violation, timeout, infrastructure error
   - **Failure summary**: the specific test name, error message, or compilation error (1-2 lines)
   - **File and line** (if available): the source location of the failure
5. Store the enrichment alongside the PR data for use in Step 3 and Step 4.

**For the morning summary (optional, not per-PR):**

If this is a full briefing (not a targeted CI check), also call `mcp__jenkins-mcp__get_recent_failures` to scan all jobs for recent FAILURE/UNSTABLE builds. Include any relevant failures in the AWARENESS section.

**Graceful degradation:**
| Failure | Behavior |
|---|---|
| Jenkins MCP not configured (no `mcp__jenkins-mcp__*` tools in system prompt) | Skip entirely — use `gh pr checks` data only (current behavior) |
| Jenkins MCP tool call fails | Log `Note: Jenkins log fetch failed for PR #{n} — showing check names only` and continue |
| Jenkins MCP returns empty/unclear | Use `gh pr checks` data — do not invent details |
| Jenkins MCP times out (>10s per PR) | Skip that PR's enrichment and continue |

**Performance budget:** Jenkins enrichment should add <5 seconds total to the briefing. If >3 PRs have failing CI, process them in parallel.

### Step 3 — Analyze and Prioritize

Derive the following signals from the raw query results:

**From GitHub:**
- **Failing CI:** PRs where `statusCheckRollup` contains any failure or error state. If Jenkins enrichment (Step 2.5) provided failure details, include the failure type, summary, and source location.
- **Changes requested:** PRs where `reviewDecision == "CHANGES_REQUESTED"`
- **Unresolved threads:** PRs from `--author @me` where the GraphQL reviewThreads query returned any node with `isResolved == false`. Include the count of unresolved threads per PR.
- **@mentions:** PRs returned by `gh search prs --mentions @me` that are NOT in the `--author @me` set (filter out self-mentions). These are other people's PRs where someone explicitly mentioned the user.
- **Stale PRs:** Open, non-draft PRs with `createdAt` older than 3 days and no approval
- **Draft promotable:** Draft PRs (`isDraft == true`) where CI is passing
- **Review requests:** All PRs returned by the `review-requested` query

**From Jira:**
- **P0/P1 items:** All results from the P0/P1 query
- **In Progress, no branch:** Results from the "In Progress" query where no corresponding PR exists in the GitHub results (match on ticket key in PR title/branch name)
- **Sprint summary:** Count of sprint tickets by status (Done / In Progress / To Do / other)
- **Recently assigned:** Results from the `-48h` query not already in the sprint

**From Google Calendar:**
- **Imminent meetings:** Events starting within the next 30 minutes. These are urgent — the user needs to know before starting deep work.
- **Today's schedule:** All confirmed events for the day, sorted by start time. Provides the full picture for planning.
- **Availability windows:** Gaps of 60+ minutes between meetings. Derived by computing the time ranges NOT covered by any event. These help the user decide when to do focused work.
- **Tentative events:** Events where the user's `responseStatus == "tentative"` (not yet accepted). These need a decision.
- **Conflicts:** Overlapping events (where one event's start is before another event's end and vice versa). These need resolution.

**From Slack:**
- **Direct messages:** Messages from Query 2 (DMs and group DMs). These often require a response.
- **@mentions in channels:** Messages from Query 1 that are NOT DMs (filter by channel type). Someone explicitly asked for the user's input.
- **Thread activity:** Messages from Query 3 where the user is in a thread that received new replies. The user may need to follow up.
- **Deduplicated message count:** Total unique messages across all three queries after deduplication.

**Priority ordering:**
1. **URGENT** — Failing CI, Changes Requested, P0/P1 tickets, calendar conflicts
2. **ACTION NEEDED** — Unresolved review threads (block merge), @mentions in PRs (input requested), Stale PRs (>3 days), In Progress with no branch, review requests from others, Slack DMs (response expected), tentative calendar events
3. **SCHEDULE** — Today's meetings (chronological), availability windows, imminent meetings get a time-warning prefix
4. **COMMS** — Slack @mentions in channels, thread activity, grouped by channel
5. **AWARENESS** — Sprint summary, recently assigned, draft PRs promotable

### Step 4 — Render the Briefing

Output the briefing in the exact format specified in the **Output Format** section below. Omit any section with zero items. If all sections are empty, output: `All clear — nothing urgent.`

After rendering, check for active obligations and append the OBLIGATIONS section (see the **Obligations** section below).

## Checklist

- [ ] Step 1 Jira queries fired in parallel (sprint / recently-assigned / P0-P1 / in-progress)
- [ ] Step 1b Calendar query fired (only if Google Calendar MCP is in tool surface)
- [ ] Step 1c Slack queries fired in parallel (only if Slack MCP is in tool surface) — @mentions / DMs / threads
- [ ] Step 2 GitHub queries fired (`gh pr list --author @me`, `gh pr list --search review-requested:@me`)
- [ ] Step 2 comment-monitoring queries fired after PR list returns (batched GraphQL review threads, single-call mentions search)
- [ ] Step 2.5 Jenkins CI enrichment fired only when failing CI exists AND Jenkins MCP is in tool surface
- [ ] Step 3 signals derived from cached query results (no duplicate calls)
- [ ] Step 3 priority ordering applied: URGENT → ACTION NEEDED → SCHEDULE → COMMS → AWARENESS
- [ ] Step 4 rendered in the canonical output format
- [ ] Empty sections omitted
- [ ] Each item has a `->` copy-pasteable command
- [ ] Graceful degradation notes shown for failed-but-available tools; silent skip for absent-MCP tools (Calendar/Slack/Jenkins)
- [ ] policies.yaml read and merged (global + project-scoped); matched policies routed to correct priority section
- [ ] obligations.yaml evaluated and OBLIGATIONS section appended (or omitted if no file/triggered)
- [ ] No actions taken — only queries + rendering

## Tools

- **Jira via Atlassian MCP** — `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` (primary).<!-- BEGIN OVERLAY-FRAGMENT: briefing-jira-tools-fallback-note --> <!-- END OVERLAY-FRAGMENT: briefing-jira-tools-fallback-note -->
- **GitHub via `gh` CLI** — `gh pr list --author @me`, `gh pr list --search review-requested:@me`, `gh api graphql` (batched review-thread queries), `gh search prs --mentions @me`.
- **Google Calendar via MCP** (optional) — `mcp__claude_ai_Google_Calendar__list_events`. Skipped silently if MCP is not in the tool surface.
- **Slack via MCP** (optional) — `mcp__claude_ai_Slack__slack_search_public_and_private` (three queries: @mentions, DMs, thread replies). Skipped silently if MCP is not in the tool surface.
- **Jenkins via MCP** (optional, enrichment only) — `mcp__jenkins-mcp__get_multibranch_branch`, `mcp__jenkins-mcp__get_build_errors`, `mcp__jenkins-mcp__get_test_results`, `mcp__jenkins-mcp__get_recent_failures`. Skipped silently if MCP is not in the tool surface.
- **Filesystem reads** — `~/.claude/policies.yaml` (global), `.claude/policies.yaml` (project), `~/.claude/tasks/<project>/obligations.yaml` (active obligations).

## Resources

- **Output format spec** — see the [Output Format](#output-format) section below for the canonical render template, emoji key, and formatting rules.
- **Per-data-source query reference** — [Jira Queries](#jira-queries), [GitHub Queries](#github-queries), [Calendar Queries](#calendar-queries), [Slack Queries](#slack-queries) — full invocations + derived signals + API cost budgets.
- **Failure-mode reference** — see [Graceful Degradation](#graceful-degradation) for the comprehensive failure-mode table and the Calendar/Slack-vs-Jira/GitHub design distinction.
- **Policies integration** — see [Policies](#policies) for `policies.yaml` merge rules, condition evaluation, and `{variable}` interpolation reference.
- **Obligations integration** — see [Obligations](#obligations) for cross-session obligation evaluation and the OBLIGATIONS render block.
- **Invocation reference** — see [Invocation Modes](#invocation-modes) for manual / scheduled / RemoteTrigger invocation paths.
- **Companion skills** — `/schedule` (recurring briefing via cron), `/obligations` (manage tracked obligations), `/swarm` and `/pickup` (downstream actions on AWARENESS items), `/scout-reviewer` and `/ranger-reviewer` (downstream actions on ACTION NEEDED review-request items).

## Examples

**Manual morning invocation:**

```
User: /briefing

Briefing flow:
1. Step 1   — fires 4 Jira JQL queries in parallel via Atlassian MCP (sprint,
              recently-assigned, P0/P1, in-progress)
2. Step 1b  — Google Calendar MCP is in tool surface → list_events for
              today, filter cancelled/declined
3. Step 1c  — Slack MCP is in tool surface → 3 parallel queries (@mentions,
              DMs, thread replies); deduplicate by ts+channel
4. Step 2   — gh pr list --author @me + gh pr list --search
              review-requested:@me; then batched GraphQL for review threads
              (3 PRs, 1 query) + gh search prs --mentions @me
5. Step 2.5 — 2 PRs have failing CI; Jenkins MCP is in tool surface →
              parallel resolve+get_build_errors+get_test_results per PR
6. Step 3   — derive signals; sort by URGENT / ACTION NEEDED / SCHEDULE /
              COMMS / AWARENESS
7. Step 4   — render output; append OBLIGATIONS section after evaluating
              ~/.claude/tasks/<project>/obligations.yaml
8. User sees the prioritized briefing with copy-pasteable -> commands.
```

**Degraded invocation (Calendar + Slack MCPs absent):**

```
User: /sitrep

Briefing flow:
1. Step 1   — Jira queries fire normally
2. Step 1b  — Google Calendar MCP NOT in tool surface → silent skip
              (no degradation note shown — Calendar is optional)
3. Step 1c  — Slack MCP NOT in tool surface → silent skip
              (no degradation note shown — Slack is optional)
4. Step 2   — GitHub queries fire normally
5. Step 2.5 — Jenkins MCP NOT in tool surface → silent skip; CI items
              show check names only via existing gh data
6. Step 3   — derive signals from Jira + GitHub only
7. Step 4   — render output; SCHEDULE and COMMS sections omitted
              entirely (no events / messages to show)
8. Result: clean Jira+GitHub briefing without spurious "Calendar
   unavailable" warnings.
```

---

## Jira Queries

### Primary invocation (Atlassian MCP)

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql(
  jql="<query>",
  maxResults=25
)
```

<!-- BEGIN OVERLAY-FRAGMENT: briefing-jira-fallback-invocation -->
<!-- END OVERLAY-FRAGMENT: briefing-jira-fallback-invocation -->

If the primary tool returns an error or is unavailable, log `Jira unavailable — showing GitHub data only` and proceed.

---

## GitHub Queries

Run both commands via `Bash` tool:

```bash
gh pr list --author @me --state open \
  --json number,title,createdAt,reviewDecision,statusCheckRollup,isDraft,url \
  --limit 25
```

```bash
gh pr list --search "review-requested:@me" --state open \
  --json number,title,createdAt,url \
  --limit 10
```

**Derived signals (no additional queries needed):**
- Stale: `createdAt` > 3 days ago, `reviewDecision` is null or `"REVIEW_REQUIRED"`, `isDraft == false`
- Failing CI: `statusCheckRollup` contains any `FAILURE` or `ERROR` state
- Changes requested: `reviewDecision == "CHANGES_REQUESTED"`
- Draft promotable: `isDraft == true` AND `statusCheckRollup` all passing

#### Comment-monitoring queries

```bash
# Batched GraphQL: unresolved review threads on my PRs
# Run ceil(N/10) queries, each batching up to 10 PRs via GraphQL aliases.
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pr<NUMBER>: pullRequest(number: <NUMBER>) {
        number
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
      ... (up to 10 aliases per query)
    }
  }
'
```

```bash
# @mentions search (single query, O(1))
gh search prs --mentions @me --state open --repo {owner}/{repo} \
  --json number,title,url,author --limit 20
```

**Derived signals (from comment-monitoring queries):**
- Unresolved threads: for each PR, count `reviewThreads.nodes` where `isResolved == false`. If count > 0, the PR has unresolved threads.
- @mentions: PRs returned by the mentions search, MINUS any PR already in the `--author @me` set (exclude self-mentions on own PRs).

**API cost budget:**
- Review threads: ceil(N/10) GraphQL calls (max 3 for 25 PRs)
- @mentions: 1 search call
- Total additional calls: max 4 (for a user with 25 open PRs)

---

## Calendar Queries

**Prerequisite check:** Only run if `mcp__claude_ai_Google_Calendar__list_events` exists in the available tools list.

### Invocation

~~~
mcp__claude_ai_Google_Calendar__list_events(
  startTime="<today>T00:00:00",
  endTime="<tomorrow>T00:00:00",
  orderBy="startTime",
  pageSize=50
)
~~~

Compute `<today>` and `<tomorrow>` as ISO 8601 date strings based on the current date.

**Derived signals (no additional queries needed):**
- Imminent: events with `start.dateTime` within 30 minutes of current time
- Tentative: events where current user's `responseStatus == "tentative"`
- Conflicts: events where `start.dateTime < previous_event.end.dateTime` (detect by iterating sorted events)
- Availability windows: gaps of 60+ minutes between consecutive events (and before first / after last event within working hours 8am-6pm)
- All-day: events with `start.date` instead of `start.dateTime`

**Filtering:**
- Exclude `status == "cancelled"` events
- Exclude events where user's `responseStatus == "declined"`
- Exclude all-day events where the user is not an attendee (informational holidays, etc.)
- Exclude events that have already ended (end time < current time)

---

## Slack Queries

**Prerequisite check:** Only run if `mcp__claude_ai_Slack__slack_search_public_and_private` exists in the available tools list.

### Invocations

Run all three queries in parallel:

~~~
# Query 1 — @mentions (overnight)
mcp__claude_ai_Slack__slack_search_public_and_private(
  query="to:me after:<16h_ago_unix_ts>",
  sort="timestamp",
  sort_dir="desc",
  limit=20,
  include_context=false,
  response_format="concise"
)
~~~

~~~
# Query 2 — DMs (overnight)
mcp__claude_ai_Slack__slack_search_public_and_private(
  query="to:me after:<16h_ago_unix_ts>",
  channel_types="im,mpim",
  sort="timestamp",
  sort_dir="desc",
  limit=10,
  include_context=false,
  response_format="concise"
)
~~~

~~~
# Query 3 — Thread replies (overnight)
mcp__claude_ai_Slack__slack_search_public_and_private(
  query="to:me is:thread after:<16h_ago_unix_ts>",
  sort="timestamp",
  sort_dir="desc",
  limit=10,
  include_context=false,
  response_format="concise"
)
~~~

Compute `<16h_ago_unix_ts>` as the Unix timestamp for 16 hours before the current time. This lookback window covers overnight activity since the user's last likely work session.

**Deduplication:**
- Messages appearing in multiple queries are deduplicated by `ts` + `channel.id`
- Keep the first occurrence; discard duplicates

**Derived signals (from combined results):**
- DMs: messages from Query 2 results
- @mentions: messages from Query 1 that are NOT in DM channels (channel type is `public_channel` or `private_channel`)
- Thread activity: messages from Query 3
- Unique message count: total after deduplication

**API cost budget:**
- 3 search API calls total (all run in parallel)
- `concise` format + `include_context=false` minimizes token usage
- Total token budget: <2000 tokens for typical overnight volume

---

## Output Format

```
Briefing — {date}

URGENT ({count})
  PR #{n}  "{title}"  CI FAILING ({n} checks)
    {failure_summary}
    -> Type: gh pr checks {n}
  {KEY}  P1 Bug  "{summary}"  In Progress, no branch
    -> Type: Pickup {KEY}

ACTION NEEDED ({count})
  PR #{n}  "{title}"  {n} UNRESOLVED THREAD(S)
    -> Type: gh pr view {n} --web
  @mentioned in PR #{n} by @{author}  "{title}"
    -> Type: gh pr view {n} --web
  PR #{n}  "{title}"  STALE ({n} days, no review)
    -> Type: Ranger, review PR #{n}
  PR #{n}  "{title}"  CHANGES REQUESTED ({n} days ago)
    -> Type: gh pr diff {n}
  Review requested: PR #{n} by @{author}  "{title}"
    -> Type: Scout, review PR #{n}

SCHEDULE ({count} events, {available_hours}h available)
  {emoji} {start_time}-{end_time}  "{title}"  ({duration})
    {meeting_link_or_location}
  ...
  Next available: {time} ({duration} block)
  -> open calendar = Open Google Calendar

COMMS ({count} new)
  DMs:
    @{sender} in DM: "{text_preview}"  ({age})
      -> Type: Reply in Slack
  Mentions:
    @{sender} in #{channel}: "{text_preview}"  ({age})
      -> Type: Open in Slack ({permalink})
  Threads:
    #{channel} thread: "{text_preview}"  ({n} new replies)
      -> Type: Open in Slack ({permalink})

AWARENESS
  Sprint: {n} tickets ({n} Done, {n} In Progress, {n} To Do)
  New since last check: {KEY} "{summary}"
  Draft PRs: #{n} "{title}" (CI passing, consider promoting)
    -> Type: gh pr ready {n}

  -> swarm     = Swarm unstarted tickets ({n} To Do)
  -> pickup N  = Pick up a specific ticket
  -> x         = Dismiss
```

**Emoji key for SCHEDULE section:**
- `>>>` — event starting within 30 minutes (imminent — attention grabber, using `>>>` instead of emoji per project convention of no emojis)
- `[?]` — tentative event (needs RSVP decision)
- `[!]` — conflicting event (overlaps with another)
- (no prefix) — normal confirmed event

**Formatting rules:**
- No tables — use indented lists
- Counts in section headers: `URGENT (2)` so the user knows scope at a glance
- One-command actions on every item — every `->` line is copy-pasteable
- Truncate ticket summaries and PR titles to ~50 characters
- Omit any section with zero items entirely
- If Jira is unavailable, omit all Jira-sourced rows silently (but show the degradation note at the top)
- If GitHub is unavailable, omit all GitHub-sourced rows (show degradation note at top)
- SCHEDULE section: events sorted chronologically. Show times in 12h format (e.g., 9:30a-10:00a). Show availability windows as "Next available: 10:00a (2h block)". Omit events that have already ended.
- COMMS section: group by type (DMs first, then mentions, then threads). Within each group, sort by recency (newest first). Truncate message previews to ~60 characters. Show relative age (e.g., "2h ago", "overnight").
- If Calendar is unavailable, omit SCHEDULE section silently (but show degradation note at top).
- If Slack is unavailable, omit COMMS section silently (but show degradation note at top).
- SCHEDULE appears after ACTION NEEDED and before COMMS. COMMS appears after SCHEDULE and before AWARENESS. This ordering ensures the user sees: what's broken -> what needs response -> what's on the clock -> what's in comms -> what to be aware of.

---

## Invocation Modes

### Manual (works today)

```
/briefing
/sitrep
Sitrep, catch me up
What needs my attention?
```

Any of the above triggers this skill. Use at the start of a work session for a quick orientation.

### Session-scoped recurring (via `/schedule`)

To have the briefing run automatically each morning while a session is active:

```
/schedule
```

Then set up: `CronCreate(cron="7 9 * * 1-5", prompt="/briefing", recurring=true)`

This fires every weekday at 9:07am. CronCreate jobs auto-expire after 7 days and require an active session.

### Cross-session automation (future — RemoteTrigger)

For a true cross-session briefing that fires even without an open Claude Code window:

```
RemoteTrigger(action="create", body={
  name: "daily-briefing",
  description: "Morning situation report",
  allowed_tools: ["Bash", "mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql", "mcp__claude_ai_Google_Calendar__list_events", "mcp__claude_ai_Slack__slack_search_public_and_private"],
  prompt: "/briefing"
})
```

RemoteTrigger requires an external caller (macOS cron, CI schedule, Slack bot) to fire the trigger. This is a future enhancement — not available out of the box.

---

## Graceful Degradation

Follow the CLAUDE.md principle: degrade gracefully, never silently.

| Failure | Behavior | User sees |
|---|---|---|
| Jira MCP unavailable (both primary + fallback fail) | Skip all Jira rows | `Jira unavailable — showing GitHub data only` at top |
| `gh` auth error | Skip all GitHub rows | `GitHub: run 'gh auth login' to authenticate` at top |
| `gh` non-auth error | Skip all GitHub rows | `GitHub query failed: {error}` at top |
| Both Jira AND GitHub unavailable | No briefing content | `Cannot reach Jira or GitHub — briefing unavailable. Check MCP and gh auth status.` |
| Jira returns empty results | Treat as clean | Show "No sprint tickets found" in AWARENESS |
| `gh` returns no PRs | Treat as clean | Omit PR rows; no error |
| One Jira query fails, others succeed | Show what succeeded | `Note: {query-name} query failed — results may be incomplete` |
| Jenkins MCP unavailable | Skip CI enrichment | CI items show check names only (current behavior) |
| GraphQL review-thread query fails | Skip unresolved-thread signal | `Note: Could not check review threads — thread status unavailable` |
| `gh search` mentions query fails | Skip @mentions signal | `Note: Could not check @mentions — mention alerts unavailable` |
| Google Calendar MCP not connected (no `mcp__claude_ai_Google_Calendar__*` tools in system prompt) | Skip entirely — omit SCHEDULE section | No note needed (Calendar is optional enrichment) |
| Google Calendar MCP tool call fails | Skip SCHEDULE section | `Note: Calendar query failed — schedule unavailable` at top |
| Google Calendar returns empty (no events) | Treat as clean | Show "No meetings today" in SCHEDULE section (or omit section entirely — either is acceptable) |
| Slack MCP not connected (no `mcp__claude_ai_Slack__*` tools in system prompt) | Skip entirely — omit COMMS section | No note needed (Slack is optional enrichment) |
| Slack MCP tool call fails | Skip COMMS section | `Note: Slack query failed — message alerts unavailable` at top |
| Slack returns empty (no mentions/DMs) | Treat as clean | Omit COMMS section entirely |
| One Slack query fails, others succeed | Show what succeeded | `Note: {query-name} Slack query failed — results may be incomplete` |

**Important design decision:** When Calendar or Slack MCP is simply not connected (tools don't appear in the system prompt), we do NOT show a degradation note. This is different from Jira/GitHub where absence is a problem. Calendar and Slack are optional enrichment — their absence is the default state, not an error. We only show degradation notes when the tools ARE available but fail at runtime.

Never block the entire briefing on a single query failure. Partial data is better than no data.

---

## Policies

### Reading policies.yaml

At invocation, read policy files in this order:

1. `~/.claude/policies.yaml` — global policies (from dotfiles)
2. `.claude/policies.yaml` in the current git repo root — project-scoped policies (if present)

**Merge rules:**
- Project policies override global policies that share the same `name`. All other policies from both files remain active.
- Policies with `enabled: false` are skipped entirely.
- Validate `version: 1` at the top of each file. If an unknown version is encountered, warn in the briefing header and skip that file.

**Evaluating conditions:**

For each active policy:
- `source: github` — evaluate the condition against the GitHub query results already fetched in Step 2
- `source: jira` — evaluate the condition against the Jira query results already fetched in Step 1
- `type: jql_cross_reference` — run the specified JQL, then cross-reference results against GitHub data (branches, merged PRs)

**Rendering:**

Group matched policies by `priority` and map to the output format:
- `priority: urgent` → **URGENT** section
- `priority: action_needed` → **ACTION NEEDED** section
- `priority: awareness` → **AWARENESS** section

Use the `message` and `suggestion` fields as templates. Interpolate `{variable}` placeholders with live data.

**Available variables for interpolation:**

| Source | Variables |
|---|---|
| GitHub PRs | `{number}`, `{title}`, `{url}`, `{age}`, `{author}`, `{failed_checks}`, `{failure_summary}`, `{review_decision}` |
| GitHub PR threads | `{number}`, `{title}`, `{url}`, `{unresolved_count}` |
| GitHub PR mentions | `{number}`, `{title}`, `{url}`, `{author}` (PR author, not commenter) |
| Jira tickets | `{key}`, `{summary}`, `{status}`, `{priority}`, `{age}`, `{count}` |
| Calendar events | `{title}`, `{start_time}`, `{end_time}`, `{duration}`, `{minutes_until}`, `{meeting_link}`, `{location}`, `{time_range}`, `{title_1}`, `{title_2}` |
| Slack messages | `{count}`, `{senders}`, `{channels}`, `{sender}`, `{channel}`, `{text_preview}`, `{age}`, `{permalink}` |

**Fallback defaults:**

The analysis logic in Steps 3-4 (hardcoded thresholds) remains active as a fallback when no `policies.yaml` is present or when the file cannot be read. The 8 default policies defined in `~/.claude/policies.yaml` match these hardcoded thresholds exactly — the file is the canonical reference for what the defaults are.

---

## Obligations

### Checking obligations at briefing time

After completing Steps 1-4 (Jira queries, GitHub queries, analysis, rendering), check for active obligations:

1. **Resolve the file path:** `~/.claude/tasks/<project>/obligations.yaml` where `<project>` is `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
2. **Read the file.** If the file does not exist or is empty, skip this section silently.
3. **Evaluate each active obligation** using the evaluation loop from the `/obligations` skill:
   - For `gh_query` conditions: reuse GitHub data already fetched in Step 2 if the target PR is in the cached set. Only run additional `gh` commands for obligations targeting PRs not in the cache.
   - For `jql` conditions: reuse Jira data already fetched in Step 1 if the target ticket is in the cached set. Only run additional JQL queries for uncached targets.
   - For `time` conditions: compare against current timestamp (no external query).
4. **Render triggered obligations** in a new section after AWARENESS:

```
OBLIGATIONS ({count} triggered)
  [ob-001] PR #482 still waiting for review. Nudge reviewer?
    -> Type: gh pr view 482
  [ob-003] 4 sprint tickets still in To Do. Consider swarming them.
    -> Type: Swarm, pick up my unstarted tickets

  Evaluated: {total} active, {triggered} triggered, {expired} expired, {skipped} skipped (cooldown)
  -> /obligations = Manage obligations
```

5. **Clean up** — update expired/resolved obligations' status in the YAML and write back.
6. **If no obligations triggered** but active obligations exist, show a one-line summary: `Obligations: {n} active, none triggered. -> /obligations to manage`
7. **If no obligations file exists**, omit the section entirely.

### Performance constraint

Obligation evaluation should add <2 seconds to the briefing for up to 10 active obligations. Reuse cached Jira/GitHub data wherever possible.
