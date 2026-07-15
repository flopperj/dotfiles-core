### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean.
- Offload research, exploration, and parallel analysis to subagents.
- For complex problems, throw more compute at it via subagents.
- One task per subagent for focused execution.
- **Always use maximum reasoning effort** for all agents and workflows. Never downgrade effort to save tokens or time unless explicitly asked for a lighter pass.
- **Subagents load at session start.** Edits to `.claude/agents/<name>.md` frontmatter (e.g., `maxTurns`, `disallowedTools`, `model`, `tools`) only take effect in a **fresh** Claude Code session. The currently running session uses the agent definitions it loaded at startup, even after `install.sh` re-symlinks the file. **Smoke-testing any frontmatter change requires a session restart** — otherwise a "fail" signal may just be the stale in-memory definition. Reference: https://code.claude.com/docs/en/sub-agents § "Write subagent files".

### 3. Self-Improvement Loop
- After ANY correction from the user: update `~/.claude/tasks/<project>/lessons.md` using the **Signs (Trigger / Do / Why) format** — template at `~/.claude/_shared/lessons-signs-format.md`.
- Write rules for yourself that prevent the same mistake.
- Ruthlessly iterate on these lessons until mistake rate drops.
- Review lessons at session start for relevant project.

### 4. Verification Before Done
- Never mark a task complete without proving it works.
- Diff behavior between main and your changes when relevant.
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness.
- Gate completion against `~/.claude/DoD.md` — its 9 sections are the canonical bar.

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution."
- Skip this for simple, obvious fixes – don't over-engineer.
- Challenge your own work before presenting it.

### 6. Autonomous Bug Fixing
- When given a bug report: **just fix it.** Don't ask for hand-holding.
- Point at logs, errors, failing tests – then resolve them.
- Zero context switching required from the user.
- Go fix failing CI tests without being told how.

### 7. Autonomous Ticket Swarm
- Use `/ticket-swarm` or "Swarm, fix my bugs" to batch-process Jira tickets.
- Use `/ticket-pickup` or "Pickup PROJ-1234" for single-ticket entry.
- Ticket-pickup detects Stories/Epics and decomposes them into swarmable sub-tickets.
- Each ticket is auto-classified: Simple -> Cyrus, Medium -> Optimus+Cyrus, Complex -> Aristotle+Optimus+Cyrus.
- Tickets are grouped by domain (backend, frontend, infra) and managed by team-lead coordinators.
- Team leads detect intra-cluster dependencies and sequence tickets to prevent merge conflicts.
- Gates auto-approve in swarm mode; human reviews at triage selection and PR creation only.
- Best-of-N for complex tickets: 2 parallel fix attempts, best one wins.
- All pipelines run in isolated branches to avoid conflicts.
- Agent roles are unchanged — swarm mode changes orchestration flow, not agent behavior.

---

## Task Artifact Location

All task artifacts live outside the workspace at `~/.claude/tasks/<project>/`,
where `<project>` is the basename of the git repo root (or CWD if not in a
git repo). Resolve with: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
Create the directory on first use.

Subdirectories and files:
- `plans/` and `plans/archive/` — Optimus execution plans
- `swarm-runs/` — ticket-swarm run logs
- `todo.md` — task tracking
- `lessons.md` — self-improvement patterns

## Task Management

1. **Plan First**: Write plan to `~/.claude/tasks/<project>/todo.md` with checkable items.
2. **Verify Plan**: Check in before starting implementation.
3. **Track Progress**: Mark items complete as you go.
4. **Explain Changes**: High-level summary at each step.
5. **Document Results**: Add review section to `~/.claude/tasks/<project>/todo.md`.
6. **Capture Lessons**: Update `~/.claude/tasks/<project>/lessons.md` after corrections.

---

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Token Economy

Context is the scarce resource — the more an agent re-reads, re-sends, or regenerates, the slower and more expensive the work, and the sooner a long session hits a wall. These rules make the cost discipline the architecture already encodes explicit, so every skill and agent inherits it:

- **Scope before exploring.** An unscoped task explores wide and burns tokens on investigation that a one-line constraint would have ruled out. State the target, the boundary, and the done-condition up front (this is also why the Optimus → Cyrus pipeline plans before it builds — scoping is a cost-control mechanism, not only a quality one).
- **Batch and parallelize agent calls; don't serialize what's independent.** Each subagent invocation re-sends its prompt and re-reads context. Independent work should fan out in one parallel wave (as `code-auditor` does with its 3 analysis agents), and related asks to the same agent should go in one prompt rather than a sequence of follow-ups. Reserve sequential calls for genuine dependencies.
- **Prefer targeted edits over regeneration.** Change the section that changed; don't re-emit an unchanged file, plan, or report to alter one part of it. When asking a subagent for a revision, point it at the specific delta.
- **Route work to the cheapest sufficient tier.** Mechanical, high-volume work belongs on the cheaper model tier; reserve the top tier for the reasoning steps that gate everything downstream. See `~/.claude/_shared/model-tiers.md` for the per-agent assignments and rationale.
- **Offload to subagents to keep the main context clean** (see Subagent Strategy above) — but weigh that against the per-call re-send cost; a subagent is worth it when it keeps a large exploration out of the main window, not for a cheap lookup the main loop could do inline.

## Code Comments

Applies to every agent that writes or edits code (Cyrus, Optimus snippets, direct implementation, frontend-design, etc.).

**Guiding principle:** Never add narrative comments where the code is self-explanatory. Only add comments where context would be helpful to a future contributor who did not write the code. The default is no comment.

- **Do not add narrative comments that restate what the code does.** Avoid obvious, redundant comments like `// import the module`, `// define the function`, `// loop over items`, `// return the result`, `// handle the error`, or `# increment counter`.
- **Do not leave "what I changed" comments.** Never use comments to explain the edit you just made (e.g., `// switched from map to reduce for perf`, `// added null check`). That belongs in the commit message or PR description, not the source.
- **Never leak agent-pipeline vocabulary into source.** Comments (and code
  identifiers, log strings, and JSX) in shipped files must not reference the
  internal planning pipeline: no agent names (Aristotle/Optimus/Cyrus/Scout/
  Ranger), no plan step numbers (`Step 3`, `Step 4a`), no assumption or risk
  IDs (`A9`, `A10`, `risk R6`), no "wave"/"handoff"/"gate" framing. These are
  scaffolding for building the code, not facts about the code. A ticket key on
  its own (e.g. `// PROJ-1234:` linking a gotcha to its ticket) is fine; the
  step/risk/assumption tokens are not. If a comment only makes sense to someone
  who read the plan, delete it or rewrite it as the underlying constraint.
- **Comments should explain non-obvious intent, trade-offs, or constraints** that the code itself cannot convey — *why* something is done, a gotcha, a spec reference, a perf constraint, a security consideration, or a link to a ticket/issue. If a future contributor would be confused without the comment, keep it. Otherwise, delete it.
- **Keep existing meaningful comments.** Do not strip comments that explain intent, only remove the narrative ones if you encounter them during an edit.
- **Tests are code too.** The same rule applies — test names and `describe`/`it` blocks should carry the intent; do not add narrating comments inside test bodies.

If you find yourself writing a comment that paraphrases the next line, delete it. If you cannot delete it because it encodes real intent, rename the variable/function or extract a helper so the code itself communicates it.

**Reviewers (Scout, Ranger, code-auditor) must flag narrative comments** as a code quality issue during PR review, not just at write time. This is how the rule gets enforced across the pipeline.

---

## Error Handling — Global Defaults

When external tools or subagents fail, follow these defaults unless a specific
skill overrides them:

### Subagent failures
- If a parallel subagent fails, times out, or returns empty: continue with
  results from remaining agents. Note the gap in the output.
- If >50% of parallel agents in a batch fail: abort and report rather than
  presenting partial results.
- Do not auto-retry subagents — surface the failure to the user/orchestrator.

### External tool failures (`gh`, `git`)
- If `gh` fails with auth errors: prompt the user to run `gh auth login`.
- If `gh` returns a non-auth error: surface the error message and stop.
  Do not guess or retry silently.
- If `git` hits merge conflicts or dirty worktree: surface and stop.
  Do not attempt automatic conflict resolution.

### MCP / Jira failures
- All Jira operations are best-effort. Log failures, continue without
  ticket data. Never block a pipeline on Jira unavailability.
- Primary: Atlassian MCP plugin.

### Jenkins MCP failures (CI diagnosis)
- The Jenkins MCP (`jenkins-mcp`) is an OPTIONAL dependency for CI log diagnosis.
- Before calling any Jenkins MCP tool, check if `mcp__jenkins-mcp__get_build_errors` is listed in your available tools. If not, the MCP is not configured — skip Jenkins operations silently.
- If a Jenkins MCP tool call fails or times out: log the failure, continue without CI log context. Never block any workflow on Jenkins MCP availability.
- Fall back to `gh pr checks` for CI status information when Jenkins MCP is unavailable.
- **Key tools:** `get_build_errors` (primary diagnosis), `get_test_results` (JUnit), `get_failed_stages` (pipeline), `get_multibranch_branch` (branch→build resolution), `check_build` (poll status), `get_stage_log` (stage-specific logs), `get_recent_failures` (scan for broken jobs).
- Agents that use Jenkins MCP: briefing (CI enrichment), Ranger (review context), Scout (review context), Cyrus (autonomous CI fix loop).

### General principle
- **Degrade gracefully, never silently.** If something fails, the user should
  know what failed, what was skipped, and what to do about it.

---

## PR Reviews & Comments (Scout and Ranger Agents)

When using Scout or Ranger to post **PR approvals** or **PR comments**:

1. **Always draft first.** Before posting anything to GitHub, show the exact text that will be submitted and ask for explicit approval.
2. **Never auto-post.** Even if the user says "approve on my behalf" or "post the comments" — always surface the draft first, then wait for confirmation before submitting.
3. This applies to: approval reviews, inline comments, general review comments, and any other GitHub PR interactions.

## PR Review Comments — Always Pending

When posting inline review comments to GitHub PRs via the API (`pulls/{number}/reviews`), **always create pending reviews** so I can review and submit them manually from the GitHub UI.

- **Omit the `event` field entirely** from the API payload — this defaults to `PENDING` state.
- **Never use `"event": "COMMENT"`** for inline comments — that submits the review immediately.
- PR-level notes (semver labels, CI status, general observations) go in the review `body`, not as inline comments on arbitrary files.
- This applies to all agents: Ranger, Scout, code-auditor, and any manual `gh api` review calls.

## Automated Comment Marker — 🤖 prefix

Every comment an agent posts on my behalf — **Jira and GitHub alike** — is prefixed with the 🤖 robot emoji so the reader can tell at a glance that a machine authored it. This holds even when I approved the exact text (e.g. a Scout/Ranger PR comment I confirmed at the draft gate): approval makes the *content* mine, but the *authorship* is still the agent, and the marker reflects that.

**The rule:** any comment body an agent submits to an external system (Jira issue comments, GitHub PR review comments, GitHub inline/diff comments, GitHub general PR comments, GitHub issue comments) **must begin with `🤖 `** — the emoji followed by a single space, before the comment text.

**Scope — what this covers:**

- Autonomous status pings (`/ticket-pickup`, `/ticket-swarm` Jira updates) — already do this; the marker is now canonical here.
- Approval-gated PR comments (`/scout-reviewer`, `/ranger-reviewer`) — the draft I approve and the posted text both carry the prefix. Show the 🤖 in the draft preview so what I approve is what posts. (`/code-auditor` routes to these reviewers but never posts to GitHub itself, so the prefix is applied by whichever reviewer it delegates to, not by the auditor.)
- Any manual `gh api` / `gh pr comment` / Jira-MCP comment an agent issues during a task.

**The one carve-out — "unless instructed":** if I explicitly tell the agent to post in my own voice without the marker (e.g. "post this comment as me, no robot prefix"), omit it. The instruction must be explicit; the default is always to include 🤖.

**What this does NOT cover:** commit messages, PR titles, PR *bodies/descriptions* (those follow the separate Co-Authored-By / "Generated with Claude Code" conventions), and Slack posts (those follow the Slack-PR-posting emoji conventions). This rule is specifically about *comments* on issues and pull requests.

---

