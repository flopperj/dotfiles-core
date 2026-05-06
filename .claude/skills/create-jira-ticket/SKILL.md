---
name: create-jira-ticket
description: Create Jira tickets (Stories, Bugs, Tasks, Sub-tasks, Epics) in any project using the Atlassian MCP. Supports Story decomposition into swarmable sub-tasks. Use when the user asks to create a Jira ticket, story, bug, task, or issue, or mentions filing a ticket.
user-invocable: true
---

# Create Jira Ticket

Create Jira issues via MCP. All Jira operations are best-effort per CLAUDE.md.

**MCP server selection:**
1. **Primary: Atlassian MCP plugin** (`plugin-atlassian-atlassian`) — use `createJiraIssue`, `searchJiraIssuesUsingJql`, `getJiraIssue`, `getTransitionsForJiraIssue`, `transitionJiraIssue` tool names.
<!-- BEGIN DAST-ORCH-FALLBACK -->
<!-- END DAST-ORCH-FALLBACK -->

Try the Atlassian plugin first. If both fail, inform the user and continue without Jira.

## Workflow

### 0. Triage fuzzy requests (gate before Step 1)

Before gathering context, judge whether the user's request is **shaped enough** to write a useful ticket. A request is shaped when at least three of these are present or trivially inferable:

- A specific outcome (not just "fix X" or "improve Y")
- The surface area being changed (a feature, a flow, a file area)
- At least one acceptance criterion or "done when..." condition
- A reason / motivation (incident, customer ask, tech debt, etc.)

If the request is **fuzzy** (a one-liner, no acceptance criteria, no scoped surface area, no clear "done when"), offer to grill first:

```
Your request is fuzzy — a ticket created from this would have vague acceptance
criteria. Want me to grill you on it first to surface the decisions?

  -> g    = Run /grill-me first, then come back with a sharp draft
  -> skip = Create the ticket from what you gave me (I'll flag gaps in the description)
```

**If the user chooses "g":**

1. Invoke `/grill-me` with the user's rough idea as the input.
2. Wait for the interview to complete and the decision set to be locked.
3. Map the locked decisions into ticket fields:
   - **Summary** ← a one-line synthesis of the resolved problem
   - **Description** ← the locked decisions, rendered with the Description template (Summary, Acceptance Criteria, Technical Details)
   - **Acceptance Criteria** ← each locked decision that maps to a testable outcome becomes one criterion
4. Show the drafted ticket fields to the user and ask for confirmation before proceeding to Step 1.

**If the user chooses "skip":**

Proceed to Step 1 with the original input. Note any gaps you noticed (missing acceptance criteria, unclear scope) at the top of the description so they're visible to whoever picks the ticket up.

**Skip Step 0 entirely when:**
- The user provided a structured request (already has summary + acceptance criteria + scope)
- The caller is upstream automation (a swarm pipeline, another skill chaining to ticket creation) — they've already shaped the input
- The user explicitly asks for a quick/rough ticket ("just make me a placeholder for X")

### 1. Gather context

Before creating the ticket, determine:

- **Project key** (e.g., `EEE`, `MUL`). Infer from the branch name, conversation context, or ask.
- **Issue type**: Story (default when user says "ticket"), Bug, Task, or Epic.
- **Summary**: A concise title for the ticket.
- **Description**: Detailed context. Use Markdown formatting (headings, bullet lists, code blocks).
- **Sprint** (optional): The user may ask to add the ticket to a specific or "current" sprint.
- **Parent / Epic** (required prompt): Always ask the user for the parent Epic. Use `searchJiraIssuesUsingJql` to help find Epics in the project if needed.
- **Story points** (required estimate): Estimate the ticket size using the Fibonacci scale: **1, 2, 3, 5, 8**. Base the estimate on the scope of work described, then confirm with the user before creating.
  - **1 pt**: Trivial change — a single config update, copy change, or one-liner fix
  - **2 pts**: Small, well-defined task — a single file change with minimal risk
  - **3 pts**: Medium task — touches 2-3 files, straightforward implementation
  - **5 pts**: Larger task — multiple files, some complexity or unknowns
  - **8 pts**: Significant effort — cross-cutting changes, new patterns, or substantial unknowns
- **Labels, priority** (optional): Only set if the user specifies them.

### 2. Prompt for parent Epic and estimate

**Always** prompt the user for the parent Epic before creating the ticket. Use `AskQuestion` if available:

```
AskQuestion:
  - "Which Epic should this ticket belong to?" (free text or offer to search)
  - "I estimate this at N points based on [reasoning]. Does that look right?"
    options: 1, 2, 3, 5, 8
```

If the user doesn't know the Epic, search for Epics in the project using the Atlassian plugin `searchJiraIssuesUsingJql`.

Present the results and let the user pick. If they explicitly decline to set an Epic, proceed without one.

### 3. Discover required fields

Before creating, use the Atlassian plugin to check field requirements for the project and issue type.

### 4. Find the sprint (if needed)

If the user wants the ticket in the current or a specific sprint, use the Atlassian plugin to find the board and active sprint.

### 5. Create the ticket

Use `createJiraIssue` with:

```json
{
  "projectKey": "EEE",
  "issueType": "Story",
  "summary": "Concise ticket title",
  "description": "## Summary\n\nMarkdown description...\n\n## Acceptance Criteria\n\n- ...",
  "sprint": 12345,
  "parent": "EEE-100",
  "storyPoints": 3,
  "labels": ["label"],
  "priority": "P2: Medium"
}
```

<!-- BEGIN DAST-ORCH-EXAMPLES -->
<!-- END DAST-ORCH-EXAMPLES -->

**Required fields**: `projectKey`, `issueType`, `summary`.

### 6. Report back

After creation, share the ticket key and URL with the user:
- Key: returned in `key` field (e.g., `EEE-11907`)
- URL: returned in `url` field

### 7. Story decomposition (Stories only)

This step **only triggers for `issueType: "Story"`**. It does not apply to Bugs, Tasks, or Epics.

After the Story is created and reported (Step 6), offer to decompose it into sub-tasks:

```
The Story <KEY> has been created. Would you like to decompose it into sub-tasks?

  -> d = Decompose into sub-tasks (AI suggests, you edit before creation)
  -> n = No decomposition needed
  -> p = I'll add sub-tasks manually in Jira
```

**If the user chooses "d":**

1. **AI suggestion**: Analyze the Story's description and acceptance criteria. Propose sub-tasks targeting ~1 sub-task per 1-2 story points of the parent. Minimum 2, maximum 8 sub-tasks. Present an editable table:

```
Proposed sub-tasks for <KEY> (<parent-points> pts):

| # | Summary                           | Points | Notes                |
|---|-----------------------------------|--------|----------------------|
| 1 | Implement data model changes      | 2      | Schema + migrations  |
| 2 | Add API endpoint for X            | 3      | Controller + service |
| 3 | Write integration tests           | 2      | Covers AC 1-3        |

Total: 7 pts (parent estimate: 8 pts)

Edit this list (add/remove/change), or confirm to create.
```

2. **Edit loop**: Wait for the user to confirm or modify. They can add rows, remove rows, rename summaries, or adjust points. Re-present the table after edits until the user confirms.

3. **Create sub-tasks**: For each confirmed sub-task, call `createJiraIssue` sequentially (not in parallel — sequential creation allows error handling per sub-task):

```json
{
  "projectKey": "EEE",
  "issueType": "Sub-task",
  "summary": "Sub-task summary",
  "description": "## Context\n\nSub-task of <PARENT-KEY>: <parent-summary>\n\n## Scope\n\n- ...",
  "parent": "<PARENT-KEY>",
  "storyPoints": 2
}
```

Key details:
- `issueType` must be `"Sub-task"` (not "Story" or "Task")
- `parent` is the **Story key** (e.g., `EEE-11907`), not the Epic key
- Sub-tasks inherit sprint assignment from the parent Story
- Sub-task points should roughly sum to the parent Story's estimate
- Each sub-task description should reference the parent and scope its work clearly

4. **Report**: After all sub-tasks are created, show a summary:

```
Created N sub-tasks for <PARENT-KEY>:
  - <SUB-1>: Summary (N pts) — <url>
  - <SUB-2>: Summary (N pts) — <url>
  Total: X pts across N sub-tasks
```

5. **Handoff gate**: After sub-tasks are created, offer immediate pickup:

```
Sub-tasks are ready. What next?

  -> pickup = Pick up <PARENT-KEY> with /ticket-pickup (routes to swarm)
  -> done   = Stop here
```

If the user chooses "pickup", invoke `/ticket-pickup <PARENT-KEY>`. The pickup skill will detect the 2+ children and offer the swarm gate.

## Description template

Use this structure for Story descriptions:

```markdown
## Summary

[1-2 sentence overview of what this story accomplishes]

## Acceptance Criteria

- [Specific, testable criterion]
- [Another criterion]

## Technical Details

- **Key files**: `path/to/file.tsx`
- **Feature flag**: `team.flag_name`
- [Other relevant technical context]
```

**Decomposition tip:** When a Story is intended for sub-task decomposition (Step 7), write granular acceptance criteria — each criterion should map cleanly to one sub-task. This gives the AI decomposer clear boundaries for splitting work.

For Bugs, use:

```markdown
## Description

[What is happening vs. what should happen]

## Steps to Reproduce

1. [Step 1]
2. [Step 2]

## Expected Behavior

[What should happen]

## Actual Behavior

[What actually happens]
```

## Updating existing tickets

Use `editJiraIssue` with the issue key and fields to change.

## Adding tickets to a sprint after creation

Use the Atlassian plugin sprint tools to add issues to a sprint after creation.

## Transitioning ticket status

1. First get available transitions with `getTransitionsForJiraIssue`.
2. Then transition with `transitionJiraIssue`.

## Notes

- Priority values: `P0: Immediate`, `P1: High`, `P2: Medium`, `P3: Low`, `None`
- Description fields accept standard Markdown (bold, italic, code blocks, headings, lists, links)
- When the user says "ticket" they usually mean a Story
- Always prompt for the parent Epic and story point estimate before creating
- Always confirm the ticket details before creating if the information is ambiguous
- Story points use the Fibonacci scale: **1, 2, 3, 5, 8** — never use other values
- **Sub-tasks**: Use `issueType: "Sub-task"` (not "Story" or "Task"). The `parent` field takes the **Story key** (e.g., `EEE-11907`), not the Epic key. Sub-tasks inherit sprint assignment from their parent Story. Sub-task points should roughly sum to the parent Story's estimate.
- **Decomposition**: Step 7 only triggers for Stories. It is gated (user must choose "d") and never auto-fires. The `/ticket-pickup` skill expects Stories with 2+ children to be swarmable.
- **Fuzzy requests**: Step 0 gates on shape. If the user arrives with a one-liner and no acceptance criteria, offer `/grill-me` first to sharpen the ticket. The user can skip the gate for trivial or quick tickets.
