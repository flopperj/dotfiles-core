### Trigger-Based Skill Invocation

These skills are invoked when the user's request matches a trigger phrase (not a name prefix):

| Trigger phrase | Skill invoked | What it does |
|---|---|---|
| "deconstruct this to first principles", "strip the assumptions", "think from first principles", "what's really true here" | `/aristotle-deconstructor` | First-principles deconstruction → Optimus → Cyrus pipeline |
| "plan this out", "create an execution plan", "break this down into steps", "architect this" | `/optimus-planner` | Detailed execution plan → Cyrus handoff |
| "implement this with TDD", "write tests first", "build this test-first", "add test coverage" | `/cyrus-tdd-engineer` | TDD implementation (Red-Green-Refactor) with 80%+ coverage |
| "audit this code" | `/code-auditor` | Complexity audit + auto-route to Scout or Ranger |
| "review this PR thoroughly", "do a staff-level review", "is this ready to merge", "post review comments" | `/ranger-reviewer` | Staff-level PR review (Opus, approval-gated) |
| "pick up a ticket", "grab the next bug", "what's my next ticket" | `/ticket-pickup` | Single-ticket entry point for the agent pipeline |
| "fix my bugs", "swarm my tickets", "batch fix bugs", "process my bug queue", "swarm this story" | `/ticket-swarm` | Batch ticket pickup → team leads → parallel pipelines → PRs |
| "analyze my last swarm", "review swarm results", "what went wrong in the swarm", "improve swarm accuracy" | `/swarm-retro` | Analyze swarm runs for misclassifications and improvement opportunities |
| "update my dotfiles", "sync dotfiles", "pull latest dotfiles", "are my dotfiles up to date" | `/dotfiles-sync` | Check for dotfiles updates, preview changes, pull and re-run install.sh |
| "check my setup", "is everything working", "run diagnostics", "validate my dotfiles" | `/doctor` | Diagnostic health check — validates symlinks, CLI tools, MCP, plugins, agent memory |
| "create an overlay", "scaffold an overlay", "set up a new overlay", "add an overlay skill", "configure my overlay", "add an overlay fragment" | `/overlay-init` | Scaffold a new dotfiles-core overlay or extend an existing one (add skill / fragment / context section) |
| "briefing", "sitrep", "what needs my attention", "catch me up", "morning briefing", "show me my dashboard", "what should I work on", "what's my status" | `/briefing` | Session-start situation report — Jira sprint status, open PRs, CI, suggested actions |
| "remind me", "watch this", "nudge me", "track this", "show my obligations", "cancel obligation" | `/obligations` | Create, view, cancel, and evaluate cross-session obligations |
| "create a ticket", "file a bug" | `/create-jira-ticket` | Create Jira tickets (Stories, Bugs, Tasks, Epics) via MCP |
| "tech spec", "design doc", "design document", "implementation proposal" | `/create-tech-spec` | Generate tech spec with solution approach, estimates, and rollout plan |
| "mermaid to PNG", "diagram image", "export diagram" | `/mermaid-diagrams` | Convert Mermaid syntax to PNG via mmdc |
| "Google Doc", "save to Docs" | `/google-docs` | Create, read, and edit Google Docs with markdown conversion |
| "Google Drive", "upload to Drive" | `/google-drive` | Search, upload, download, and share Google Drive files |
| "smart compact", "compact with options", "context is getting big, help me compact smartly", "let's compact but I want to pick what to keep" | `/smart-compact` | Smarter /compact — shows a topic menu so you choose what survives the summary |
| "show me context percentage", "set up my statusline", "I want to see how much context I have left" | `/smart-statusline` | Install a Claude Code statusline showing model, cost, and context usage |
| "agent stats", "agent metrics", "first-pass rate", "how is the pipeline doing" | `/agent-stats` | Aggregate metrics.jsonl across projects: first-pass rate, classification distribution, health flags |
| "lessons review", "what have I learned", "show me my lessons", "patterns across projects" | `/lessons-review` | Surface all per-project lessons.md entries in one view; gate promotion to cross-project lessons on user approval |
| "grill me", "stress-test this plan", "interview me on this design" | `/grill-me` | Interview the user one question at a time until shared understanding is reached on every branch of the design tree |
| "to-prd", "create a PRD", "write a PRD", "save this as a PRD" | `/to-prd` | Synthesize the current conversation context into a structured PRD saved to `~/.claude/tasks/<project>/prds/<slug>.md` |
| "forge this", "from idea to PR", "shape this from scratch", "take this from rough idea to built", "let's grill this idea, write it up, and build it" | `/forge` | Five-stage sense-making + build pipeline orchestrating grill-me → to-prd → aristotle-deconstructor → optimus-planner → cyrus-tdd-engineer with two orchestrator gates |
| "park this session", "park work for a fresh session", "hand off this task", "checkpoint this session" | `/handoff` | Park the current session — capture typed rejections + next intent for the next session on this branch |

Each skill defines its own orchestration flow, gates, and downstream handoffs. Refer to the skill's SKILL.md for details.

