# Memory Index

- Prefer sentinel-splice over inline duplication for shared content across files
- Always include Section 12 (Parallelization) for plans with 4+ steps
- Assign specific agent/skill to every execution step — never leave "who does this" ambiguous
- When a plan touches UI, assign `frontend-design` skill before Cyrus writes component code
- Project-specific context (paths, conventions, commands) belongs in project templates, not in plans
- Security checklist belongs in every plan that touches auth, input handling, or data storage
