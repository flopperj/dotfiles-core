---
name: create-tech-spec
description: Generate a technical specification or design document for a proposed implementation using context from prior research. Includes solution approach, component breakdown (leverage/enhance/build), sequence diagrams, work estimates, and rollout plan. Use when the user wants to create a tech spec, write a design doc, document a proposed solution, or says "tech spec", "design document", or "implementation proposal" after completing research.
disable-model-invocation: true
user-invocable: true
---

# Create Tech Spec

Generate a tech spec using context from a prior `/research` or `/create-report` run.

## Output Location

Before generating output, determine where to save files:

1. **Check user prompt** — if the user specifies a path, use that (one-time override)
2. **Check `persist-path.txt`** — look for `data/persist-path.txt` in this skill's directory (resolves via `~/.claude/skills/create-tech-spec/data/persist-path.txt` or `~/.cursor/skills/create-tech-spec/data/persist-path.txt`)
3. **If file exists** — use the path from it
4. **If file does not exist** — prompt the user:
   > "Where would you like tech specs saved? Provide an absolute path (e.g., `~/Desktop/Tech Specs`)."
5. **Persist the choice** — write to `data/persist-path.txt` in this skill's directory

## Prerequisites

This skill works best with prior context from research or an existing report. If no prior context exists, prompt the user to provide relevant background or run a codebase exploration first.

## Process

1. **Review existing context** - Use findings from prior research/report
2. **Identify gaps** - Determine missing information for the spec
3. **Ask clarifying questions** - Fill in gaps before generating
4. **Generate tech spec** - Use the template below
5. **Save to desktop** - Output as markdown file

## Output

Save the tech spec (path from persist-path.txt; see "Output Location" section):
- Filename: `[feature-name]-tech-spec-[YYYY-MM-DD].md`

## Template

Use the template in `tech-spec-template.md` (in this skill directory).

## Guidance

When filling out sections:

- **Section 3.2 Alternatives**: Pull from prior research/report analysis
- **Section 4.1 Components**: Categorize as Leverage (reuse), Enhance (modify), Build (new)
- **Section 4.2 Sequence diagrams**: Use Mermaid syntax if possible
- **Section 6 Work estimates**: Provide ranges if uncertain
- **Section 8 Rollout plan**: Include feature flag strategy per project conventions

## Google Docs Integration

After saving the tech spec locally:

1. **If user mentioned "Google Doc" in prompt** → Create immediately without confirmation
2. **Otherwise** → Ask: "Would you like me to create this as a Google Doc?"

If yes:

```bash
bash ~/.claude/skills/google-docs/scripts/create_from_markdown.sh "[Feature] Tech Spec - [YYYY-MM-DD]" --file /path/to/spec.md
```

See `google-docs/integration.md` skill for details.

If the tech spec contains mermaid diagrams that need to be exported as PNG images for Google Docs, use the `/mermaid-diagrams` skill to convert them.
