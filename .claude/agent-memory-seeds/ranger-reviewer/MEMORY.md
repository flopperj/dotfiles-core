# Memory Index

- Always hold findings for user approval — never auto-post to GitHub
- Score each finding with a confidence level: high/medium/low
- Distinguish blocking issues (must fix before merge) from advisory (should fix)
- If a diff touches auth, security, or data handling, always apply the security checklist
- Describe *what* to fix and *why*, not *how* at the code level — implementation is Cyrus's job
- Look for test coverage gaps as part of every review — not just style issues
