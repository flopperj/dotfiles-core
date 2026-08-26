---
name: pr-create-from-commits
description: "Create a PR from recent commits. Use when the user says 'create a PR', 'open a pull request', 'make a PR from my commits', or similar. Detects the repo's PR template automatically, handles Jira ticket status via MCP, asks for missing context upfront, and populates the PR body based on whatever template structure the repo uses."
user-invocable: true
---

# Pull Request Create

Create a PR from recent commits. Detects the repo's PR template automatically, asks for any missing context upfront, handles Jira ticket status, and populates the PR body based on whatever template structure the repo uses.

## Steps

### 1. Gather context from git history

- Detect the default branch: use `git remote show origin | grep 'HEAD branch' | awk '{print $NF}'` to find it, falling back to `main` then `master`
- Run `git log origin/{default_branch}..HEAD --oneline` to see commits on this branch
- Run `git diff origin/{default_branch}` for a full diff overview
- Understand the purpose and scope of the changes
- Extract the Jira ticket number from the branch name (format: `ABC-1234`). If not found in the branch name, ask the user. If no ticket exists yet, offer to create one via `/create-jira-ticket`.
- **Check for flag-only changes:** if the only changed file is `config/flags.ini`, suggest using `/mc-pr-flag` instead for a specialized flag PR template with proper rollout metadata.
- **Check for mixed changes:** if commits contain clearly unrelated concerns, WARN the user and suggest splitting into multiple PRs. Only proceed if the user confirms.

### 2. Detect PR template

Search for a PR template in the following locations (in order):

1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/PULL_REQUEST_TEMPLATE/` — if this directory exists and contains multiple templates, list them and ask the user which to use
4. `docs/pull_request_template.md`
5. `pull_request_template.md` (repo root)

If a template is found, read it in full — it defines the exact sections to populate. If no template is found, use a sensible default structure: Description, Changes, Testing, Notes.

### 3. Ask for missing context upfront

Before doing any git operations, identify what information is required by the template but cannot be inferred from the code. Always ask for:

- **Slack team channel** — almost never determinable from code; always ask if not explicitly mentioned in the diff or commit messages
- Any other template fields that are blank placeholders and cannot be reasonably inferred

Ask all missing questions in a single message — don't interrupt later steps with follow-up questions.

### 4. Check and update Jira ticket status

**Primary: Atlassian MCP plugin**
1. Call `getJiraIssue` with the ticket key. If the Atlassian plugin is unavailable, fall back to an alternative Jira integration if available.
2. Check the status field. If already In Progress/Verify/Blocked/Closed: show `ℹ️ Ticket {TICKET} is: {status} (no status change needed)` and continue.
3. Call `getTransitionsForJiraIssue`, find an "In Progress" transition (look for: "In Progress", "Start Progress", "Start Work"), then call `transitionJiraIssue`. Show `✅ Moved {TICKET} to In Progress`.

For company-specific Jira fallback, consult `## Jira fallback` in `~/.claude/overlay-context.md`. If that file is absent, proceed with the primary tool only.

<!-- BEGIN OVERLAY-FRAGMENT: pr-create-jira-fallback -->
<!-- END OVERLAY-FRAGMENT: pr-create-jira-fallback -->

All Jira operations are best-effort — never block PR creation on a Jira failure. Follow CLAUDE.md error handling defaults.

### 5. Git operations

1. Check for uncommitted changes (`git status`):
   - If YES: ask the user if they want to stage and commit them before creating the PR. If confirmed, stage relevant files and commit.
2. Check current branch:
   - If on `main` or `master`: create a new branch named `{ticket-prefix}-{ticket-num}-{feature-summary}` (e.g. `EEE-1234-add-campaign-preview`) and check it out.
3. Push the branch to origin if not already pushed: `git push -u origin {branch}`.

### 6. Create the PR

1. Populate every section of the detected template based on code analysis. Let the template structure drive the write-up — do not impose a fixed format. Be specific and accurate; ask rather than guess. Only use "N/A" when information genuinely cannot be determined.
2. For each placeholder or table row in the template, fill it in using:
   - Code diff analysis for technical content (what changed, how to test, risk areas)
   - User-provided answers from Step 3 for anything that required asking (e.g. Slack channel)
   - Ticket number and any Jira metadata retrieved in Step 4

   **2b. Merge order section (repo-split tickets only).** Applies only when the ticket is one half of a repo split, in either shape: (a) a Jira sub-task carrying a `repo:<name>` label whose parent has 2+ sub-tasks with `repo:` labels, or (b) a standard Task carrying a `repo:<name>` label with a `Relates` link to a parent issue that has 2+ `repo:`-labeled `Relates`-linked issues — the fallback shape create-jira-ticket's batch mode produces when the project has no Sub-task type. Fetch the siblings via `getJiraIssue` on the parent: its sub-tasks in shape (a), its `Relates`-linked `repo:`-labeled issues in shape (b). Derive the order from the `blocks` links between the siblings: a sub-task that blocks another comes first. For each sibling, resolve its PR URL from the sibling ticket's remote links, or a `gh pr list --head <branch>` lookup in that sibling's repo when the repo is resolvable; if no PR exists yet, use `PR pending`.

   This does not conflict with the "do not impose a fixed format" rule in item 1: the Merge order section is **appended after** the template's own sections, never replacing or restructuring them. It counts toward the body-length and heading checks in item 3.

   Append exactly this shape (canonical example — the sentinels and entry-line grammar are a stable, machine-parsed contract enforced by `tests/merge-order-format.bats`, which parses this fenced block verbatim; keep it unindented):

```markdown
## Merge order

<!-- merge-order:v1 -->
1. [ ] omni-agent — PROJ-1235 — https://github.com/acme-corp/omni-agent/pull/42
2. [ ] mc-omni-agent-ui — PROJ-1236 — this PR

Built against the unmerged changes in the PR above — merge that one first.
<!-- /merge-order:v1 -->
```

   Grammar: parsers read only lines matching `^[0-9]+\. \[[ x]\] <repo> — <TICKET-KEY> — <url | this PR | PR pending>` between the `merge-order:v1` sentinels; any other line inside the block is human prose. Field separators are em-dashes (—) surrounded by single spaces. Indices are contiguous starting at 1, in merge order; exactly one entry is `this PR` (the PR being created). The unmerged-provider caveat sentence is **mandatory** whenever any earlier entry is not `this PR` — the reviewer must know this PR was built against unmerged changes.

3. **Validate body length and shape before firing `gh pr create`** (skip if the user passed `skip_body_validation: true`):
   - Compute the visible body length: strip leading/trailing whitespace, then count **bytes** with `printf '%s' "$body" | wc -c`. (Use `wc -m` if you need a true Unicode character count — but for the 100-byte threshold below, `wc -c` is sufficient and consistent across platforms. The threshold is intentionally a byte count, not a Unicode codepoint count, because thin English bodies are the failure mode this check exists to prevent.)
   - **Minimum length: 100 bytes.** A body shorter than 100 bytes is almost always a stub.
   - **Required shape:** the body must contain at least one heading whose text matches `Summary`, `Why`, `Motivation`, `Context`, or `Overview` (case-insensitive). A heading is any line starting with `#`, `##`, `###`, or a bold pattern like `**Summary**`.
   - If either check fails, **pause** and surface the specific problem to the user:
     - Body too short: "PR body is N bytes; minimum is 100. Add a Summary or Why section explaining the change."
     - Missing summary heading: "PR body has no Summary/Why/Motivation/Context/Overview section. Add one before I create the PR."
   - Wait for the user to provide an expanded body (or confirm `skip_body_validation`). Re-check after the expansion. Only proceed when the body passes both checks.
4. Create the PR as a **draft by default**:
   ```
   gh pr create --draft --title "[{TICKET}] {Title}" --body "{populated_template}"
   ```
5. If the user explicitly requests a non-draft PR (e.g., "open a PR for review", "create a ready PR"): use `gh pr create --title "..." --body "..."` without `--draft`. Non-draft PRs require the code auditor to run first (see CLAUDE.md PR Creation Workflow).

   **5b. Parent-ticket comment (repo-split tickets only, best-effort).** For the same trigger as item 2b (either shape), after the PR is created, post a comment via `addCommentToJiraIssue` on the **parent** ticket — plain language with the 🤖 prefix, stating which repo's PR this is, the full merge order, and that later PRs are built against earlier unmerged changes. Example:

   > 🤖 Opened the omni-agent half of this ticket: https://github.com/acme-corp/omni-agent/pull/42. This work spans two repositories — merge order: 1) omni-agent (this PR), 2) mc-omni-agent-ui (PR pending). The second PR is being built against the first one's unmerged changes.

   If a comment from a previous sub-task PR already states the merge order, post an updated comment rather than editing the old one. Like all Jira operations in this skill, this is best-effort: if the comment fails, log it and continue — never block PR creation on it.

6. Return the PR URL to the user.

### 7. Promote draft PR to ready-for-review

If the user asks to promote an existing draft PR (e.g., "open my draft PR", "mark PR #N as ready", "promote this to ready for review"):

1. Identify the draft PR (`gh pr view <number>` or `gh pr list --draft`)
2. Invoke `/code-auditor` on the PR's diff — the auditor analyzes complexity and routes to Scout or Ranger
3. Surface the reviewer's findings and wait for acknowledgment or resolution of any blocking issues
4. If the user gives the go-ahead: run `gh pr ready <number>`
5. Return confirmation with the PR URL

### Error handling

Follow CLAUDE.md error handling defaults. Specifically:
- If `gh pr create` or `gh pr ready` fails, surface the error and stop
- If `git push` fails (e.g., rejected, no upstream), surface the error and suggest resolution
- All Jira operations are best-effort — never block PR creation on Jira failure

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
