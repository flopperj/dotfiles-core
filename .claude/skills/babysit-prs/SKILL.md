---
name: babysit-prs
description: "Watch open PRs under the built-in /loop — one tick per invocation: watch CI, review when ready, and (opt-in) fix, approve, or merge behind a reversibility × blast-radius gate. Use when the user types /babysit-prs, starts a prompt with 'Babysit', or asks to 'watch my PR', 'babysit this PR', 'watch these PRs and merge when green', or 'watch a channel for PRs'."
user-invocable: true
---

<!-- shape: checklist-v1 -->

# Babysit PRs

<!--
  Procedural skill (checklist-v1). NO companion agent persona — this SKILL.md is an
  orchestrator that composes the existing Scout/Ranger (via /code-auditor) and Cyrus
  agents. Do NOT create .claude/agents/babysit-prs.md.

  Helper scripts live under scripts/ (babysit-gate.sh, babysit-state.sh). `make lint`
  shellchecks them via the `.claude/skills/*/scripts/*.sh` glob in the Makefile's
  LINT_FILES, so CI keeps them clean; you can also run them directly:
      shellcheck .claude/skills/babysit-prs/scripts/*.sh
  Each babysit-gate.sh subcommand is a pure function (JSON/args in → decision token +
  reason on stdout, exit 0, no side effects); all gh/Slack/git mutations are owned by the
  Actor prose in this file, never by the scripts.
-->

## When to Use

- The user types `/babysit-prs`, starts a prompt with `Babysit, ...`, or asks to "watch my PR", "babysit this PR", "watch these PRs and merge when green", or "watch a channel for PRs".
- The intended invocation is **under the built-in `/loop`**, which owns cadence: `/loop <interval> /babysit-prs <targets> [flags]`. This skill performs **exactly one tick** of PR-babysitting work per invocation and is otherwise interval-agnostic (it never sleeps or schedules — it only emits a self-pace *hint*).
- The user wants a PR (their own or a teammate's) watched from "CI still running" through review, optional fix, and — for their own or explicitly-named PRs — optional approve/merge, without hand-refreshing the PR page.
- The user wants to point a loop at a Slack channel so PRs shared there are pulled onto the watchlist as they appear.

**Do not** use this skill for a one-off review (use `/code-auditor` → Scout/Ranger) or a one-off fix (use `/cyrus-tdd-engineer`). This skill is the *scheduler* that composes those as subagents across ticks.

### Targets and flags (parsed once, echoed at launch)

- **Seed targets**: PR numbers/URLs on the command line (e.g. `#482`, `owner/repo#491`, a full PR URL). Seeds are flagged `explicitly_named = true`.
- **Capability flags** (escalating, typed opt-in — the flag *is* the durable authorization; there is no per-action prompt):
  - `--review-only` (default): watch CI → review → report. Never mutates.
  - `--fix`: hand blocking findings and flake-guarded CI failures to Cyrus.
  - `--approve`: auto-approve clean PRs (including teammates' — approval is reversible).
  - `--merge`: merge when the strict gate passes and blast-radius is not high.
- **Tuning flags**: `--max-fix-attempts N` (default 3), `--repos owner/a,owner/b`, `--merge-method squash|merge|rebase`, `--slack #channel`, `--hold-above <threshold>` / `--no-hold-above`, `--until <time>`, `--until-empty`.

> The capability flags select *which* capability is enabled; the gate script (`scripts/babysit-gate.sh`) decides *how much unattended latitude* that capability has on a given PR. There is deliberately no third latitude-config surface — see the Actor half.

## Workflow

> **Internal split (one command, two concerns).** Behind the single `/babysit-prs` command this tick runs two internally-separated concerns: a read-only **Watcher** (this half — target resolution, one `gh pr view` read per PR, transition detection, CI classification) and an in-session **Actor** (the next half — the review → fix → approve → merge → settle engine that is the *only* half that mutates). The Watcher answers *"did anything change, and what?"* using **reads only**. It hands the Actor one small record per PR — `{pr_ref, transition_kind, routing_ctx}` — and does nothing else. Keeping the split internal (not a second command) is deliberate.

### Step 0 (WATCHER): Launch-time capability echo

**This is an echo, not a gate.** It does not prompt for confirmation — the typed flags are the authorization. Emit it **once, before the first tick's work**, then proceed.

1. Print a one-line summary of exactly which autonomous capabilities are enabled, e.g.:
   > `Babysitting 3 PRs — review + fix + merge enabled; approve off. Merge restricted to PRs you author or explicitly named.`
   Derive "review + fix + …" from the parsed flags; `--review-only` (the default) prints `review only — no mutation`.
2. Print a single-line accountability reminder, e.g.:
   > `You are accountable for what this loop approves or merges; review quality is bounded by the reviewer agent.`
3. Include the **who-can-be-merged reminder** verbatim in the echo: merge fires only for PRs you author or explicitly named — a teammate's PR **you did not name** can never be merged unattended (a Slack-discovered foreign PR tops out at review + fix + approve and is reported as "merge-ready, awaiting your OK"; naming a teammate's PR on the command line *is* your authorization to merge it, once the six-condition gate and size/files blast-radius clear). This is a plain-language restatement of the gate's blast-radius rule; the gate remains the enforcement point.

Do not re-print this echo on subsequent ticks (it is a launch banner, not a per-tick line).

### Step 1 (WATCHER): Resolve run identity and targets

Do this once at run start (resume-aware), then keep the resolved values in the run-level state via `scripts/babysit-state.sh`.

1. **Resolve `my_login` once per run**: `gh api user --jq .login`. Store it run-level (`state-set-run --run-id <id> --set my_login=<login>`). `authored_by_me` for every PR is `PR author == my_login`. Never hardcode a login.
2. **Resume-match or init the state file**:
   - Canonicalize the seed target set and try `babysit-state.sh state-load --targets "<seeds>"`. If it prints a `run_id`, resume that run (counters/history intact).
   - Otherwise `babysit-state.sh state-init --run-id <new-id> --flags "<verbatim flag string>" --my-login <login> --targets "<seeds>"`.
3. **Seed targets → watchlist**: add each command-line PR to the watchlist with `explicitly_named = true`. Seed PRs receive **no** Slack ack (they weren't discovered via Slack).
4. **Slack discovery (only when `--slack #channel` is set)**:
   - **Resolve the channel_id at runtime** — do not hardcode. Resolve `#channel` → `channel_id` via `slack_search_channels` and store it run-level (`state-set-run … --set slack.channel_id=<id> --set slack.enabled=true`).
   - **Resolve the loop's own Slack `user_id` at runtime** via `slack_search_users` / `slack_read_user_profile` (needed later so the Actor's human-deference check can tell a human reply from the loop's own ack). Do not hardcode it.
   - **Read only new messages**: call `slack_read_channel` with `oldest = <stored last_seen_ts>`, newest-first. On the first tick with no watermark, use a sensible recent bound rather than the full channel history.
   - **Extract PR URLs** from the new messages (GitHub PR URL / `owner/repo#N` patterns).
   - **Filter to the launch repo** by default, or to `--repos owner/a,owner/b` when set. Drop non-matching URLs so a busy channel doesn't add noise.
   - **Add new matches** to the watchlist with `explicitly_named = false` (discovered, not seeded) — these are the PRs the Actor may later post the single "🤖 babysitting" ack on.
   - **Advance `last_seen_ts`** to the newest message timestamp seen this tick (`state-set-run … --set slack.last_seen_ts=<ts>`), so the next tick never re-scans history.

> Slack in the Watcher is **read-only**. The one narrow Slack *write* (the discovered-PR ack) belongs to the Actor half, not here.

### Step 2 (WATCHER): Read PR state and compute the hand-off record

For **each** watched PR, do **one** `gh pr view --json` read per tick and compute the single Watcher→Actor hand-off record. No mutation, no review, no second read.

1. **One read per PR** — request all fields the tick needs in a single call, e.g.:
   ```
   gh pr view <pr> --json number,headRefOid,author,state,isDraft,mergeable,\
     reviewDecision,reviews,statusCheckRollup,additions,deletions,changedFiles,baseRefName
   ```
2. **Compute `routing_ctx`** — the facts the Actor and the gate need, derived from this read (no extra calls):
   - `authored_by_me` = `author.login == my_login`.
   - `explicitly_named` = the watchlist flag from Step 1 (seed vs discovered).
   - `head_sha` = `headRefOid`.
   - `last_review` = the stored `last_review` block for this PR from state (`sha`, `ci`, `reviewDecision`, `blockers`) — the change-detector; do not recompute a review here.
3. **Determine `transition_kind`** by comparing this read against the PR's stored record (`head_sha`, `last_review.ci`, `last_review.reviewDecision`, prior draft state). Emit exactly one of:
   - `newly_discovered` — first time this PR is seen this run.
   - `new_commit` — `head_sha` differs from the stored `head_sha` (this resets flake counters, fix_attempts, and fingerprints downstream per the locked mechanics — the Watcher only *reports* the change).
   - `ci_settled_green` — required-check set (Step 3) is all `SUCCESS`/`NEUTRAL` and CI was previously pending/failing.
   - `ci_failed` — a required check concluded `FAILURE` (hand to the Actor's flake-guarded path; the Watcher does not itself decide to fix).
   - `review_decision_changed` — `reviewDecision` differs from `last_review.reviewDecision` (e.g. a human just left `CHANGES_REQUESTED` or approved).
   - `draft_to_ready` — PR was draft and is now ready.
   - `no_change` — none of the above; nothing moved since the last tick.
4. **Emit the hand-off record** `{pr_ref, transition_kind, routing_ctx}` to the Actor half. On `no_change`, the Actor may cheap-poll or stay settled; the Watcher's job for this PR is done either way.

> **Terminal PRs shortcut:** if the stored `status` is `merged` or `closed`, skip the read entirely (terminal is terminal). A `settled` PR still gets the single `gh pr view` read — that read *is* the cheap change-detection poll that lets `babysit-gate.sh rearm?` decide whether to re-arm it.

### Step 3 (WATCHER): Classify CI

Fold this into the Step 2 read (`statusCheckRollup` is already fetched). It decides whether this PR is even reviewable this tick and feeds the flake guard.

1. **Determine the required-check set**:
   - Query branch-protection required checks: `gh api repos/{owner}/{repo}/branches/{baseRefName}/protection` and read `required_status_checks.contexts` (and any required check runs).
   - **Fall back to treating *all* checks as required** when branch protection is absent or the API returns nothing — absence of a required set must fail *safe* (gate on everything), never fail open.
2. **Classify the required set's aggregate conclusion** and pick the tick's next move for this PR:
   - **PENDING** (any required check still running) → **skip** this PR this tick. A review on code that may still change is wasted.
   - **SUCCESS** (all required checks green) → **reviewable** — hand to the Actor for the review stage.
   - **NEUTRAL / none configured** → **reviewable** — absence of checks is not a blocker; review it.
   - **FAILURE** (a required check concluded failed) → **flake-guarded**. Delegate the counter to the gate: `babysit-gate.sh flake-tick --check <name> --conclusion FAILURE --prior <ci_failures-json>` (pass `--new-sha` on a `new_commit` transition so all counters reset). A red check becomes actionable **only** once the *same name-matched check* (never the run ID) returns count `>= 2`. Match checks by **name**; run IDs change every execution and must not be used as identity.
3. **Persist the updated `ci_failures` map** for this PR via `state-write-pr` (the Watcher owns this read-derived counter update; the Actor consumes the armed/not-armed result). Any non-`FAILURE` conclusion for a check resets that check's count to `0`; a `new_commit` clears the whole map.

> **The Watcher stops here.** It has produced, per PR: the hand-off record, the reviewable/skip decision, and the armed/not-armed CI-failure state. It has made **zero** mutations. Everything that acts on this — human-deference, review, fix, approve, merge, settle, the Slack ack, and the stop-condition check — is the **Actor** half, authored next.

> **The Actor half begins here (one command, second concern).** Everything above is the read-only Watcher. Everything below is the in-session **Actor** — the *only* half that mutates. It consumes the Watcher's per-PR hand-off record and runs the review → fix → approve → merge → settle engine. **All four locked mechanics live here** (the six-condition merge gate, the flake guard, the progress-aware fix bound, the settled state) — but the Actor never *re-implements* a decision. Every gate is a call to `scripts/babysit-gate.sh`, which is the tested source of truth. The Actor's job is to gather facts, call the gate, and perform the I/O the gate's token authorizes.

### Per-PR processing is SEQUENTIAL within a tick

Process watched PRs **one at a time, in order** — never fan out in parallel. The state file is a single JSON document written by `scripts/babysit-state.sh`; sequential processing makes the Actor the **single writer** per tick, so no locking is needed and two PRs can never race a `state-write-pr`. Finish one PR's full sequence (Steps 4–9 below) and persist its record (Step 9) before starting the next PR.

For each watched PR the Watcher handed off (`{pr_ref, transition_kind, routing_ctx}`), run Steps 4 → 9 in order. A `HOLD` / `SKIP` / settle at any step ends that PR's processing for this tick — report the reason inline and move to the next PR. Then run Step 10 (stop conditions) **once** at the end of the tick.

> **Assemble the gate-facts blob once per PR.** Before calling `babysit-gate.sh`, build a small JSON `--pr` facts blob from the Watcher's single `gh pr view` read plus the CI classification: `{authored_by_me, explicitly_named, additions, deletions, changedFiles, ci, blockers, review_valid_for_head, human_changes_requested, mergeable, draft, state}`. `ci` is the *classified aggregate* from Step 3 (`SUCCESS` only when the required set is all green), not the raw rollup. `blockers` is the count of surviving blocking findings from the review valid for the current head SHA (0 until a review runs; the stored `last_review.blockers` when the SHA has not moved). This is the exact shape the gate's `decide` / `merge-gate` / `settle?` subcommands read — pass the same blob to each so every decision sees identical facts.

### Step 4 (ACTOR): Human-deference check — hold before acting

Before the Actor reviews, approves, or merges a PR, defer to a human who is already engaged. This is a **courtesy hold**, distinct from the permanent `CHANGES_REQUESTED` merge veto (which lives in the merge gate, Step 8).

1. **Gather the three engagement signals** from the Watcher's read (no extra mutation): `human_review_in_flight` (a human review is `PENDING` / in-flight or freshly submitted), `human_thread_reply` (a **non-bot, non-self** reply on the discovering Slack message), `human_approval_exists` (an existing human `APPROVED` review).
   - **Self / bot exclusion is load-bearing.** A reply from the loop's own Slack `user_id` (resolved in Step 1) or from any bot must **not** count as human engagement — otherwise the loop's own "🤖 babysitting" ack would make it defer to itself forever. Compute these three booleans with the self/bot filter applied before calling the gate.
2. **Call the gate:** `babysit-gate.sh defer? --pr <facts-with-engagement>`.
   - `PROCEED` → continue to Step 5.
   - `HOLD:human-engaged:<why>` → **hold this PR for this tick.** Report inline (e.g. `#491 held — a human review is in flight; deferring`) and skip Steps 5–8 for this PR. Still run Step 9 (settle/re-arm) so a deferred-but-clean PR parks cheaply rather than re-checking engagement every tick.

> Deference holds the *loop's* action; it is not itself a merge veto. Once the human finishes and the PR is clean, the next tick proceeds normally (unlike `CHANGES_REQUESTED`, which the merge gate blocks permanently).

### Step 5 (ACTOR): Review — only when the transition warrants it and the SHA moved

Reviews are the expensive step; run one only when it can change a decision.

1. **Decide whether to review at all.** Review this tick iff **both**:
   - the PR is reviewable (Watcher Step 3 said `SUCCESS` / `NEUTRAL` / no-checks — never `PENDING`), **and**
   - the code is unreviewed at this SHA: `head_sha != last_review.sha` (SHA moved since the last clean review), **or** `transition_kind` is one that invalidates the prior review (`new_commit`, `newly_discovered`).
   - **SHA-validity caching:** if `head_sha == last_review.sha`, the stored review is still valid — **do not re-review.** Reuse `last_review.blockers` as the blocker count. This is the correctness guarantee that the reviewed code is the code being approved/merged, without paying for a redundant pass on frozen code.
2. **Dispatch the review through `/code-auditor` routing** (never a bespoke reviewer here): the auditor analyzes complexity and routes to Scout (lighter) or Ranger (deeper). Pass the PR number and any ticket context. The Actor composes the reviewer as a subagent; it does not re-implement review logic.
3. **Extract blocking findings → fingerprints.** From the reviewer output, take only the **blocking** findings. For each, compute a stable fingerprint via `babysit-gate.sh fingerprint --file <path> --category <cat> --claim <text>` — deliberately **line-number-independent**, so a finding that only moved lines is the *same* fingerprint. Store the fingerprint set and the blocker count in `last_review` (with `last_review.sha = head_sha`).
4. **Report** the review outcome inline (clean, or N blockers with their categories).

> The review's *decisions* about severity/verification are Scout/Ranger's job (verify-then-draft, findings-critique). The Actor only consumes the blocker set and reduces it to fingerprints for convergence tracking.

### Step 6 (ACTOR): Fix — only under `--fix`, behind the flake guard and the progress-aware bound

The fix path is guarded by **three** locked mechanics the Actor applies **before** calling the gate. The gate's `fix` decision is flag-only (`babysit-gate.sh decide --action fix` returns `ALLOW` whenever `--fix` is set); the *real* fix gating is these three guards.

1. **Capability gate:** `babysit-gate.sh decide --action fix --pr <facts> --flags <flags>`. `HOLD:fix-capability-off` → `--fix` is not set; skip fixing entirely (review-only for this PR).
2. **What is fixable this tick** — union of two sources:
   - **Blocking review findings** from Step 5 (already fingerprinted).
   - **Flake-guarded CI failures.** A red required check is fixable **only** once the *same name-matched* check (never the run ID) has failed on **two consecutive ticks** — i.e. `babysit-gate.sh flake-tick` returned `>= 2` for it in Watcher Step 3. A check below 2 is treated as a possible flake and left alone this tick.
3. **Progress-aware attempt bound** (default cap 3, `--max-fix-attempts N` overrides):
   - If `fix_attempts >= cap` for this PR → **stop.** Mark `status = needs-human`, drop to review-only for the rest of the run, report the reason (`#482 needs-human — still has N blockers after 3 fix attempts`).
   - **Non-convergence early stop (before exhausting the cap):** after each dispatch, recompute the surviving blocker fingerprints and call `babysit-gate.sh converged? --prior <fingerprints-before> --surviving <fingerprints-after>`. `STOP:non-convergence` (≥ 1 prior fingerprint survived the dispatch) → **stop immediately**, mark `needs-human`, report — do not burn the remaining attempts. `CONVERGED` (the survivors are all *new* blockers, none repeated) → a fresh blocker is progress; it starts its own history and may be fixed within the remaining cap.
4. **Dispatch Cyrus** (the only agent allowed to write fix code) with: the blocking findings, and — for CI failures — the failing job logs. Gather logs from `gh run view <run-id> --log-failed` (GitHub Actions) or the Jenkins MCP (`get_failed_stages` → `get_build_errors`) when the check is a Jenkins job. Increment `fix_attempts`.
5. **Reset rules (the Actor honors what the Watcher reported):**
   - A **new commit by a human** (head SHA moved to a **non-Cyrus** author) resets `fix_attempts` **and** `blocker_fingerprints` — when the user steps in to unblock the hard part, the loop resumes from a clean slate. (A `new_commit` transition also cleared the flake `ci_failures` map in Watcher Step 3.)
   - **Cyrus's own commits do NOT reset** the attempt/fingerprint history — otherwise the bound could never be reached.

### Step 7 (ACTOR): Approve — only under `--approve`, once per head SHA

1. **Gate:** `babysit-gate.sh decide --action approve --pr <facts> --flags <flags>`.
   - `HOLD:approve-capability-off` → `--approve` not set; skip.
   - `HOLD:not-clean-<condition>` → the clean predicate (the six-condition gate, authorship *not* consulted) failed; report which condition and skip.
   - `HOLD:blast-radius-<size|files>` → the **size/files** valve held it (a large blast-radius change gets your eyes even when clean). **Foreign-authorship never holds approve** — approving others' PRs is the whole point, and GitHub blocks self-approval anyway.
   - `ALLOW` → proceed.
2. **Once-per-SHA dedup:** before posting, confirm this head SHA is not already approved: `babysit-gate.sh auto-approve? --pr <facts> --flags <flags> --approved-sha <stored-approved-sha> --head-sha <head_sha>`. `SKIP:already-approved-this-sha` → no-op (never stack duplicate approvals tick after tick). `SKIP:own-pr-self-approval-blocked` → own PR; approve is a no-op (merge, if enabled, proceeds on its own gate in Step 8). `APPROVE` → post.
3. **Post a peer-toned, 🤖-marked approval** via `gh pr review --approve`: short, plain, a colleague's LGTM (what was checked, that it's clean, done) — **not** a dense staff-level explanation. Prefix the body with `🤖 ` per the Automated Comment Marker rule. Record `approved = true` with the current head SHA in state so the dedup re-arms only when the SHA moves.

### Step 8 (ACTOR): Merge — only under `--merge`, behind the strict gate AND blast-radius

<!-- WHY the merge gate is shaped this way (the precedence flip — read before editing):
     Merge eligibility USED to be "authored_by_me OR explicitly_named". It is NOW
     "the strict six-condition merge gate holds AND blast-radius != high", with
     authorship folded in as ONE of three blast-radius OR-clauses. Because a foreign
     PR is high blast-radius, a teammate's PR can never merge unattended — but that
     conclusion is now DERIVED from the reversibility × blast-radius gate, not a
     bolted-on standalone authorship predicate. The Actor CALLS the gate; it never
     re-derives merge eligibility here. -->

1. **Gate:** `babysit-gate.sh decide --action merge --pr <facts> --flags <flags>`. This is the strict/irreversible end — the six-condition gate **and** blast-radius `!= high`, in one call.
   - `HOLD:merge-capability-off` → `--merge` not set; skip.
   - `HOLD:draft` / `HOLD:human-changes-requested` / `HOLD:ci-not-green-<x>` / `HOLD:blockers-<n>` / `HOLD:stale-review-sha` / `HOLD:not-mergeable-conflict-<x>` / `HOLD:state-terminal-<x>` → the six-condition gate blocked; **report WHICH condition** blocked so the user sees at a glance what is holding the PR.
   - `HOLD:blast-radius-<size|files|foreign-author>` → blast-radius is high. A **foreign** PR that is otherwise clean lands here (`foreign-author`) — report it as **"merge-ready, awaiting your OK"** (surfacing others' work never crosses into merging it). A large **own** clean PR lands here (`size` / `files`) — held for your explicit OK (the size valve).
   - `ALLOW` → merge.
2. **Merge** via `gh pr merge`: **squash when the repo allows it**, else the repo default. Resolve allowed methods from `gh api repos/{owner}/{repo}` (`squashMergeAllowed` etc.); `--merge-method squash|merge|rebase` overrides. Set `status = merged` (terminal) and report the merge inline.

> **`--merge` never merges a teammate's PR.** That is not a special-cased rule bolted on top — it *falls out* of the gate: foreign-authorship makes blast-radius high, and merge requires blast-radius `!= high`. The one-line WHY comment above records the precedence flip; the gate script is the enforcement point.

### Step 9 (ACTOR): Settle / re-arm, then persist the PR record

1. **Settle decision:** `babysit-gate.sh settle? --pr <facts> --flags <flags>`.
   - `WATCHING` → the PR can still advance toward merge this run (e.g. `--merge` is on and a merge would fire once a transient block clears); keep it in `watching` and let the next tick re-run the full sequence.
   - `SETTLE` → clean-but-can't-advance (not mergeable this tick in a way this tick can change — foreign blast-radius, a parked human `CHANGES_REQUESTED`, or draft). Set `status = settled`. A settled PR gets only the **cheap `gh pr view` change-detection poll** next tick (Watcher Step 2), not a fresh review/fix/merge pass.
2. **Re-arm check (for a PR that was already settled):** `babysit-gate.sh rearm? --last <stored-last_review> --pr <facts-with-head_sha-ci-reviewDecision-draft>`.
   - `REARM:<sha|ci|reviewDecision|draft-to-ready>` → a watched signal changed; flip `status` back to `watching` so the next tick processes it fully. **This is how a merge-authorized PR blocked only by a human `CHANGES_REQUESTED` merges the tick after the human clears it** — the cleared review is a `reviewDecision` change that re-arms it.
   - `STAY-SETTLED` → nothing changed; the poll was a no-op.
3. **Persist the per-PR record — single-writer, end of each PR.** Write the updated record (`head_sha`, `ci_failures`, `fix_attempts`, `blocker_fingerprints`, `last_review`, `approved`, `status`) via `babysit-state.sh state-write-pr --run-id <id> --pr <n> --record <json>`. Because processing is sequential (single writer), this needs no lock; the helper's atomic write-temp-then-rename keeps the file valid on disk.

> `merged` / `closed` are **terminal** (never re-armed — the Watcher skips the read entirely next tick). `settled` is **re-armable**. `needs-human` is **latched for the run** (a human commit resets its attempt/fingerprint history but does not auto-un-latch `needs-human`; re-launching the loop clears it).

### The narrow Slack write — exactly one ack on DISCOVERED PRs

This is the Actor's **only** Slack write; Slack is otherwise read-only (the existing on-behalf-of-user Slack PR-post/reaction protocol is untouched).

1. **Scope:** post the ack **only** on a PR that was **discovered via `--slack`** (`explicitly_named = false`). **Seed PRs named on the command line get no ack** — they were not discovered.
2. **Own-ack recognition (dedup):** before posting, check whether the loop already posted its "🤖 babysitting" ack on this PR's discovering message (match by the loop's own Slack `user_id` from Step 1). If found, **do not re-post** — the Slack-visible ack doubles as cross-tick, cross-*teammate* dedup, complementing the state file's own-process dedup.
3. **Post exactly once, as a threaded reply:** `🤖 babysitting this PR (#NNN)` on the discovering message's thread. The 🤖 prefix is required per the Automated Comment Marker rule. **Reaction fallback:** a reaction (e.g. `:eyes:`) is preferred but the current hosted Slack connector cannot add reactions — so the ack is a threaded reply; add a reaction *in addition* only if a connector exposing `reactions.add` is present.

### Self-pace hint (interval-agnostic)

The skill never sleeps or schedules — `/loop` owns cadence. At the end of a tick, emit a **hint** sized to this tick's activity so a bare `/loop /babysit-prs` (no interval) can self-pace:

- **~5 minutes** while actively **fixing or merging** (stays within the prompt-cache window for cheap polls).
- **~20–30 minutes** while **only watching** (nothing to advance; don't burn tokens on needless wake-ups).

This is a hint only; an explicit `/loop <interval>` always wins.

### Step 10 (ACTOR): Stop conditions — read the REAL wall-clock at tick start

Evaluate stop conditions **once per tick**, using the wall-clock time **read at the start of this tick** — never a time trusted from the schedule. `/loop` ticks can fire late or be skipped while the session is busy; reading the real clock is a *correctness dependency of `--until`*, not a nicety.

1. **Read `now`** at tick start: `TZ=<zone> date +%s` (timezone defaults to the user's local zone, overridable). Convert `--until <time>` (e.g. `5pm`) to an epoch once.
2. **Call the gate:** `babysit-gate.sh stop? --flags <flags> --now <now-epoch> --until <until-epoch|empty> --all-terminal <true|false>`, where `all-terminal` is true iff every watched PR is `merged` / `closed` / `settled-with-nothing-to-do`.
   - `STOP:until-time-reached` → the real `now` has reached/passed `--until` (**including the late-tick case** where `now` is already past the boundary — the gate stops rather than sailing past). Emit the end-of-run recap and do not schedule another tick.
   - `STOP:all-terminal-empty` → `--until-empty` and everything watched is done. Recap and stop.
   - `CONTINUE` → schedule the next tick per the self-pace hint.
3. **End-of-run recap** (on any `STOP`): per PR, its final `status` and the last gate reason (`HOLD:<...>` / merged / needs-human), so a returning human can reconstruct what happened while away.

### Observability — the state file IS the audit log

Every gate `HOLD:<reason>` the Actor echoes inline is *also* stored in the per-PR record (`status`, `last_review`, `ci_failures`, `fix_attempts`), so "why didn't it merge #491?" is always answerable after the fact from `~/.claude/tasks/<project>/babysit-prs/<run_id>.json`. The file persists after the run for inspection. Inline narration is the live surface; the state file is the durable one.

## Checklist

**Watcher (read-only) — per run and per tick:**

- [ ] Launch-time capability echo printed once (enabled capabilities + accountability line + who-can-be-merged reminder) — echo, not a gate
- [ ] `my_login` resolved once via `gh api user --jq .login` and stored run-level
- [ ] State file resumed (`state-load` on the target set) or initialized (`state-init`); counters/history intact on resume
- [ ] Seed targets added with `explicitly_named = true`; seed PRs get no Slack ack
- [ ] Slack (if `--slack`): `channel_id` and the loop's own `user_id` resolved at runtime (never hardcoded); `slack_read_channel` uses `oldest = last_seen_ts`, newest-first; PR URLs extracted, filtered to launch repo / `--repos`; `last_seen_ts` advanced
- [ ] Exactly one `gh pr view --json` read per non-terminal PR per tick (terminal PRs skipped)
- [ ] Hand-off record `{pr_ref, transition_kind, routing_ctx}` computed per PR; exactly one `transition_kind` assigned
- [ ] Required-check set = branch-protection required checks when defined, else all checks (fails safe, never open)
- [ ] CI classified PENDING→skip / SUCCESS→review / NEUTRAL|none→review / FAILURE→flake-guarded
- [ ] Flake counter delegated to `babysit-gate.sh flake-tick` (name-matched, not run-ID; `--new-sha` on `new_commit`); `ci_failures` persisted; a red check arms only at count ≥ 2
- [ ] Watcher made zero mutations (no review, no fix, no approve, no merge, no Slack write)

**Actor (in-session, the only mutating half) — per PR, sequential within a tick:**

- [ ] PRs processed **sequentially** (single-writer state); one PR's full sequence + `state-write-pr` completes before the next PR starts
- [ ] Gate-facts `--pr` blob assembled once per PR from the Watcher read + CI classification; the same blob passed to every gate call
- [ ] Human-deference checked via `babysit-gate.sh defer?` (self/bot-filtered); `HOLD:human-engaged` holds the loop's action for the tick (distinct from the permanent `CHANGES_REQUESTED` merge veto)
- [ ] Review run only when reviewable AND the SHA moved (`head_sha != last_review.sha`); dispatched via `/code-auditor` (never a bespoke reviewer); SHA-valid review reused, not re-run
- [ ] Blocking findings reduced to line-number-independent fingerprints via `babysit-gate.sh fingerprint`
- [ ] Fix (`--fix` only) behind the flake guard (same name-matched check `>= 2`), the attempt bound (default 3, `--max-fix-attempts` overrides), and the non-convergence early stop (`babysit-gate.sh converged?` → `STOP` marks `needs-human` immediately)
- [ ] Cyrus is the only agent dispatched to write fix code, given findings + failing logs (`gh run view --log-failed` / Jenkins MCP); a human commit resets `fix_attempts` + fingerprints, a Cyrus commit does not
- [ ] Approve (`--approve` only) via `babysit-gate.sh decide --action approve`; held only by the **size/files** blast-radius signal, never foreign-authorship; posted peer-toned + 🤖-marked, once per head SHA (`auto-approve?` dedup)
- [ ] Merge (`--merge` only) via `babysit-gate.sh decide --action merge` (six-condition gate AND blast-radius `!= high`); a foreign clean PR HOLDs via the blast-radius clause and is reported "merge-ready, awaiting your OK"; on HOLD the **blocking condition is named**; squash when allowed else repo default (`--merge-method` overrides)
- [ ] Settle / re-arm via `babysit-gate.sh settle?` / `rearm?`; settled PRs get only the cheap `gh pr view` poll; a `reviewDecision` re-arm merges the tick after a human clears `CHANGES_REQUESTED`
- [ ] Per-PR record persisted via `babysit-state.sh state-write-pr` at the end of each PR (single-writer, atomic)
- [ ] Slack ack posted **only** on discovered PRs (`explicitly_named = false`), exactly once (own-ack dedup), as a 🤖-prefixed threaded reply; seed PRs get no ack
- [ ] Self-pace hint emitted (~5 min fixing/merging, ~20–30 min watching) — a hint only; explicit `/loop <interval>` wins
- [ ] Stop conditions evaluated once per tick via `babysit-gate.sh stop?` using the **real wall-clock read at tick start**; `--until` never sails past on a late tick; end-of-run recap emitted on any STOP

## Tools

- **`scripts/babysit-gate.sh`** — the tested decision core. Subcommands: `decide` (the reversibility × blast-radius gate), `merge-gate`, `blast-radius`, `flake-tick`, `fingerprint`, `converged?`, `settle?`, `rearm?`, `auto-approve?`, `defer?`, `stop?`. Every subcommand is a pure function (JSON/args in → token + reason on stdout, exit 0, no side effects). Shellchecked by `make lint` (via the `.claude/skills/*/scripts/*.sh` glob); its behavior is covered by `tests/babysit-gate.bats`.
- **`scripts/babysit-state.sh`** — the per-run JSON state store: `state-init`, `state-load` (resume-match), `state-read-pr`, `state-write-pr`, `state-set-run`. Atomic write-temp-then-rename (refuses to commit empty content); single-writer per tick (no locking). Shellchecked by `make lint`; covered by `tests/babysit-state.bats`.
- **`data/state-schema.json`** — documents and round-trip-fixtures the per-run state shape.
- **`gh` CLI** — `gh api user` (login), `gh pr view --json` (the one read per PR), `gh api repos/.../branches/.../protection` (required checks), `gh run view --log-failed` (failing logs), `gh pr review --approve`, `gh pr merge`, `gh api repos/{owner}/{repo}` (allowed merge methods).
- **Agent tool** — composes `/code-auditor` → Scout/Ranger for review, and `cyrus-tdd-engineer` for fixes. This skill never reviews or writes fix code itself.
- **Jenkins MCP** — `get_failed_stages` → `get_build_errors` for failing-stage logs when a required check is a Jenkins job.
- **Slack MCP** — `slack_search_channels` / `slack_search_users` / `slack_read_channel` / `slack_read_user_profile` (read-only discovery + self-id) and one narrow threaded-reply write (the discovered-PR ack).

## Resources

- **Driver** — the built-in `/loop` (owns cadence + `ScheduleWakeup`; this skill is interval-agnostic and emits only a self-pace hint).
- **Review router** — `/code-auditor` (picks Scout vs Ranger by complexity); companion reviewers `/scout-reviewer`, `/ranger-reviewer`.
- **Fix implementer** — `/cyrus-tdd-engineer` (the only agent allowed to write fix code).
- **State home** — `~/.claude/tasks/<project>/babysit-prs/<run_id>.json` (+ `latest.json` symlink); persists after the run for inspection.
- **Global rules** — `~/.claude/AGENTS.md` § "Automated Comment Marker — 🤖 prefix" (the ack + approval markers) and the PR-review draft-first rules.
- **Sibling prior art** — `oncall-pr-review-loop` (the accountability echo, defer-to-in-flight-human, own-ack dedup, reaction→threaded-reply fallback, wall-clock robustness, and size/complexity hold valve were borrowed from it).

## Examples

Each example fixes a **snapshot of facts** (the gate-facts `--pr` blob + `--flags`) and asserts the **decision the tick reaches**. Because every decision is delegated to `scripts/babysit-gate.sh`, the tokens below are exactly what `tests/babysit-gate.bats` asserts — the wiring here, the correctness in the tested helper.

### Example 1 — Own clean small PR under `--merge`: it merges

**Invocation:** `/loop 10m /babysit-prs #482 --fix --approve --merge`

**Facts** (Watcher read of #482, authored by me, green, no blockers, small):

```json
pr    = {"authored_by_me": true, "explicitly_named": true, "additions": 40, "deletions": 10,
         "changedFiles": 3, "ci": "SUCCESS", "blockers": 0, "review_valid_for_head": true,
         "human_changes_requested": false, "mergeable": "MERGEABLE", "draft": false, "state": "OPEN"}
flags = {"review_only": false, "fix": true, "approve": true, "merge": true,
         "size_threshold": 400, "files_threshold": 20, "hold_above": true}
```

**Tick trace:**
1. Step 4 `defer?` → `PROCEED` (no human engaged).
2. Step 5 — SHA unchanged since a clean `last_review`; review reused, `blockers = 0`.
3. Step 6 — `--fix` on but nothing to fix (0 blockers, no red checks); no dispatch.
4. Step 7 `decide --action approve` → own PR, so Step 7's `auto-approve?` returns `SKIP:own-pr-self-approval-blocked` (GitHub blocks self-approval); approve is a no-op.
5. Step 8 `decide --action merge` → **`ALLOW`** (six conditions hold; blast-radius `low`).

**Decision:** **merge #482** (squash if allowed), `status = merged` (terminal).

### Example 2 — Foreign clean small PR under `--approve --merge`: approved, merge HELD (the precedence flip)

**Invocation:** `/loop 15m /babysit-prs --slack #eng-prs --approve --merge` (PR #491 discovered in the channel)

**Facts** (green, no blockers, small, but **not mine and not explicitly named**):

```json
pr    = {"authored_by_me": false, "explicitly_named": false, "additions": 40, "deletions": 10,
         "changedFiles": 3, "ci": "SUCCESS", "blockers": 0, "review_valid_for_head": true,
         "human_changes_requested": false, "mergeable": "MERGEABLE", "draft": false, "state": "OPEN"}
flags = {"review_only": false, "fix": false, "approve": true, "merge": true,
         "size_threshold": 400, "files_threshold": 20, "hold_above": true}
```

**Tick trace:**
1. Slack ack posted once as a 🤖-prefixed threaded reply on the discovering message (discovered PR; own-ack dedup on later ticks).
2. Step 4 `defer?` → `PROCEED`.
3. Step 7 `decide --action approve` → **`ALLOW`** (clean; approve is held *only* by the size/files signal, and this PR is small — foreign-authorship never holds approve). Post a peer-toned 🤖 approval, once per SHA.
4. Step 8 `decide --action merge` → **`HOLD:blast-radius-foreign-author`**. A teammate's PR can never merge unattended — and the hold **attributes to blast-radius, not to a standalone authorship predicate** (the precedence flip). Report **"#491 merge-ready, awaiting your OK."**

**Decision:** **approve #491, HOLD merge**; report awaiting-OK. Step 9 `settle?` → `SETTLE` (can't advance this run) → next tick is the cheap poll until a signal re-arms it.

### Example 3 — Red CI that survives the flake guard under `--fix`, then non-convergence → needs-human

**Invocation:** `/loop 5m /babysit-prs #503 --fix`

**Tick N** — `unit-tests` required check is `FAILURE` for the **first** time:
- Watcher Step 3 `flake-tick --check unit-tests --conclusion FAILURE --prior '{}'` → `1`. Below 2 → treated as a possible flake, **not** fixed this tick.

**Tick N+1** — same `unit-tests` check `FAILURE` again, same head SHA:
- Watcher Step 3 `flake-tick --check unit-tests --conclusion FAILURE --prior '{"unit-tests":1}'` → `2`. **Armed.**
- Step 6 — capability `decide --action fix` → `ALLOW` (`--fix` set). Fingerprint the failure, dispatch Cyrus with the failing logs (`gh run view <run> --log-failed`). `fix_attempts` → 1.

**Tick N+2** — Cyrus committed, but the **same-fingerprint** blocker is still present:
- Step 6 recompute survivors, `converged? --prior <fp-before> --surviving <fp-after>` → **`STOP:non-convergence`** (≥ 1 prior fingerprint survived the dispatch).

**Decision:** **stop immediately** (do not burn the remaining attempts), set `status = needs-human`, drop to review-only, report `#503 needs-human — CI blocker did not converge after a fix`. A later **human** commit (non-Cyrus SHA) resets `fix_attempts` + fingerprints; re-launching the loop clears the `needs-human` latch.

## Responsibility boundaries

<!-- The BEGIN/END sentinels + the "Sole responsibility" / "NEVER does" table header
     below are required by scripts/lint-agents.sh for any skill carrying a
     "## Responsibility boundaries" section. The table is generated by
     scripts/boundaries-gen.sh (make gen-boundaries) — do not hand-edit its rows. -->

<!-- BEGIN RESPONSIBILITY BOUNDARIES -->
| Agent | Sole responsibility | NEVER does |
|---|---|---|
| **Aristotle** | Strategic analysis — assumptions, first principles, highest-leverage direction | Name file paths, produce code, plan execution, review PRs |
| **Optimus** | Execution planning — file paths, step sequencing, risk assessment, architecture | Write code, make file edits, run commands, re-litigate upstream strategic decisions, review PRs |
| **Cyrus** | TDD implementation — write tests first, then code, hit 80%+ coverage | Redesign architecture, question strategic direction, skip tests, review PRs |
| **Ranger** | Staff-level PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Scout** | PR review — analyze diffs, score issues, report findings | Write code, make edits, implement fixes, plan architecture, perform strategic analysis |
| **Auditor** | Code complexity analysis, reviewer routing | Write code, review code, post to GitHub, implement fixes |
<!-- END RESPONSIBILITY BOUNDARIES -->

`/babysit-prs` is an **orchestrator**, not a persona. It has **no companion agent file** — it composes the existing agents as subagents and owns only the scheduling, gating, and I/O glue:

- **Composes, never re-implements.** Reviews go through `/code-auditor` → Scout/Ranger; fixes go to Cyrus. This skill does not review code or write fix code itself — if it drifts into either, that is a boundary violation.
- **Decides via the tested gate, never inline.** Every accept/hold/settle/stop decision is a call to `scripts/babysit-gate.sh`. The Actor gathers facts and performs the I/O the returned token authorizes; it does **not** re-derive merge eligibility, flake arming, convergence, or stop timing in prose. The script is the single source of truth for those decisions (and the only part with unit tests).
- **Mutates only through the Actor half, only under the matching flag.** The default (`--review-only`) never mutates. Fix requires `--fix`, approve requires `--approve`, merge requires `--merge`. Each flag is durable authorization for the named/authored PR set — but merge eligibility is still the gate's call, not the flag's.

**Out of scope (locked — these never happen, by design):**

- **Autonomous merge of a teammate's PR.** Foreign PRs top out at review + fix + approve; merge is held via the blast-radius clause and reported "awaiting your OK." This is derived from the gate, not a bolted-on rule.
- **Promoting a draft to ready.** The loop never changes draft status; a draft is an author's explicit hold.
- **General Slack posting.** The only write is the single "🤖 babysitting" ack on discovered PRs; everything else on Slack is read-only.
- **A bespoke scheduler / headless-cron watching.** Cadence is entirely `/loop`'s job; watching lives and dies with the session (no daemon, no cron).
- **Re-implementing review or fix logic**, or **adding a per-capability latitude config surface** (the flags select the capability; the gate decides the latitude — there is deliberately no third surface).
