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
