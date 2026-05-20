<!-- Shared review-discipline fragment.
     Referenced by:
       - .claude/skills/scout-reviewer/SKILL.md
       - .claude/skills/ranger-reviewer/SKILL.md
     Edit here; both skills splice this content via sentinel-anchored blocks.
-->

<!-- BEGIN VERIFY-THEN-DRAFT -->
#### Verify findings before drafting comments

The reviewer agent (Scout or Ranger) returns confidence-scored findings. **A confidence score is the agent's self-assessment, not verification.** Before drafting any comment text, the orchestrator must trace each finding to the code:

1. **Read the cited function or block.** If the finding says "X happens at file.ts:42", open file.ts and read the surrounding context — not just line 42.
2. **Follow at least one call out.** If the finding claims a function "writes to the backend" or "fires a side effect", read the called function and confirm the side effect actually occurs. Stop at the first concrete answer (call resolves, gate condition is found, the trace dead-ends in a no-op).
3. **Check gating conditions.** Many false positives come from claims that ignore a guard upstream — e.g. "this handler fires on every keydown" when the handler bails out when `selectedBlockId` is null and an earlier code path clears it.
4. **Decide one of three actions per finding:**
   - **Confirmed** — trace supports the claim. Draft the comment.
   - **Narrowed** — the underlying issue is real but smaller than the agent claimed. Rewrite the finding to the smaller, accurate claim before drafting.
   - **Dropped** — trace contradicts the claim, or the issue collapses to a pedantic nit. Do not draft a comment.

**Hard rule: never lump a verified finding with an unverified one in the same comment.** If you bundle them, the unverified claim weakens the verified one in the author's eyes and the reviewer loses credibility on the whole comment. Verify each finding standalone before deciding whether to combine.

**Hard rule: a high confidence score (>=85) does not skip verification.** It biases priority — verify high-confidence findings first because they're more likely to matter — but verification is still required.

If verification cannot be completed (file no longer exists in the diff, trace blocks on a dependency the orchestrator cannot read, etc.), drop the finding and note "Could not verify — dropped" in the audit trail to the user. Do not draft a speculative comment.
<!-- END VERIFY-THEN-DRAFT -->

<!-- BEGIN FINDINGS-CRITIQUE -->
#### Findings Critique: bar-fit pass

After verifying each finding against the code (VERIFY-THEN-DRAFT) and before drafting any comment, stress-test each surviving finding against the senior-staff peer-review bar. Verification answers *"is this claim true?"*; this step answers *"does this claim matter?"* They are independent filters and both must pass.

For each verified finding, score it against four questions:

1. **Does it bend the codebase or just nick it?** A finding that nicks (a one-character spacing preference, a not-quite-idiomatic but functionally fine pattern, a style choice with no behavioral consequence) is a nit. Drop it.
2. **Would the author's action change after reading it?** If the comment is information-only — no fix prescribed, no question raised, no judgment requested — the author has nothing to do with it. Drop it.
3. **Is the severity tier (Blocker / Important / Suggestion) defensible if challenged?** If you cannot defend Important over Suggestion in one sentence, demote. If you cannot defend Suggestion over drop in one sentence, drop.
4. **Does the finding stand alone without the others?** If a finding only makes sense bundled with two others, combine or drop. A finding that only matters because the reviewer is also flagging X and Y is a bookkeeping concern, not a peer-review concern.

For each finding, output one line:

- ✅ `<finding short title>` — survives bar-fit
- ⚠️ `<finding short title>` — demoted from `<tier>` to `<tier>` because `<one sentence>`
- ❌ `<finding short title>` — dropped because `<one sentence>`

After the per-finding lines, output a single verdict line:

> **Findings Critique verdict:** REVIEW READY | NARROWED (N demoted, M dropped) | RETHINK (>50% of findings collapsed — re-prompt the agent before drafting).

**Hard rule: if the verdict is RETHINK, do not draft any comments.** Surface the verdict to the user, propose a re-prompt of the reviewer with explicit narrower scope, and gate on user approval before re-running.

**Hard rule: this pass is orchestrator-side, not agent-side.** The reviewer agent's confidence score is a self-assessment; same-model self-critique biases toward keeping its own findings. The orchestrator runs in a fresh context and is the credible demoter.

The orchestrator surfaces the entire critique block (per-finding lines + verdict) **above the gate menu**, so the user sees the bar-fit pass before choosing post / edit / approve / fix / done. If the user picks `e` (edit), the per-finding ⚠️/❌ lines double as a starting list of cuts.
<!-- END FINDINGS-CRITIQUE -->

<!-- BEGIN TONE-CALIBRATION -->
#### Calibrate tone to author seniority

The reviewer agent's default voice is "staff-level explanatory" — restate context, prescribe an A/B fix, frame findings as "verified concern is...". This voice is **correct** for reviewing junior or unfamiliar contributors and **wrong** for peer-to-peer review of a senior-staff PR, where a one-sentence question often lands better than a multi-paragraph explanation.

The orchestrator detects the author signal and offers a tone choice at draft time. **The default Ranger voice is not changed everywhere — the choice is made per review.**

### Author signal detection (best-effort)

Before drafting comments, infer the author signal from PR metadata. Order of preference:

1. **Bot author** (`author.is_bot` true, or username contains `dependabot`, `renovate`, etc.) → use **minimal** tone: state the issue and stop. No prescription, no positives section.
2. **Contributor history available** — run `gh api repos/{owner}/{repo}/contributors --jq '.[] | select(.login == "{author}") | .contributions'`. If the author has >=50 merged PRs in this repo, lean **peer**. If <10, lean **explanatory**.
3. **Otherwise**, defer to the user: ask before drafting (see prompt below).

If `gh` calls fail or are rate-limited, skip to step 3 (defer). Do not block on the lookup.

### Tone choice prompt

Before showing comment drafts, ask:

```
Tone for review comments:
  -> p = Peer (senior author) — short, question-led, no restated context, no A/B prescription
  -> e = Explanatory (default) — staff-level voice with context, A/B fix, rationale
  -> m = Minimal (bot or terse author) — state the issue and stop
  -> ? = I'll guess from author signal: <detected signal here>
```

In autonomous/swarm mode: auto-select based on detected signal. Default to explanatory if signal is ambiguous.

### Tone reference patterns

**Peer (one-sentence question or observation):**
> Does `editComplete()` here also persist? I read the trace as in-memory-only — flagging in case I missed a write.

**Explanatory (default Ranger):**
> Verified concern: when the user clicks Save and exit, the handler calls `editComplete()` but does not propagate to the backend. Two ways forward: (A) add a `persistDraft()` call before `editComplete()`, or (B) move persistence into `editComplete()` itself. Either is fine; (A) is the smaller diff.

**Minimal (bot/terse):**
> `editComplete()` does not persist — Save and exit will lose changes.

Both reviewers (Scout and Ranger) honor this choice; tone is a presentation concern, not a finding concern. The same finding renders in three voices.
<!-- END TONE-CALIBRATION -->

<!-- BEGIN ANCHOR-CONSTRAINTS -->
#### GitHub review comment anchoring rules

The GitHub `POST /repos/{owner}/{repo}/pulls/{number}/reviews` endpoint enforces hunk-locality on multi-line comments. Violating the rules returns HTTP 422 and the entire review (not just the offending comment) fails to post.

### Hard constraints

- **Both endpoints must be inside the diff.** `start_line` and `line` must each correspond to a line that appears in the unified diff for the PR (with the correct `side` — `LEFT` for removed/context-on-old, `RIGHT` for added/context-on-new). A line that is "untouched" but visible as context in the diff is in the diff; a line that does not appear at all is not.
- **Both endpoints must be in the same hunk.** A hunk is a `@@ -a,b +c,d @@` block. Two separate hunks in the same file are two separate hunks even if they are visually adjacent in the rendered diff. Anchoring across an untouched block (lines not shown in the diff because GitHub elided them) crosses hunks.
- **`side` must be consistent.** A multi-line comment cannot start on `LEFT` and end on `RIGHT`.
- **Single-line comments** (`line` only, no `start_line`) are the safest fallback.

### Fallback order

When drafting an anchor, attempt in order and use the first one that satisfies the constraints:

1. **Narrow multi-line within one hunk.** If the relevant logic is more than one line, anchor to the smallest contiguous range that captures it AND is fully inside one hunk.
2. **Single-line on the most relevant touched line.** If the multi-line range crosses a hunk boundary, drop to a single line — pick the most representative changed line (the line where the issue first manifests, not the line that ends the block).
3. **General PR conversation comment.** If neither inline anchor works (e.g. the issue spans untouched context that is not in any hunk), post as a `gh pr comment` general comment and reference file:line in the body text.

### Pending review semantics

When creating a pending review (so the user can preview before submit), **omit the `event` field from the payload**. Including `event: "COMMENT"`, `"APPROVE"`, or `"REQUEST_CHANGES"` submits the review immediately. The endpoint to create a pending review is:

```
POST /repos/{owner}/{repo}/pulls/{number}/reviews
{
  "body": "...",
  "comments": [
    { "path": "...", "line": 42, "side": "RIGHT", "body": "..." }
  ]
  // no "event" field — this leaves the review in PENDING state
}
```

To submit a pending review afterwards:

```
POST /repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}/events
{ "event": "COMMENT" }
```

### Pre-flight check (orchestrator-side)

Before posting, the orchestrator should run `gh pr diff <number>` and verify, for each drafted comment, that the `start_line` and `line` both appear in the same `@@` block. If they do not, downgrade per the fallback order above and re-draft the anchor (not the comment body) before sending. A 422 from GitHub is a process failure, not a content failure — it means the orchestrator skipped this check.
<!-- END ANCHOR-CONSTRAINTS -->
