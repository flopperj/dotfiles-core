#### Calibrate tone to author seniority

The reviewer's default voice is **peer** — a short question or observation, with no restated context and no A/B prescription. A one-sentence question lands better with a senior author than a multi-paragraph explanation. **Explanatory** is the opt-in voice for junior or unfamiliar contributors: it restates context, prescribes a fix, and explains rationale — correct for that audience, condescending noise for a peer.

The default is peer for both reviewers; the per-review tone prompt can override it.

### Author signal detection (best-effort)

Before drafting comments, infer the author signal from PR metadata. Order of preference:

1. **Bot author** (`author.is_bot` true, or username contains `dependabot`, `renovate`, etc.) → use **minimal** tone: state the issue and stop. No prescription, no positives section.
2. **Contributor history available** — run `gh api repos/{owner}/{repo}/contributors --jq '.[] | select(.login == "{author}") | .contributions'`. If the author has fewer than 10 contributions in this repo, lean **explanatory** — this is the case the explanatory voice exists for. Otherwise stay **peer**.
3. **Otherwise** (history unavailable, `gh` failed or rate-limited), stay **peer**. Do not block on the lookup.

An explicit user choice of `e` or `m` always wins over the detected signal.

### Tone choice prompt

Before showing comment drafts, ask:

```
Tone for review comments:
  -> p = Peer (default) — short, question-led, no restated context, no A/B prescription
  -> e = Explanatory (junior or unfamiliar author) — staff-level voice with context, prescribed fix, rationale
  -> m = Minimal (bot or terse author) — state the issue and stop
  -> ? = I'll guess from author signal: <detected signal here>
```

In autonomous/swarm mode: auto-select based on detected signal. Default to peer if signal is ambiguous.

### Density budget

The default (peer) voice obeys a hard budget on ceremony:

1. **Ceiling: a comment body is at most two sentences.** One is better.
2. **No restated context.** Do not describe what the code does — the reader is looking at it, anchored. Skip the "Verified concern: when the user clicks X, the handler calls Y…" opener and go straight to the concern.
3. **No A/B prescription by default.** Do not offer "(A) … or (B) …" menus. State the concern; if a fix is obvious, name it in a clause, not a section. Prescribe options only when the fix is genuinely ambiguous *and* the choice is consequential.
4. **No positives or nitpick padding** in a comment body. Praise and summary belong in the review summary, not on an inline anchor.

**Escape hatch:** a **Blocking** finding whose mechanism cannot be conveyed in two sentences may exceed the ceiling — lead with the concern in sentence one and keep the mechanism to a short second paragraph. The budget is a bar on ceremony, never on information needed to act: when in doubt between terse and actionable, choose actionable.

### Tone reference patterns

**Peer (default — one-sentence question or observation, within the density budget):**
> Does `editComplete()` here also persist? I read the trace as in-memory-only — flagging in case I missed a write.

**Explanatory (opt-in voice — intentionally exceeds the density budget for a junior or unfamiliar author):**
> Verified concern: when the user clicks Save and exit, the handler calls `editComplete()` but does not propagate to the backend. Two ways forward: (A) add a `persistDraft()` call before `editComplete()`, or (B) move persistence into `editComplete()` itself. Either is fine; (A) is the smaller diff.

**Minimal (bot/terse):**
> `editComplete()` does not persist — Save and exit will lose changes.

Both reviewers (Scout and Ranger) honor this choice; tone is a presentation concern, not a finding concern. The same finding renders in three voices.
