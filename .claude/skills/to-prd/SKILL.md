---
name: to-prd
description: Turn the current conversation context into a PRD and save it as a markdown file. Use when the user wants to capture a feature plan, design discussion, or implementation idea as a structured PRD. Triggers on "to-prd", "create a PRD", "write a PRD", "save this as a PRD".
user-invocable: true
---

This skill takes the current conversation context and codebase understanding and produces a structured PRD saved as a markdown file. Do NOT interview the user — synthesize what you already know from the conversation.

## Process

### 1. Explore the codebase (if not already done)

Explore the repo to understand the current state of any code relevant to this feature. Identify the major modules that would need to be built or modified.

Actively look for opportunities to extract **deep modules** — modules that encapsulate a lot of functionality behind a simple, stable, testable interface. Prefer deep modules over shallow ones.

### 2. Check understanding with the user

Before writing, present:
- A short summary of the problem and proposed solution as you understand it
- A list of the major modules you expect to build or modify
- Which of those modules you'd recommend writing tests for

Ask the user to confirm or correct before continuing.

### 3. Resolve the output path

Output path: `~/.claude/tasks/<project>/prds/<slug>.md`

- Resolve `<project>` with: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
- Derive `<slug>` from the feature name: lowercase, words separated by hyphens (e.g., `user-profile-caching.md`)
- Create the `prds/` directory if it doesn't exist

### 4. Write the PRD

Use the template below. Be thorough — especially on user stories. A short PRD is a weak PRD.

### 5. Confirm and share

After writing the file:
- Show the full resolved path
- Print a short summary (problem + solution, 2–3 sentences)
- Suggest the user share the file path with teammates or attach it to the relevant Jira ticket

---

## PRD Template

```markdown
# PRD: <Feature Name>

**Project:** <project>
**Date:** <YYYY-MM-DD>
**Status:** Draft

---

## Problem Statement

The problem that the user is facing, from the user's perspective.

---

## Solution

The solution to the problem, from the user's perspective.

---

## User Stories

A numbered list of user stories covering all aspects of the feature. Each in the format:

1. As a <actor>, I want <feature>, so that <benefit>.

Be exhaustive — cover happy paths, edge cases, error states, and admin/operator scenarios.

---

## Implementation Decisions

A list of implementation decisions made during planning. May include:

- Modules to build or modify
- Interface contracts between modules
- Architectural decisions and trade-offs considered
- Schema changes
- API contracts
- Specific interactions and data flows

Do NOT include specific file paths or code snippets — they go stale fast.

---

## Testing Decisions

- What makes a good test for this feature (test external behavior, not implementation details)
- Which modules will have tests written
- Prior art in the codebase (similar test patterns to follow)

---

## Out of Scope

What is explicitly not being built in this iteration.

---

## Further Notes

Anything else worth capturing — open questions, follow-up spikes, links to prior art or related PRDs.
```
