## Agent Routing — Name-Based Invocation

When the user's prompt starts with an agent name, invoke that agent's skill automatically. Strip the agent name prefix and pass the rest as the problem/task.

| Prompt prefix | Skill invoked | What it does |
|---|---|---|
| **Aristotle, ...** | `/aristotle-deconstructor` | First-principles deconstruction → Optimus → Cyrus pipeline |
| **Optimus, ...** | `/optimus-planner` | Detailed execution plan → Cyrus handoff |
| **Cyrus, ...** | `/cyrus-tdd-engineer` | TDD implementation (Red-Green-Refactor) |
| **Ranger, ...** | `/ranger-reviewer` | Staff-level PR review (Opus, approval-gated) |
| **Scout, ...** | `/scout-reviewer` | PR review (Sonnet, approval-gated) |
| **Swarm, ...** | `/ticket-swarm` | Batch ticket pickup -> team leads -> parallel pipelines -> PRs |
| **Pickup, ...** | `/ticket-pickup` | Single ticket fetch + classify + route to pipeline |
| **Retro, ...** | `/swarm-retro` | Analyze last swarm run, find misclassifications, propose heuristic updates |
| **Auditor, ...** | `/code-auditor` | Complexity audit + auto-route to Scout or Ranger |
| **Sitrep, ...** | `/briefing` | Situation report: sprint status, PRs, CI, stale reviews, suggested actions |
| **Obligations, ...** | `/obligations` | Create, view, cancel, and evaluate cross-session obligations |
| **Sync, ...** | `/dotfiles-sync` | Check for dotfiles updates, preview changes, pull and re-run install.sh |
| **Doctor, ...** | `/doctor` | Diagnostic health check — validates symlinks, CLI tools, MCP, plugins, agent memory |
| **Forge, ...** | `/forge` | Five-stage sense-making + build pipeline (grill-me → to-prd → aristotle-deconstructor → optimus-planner → cyrus-tdd-engineer) |

> When the user asks to "review my PR", "check this PR", or "review my changes" without specifying Scout or Ranger by name, invoke `/code-auditor` to let the auditor choose the appropriate reviewer based on code complexity.

