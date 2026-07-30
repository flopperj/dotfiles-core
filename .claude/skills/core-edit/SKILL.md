---
name: core-edit
description: "Edit a skill inside dotfiles-core from within an overlay repo — handles the cd, commit, push, and submodule pointer-bump sequence. Use when the user says /core-edit <skill>, 'edit core skill', or 'update core'. Automates the cross-repo edit workflow."
user-invocable: true
---

# Core-Edit — Cross-Repo Skill Editor

Edit a skill inside `dotfiles-core` from within an overlay repo. Handles
the submodule cd, commit, push (to both remotes), and overlay pointer-bump
in one supervised sequence.

---

## Prerequisites

This skill requires an overlay context — a repo with `.gitmodules`
referencing `.claude/dotfiles-core`. Running it from a standalone
`dotfiles-core` clone is an error.

---

## Step 1 — Detect context

Verify overlay context:

```bash
# Must be run from the overlay root (or a subdir)
# Find overlay root by walking up to find .gitmodules
git rev-parse --show-toplevel
```

Check:
1. The result has `.gitmodules` at the root that references `dotfiles-core`.
2. `.claude/dotfiles-core/.git` exists (submodule initialized).

If either check fails:
```
ERROR: /core-edit must be run from inside an overlay repo with a dotfiles-core submodule.
Current directory does not appear to be an overlay root.
Hint: cd to your dotfiles overlay directory and re-run.
```
Stop.

---

## Step 2 — Validate skill argument

The user must provide a skill name:

```
/core-edit <skill-name>
```

Check that `.claude/dotfiles-core/.claude/skills/<skill-name>/` exists.

If missing:
```
ERROR: skill '<skill-name>' not found in dotfiles-core.
Available skills:
  <list from ls .claude/dotfiles-core/.claude/skills/>
```
Stop.

If found: confirm the path and proceed.

---

## Step 3 — Show current content

Before editing, show the user what's in the skill:

```bash
cat .claude/dotfiles-core/.claude/skills/<skill-name>/SKILL.md | head -30
```

Report: "Opening `.claude/dotfiles-core/.claude/skills/<skill-name>/SKILL.md` for editing."

---

## Step 4 — Present targeted edit

Ask the user what they want to change. Receive the edit intent and apply
it using the standard Edit tool on the file at:

```
.claude/dotfiles-core/.claude/skills/<skill-name>/SKILL.md
```

Run leakage check on the modified file before proceeding:

```bash
bash .claude/dotfiles-core/scripts/check-no-leakage.sh .claude/dotfiles-core/.claude/skills/<skill-name>/
```

If the leakage check fails, it reports file/line references only (matched
content is withheld by design) — ask the user to revise the edit against
those locations and re-check. Do not commit a file with leakage tokens.
On machines without the company-context marker the check skips cleanly.

---

## Step 5 — Show diff and confirm

```bash
git -C .claude/dotfiles-core diff .claude/skills/<skill-name>/
```

Present the diff. Ask:

```
Commit this change to dotfiles-core?
  -> y = Yes, commit and push
  -> n = Discard
  -> e = Edit more
```

---

## Step 6 — Commit and push to core

On `y`:

```bash
cd .claude/dotfiles-core
git add .claude/skills/<skill-name>/
git commit -m "feat(<skill-name>): <user-provided description>"
git push origin main
cd ../..
```

Report the commit SHA:
```
Committed to dotfiles-core: <sha> — <message>
Pushed to origin (GHE).
```

---

## Step 7 — Bump submodule pointer in overlay

```bash
# In overlay root
new_sha=$(git -C .claude/dotfiles-core rev-parse --short HEAD)
git add .claude/dotfiles-core
git commit -m "core: bump pointer to ${new_sha} (<skill-name> update)"
```

Report:
```
Overlay submodule pointer bumped to <new_sha>.
Commit: core: bump pointer to <new_sha> (<skill-name> update)
```

---

## Step 8 — Reinstall

Re-run core's installer to pick up any changes to the skill directory
(symlinks are resolved at install time, so this is usually a no-op for
skill edits — but it ensures freshness):

```bash
bash .claude/dotfiles-core/install.sh
```

---

## Summary

Report:
```
/core-edit complete.
  Skill:         <skill-name>
  Core commit:   <sha>
  Pointer bump:  overlay @ <new_sha>
  Reinstall:     done
```

---

## Gate rules

- **Always confirm before committing** to either repo (Step 5 gate).
- **Never commit a leakage-check failure.** The check in Step 4 is mandatory.
- **Never edit files outside the target skill directory** in the core repo.
- **Pointer bump is mandatory** after every core commit. Leaving the overlay
  pinned to an old SHA creates confusion.
