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
