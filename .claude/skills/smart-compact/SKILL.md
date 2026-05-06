---
name: smart-compact
description: "Smarter /compact — shows a topic menu from the current session so you choose what survives the summary. Use when the user types /smart-compact, says 'smart compact', asks to 'compact with options', wants to 'choose what to focus the compact on', wants to reduce context or tokens while staying in control of what gets kept, or says things like 'context is getting big, help me compact smartly' or 'let's compact but I want to pick what to keep'. Surfaces the top 5 topics most-recent-first, lets the user pick by number, select all, smart-pick, custom, or default, then generates the exact /compact command to run."
user-invocable: true
---

# Smart Compact

The user wants to compact the conversation but stay in control of what survives
the summary. Your job is to reflect on the conversation, surface the key topics
as a clean menu, let the user pick, then run `/compact` with a precise focus
string.

This costs almost nothing extra — the conversation is already in your context,
so topic extraction is just reflection, not a new scan.

## Step 1: Show topic menu

Show the topic menu. Extract the 5 most meaningful discussion
topics from this session, **sorted most recent first** — the freshest work at
the top since that's most likely what the user wants to preserve.

Be specific, not generic. "Discussed billing code" is bad.
"OrderPaymentService null pointer bug — root cause traced to getPricingPlan()" is good.

Format:
```
🧠 Smart Compact — here's what we covered this session:

1. {topic — one line, specific, includes key outcome or artifact}
2. {topic}
3. {topic}
4. {topic}
5. {topic}

💬 Showing top 5 by recency — type 'm' to see all topics

What to keep in the summary?
  → Enter numbers (e.g. 1,3,5)
  → a  = all of the above
  → m  = show more topics
  → c  = custom focus (you type it)
  → s  = smart pick (I'll choose what matters most for continuing work)
  → d  = default   (no focus — /compact decides everything)
```

Good topics mention: the specific thing worked on, what was found/decided/built,
and any artifact (file, ticket, PR, fix). Avoid vague phrases like "discussed X"
— say what the outcome was.

If the user types **m**, show all topics (up to 10), numbered continuing from 6,
then re-show the options menu so they can pick from the full list.

## Step 2: Wait for user input

Wait for the user to respond. Don't proceed until they pick.

## Step 3: Confirm and compact

Based on their choice:

After determining the focus, always end with this exact format so the user knows
what to do — `/compact` is a built-in CLI command that only the user can run,
not Claude:

```
📋 Copy and run this in your chat input to compact:

/compact Focus on: {focus string}
```

**Numbers (e.g. "1,3")** — combine those topics into a focused sentence:
```
Got it — compacting with focus on:
  • {topic 1 title}
  • {topic 3 title}

📋 Copy and run this in your chat input to compact:

/compact Focus on: {one sentence combining the selected topics, specific enough
that the summary will preserve the key facts, decisions, and artifacts from each}
```

**"a" (all)** — cover ALL topics discussed in the session, not just the 5 shown.
Reflect on the full conversation to write a comprehensive focus string:
```
Got it — keeping everything.

📋 Copy and run this in your chat input to compact:

/compact Focus on: {comprehensive sentence covering all topics discussed}
```

**"c" (custom)** — ask them to type their focus, then:
```
📋 Copy and run this in your chat input to compact:

/compact Focus on: {their exact words}
```

**"d" (default)** — no focus string, let `/compact` decide everything:
```
Got it — running default compact, no focus guidance.

📋 Copy and run this in your chat input to compact:

/compact
```

**"s" (smart pick)** — choose the 2-3 topics most likely to matter for
continuing work (prefer: decisions made, code changed, open tickets, unresolved
issues over: background research, debugging dead-ends, already-resolved issues):
```
Smart pick — keeping the topics most useful for continuing:
  • {topic A}
  • {topic B}

📋 Copy and run this in your chat input to compact:

/compact Focus on: {focused sentence on chosen topics}
```

## What makes a good focus string

The focus string tells `/compact` what to prioritize in the summary. A good one:
- Names specific files, tickets, PRs, functions, or decisions
- Mentions what was concluded, not just what was discussed
- Is one sentence, 20-40 words

Bad: "Focus on: the work we did today"
Good: "Focus on: FINOPS-4925 open PR #311134 payment validation logging,
OrderPaymentService null pointer root cause at line 894, and Jira MCP auth fix
via token refresh"

## Maintenance

If you discover something during this task that would improve this skill,
propose the change and ask me to confirm before saving it.
