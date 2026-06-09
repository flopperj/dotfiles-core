# Google Docs linking mechanics (hard-won)

Writing into a Google Doc via the Docs API is straightforward for plain text but
deceptively tricky when applying **links to specific words inside prose**. These
are the traps that cost real time, and how to avoid them. Prefer the
**google-docs** skill for routine operations; this file is the linking-specific
knowledge it doesn't cover.

## Auth

```bash
TOKEN=$(gcloud auth application-default print-access-token)
# gcloud may not be on PATH; common fallback:
#   ~/Downloads/google-cloud-sdk/bin/gcloud
curl -s "https://docs.googleapis.com/v1/documents/<DOC_ID>" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: <QUOTA_PROJECT>"   # required, else 403 "quota project not set"
```

The quota project comes from config (default in config-defaults.md).

## The core problem: run coalescing

Google Docs stores text as `textRun`s. **Adjacent runs with identical styling
merge into one run.** This breaks naive in-run linking in two ways:

1. **Stale offsets bleed.** If you compute a character offset for a word against
   an *old* document snapshot, then apply a link there after other edits have
   shifted the text, the link lands a few characters early — it "bleeds" onto
   the preceding text (e.g. you link "Cyrus" but the link covers "nts (Cyrus").

   **Fix:** always compute link offsets against a **fresh** GET of the document,
   taken *after* any text edits in the same batch sequence. Then **verify**: read
   back each linked run and confirm its content equals the exact phrase. If it
   bled, clear the link on just the bleed-prefix range and re-apply.

2. **Per-key updates on bundles fail.** A slash-bundle like
   `(EEE-1 / EEE-2 / EEE-3)` is often a few coalesced runs. Trying to drop or
   relink one key with `updateTextStyle` against computed offsets fights the
   coalescing and mislands.

   **Fix:** rewrite the whole bundle as plain text with `replaceAllText`
   (`"(EEE-1 / EEE-2 / EEE-3)"` → `"(EEE-1 / EEE-3)"`), which strips links on the
   *survivors* too — then re-apply links to each surviving key at fresh offsets
   read from a new snapshot. One bundle at a time, re-fetching between bundles.

## Safe editing patterns

- **`replaceAllText` only touches unlinked prose you intend to change.** If your
  match string spans a linked token, the replacement strips that link. To edit
  prose *around* a link, split the edit: replace the text before the link and
  the text after it separately, leaving the linked run untouched.
- **Dropping a linked ticket lowers the link count by one.** Expected, not a bug.
- **Applying a link to an exact existing token** is the safest operation: find
  the token's run, apply `updateTextStyle` with `fields:"link"` to
  `[run.start, run.end]` when the run *is* exactly the token. When the token is
  embedded in a larger run, compute `[run.start + offset, ...]` from a fresh
  snapshot and verify afterward.

## Request types you'll use

- `replaceAllText` — bulk text swaps (position-independent; safest for prose).
- `updateTextStyle` with `fields:"link"` — apply/clear a link on a range.
  `link: null` clears.
- `updateTextStyle` with `fields:"bold"` — bold a lead-in phrase. After a
  `replaceAllText` that changes a bold lead-in's length, re-apply bold to just
  the lead phrase and unbold the remainder (the replacement inherits the old
  run's bold across the whole new string).
- `insertText` / `deleteContentRange` — for structural edits; work
  **bottom-to-top** (highest index first) so earlier edits don't shift later
  indices within one batch.
- `createParagraphBullets`, `updateParagraphStyle` (indent, namedStyleType),
  `updateTableColumnProperties` (FIXED_WIDTH in PT) — for layout.

## Verify after every batch

Re-fetch the doc and check:

- Link counts by type (Jira / PR / repo) match expectations.
- No unlinked ticket-key tokens remain (regex scan).
- No link "bleed": every linked run's text equals the intended phrase.
- Dropped tokens are gone; no dangling separators.

## Final visual check

Export to PDF and read it:

```bash
curl -s "https://www.googleapis.com/drive/v3/files/<DOC_ID>/export?mimeType=application/pdf" \
  -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: <QUOTA_PROJECT>" \
  -o /tmp/review.pdf
```

PDF rendering reveals bullet nesting, bold spans, table-cell wrapping, link
coloring, and header person-chips that text inspection misses. Person chips
(the header "Employee Name" field) are interactive elements that don't appear in
text extraction — confirm them via the PDF, not the GET response.

## Permalinks for your own repo references

When citing skills/agents from the user's dotfiles, link to a **pinned commit
SHA** (`.../blob/<sha>/path`), not a branch tip — branch links drift as the repo
changes. Get the SHA once (`gh api repos/<owner>/<repo>/commits/<branch>
--jq .sha`) and verify each path resolves at that SHA before linking
(`gh api "repos/<owner>/<repo>/contents/<path>?ref=<sha>"`).
