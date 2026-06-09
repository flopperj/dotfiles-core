# Evidence engine — exact gathering commands

The three contribution sources, with the exact commands and the gotchas that
bite. All of these read config from `performance-review.yaml` (cloudId, GitHub
host, username, bot logins, tooling repos) — substitute those values. The goal
is a verified, deduplicated list of *the user's* shipped work in the window,
which Step 3 then audits ticket-by-ticket.

## Table of contents
1. Jira (assigned work in the window)
2. GitHub (contribution stats + authored PRs)
3. Tooling adoption (force-multiplier evidence)
4. Last year's goals (for Section 2)

---

## 1. Jira — issues the user owned in the window

Query via the Atlassian MCP (`searchJiraIssuesUsingJql`) with the cloudId from
config. Restrict to the user as assignee and to the fiscal window.

JQL shape:

```
assignee = currentUser()
AND project IN (<project_keys from config>)
AND (resolved >= "<window_start>" OR updated >= "<window_start>")
AND updated <= "<window_end>"
ORDER BY resolved DESC
```

Request only the fields you need — `summary`, `status`, `assignee`,
`issuetype`, `resolution` — to keep the payload small.

**Gotcha — large results exceed the tool's token limit.** When the result is
big, the MCP saves it to a file and returns a path instead of inline JSON. Do
**not** try to read the raw file into context. Extract the compact fields with
`jq`:

```bash
jq -r '.issues.nodes[]
  | [.key,
     (.fields.issuetype.name // "?"),
     (.fields.status.name // "?"),
     (.fields.status.statusCategory.key // "?"),
     (.fields.assignee.emailAddress // "UNASSIGNED"),
     (.fields.summary // "")]
  | @tsv' "<saved-result-file>"
```

`statusCategory.key` is the reliable done/in-progress signal: `done` =
Closed/Resolved; `indeterminate` = In Progress / Verify; `new` = open/backlog.
Use it (not the display name) to drive the shipped-vs-built-vs-in-progress
language in honesty-bar rule 2.

This list feeds **Step 3 (verify every ticket)**: drop anything whose
`assignee` isn't the user; frame anything not in `done` per its real status.

## 2. GitHub — contribution stats + authored PRs

Per-repo contributor stats (commit count, total, rank) via the host from config:

```bash
gh api --hostname <github_host> "repos/<org>/<repo>/stats/contributors"
```

**Gotcha — first call returns HTTP 202** while GitHub computes the stats cache.
Retry (with a short sleep) until it returns a populated array:

```bash
for i in 1 2 3 4 5; do
  RESP=$(gh api --hostname <github_host> "repos/<org>/<repo>/stats/contributors" 2>/dev/null)
  [ -n "$RESP" ] && [ "$RESP" != "[]" ] && break
  sleep 4
done
```

Then compute the user's rank and **lead over the next _human_ contributor** —
exclude bot/service accounts (the `bot_logins` list from config, plus the
heuristic: any login matching `svc-*`, `*-bot`, or containing `bot`):

```bash
echo "$RESP" | jq --arg me "<username>" '
  [ .[] | {login: .author.login, total} ]
  | sort_by(-.total) as $all
  | ($all | map(select(.login | test("bot|^svc-"; "i") | not))) as $humans
  | { me: ($all[] | select(.login==$me)),
      total: ($all | map(.total) | add),
      next_human: ($humans | map(select(.login != $me)) | .[0]) }'
```

The contributor-rank stat is good evidence (honesty-bar rule 3) — the graph is
third-party and one click away. Capture the graph URL to link in the doc:
`https://<github_host>/<org>/<repo>/graphs/contributors`.

Authored PRs org-wide (for breadth across repos):

```bash
GH_HOST=<github_host> gh search prs --author <username> \
  --created ">=<window_start>" --json repository,number,title,url
```

## 3. Tooling adoption — force-multiplier evidence

If the user has tooling repos (config `tooling_repos`), detect peers who built
on them — this supports a "force-multiplier / leverage beyond myself" narrative
(relevant to the impact-radius discussion in honesty-bar rule 6).

```bash
# Commits authored by someone other than the user, in the user's repo:
gh api --hostname <github_host> \
  "repos/<owner>/<repo>/commits?author=<peer-login>&sha=<default-branch>" \
  --jq '.[].sha' | head
```

Confirm names/handles before citing anyone (honesty-bar rule 5 — and basic
courtesy). "Several teammates built on it, including <names>" is only worth
saying if it's verifiably true.

## 4. Last year's goals (for Section 2, Goals Review)

The skill can't invent the goals the user set last cycle. Ask for them — the
previous review doc, a Betterworks/goals export, or the user pasting them. Each
goal then gets a row in the Section 2 table with a status (Met/Partially/Not
Met for year-end; On Track/At Risk for mid-year) and a notes cell that links
the supporting tickets gathered above.
