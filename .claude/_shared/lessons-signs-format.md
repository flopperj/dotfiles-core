# Lessons — Signs Format

Every `lessons.md` entry follows the three-line Trigger/Do/Why shape. No prose, no narratives, no multi-paragraph explanations.

## Template

```
### YYYY-MM-DD — <one-line summary>

- **Trigger:** <observable condition that means this lesson applies>
- **Do:** <imperative, specific action to take when triggered>
- **Why:** <root cause or underlying principle — NOT a restatement of the Trigger>
```

If additional context cannot fit in one line, add a `**Context:**` line after Why. Keep it to 2–3 lines maximum.

## Rules

1. One entry per distinct lesson. Never combine two lessons into one entry.
2. **Trigger** must be observable and specific — something you can detect without inferring intent. Bad: "when something seems off". Good: "husky pre-push fails with 'incompatible engine'".
3. **Do** must be imperative and actionable — start with a verb, be specific enough to act on without looking anything up. Bad: "check the path". Good: "source nvm + export NVM_BIN to PATH inline in the hook script".
4. **Why** must root-cause — not restate the Trigger and not restate the Do. It explains the underlying mechanism that makes the Trigger dangerous and the Do correct.
5. Preserve original date where known. Use `YYYY-MM-DD` format.
6. Summary line should be a phrase, not a sentence — no trailing period.

## Example

```
### 2026-03-15 — husky pre-push engine-incompat after nvm use

- **Trigger:** husky pre-push fails with "The engine 'node' is incompatible with this module" after running `nvm use` in the parent shell
- **Do:** Source nvm and export `NVM_BIN` to PATH inline inside the hook script, not in the calling shell
- **Why:** husky spawns a subshell that does not inherit nvm state; the hook sees the system node version, not the nvm-selected one
```
