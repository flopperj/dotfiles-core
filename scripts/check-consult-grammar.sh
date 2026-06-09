#!/usr/bin/env bash
# check-consult-grammar.sh — positive grammar check for consult-instructions.
#
# Usage: bash scripts/check-consult-grammar.sh [SCAN_DIR [VOCAB_FILE]]
#   SCAN_DIR   defaults to "." (current directory)
#   VOCAB_FILE defaults to "scripts/consult-vocabulary.txt" (relative to this script)
#
# Exit codes:
#   0 — all consult-instructions are valid (or none present)
#   1 — at least one grammar violation (vocabulary mismatch or anti-prose)
#   2 — fatal configuration error (vocabulary file missing or empty)
#
# What is checked:
#   Check 1 — Vocabulary match: every consult-instruction's section name must
#             appear in the vocabulary file. Backtick form is required.
#   Check 2 — Anti-prose: any mention of "overlay-context.md" that is NOT in the
#             valid backtick form is a violation (symmetric to overlay's Check 2).
#
# The vocabulary file format: one "## Section Name" line per entry; lines
# beginning with "#" are comments.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_DIR="${1:-.}"
VOCAB_FILE="${2:-$SCRIPT_DIR/consult-vocabulary.txt}"

# ---------------------------------------------------------------------------
# Load vocabulary
# ---------------------------------------------------------------------------

if [ ! -f "$VOCAB_FILE" ]; then
    echo "ERROR: vocabulary file not found at $VOCAB_FILE" >&2
    exit 2
fi

# Read section entries only: lines that start with "## " (two hashes + space).
# Comment lines (single # followed by space or end of line) are skipped.
# Note: avoid `mapfile`/`readarray` (bash 4+); this repo targets macOS bash 3.2.
VOCAB_SECTIONS=()
while IFS= read -r _line; do
    VOCAB_SECTIONS+=("$_line")
done < <(grep '^## ' "$VOCAB_FILE")

if [ "${#VOCAB_SECTIONS[@]}" -eq 0 ]; then
    echo "ERROR: vocabulary file is empty (no section entries found): $VOCAB_FILE" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Scan SKILL.md files
# ---------------------------------------------------------------------------

# Grammar regex for a well-formed consult-instruction:
#   consult `## <section-name>` in `~/.claude/overlay-context.md`
CONSULT_GRAMMAR_REGEX='consult `## [^`]+` in `~/.claude/overlay-context.md`'

# Anti-prose regex: any mention of overlay-context.md not part of a valid
# backtick-section form. We catch lines containing overlay-context.md that
# do NOT contain the full well-formed pattern.
ANTI_PROSE_REGEX='overlay-context\.md'

FOUND=0

while IFS= read -r -d '' skill_file; do
    # ---------------------------------------------------------------------------
    # Check 1: Every consult-instruction section name must be in the vocabulary
    # ---------------------------------------------------------------------------
    while IFS= read -r consult_line; do
        # Extract the section name from the backtick form.
        # Pattern: consult `## <name>` in `~/.claude/overlay-context.md`
        section_name="$(printf '%s' "$consult_line" | grep -oE '`## [^`]+`' | head -1 | tr -d '`')"

        if [ -z "$section_name" ]; then
            continue
        fi

        # Check whether the extracted section is in the vocabulary.
        found_in_vocab=0
        for vocab_entry in "${VOCAB_SECTIONS[@]}"; do
            if [ "$vocab_entry" = "$section_name" ]; then
                found_in_vocab=1
                break
            fi
        done

        if [ "$found_in_vocab" -eq 0 ]; then
            FOUND=1
            echo "GRAMMAR VIOLATION in $skill_file: unknown section '$section_name'" >&2
            echo "GRAMMAR VIOLATION in $skill_file: unknown section '$section_name'"
        fi
    done < <(grep -E "$CONSULT_GRAMMAR_REGEX" "$skill_file" 2>/dev/null || true)

    # ---------------------------------------------------------------------------
    # Check 2: Anti-prose — a line that has "consult" and "overlay-context.md"
    # but does NOT match the well-formed backtick consult-instruction form.
    # Pure documentary mentions of overlay-context.md (without "consult") are
    # not consult-instructions and are not flagged.
    # ---------------------------------------------------------------------------
    while IFS= read -r prose_line; do
        # Only flag lines that have both "consult" and "overlay-context.md"
        # but do not match the valid backtick form — i.e., a prose-form
        # consult-instruction attempt.
        # Match "consult" as a standalone word (not "consult-instruction" compound).
        # The word boundary check: not preceded or followed by [-a-zA-Z0-9].
        if printf '%s' "$prose_line" | grep -qiE '(^|[^a-zA-Z0-9-])consult([^a-zA-Z0-9-]|$)' && \
           ! printf '%s' "$prose_line" | grep -qE "$CONSULT_GRAMMAR_REGEX"; then
            FOUND=1
            echo "GRAMMAR VIOLATION in $skill_file: prose-form consult-instruction (use backtick form: consult \`## Section\` in \`~/.claude/overlay-context.md\`)" >&2
            echo "GRAMMAR VIOLATION in $skill_file: prose-form consult-instruction (use backtick form: consult \`## Section\` in \`~/.claude/overlay-context.md\`)"
        fi
    done < <(grep -iE "$ANTI_PROSE_REGEX" "$skill_file" 2>/dev/null || true)

done < <(find "$SCAN_DIR" \
    -path "*/.claude/skills/*/SKILL.md" \
    -type f \
    -print0 2>/dev/null)

if [ "$FOUND" -ne 0 ]; then
    exit 1
fi

exit 0
