### Compound Intent Detection (Skill Chaining)

When the user's request implies multiple skills in sequence, detect the compound intent and chain them automatically with a gate between each stage. Do not wait for the user to manually invoke the second skill — recognize the full intent upfront.

| Intent pattern | Chain | Gate between stages |
|---|---|---|
| "create a ticket and implement it", "file a bug and fix it", "create a story and build it" | `/create-jira-ticket` → `/ticket-pickup <new-ticket-ID>` | Show created ticket, confirm before pickup |
| "create a tech spec and implement it", "write a design doc then build it" | `/create-tech-spec` → feed spec to `/optimus-planner` → `/cyrus-tdd-engineer` | Show spec, confirm before planning |
| "grill this then build it", "interview me, write a PRD, and ship it", "from rough idea to built", "let's stress-test, capture, challenge, plan, and build" | `/forge` (chains `/grill-me` → `/to-prd` → `/aristotle-deconstructor` → `/optimus-planner` → `/cyrus-tdd-engineer`; the last three are owned by `/aristotle-deconstructor`) | Two `/forge` gates (after grill-me, after to-prd); `/aristotle-deconstructor` owns its three internal gates |

**Rules for chaining:**
- **Always gate between creation and implementation stages.** The user should see what was created before committing to implementation.
- **Low-risk chains (test → lint) can auto-proceed** without an explicit gate.
- **Pass context forward.** The output of stage 1 (ticket ID, spec content, plan content) becomes the input to stage 2. Never lose context between stages.
- **If the first stage fails, stop.** Do not proceed to the second stage. Surface the failure.
- **Single-intent requests still use single skills.** "Create a ticket" without implementation intent invokes only `/create-jira-ticket`. The chaining only activates when the user's phrasing implies both creation and follow-through.

### General rules

- **Every stage transition requires user approval** in gated mode. Never auto-chain agents without the user confirming at each gate.
- **Autonomous mode relaxes gates** — used by ticket-swarm and ticket-pickup when processing batches. Pipeline transitions auto-approve; only triage selection and PR creation require user approval.
- **Each agent runs as a subagent** via the Agent tool to keep the main context clean.
- **Name matching is case-insensitive and flexible.** "Aristotle," / "aristotle:" / "ARISTOTLE" all match. The name must appear at the start of the prompt.
- **Slash commands work too.** Each of the following invokes the corresponding skill directly:
  - `/aristotle-deconstructor`, `/optimus-planner`, `/cyrus-tdd-engineer`
  - `/ranger-reviewer`, `/scout-reviewer`, `/code-auditor`
  - `/ticket-swarm`, `/ticket-pickup`, `/swarm-retro`
  - `/dotfiles-sync`, `/doctor`
  - `/briefing`, `/sitrep`, `/pr-create-from-commits`
  - `/smart-compact`, `/smart-statusline`
  - `/create-jira-ticket`, `/create-tech-spec`, `/mermaid-diagrams`
  - `/obligations`, `/google-docs`, `/google-drive`
  - `/agent-stats`, `/lessons-review`
  - `/grill-me`, `/to-prd`, `/forge`
  - `/handoff`

---

