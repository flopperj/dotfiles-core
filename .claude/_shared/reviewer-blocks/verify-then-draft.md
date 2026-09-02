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
