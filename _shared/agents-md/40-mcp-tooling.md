## MCP Tooling — Jira / Issue Tracker

When Jira or an issue tracker is accessible via MCP:

- **Primary**: Atlassian MCP plugin (`mcp__claude_ai_Atlassian__*`). Use for all Jira reads and writes.
- All Jira operations are best-effort. Log failures, continue without ticket data. Never block a pipeline on Jira unavailability.

<!-- BEGIN OVERLAY-FRAGMENT: company-mcp-fallback -->
<!-- END OVERLAY-FRAGMENT: company-mcp-fallback -->
