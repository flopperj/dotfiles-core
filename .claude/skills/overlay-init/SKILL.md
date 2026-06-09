---
name: overlay-init
description: "Scaffold a new dotfiles-core overlay or extend an existing one. Use when the user types /overlay-init, asks to 'create an overlay', 'scaffold an overlay', 'set up a new overlay', 'add an overlay skill', 'configure my overlay', or 'add an overlay fragment'. Bare invocation scaffolds; add-skill / add-fragment / add-context configure."
user-invocable: true
---

# overlay-init — Overlay Scaffold & Configuration Skill

Scaffold a new dotfiles-core overlay from scratch, or extend an existing one
by adding skills, skill-fragments, or overlay-context sections.

---

## Step 1 — Parse subcommand and detect context

Determine mode from the arguments passed:

- If args begin with `add-skill`, `add-fragment`, or `add-context` → **configure mode**
  (requires an existing overlay; refuses otherwise — see gate rules).
- All other invocations → **scaffold mode**.

**Overlay context detection** (same check as `/core-edit`):

```bash
git rev-parse --show-toplevel
```

Confirm two conditions:
1. The toplevel has `.gitmodules` referencing `dotfiles-core`.
2. `.claude/dotfiles-core/.git` exists (submodule initialized).

If both conditions pass → running inside an overlay. If either fails → not in an overlay.

**Configure mode with no overlay context:** refuse immediately:

```
ERROR: This subcommand requires an overlay context.
Current directory does not appear to be inside an overlay repo.
Hint: cd to your dotfiles overlay directory and re-run, or use bare
/overlay-init to scaffold a new overlay.
```

---

## Step 2 — Scaffold route (bare invocation)

Prompt for the two required values if not already supplied as arguments:

- **Target directory** — where to scaffold the overlay (default: `~/dotfiles`)
- **Overlay name** — human-readable name used in README and commit messages
  (default: basename of the target directory)

Optional flags passed through to the engine:
- `--force` — overwrite a non-empty target dir instead of refusing
- `--core-url <url>` — explicit submodule URL (required when core's `origin` is a local path)

Locate the core engine. The engine lives at:

```bash
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="$CORE_DIR/scripts/new-overlay.sh"
```

Invoke the engine:

```bash
bash "$ENGINE" "<target>" "<overlay-name>" [--force] [--core-url <url>]
```

**Surface the engine's output verbatim** — this includes the next-step command block
and the `--check` result printed by the engine.

**Reasoning layer added by this skill (not the engine):** if `--check` exits non-zero,
explain to the user the two most likely causes:

1. The submodule was not cloned with `--recurse-submodules`, so
   `.claude/dotfiles-core/` is an empty dir without a valid HEAD.
   Remedy: `git submodule update --init --recursive` inside the new overlay dir.
2. The install state that `--check` validates is the *current* `~/.claude` install,
   not the freshly-scaffolded dir in isolation. A failure here means the existing
   dotfiles install has a broken symlink or missing tool — not that the scaffold
   itself is broken. Remedy: run `bash <target>/install.sh` once the overlay is
   fully set up (after commit + push).

Do NOT auto-fix beyond what the engine did. Surface the failure and stop.

---

## Step 3 — add-skill route (overlay-local)

Usage: `/overlay-init add-skill <name>`

Refuse if not in an overlay (Step 1 gate).

Create the skill stub in the overlay's own skill directory:

```bash
mkdir -p ".claude/skills/<name>"
```

Write `.claude/skills/<name>/SKILL.md` with minimal correct frontmatter:

```
---
name: <name>
description: "<name> — describe what this skill does and when to invoke it."
user-invocable: true
---

# <name>

TODO: Document this skill.
```

Confirm to the user:
```
Created overlay skill: .claude/skills/<name>/SKILL.md
Next: edit the description and body, then run install.sh to symlink it.
```

This is purely overlay-local. No core files are touched.

---

## Step 4 — add-fragment route (overlay-local)

Usage: `/overlay-init add-fragment <core-skill>`

Refuse if not in an overlay (Step 1 gate).

Create the fragment directory:

```bash
mkdir -p ".claude/skill-fragments/<core-skill>"
```

Append a complete, valid entry to `.claude/overlay-fragments.yaml`. The entry
must match the exact schema that `apply_manifest` parses (name / target / source):

```yaml
  - name: <core-skill>-overlay-ext
    target: ~/.claude/skills/<core-skill>/SKILL.md
    source: .claude/skill-fragments/<core-skill>/ext.md
```

A half-entry must never be written. If the manifest does not yet exist, create it
with the empty manifest header first:

```yaml
fragments: []
```

Then append the entry. If it does exist, append after the last entry.

Confirm to the user:
```
Created fragment dir:  .claude/skill-fragments/<core-skill>/
Appended entry to:     .claude/overlay-fragments.yaml
  name:   <core-skill>-overlay-ext
  target: ~/.claude/skills/<core-skill>/SKILL.md
  source: .claude/skill-fragments/<core-skill>/ext.md
Next: write the fragment content to ext.md, then run install-overlay.sh.
```

If the manifest-append logic grows beyond a few lines, extract it into a
focused helper in `scripts/` and add bats coverage for that helper.

---

## Step 5 — add-context route (THE CENTERPIECE — bilateral contract)

Usage: `/overlay-init add-context <Section>`

This is the fully decidable bilateral contract operation. `<Section>` is the
exact heading name (e.g., `Jenkins MCP clone URL`).

Refuse if not in an overlay (Step 1 gate).

### 5a — Write the overlay half

Append a stub section to the overlay's `overlay-context.md`:

```markdown
## <Section>

TODO: Fill in your overlay-specific context for this section.
```

### 5b — Verify the overlay half is present

Confirm the section heading now exists:

```bash
grep -Fxq "## <Section>" .claude/overlay-context.md
```

If absent, report the failure and stop.

### 5c — Check for the core-side gap

The bilateral contract requires two artifacts on the core side. Check them
using the same method the linters use:

**Artifact 1 — vocabulary entry:**

```bash
grep -Fxq "## <Section>" <core>/scripts/consult-vocabulary.txt
```

Reports: PRESENT or MISSING.

**Artifact 2 — core SKILL.md consult-instruction:**

Check whether any core SKILL.md contains a well-formed consult-instruction for
this section. The well-formed grammar is defined in PROTOCOL.md §Grammar. The
section name is the only variable component; the file path is fixed.

```bash
# The grammar requires the full form — section name AND the fixed trailing
# path. See scripts/check-consult-grammar.sh ~line 52 for the authoritative
# regex. Matching section name alone gives a false "PRESENT" when the
# trailing path is absent (make check-consult-grammar would still reject it).
SUFFIX='in `~/.claude/overlay-context.md`'
grep -rlE "consult \`## <Section>\` $SUFFIX" <core>/.claude/skills/*/SKILL.md 2>/dev/null
```

Reports: which core skill file contains it, or MISSING.

### 5d — Route core-side changes to /core-edit

Print the following TODO block verbatim, substituting `<Section>` with the
actual section name and `<core>` with the resolved core path:

```
add-context: wrote overlay half
  ## <Section>  ->  .claude/overlay-context.md         [DONE]

CORE SIDE REQUIRED — use /core-edit to land both of these:

  1. Add this line to <core>/scripts/consult-vocabulary.txt:
       ## <Section>

  2. Add a consult-instruction to the relevant core SKILL.md.
     The exact grammar is defined in PROTOCOL.md §Grammar:
       consult `## <Section>` in
       `~/.claude/overlay-context.md`
     (That two-line representation is for readability; the actual
      consult-instruction must appear on a single line in the core SKILL.md.)

Until both artifacts are present in core, `make check-consult-grammar`
(core) and the overlay's scripts/lint-consult-blocks.sh will report
## <Section> as an orphan.
```

Do NOT auto-edit core. Do NOT auto-commit. Route only.

### 5e — Optional: run the overlay's orphan linter

If `scripts/lint-consult-blocks.sh` exists in the overlay, offer to run it:

```
Offer: Run scripts/lint-consult-blocks.sh to see ## <Section> flagged as
an orphan? This confirms the core side is still missing.  [y/n]
```

If the script is absent, skip this offer silently.

---

## Gate rules

- **Never auto-edit or auto-commit core.** The `add-context` route prints a TODO
  and routes to `/core-edit`; it never touches core files directly.
- **Configure routes refuse outside an overlay.** All three configure subcommands
  (`add-skill`, `add-fragment`, `add-context`) require overlay context (Step 1
  gate). Fail loudly with the hint from Step 1.
- **Scaffold never commits.** The engine stages files (`git add -A`) but does not
  commit. Never add a commit step to the scaffold route.
- **`add-context` always prints the core-side TODO** — even if both artifacts are
  already present in core (in that case, prefix with "Core side already wired:"
  and confirm both checks pass instead of marking them MISSING).
- **Never write a half-entry to overlay-fragments.yaml.** The `add-fragment` route
  either writes a complete `name`/`target`/`source` entry or writes nothing.
