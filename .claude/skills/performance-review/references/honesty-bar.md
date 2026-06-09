# Honesty Bar — the heart of a credible self-review

A self-review goes to someone who can verify it — in Jira, in GitHub, in
calibration with your peers. A claim that doesn't survive scrutiny costs you
more than a modest claim that does. Every rule below exists because the
alternative gets caught. Apply all of them while drafting, then run the Audit at
the end.

## Table of contents
1. Verify every ticket
2. Shipped vs built vs in-progress
3. Honest metrics
4. Manager altitude (strip jargon)
5. Initiative vs ownership
6. Self-rating guidance (year-end only)
7. Promotion angle (optional)
8. Section consistency
9. Audit checklist

---

## 1. Verify every ticket before citing it

Pull live assignee + status for every Jira key before it enters the draft.

- **Drop any ticket not assigned to the user** — even if they wrote code on it.
  A reviewer who opens it and sees someone else as assignee will discount the
  whole document.
- **Drop or flag any ticket resolved by a sibling change.** If the user's work
  didn't close it, it isn't their deliverable.
- When you drop a ticket that was hyperlinked, the link count goes **down by
  one** — that's correct, not breakage.

This is the single highest-value rule. In practice it catches 2–4 tickets in a
typical review (work assigned to teammates, tickets closed by other PRs).

## 2. Shipped vs built vs in-progress — match the verb to reality

| Real state | Honest verb | Never say |
|---|---|---|
| In production, customer-facing | "shipped", "launched", "GA" | — |
| Code complete, merged, not yet customer-facing | "built", "delivered", "merged" | "shipped", "live", "customers now see" |
| Status = Verify (done, in review) | "delivered", "built" | "shipped" |
| Status = In Progress / open | "began", "in progress", "underway" | "delivered", "migrated", "shipped" |

Cross-check each verb against the ticket's real status from Step 3. The most
common overclaim is calling merged-but-flagged-off work "shipped" — a director
who knows the feature isn't live yet will notice immediately.

## 3. Honest metrics — prefer the verifiable, drop the padding

- **Contributor rank is good evidence** — the contributor graph is third-party
  and one click away ("#1 contributor by a wide margin — N of M commits"). When
  comparing, exclude bot/service accounts and compare to the next *human*.
- **Avoid raw ticket-count padding** ("196 tickets resolved"). It reads as
  volume, not impact. Prefer ownership framing: "N epics owned and closed, with
  N P0 and N P1 bugs closed inside them."
- A live ratio ("3× the next engineer") can drift before submission — if the
  user wants it bulletproof, use "far ahead of any other engineer" instead.

## 4. Audience altitude — strip jargon, skip what they already know

Write to the **stated audience** (default: the user's manager + their
calibration peers), not to your code reviewer. Two levers:

- **Strip jargon below their altitude.** Replace code identifiers and acronyms
  with plain English (table below). The test: would this reader understand the
  sentence without opening the codebase?
- **Skip context the audience already has.** A direct manager who lives your
  work doesn't need the setup sentence — get to the impact. A skip-level or
  calibration committee who *doesn't* know your day-to-day needs more "why this
  mattered," because they're ranking you against people they know better. Match
  the context depth to who's reading.

Replace code identifiers and acronyms with plain English:

| Jargon | Plain |
|---|---|
| component/class names (e.g. `FloatingPopover`) | "a reusable popover component" |
| framework internals (`CKEditor iframe`, `window.editor`) | "the rich-text editor" |
| acronyms (AST, NLS, i18n, WCAG, HEIC, ESLint, MCDS) | spell out the *user-facing* effect |
| `STUB_THEMES`, internal constants | describe what it does |

Keep altitude **consistent** — a doc that's plain in Section 1 but jargon-heavy
in Strengths reads as unfinished. The test: would a non-engineer director
understand the sentence?

## 5. Initiative vs ownership — frame flagged work honestly

If a ticket was *reported by a lead or PM* but the user delivered it, that's
**initiative on a flagged need**, not an "unowned gap." Check the ticket's
reporter/creator. "I took it on the moment it was surfaced and delivered it
end-to-end" is honest and is actually a *stronger* signal (proactive ownership)
than claiming nobody owned it. Reserve "unowned gap I picked up" for work that
genuinely had no owner and wasn't assigned.

## 6. Self-rating guidance (year-end only)

Map the evidence to the company rating ladder (from config; default ladder:
Does Not Meet / Meets / Exceeds / Trajectory-Changing) and recommend the honest
tier. **The rating is relative to the user's current level (from Step 0), not
absolute** — the same body of work earns a different rating at different levels.

- **Meets** — operating at the expectations of their *current* level: owns their
  work, ships reliably, little oversight needed.
- **Exceeds** — clearly above the expectations of their *current* level on
  multiple axes.
- **Trajectory-Changing** — performing at the *next* level already, with
  landed, org-visible impact that outlasts them.

**Calibrate to level — this is the pivot.** The exact same work reads
differently up the ladder:

- For a **Senior**: deep ownership of a surface, reusable foundations others
  build on, shipping real value, multiplying your own output → **Exceeds**.
  Broad cross-team technical influence is above-bar and points toward the next
  level.
- For a **Staff**: that same "deep ownership + reusable foundations" is roughly
  the *expected* bar (**Meets**); to **Exceed**, the evidence needs to show
  impact *radius* — shaping multi-team technical direction, scaling other
  engineers, landing org-visible outcomes, not just personal throughput.
- The general principle: **impact radius** is the axis that climbs the ladder.
  Deep-but-narrow (huge impact on one surface, mostly solo) tops out the Senior
  band; broad cross-team influence that scales others is the Staff+ signal. Tell
  the user honestly which one their evidence shows, and against which level.

Key honesty checks (apply at any level):
- **Don't recommend Trajectory-Changing if the biggest bet hasn't reached
  customers** — readiness isn't a landed outcome. Recommend **Exceeds with a
  stated line-of-sight** instead. Let the evidence make a reviewer reach for the
  higher word; don't self-declare it and hand them an easy markdown.
- If the user's evidence is "strong at their level but not yet operating at the
  next," say so plainly — that's an honest **Exceeds**, not a deflated one, and
  it's a more durable claim in calibration than an overreach.

## 7. Promotion angle (optional — only if the user raises it)

If the user is eyeing a promotion, reframe **Areas for Growth** and **Next-Year
Goals** as a deliberate *scope-expansion* trajectory — each item visibly answers
"how does my impact radius grow beyond my own output?" (scaling others, shaping
cross-team direction, landing a big bet to customers).

**Never write the words "promotion" or the target level into the doc.** A
self-eval that declares the title reads as presumptuous and shifts it from
"year in review" to "promo packet." Make the trajectory legible so the director
connects the dots themselves — that's stronger than declaring it.

A self-review is one *input* to a promo case, not the case itself. Be honest
with the user if the evidence shows "strong senior building toward staff" rather
than "already operating at staff" — the latter usually needs one more cycle of
deliberate scope-expanding work plus a landed, visible outcome.

## 8. Section consistency

Section 1 must not contradict Sections 5/6. The classic tell: Section 1 says
"customers now see X" while Support Needed says X is "waiting on a go decision."
A sharp reader catches the contradiction and it costs more credibility than an
honest "built, pending launch." After drafting, read 1 and 5/6 together.

---

## 9. Audit checklist (run before showing the user)

- [ ] Count Jira / PR / repo links — record the totals.
- [ ] Scan the full text for any unlinked ticket key (e.g. regex
      `\b(PROJ|TEAM)-\d+\b`) — any match outside a link is a **broken link**.
- [ ] Scan for residual jargon (component names, acronyms from rule 4).
- [ ] Scan for overclaim phrases ("customers now see", "shipped" on non-prod
      work, "launched" pre-launch).
- [ ] Confirm every cited ticket passed Step 3 (assignee + status).
- [ ] Confirm dropped tickets are fully absent — no orphaned links, no dangling
      separators (e.g. "/ /").
- [ ] Confirm Section 1 ↔ Sections 5/6 consistency.
- [ ] (year-end) A self-rating recommendation is present and honest.
- [ ] (mid-year) No final ratings anywhere; Goals framed as On Track / At Risk.
