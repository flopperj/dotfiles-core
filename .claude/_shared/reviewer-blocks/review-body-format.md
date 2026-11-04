#### Posted review body

The review `body` — the top of the pending review that carries the inline comments, and the body of an approval — follows one shape, so a reader of a long PR thread finds the verdict, the sha it applies to, and what is still open without reading the inline comments first. Inline comments are unchanged: anchored, one concern each, within the tone budget.

```
🤖 **<Verdict> @ `<short-sha>`**

<emoji> **<One-sentence verdict.>** <What the verdict rests on, one clause.>

| Since my review @ `<old-sha>` | Result |                       ← re-review only
|---|---|
| <prior blocker or important item, or a case traced> | ✅ Fixed in `<sha>` · ❌ Still open · ➖ Unchanged |

**Unchanged since my review:** <files or areas with no diff since then>   ← re-review only

<CI sentence>

**Blockers (N):**                                                 ← only when N > 0
- [<title>](<inline comment link>) — <one clause>

<details>
<summary>💬 Non-blocking (N important · M suggestions)</summary>

- <title> — <one clause> (<permalink>)

</details>

**After merging:** <one line>                                      ← only when there is a post-merge action
```

- **First line.** `🤖 ` first (Automated Comment Marker), then the verdict in bold — never a `#` heading, which would put `#` before the marker. The vocabulary and emoji are fixed: `✅ No blockers` (READY, posted as a comment review), `✅ Approving` (READY, on the `a` path), `🟡 Needs changes` (NEEDS CHANGES), `🔴 Blocked` (BLOCKED). The sha is the head that was reviewed (`headRefOid`, short), so a later push is visibly outside the verdict.
- **Re-review.** Step 1 fetched the PR's reviews and the user's login. When a prior review by that login exists, the first line is ``🤖 **🔁 Re-review @ `<short-sha>`**`` followed by a link to it (`[review <id>](<pr-url>#pullrequestreview-<id>)`), the table traces each blocker and important item from it to a commit in `<old-sha>..<head>` or marks it still open, and the Unchanged line names the files or areas with no diff since then (`git diff <old-sha> <head> -- <path>` is empty) — the reader learns what was not re-read as well as what was.
- **Verdict sentence.** One sentence carrying the emoji, then one clause on what it rests on ("traced the three new cases through the retry loop", "re-read the migration and its down step"). Praise is at most one specific clause here; the tone budget bans it inline.
- **CI at the head.** One sentence from the live `gh pr checks` read, never from the PR description or a request form: "CI is green at `<sha>`." / "CI is still running on `<sha>` (<check>), so let it go green before merging." / "CI is red at `<sha>` (<check>)." Pending or red CI never turns into an approval.
- **Blockers are never collapsed.** One bullet per blocking inline comment, linked, one clause each. The `<details>` block holds important items and suggestions only, with the counts in its summary so the reader can decide whether to open it; omit it when there are none. Nothing else goes in `<details>`.
- **After merging** appears only when the author has something to do after the merge (approve a deploy gate, run a backfill, watch a dashboard).
- **Links.** A PR or issue from another repo is `[owner/repo#N — title](url)`, never a bare `#N`, which GitHub resolves against the repo the review is posted in. Same-repo shas stay bare in backticks; inline comments link by `#discussion_r<id>`.
- **Literal `gh` commands.** Every `gh` call that reads or posts spells out the host and the repo (`gh api --hostname <host> repos/<o>/<r>/…`, `gh pr view <n> --repo <host>/<o>/<r>`), with no shell variable or command substitution anywhere in the command: exec guards reject the dynamic form, and a literal is what the user audits at the gate.
- **The chat view is not the posted body.** The `## PR Review:` structure the agent returns (confidence scores, Ranger confirmations, Requirements Coverage) is the working view shown at the gate; this block is what posts. Show the posted body verbatim at the gate, as with every comment.
