---
name: dotfiles-sync
description: "Check for and pull dotfiles updates, then re-run install.sh. Use when the user types /dotfiles-sync, starts a prompt with 'Sync', or asks to 'update my dotfiles', 'sync dotfiles', 'pull latest dotfiles', or 'are my dotfiles up to date'. Environment-aware for CWS (yadm) and local (git + symlinks)."
user-invocable: true
---

# Dotfiles Sync

Check for dotfiles updates, show what changed, pull with user approval,
and re-run `install.sh` to apply. Environment-aware for CWS (yadm) and
local (git + symlinks).

---

## Step 1: Detect environment

Determine whether this is a CWS workspace or a local machine:

```bash
if [ -n "${WORKSPACE_ID:-}" ] || [ -n "${CWS_WORKSPACE_ID:-}" ]; then
  # CWS: yadm manages dotfiles directly at $HOME
else
  # Local: dotfiles repo is a separate directory with symlinks
fi
```

**CWS path**: The dotfiles repo root is `$HOME` (yadm checkout). Use
`yadm` commands for all git operations.

**Local path**: Detect the dotfiles directory by following the
`~/.claude/CLAUDE.md` symlink back to its source:
```bash
cd "$(dirname "$(readlink ~/.claude/CLAUDE.md)")" && cd .. && pwd -P
```
Fall back to `~/dotfiles` if the symlink doesn't exist. Use `git`
commands in that directory.

---

## Step 2: Check for updates

Fetch the latest from origin (with a 10-second timeout to avoid hanging
on network issues):

**CWS:**
```bash
cd $HOME && timeout 10 yadm fetch origin
```

**Local:**
```bash
cd {dotfiles-dir} && timeout 10 git fetch origin
```

Then count commits behind:
```bash
git rev-list HEAD..origin/master --count
# (or yadm rev-list HEAD..origin/master --count)
```

**If fetch fails** (network unavailable, timeout):
```
Cannot reach origin to check for updates.
  -> retry = Try again
  -> x     = Skip (stay on current version)
```

**If already up to date** (count = 0):
```
Dotfiles are current. Nothing to sync.
```
Stop here.

---

## Step 3: Show what changed

If commits behind > 0, show the changes:

```bash
git log HEAD..origin/master --oneline
# (or yadm log HEAD..origin/master --oneline)
```

Also identify which categories of files changed:
```bash
git diff HEAD..origin/master --name-only
```

Categorize changes for the user:
- **Skills**: `.claude/skills/*/SKILL.md`
- **Agents**: `.claude/agents/*.md`
- **Global instructions**: `.claude/CLAUDE.md`
- **Hooks**: `.cursor/hooks.json`, `.cursor/hooks/*`
- **Install script**: `install.sh`
- **Aliases**: `.aliases.local`
- **Other**: anything else

---

## Step 4: Present and gate

Show the summary and ask:

```
Dotfiles are N commits behind origin/master.

  Commits:
    abc1234 feat: add swarm-retro skill
    def5678 feat: strengthen Jira transition instructions
    ghi9012 fix: branch creation default detection

  Changed categories:
    - Skills: ticket-swarm, swarm-retro (new), ticket-pickup
    - Agents: (none)
    - Global: CLAUDE.md
    - Hooks: hooks.json

  -> pull = Pull changes and re-run install.sh
  -> diff = Show full diff before pulling
  -> x    = Skip (stay on current version)
```

Wait for user input. Do not pull without explicit approval.

If the user picks `diff`:
```bash
git diff HEAD..origin/master
# (or yadm diff HEAD..origin/master)
```
Then re-show the gate menu.

---

## Step 5: Pull and install

**CWS:**
```bash
cd $HOME && yadm pull origin master && bash $HOME/install.sh
```

**Local:**
```bash
cd {dotfiles-dir} && git pull origin master && bash {dotfiles-dir}/install.sh
```

Capture the output of `install.sh` and present a summary.

---

## Step 6: Report results

Show what was applied:

```
Dotfiles synced successfully.

  Pulled: N commits
  New skills: swarm-retro
  Updated skills: ticket-swarm, ticket-pickup
  Updated: CLAUDE.md, hooks.json
  install.sh: completed (no warnings)

Your agent definitions, skills, and hooks are now current.
```

If `install.sh` produced warnings (e.g., "exists and is not a symlink"),
surface them prominently.

---

## Edge cases

- **Merge conflicts or dirty working tree (CWS)**: In CWS environments,
  always discard local changes in favor of what's latest on master.
  Local dotfiles edits in CWS are ephemeral — the source of truth is
  the repo. Run:
  ```bash
  yadm checkout -- .   # or git -C $HOME checkout -- .
  yadm pull origin master
  ```
  Inform the user that local changes were discarded, but do not gate
  on approval — CWS local changes are never authoritative.
- **Merge conflicts or dirty working tree (local)**: On local machines,
  warn the user and suggest stashing or committing first. Do not
  auto-discard — local machines may have intentional uncommitted work.
- **yadm not installed** (CWS without yadm binary): Fall back to plain
  git if the yadm repo is at `$HOME`. Use `git -C $HOME` commands.
- **Branch mismatch**: If the local branch is not `master`, note this
  and ask which branch to pull from.

---

## Gate rules

- **Never auto-pull on local machines.** Always show changes and wait for approval.
- **CWS environments auto-discard local changes.** The remote master is
  always authoritative in CWS. Discard local modifications and pull
  without gating on dirty-tree approval (still show what was pulled).
- **Never modify dotfiles content.** This skill pulls and installs;
  it does not edit skill files, agents, or CLAUDE.md.
- **Network failures are non-blocking.** If fetch fails, inform and
  offer retry. Do not error out.
- **install.sh is always re-run after pull.** Even if only one file
  changed, the install script ensures all symlinks and plugins are
  current.

---

## Step 7: Submodule pointer-bump (dotfiles-core)

After pulling overlay updates, check whether the dotfiles-core submodule
has upstream changes available.

### Step 7a — Detect submodule

Check if `.claude/dotfiles-core/` exists as a submodule in the overlay:

```bash
git -C {dotfiles-dir} submodule status .claude/dotfiles-core 2>/dev/null
```

If the submodule is absent or not initialized, skip this entire Step 7.

### Step 7b — Fetch core updates

```bash
git -C {dotfiles-dir}/.claude/dotfiles-core fetch origin 2>&1
```

Count commits the submodule is behind:

```bash
git -C {dotfiles-dir}/.claude/dotfiles-core rev-list HEAD..origin/main --count
```

If count = 0, report "dotfiles-core is current." and skip Step 7c.

### Step 7c — Show new core commits

```bash
git -C {dotfiles-dir}/.claude/dotfiles-core log --oneline HEAD..origin/main
```

Present:

```
dotfiles-core has N new commits upstream:

  abc1234 feat: migrate briefing skill into core
  def5678 fix: trap cleanup in lib-overlays.sh

  -> b = Bump submodule pointer to latest + reinstall
  -> s = Skip (leave submodule at current SHA)
  -> h = Help (explain what bumping does)
```

Wait for user input.

On `h`:
```
Bumping the pointer means:
  1. git -C .claude/dotfiles-core checkout origin/main
  2. git add .claude/dotfiles-core
  3. git commit -m "core: bump pointer to <short-sha>"
  4. Re-run install-overlay.sh then dotfiles-core/install.sh
The overlay's submodule then tracks the new core SHA.
```
Re-show the menu.

### Step 7d — Bump pointer

On `b`:

```bash
# Advance submodule to origin/main
git -C {dotfiles-dir}/.claude/dotfiles-core checkout origin/main

# Commit the pointer bump in the overlay
cd {dotfiles-dir}
new_sha=$(git -C .claude/dotfiles-core rev-parse --short HEAD)
git add .claude/dotfiles-core
git commit -m "core: bump pointer to ${new_sha}"

# Re-run overlay install (apply fragments), then core install (symlinks)
bash {dotfiles-dir}/.claude/dotfiles-core/install.sh
```

Report:

```
dotfiles-core bumped to <new-sha>.
Reinstalled core symlinks and overlay fragments.
```

---

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
