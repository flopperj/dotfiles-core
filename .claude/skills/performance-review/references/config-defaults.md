# Config defaults + schema

The skill reads company specifics from `~/.claude/performance-review.yaml`
(a project-scoped `.claude/performance-review.yaml` overrides it). This keeps
the core skill shareable: anyone who forks the framework plugs in their own
company's values without editing the skill.

If the file is absent, use the built-in defaults below and **tell the user which
defaults you're assuming** so they can correct any that are wrong before you
gather evidence.

## Config schema (`performance-review.yaml`)

```yaml
version: 1

fiscal_year:
  anchor_month: 8        # fiscal year starts in this month (1-12). 8 = August.
                         # year-end = full FY; mid-year = first ~6 months.
  label_style: short     # "short" -> FY26 ; "long" -> FY2026

jira:
  cloud_id: ""           # Atlassian cloudId for searchJiraIssuesUsingJql
  project_keys: []       # e.g. ["EEE", "FREDDIE"] — restricts/orders the search
  issue_browse_base: ""  # e.g. https://your-org.atlassian.net/browse/

github:
  host: github.com       # e.g. github.com or github.enterprise.com
  username: ""           # your GitHub login on that host
  bot_logins: []         # service/bot accounts to exclude from contributor rank
                         #   (e.g. svc-*, *-bot)

template:
  doc_id: ""             # Google Doc ID of the blank review template to copy
  quota_project: ""      # X-Goog-User-Project value for the Docs/Drive API

rating_ladder:           # year-end self-rating tiers, lowest to highest
  - "Does Not Meet Expectations"
  - "Meets Expectations"
  - "Exceeds Expectations"
  - "Trajectory-Changing"

tooling_repos: []        # your own repos to check for peer adoption
                         #   (e.g. ["you/dotfiles", "you/dotfiles-core"])
```

## Built-in defaults (used when config is missing)

- `fiscal_year.anchor_month`: **8** (August) — fiscal year August 1 → July 31.
- `fiscal_year.label_style`: **short** (FY26).
- `jira.cloud_id`: **none** — if empty, ask the user for it (or skip Jira and
  tell the user Jira evidence is unavailable without it).
- `github.host`: **github.com**.
- `github.bot_logins`: heuristic — treat any login matching `svc-*`, `*-bot`,
  or containing `bot` as non-human for rank comparison.
- `template.doc_id`: **none** — if empty, ask the user for the template doc ID
  (or for the blank template's structure). Without it, the skill can still draft
  content but can't auto-copy the layout.
- `template.quota_project`: **none** — required for the Docs/Drive API; ask if
  empty.
- `rating_ladder`: the four-tier default shown in the schema above.

## Notes

- The skill is designed to **degrade gracefully**: with no config it still
  drafts an honest review from whatever evidence it can gather and whatever
  template the user points it at — it just asks more questions up front.
- Keep secrets out of this file. The cloudId, GitHub host, and template doc ID
  are not secrets; tokens are obtained at runtime via `gcloud` / `gh` and never
  stored here.
