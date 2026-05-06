---
name: review-context
description: "Generate or edit a per-project llms.txt that tells Scout/Ranger what historically breaks in this project. Stored at ~/.claude/review-context/<project>/llms.txt — outside any working repo. Use when the user types /review-context, asks to 'set up review context for this repo', 'tell reviewers what to watch for', or 'create a review-context file'."
user-invocable: true
---

# Review Context

Generate or edit a per-project `llms.txt` at `~/.claude/review-context/<project>/llms.txt` (outside any working repo) that informs Scout and Ranger what historically matters in this project.

## When to Use

- Starting work on a project and wanting reviewers to know its sharp edges
- After a post-mortem or incident — encode what broke so reviewers watch for it
- Before requesting a review — priming Scout/Ranger with project-specific context
- When reviewers keep missing the same class of issue in this repo
- Updating stale context after significant architectural changes

## Workflow

1. **Resolve the project slug**: `project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")`
2. **Determine the target path**: `~/.claude/review-context/$project/llms.txt`
3. **Assert storage safety**: the target path MUST start with `$HOME/.claude/review-context/`. If it does not, fail immediately with: "Storage path assertion failed — will not write outside ~/.claude/review-context/". Never write inside the working repo.
4. **Check for existing file**:
   - If absent: offer to generate a starter from the template below. Ask the user to fill in each section or provide bullet points to seed it.
   - If present: display the current content and ask which sections to update.
5. **Write the file**: `mkdir -p "$(dirname "$target_path")"` then write or update the file.
6. **Confirm**: report the path written and remind the user that Scout/Ranger will load this automatically on the next review of this project.

## Checklist

- [ ] Project slug resolved via `git rev-parse --show-toplevel`
- [ ] Target path starts with `$HOME/.claude/review-context/` (assertion checked)
- [ ] `~/.claude/review-context/$project/` directory created
- [ ] At least one section has content (not all blank)
- [ ] No file created inside the working repo
- [ ] User confirmed the written path

## File Format

The skill writes a file with this shape (sections are headings; each section has 3–5 bullet points):

```
# Review Context — <project>

## Key Review Domains
- <what this codebase does and what makes it hard to review correctly>
- <the layer or service that receives the most bugs>

## Cross-Language Consistency
- <if the project spans multiple languages, what contracts must stay in sync>

## Data Integrity
- <schema invariants, idempotency requirements, or ordering constraints>

## Security
- <known sensitive paths, authn/authz patterns, anything that's been a vuln before>

## Performance
- <hot paths, known N+1 patterns, SLA-sensitive queries>

## Architecture
- <the key abstractions, which boundaries matter, what the "grain" of the system is>
```

Sections with nothing to say can be omitted. A file with 3 populated sections is better than 6 half-filled ones.

## Storage Rule

The file MUST live at `~/.claude/review-context/<project>/llms.txt`.

- Never at repo root (`./llms.txt`)
- Never at `.claude/review-context.md` inside the repo
- Never anywhere inside the working repo tree

This is the user's explicit decision: personal context lives outside the repo to prevent accidental staging. Teammates cannot see it; that trade-off is accepted.
