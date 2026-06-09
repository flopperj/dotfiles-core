---
name: performance-review
description: "Generate a performance self-review document (Google Doc) from your real contributions across Jira, GitHub, and your tooling repos, with every ticket/PR/repo hyperlinked and an enforced honesty bar that prevents overclaiming. Two modes — mid-year (course-correction checkpoint) and year-end (retrospective verdict). Use this skill whenever the user mentions a self-review, self-eval, performance review, year-end review, mid-year review, annual review, writing up their accomplishments for their manager/director, or fills out a review template — even if they don't name the skill. Reads company specifics (fiscal calendar, Jira cloudId, GitHub host, template doc, rating ladder) from performance-review.yaml; works with built-in defaults if absent."
user-invocable: true
---

# Performance Review

Generate an honest, evidence-backed performance self-review into your company's
review template — Google Doc, every reference hyperlinked, written at the
altitude your manager actually reads.

The hard part of a self-review isn't writing — it's being **accurate**: not
claiming work that wasn't yours, not saying "shipped" for things still in
flight, not burying impact under jargon, and not over-rating yourself in a way
a calibration committee can puncture. This skill's real value is the **honesty
bar** in [`references/honesty-bar.md`](references/honesty-bar.md) — read it
before drafting. The Google-Docs linking mechanics are genuinely finicky;
[`references/google-docs-linking.md`](references/google-docs-linking.md) has the
hard-won gotchas.

---

## Step 0 — Load config + resolve mode and window

**Config.** Company specifics live in `~/.claude/performance-review.yaml`
(an overlay/project may also place one at `.claude/performance-review.yaml`,
which overrides). Read it for: fiscal-year anchor month, Jira cloudId, GitHub
host, the blank template doc ID, and the rating ladder. If the file is absent,
fall back to the built-in defaults in
[`references/config-defaults.md`](references/config-defaults.md) and tell the
user which defaults you're using so they can correct you.

**Mode.** Ask which review this is unless the user already said:

- **year-end** — retrospective *verdict* covering the full fiscal year. Goals
  Review uses Met / Partially Met / Not Met. Includes a self-rating
  recommendation. Section 1 = what shipped *this year*.
- **mid-year** — forward-looking *course-correction* covering the first half.
  Goals Review is framed On Track / At Risk / progress-to-date — **not**
  Met/Not Met, because the year isn't over. **No final ratings.** Section 1 =
  "what I've delivered *so far* this half," explicitly partial.

**Role/level.** Ask the user their current role and level (e.g. "Senior
Software Engineer", "Staff Engineer"). This isn't just for the header's
Role/Team field — it **calibrates the rating guidance** in honesty-bar rule 6.
"Exceeds for a Senior" and "Exceeds for a Staff" are different bars; the same
body of work reads differently against each. If the user doesn't know or
declines, proceed but note the rating recommendation is un-calibrated.

**Audience.** Default to *the user's manager plus their calibration peers* —
that's who reads a self-review first, in almost every case. Don't make this a
blocking question; assume the default and note it in the confirmation. Only
adjust if the user signals a different reader (a skip-level, a committee, or a
rough self-pre-read), which changes how much context each accomplishment needs:
a manager who knows your work doesn't need the setup; a skip-level does. See
honesty-bar rule 4.

**Window.** Compute from today + the fiscal anchor month (default: August).
Determine the current fiscal year: if today's month ≥ the anchor month, the FY
label is *next* calendar year; otherwise it's the *current* calendar year.

- year-end window: anchor-month/year-1 → (anchor-month − 1 day)/year (full FY).
- mid-year window: anchor-month/year-1 → ~6 months later (first half).

**Always state the inferred mode, FY label, exact date window, role/level, and
assumed audience back to the user and get confirmation before gathering.** A
wrong window silently produces a wrong review; a wrong level produces a
miscalibrated rating; a wrong audience produces the wrong amount of context.

---

## Step 1 — Copy the template into a new doc

Use the **google-drive** skill to copy the blank template doc (ID from config)
into a new doc. Name it for the person + FY + mode, e.g.
`FY26 Year-End Self-Review — <Name>` or `FY26 Mid-Year Self-Review — <Name>`.

Copying preserves the exact section structure, the Goals table, and the
checkbox glyphs — far more reliable than rebuilding the layout via the API.
Read the copied doc once to capture its structure and indices.

The canonical 6-section structure (so you know what you're filling):

1. **Accomplishments** → "Top Accomplishments" (each: short title, what you
   did, impact/outcome) then "Additional Contributions"
2. **Goals Review** → a 3-column table (Goal | Status | Notes) + a "What got in
   the way" prose answer
3. **Strengths**
4. **Areas for Growth**
5. **Goals for Next Year** (each: Target outcome / How you'll measure success)
6. **Support Needed**

---

## Step 2 — Gather evidence

Pull from all three sources in parallel where you can. Details and exact
commands are in [`references/evidence-engine.md`](references/evidence-engine.md).

- **Jira** — issues assigned to the user, resolved/updated in the window, via
  the Atlassian MCP. Capture summary, status, assignee, issue type, resolution.
- **GitHub** — per-repo contribution stats (commit count, total, rank, lead
  over the next *human* contributor — exclude bot/service accounts), plus
  authored PRs org-wide.
- **Tooling adoption** — peers who forked or committed to the user's tooling
  repos, to support a force-multiplier narrative if one is warranted.

If the user has a previous review (last year's goals), ask for it — Section 2
(Goals Review) needs the goals they actually set, not invented ones.

---

## Step 3 — Verify every ticket (do not skip)

Before any ticket appears in the draft, confirm against live Jira data:

1. **Assignee is the user.** Drop anything assigned to someone else, even if
   the user touched the code. (A ticket someone else owns is the fastest way to
   lose credibility when a reviewer cross-references it.)
2. **Status matches the claim you'll make.** A "Closed" ticket can be called
   delivered; "Verify" means code-complete in review (also fine as delivered);
   "In Progress" must be framed as *began / in progress*, never "shipped."
3. **The work was actually the user's**, not resolved by a sibling change that
   merely closed the ticket.

This step is non-negotiable — see honesty-bar rule 1.

---

## Step 4 — Draft all six sections at manager altitude

Write in **first person**. Lead each accomplishment with *impact*, then the
ticket references. Apply the full honesty bar
([`references/honesty-bar.md`](references/honesty-bar.md)) as you write — it
covers shipped-vs-built language, jargon stripping, metric honesty, the
initiative-vs-ownership nuance, and Section-1-vs-Sections-5/6 consistency.

Mode-specific:

- **year-end** — Goals table uses Met / Partially Met / Not Met. After drafting,
  produce a **self-rating recommendation** per honesty-bar rule 6.
- **mid-year** — Goals table is On Track / At Risk / progress notes. No ratings.
  Frame Section 1 as in-progress. Sections 5/6 become "what I'll focus on in
  H2" and "what I need to land it."

If the user is eyeing a promotion, apply honesty-bar rule 7 — reframe Areas for
Growth and Next-Year Goals as a deliberate scope-expansion trajectory, but never
write the words "promotion" or the target level into the doc. Make the
trajectory legible, not declared.

---

## Step 5 — Apply hyperlinks

Link every Jira key, PR number, and repo to its real URL. If citing the user's
own skills/agents from their dotfiles, link to **pinned commit-SHA permalinks**
(verify each path resolves at that SHA first) so links don't drift.

The Google Docs API coalesces adjacent same-styled text runs, which makes
in-run linking deceptively easy to get wrong (links "bleed" onto neighboring
characters). **Read [`references/google-docs-linking.md`](references/google-docs-linking.md)
before doing any linking** — it has the offset-freshness rule, the slash-bundle
technique, and the post-link verification you need.

---

## Step 6 — Honesty + consistency audit

Before showing the user, run the audit checklist in honesty-bar.md §Audit:

- Count Jira / PR / repo links; scan for any unlinked ticket key (broken link).
- Scan for residual jargon and overclaim phrases.
- Confirm every cited ticket passed Step 3.
- Confirm Section 1 doesn't contradict Sections 5/6.
- Confirm dropped tickets are fully absent (no orphaned links).

---

## Step 7 — Visual check

Export the doc to PDF (`drive files/<id>/export?mimeType=application/pdf`) and
read it back. Rendering catches what text inspection misses — bullet nesting,
bold spans, table-cell wrapping, link styling, person chips in the header.

---

## Step 8 — Present and iterate

Show the user a summary of what's in the doc and the link/verification counts.
**Never auto-finalize** — the user reviews and steers. Self-reviews are personal;
expect multiple rounds of "soften this," "that wasn't really mine," "this is
jargon." Each correction is cheap to apply and protects their credibility.

When citing people (peers, leads), confirm names and handles before linking —
and remember the initiative-vs-ownership nuance from honesty-bar rule 5.
