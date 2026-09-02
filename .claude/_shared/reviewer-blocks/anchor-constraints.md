#### GitHub review comment anchoring rules

The GitHub `POST /repos/{owner}/{repo}/pulls/{number}/reviews` endpoint enforces hunk-locality on multi-line comments. Violating the rules returns HTTP 422 and the entire review (not just the offending comment) fails to post.

### Hard constraints

- **Both endpoints must be inside the diff.** `start_line` and `line` must each correspond to a line that appears in the unified diff for the PR (with the correct `side` — `LEFT` for removed/context-on-old, `RIGHT` for added/context-on-new). A line that is "untouched" but visible as context in the diff is in the diff; a line that does not appear at all is not.
- **Both endpoints must be in the same hunk.** A hunk is a `@@ -a,b +c,d @@` block. Two separate hunks in the same file are two separate hunks even if they are visually adjacent in the rendered diff. Anchoring across an untouched block (lines not shown in the diff because GitHub elided them) crosses hunks.
- **`side` must be consistent.** A multi-line comment cannot start on `LEFT` and end on `RIGHT`.
- **Single-line comments** (`line` only, no `start_line`) are the fallback shape, used when the clamped range collapses to one line — not the default.

### Affected block

The default anchor is the **affected block**, not a single line.

> **Affected block.** The contiguous run of changed lines the finding concerns, extended to the smallest *syntactically complete* construct that encloses it — the `if`/`for`/`try` body, the object or array literal, the JSX element, the statement group — then clamped to the enclosing `@@` hunk.

It is **not** the whole enclosing function unless the function fits inside the hunk. A function is a useful unit for a human reader and a poor one for the GitHub API: it routinely exceeds a hunk, and exceeding a hunk means HTTP 422, which fails the **entire** review.

**The clamp rule.** Anchoring is a narrowing operation, never a widening gamble. In order:

1. Compute the ideal block range.
2. **Intersect it with the enclosing hunk.** If the block extends past either hunk edge, truncate to the hunk edge — do **not** drop straight to single-line. A partial block still shows the reader more than one line, and it is 422-safe.
3. If after clamping the range is a single line, emit a single-line comment (omit `start_line`).
4. If the changed lines the finding concerns are split across two hunks, anchor to the hunk containing the line where the issue first manifests — do not span, do not post twice.
5. If no inline anchor is possible, fall back to a general PR comment referencing `file:line`.

### Fallback order

1. **Affected block range, clamped to the hunk** (the default). Anchor with `start_line` + `line` spanning the block, both endpoints inside one hunk.
2. **Single line**, when the clamp collapses the range to one line — pick the line where the issue first manifests.
3. **General PR conversation comment.** If no inline anchor works (e.g. the issue spans untouched context that is not in any hunk), post as a `gh pr comment` general comment and reference file:line in the body text.

### Pending review semantics

When creating a pending review (so the user can preview before submit), **omit the `event` field from the payload**. Including `event: "COMMENT"`, `"APPROVE"`, or `"REQUEST_CHANGES"` submits the review immediately. The endpoint to create a pending review is:

```
POST /repos/{owner}/{repo}/pulls/{number}/reviews
{
  "body": "...",
  "comments": [
    { "path": "...", "start_line": 38, "line": 45, "side": "RIGHT", "body": "..." },
    { "path": "...", "line": 42, "side": "RIGHT", "body": "..." }
  ]
  // no "event" field — this leaves the review in PENDING state
}
```

The first comment shows the default shape — a block anchor spanning `start_line`..`line` within one hunk; the second is the single-line fallback shape.

To submit a pending review afterwards:

```
POST /repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}/events
{ "event": "COMMENT" }
```

### Pre-flight check (orchestrator-side)

Before posting, the orchestrator should run `gh pr diff <number>` and verify, for each drafted comment, that the `start_line` and `line` both appear in the same `@@` block. If they do not, clamp per the rule above — truncate to the hunk edge, collapsing to single-line only when the clamp leaves one line — and re-draft the anchor (not the comment body) before sending. A 422 from GitHub is a process failure, not a content failure — it means the orchestrator skipped this check.
