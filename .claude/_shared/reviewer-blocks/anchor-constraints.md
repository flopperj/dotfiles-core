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
