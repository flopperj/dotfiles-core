#!/usr/bin/env bash
# boundaries-gen.sh — Splice canonical responsibility-boundaries table into all
# SKILL.md files that declare the <!-- BEGIN/END RESPONSIBILITY BOUNDARIES --> sentinels.
#
# Usage: bash scripts/boundaries-gen.sh
#
# Idempotent: running this script multiple times produces identical output.
# The <!-- EXTRA_ROWS: key1,key2 --> directive inside the sentinel block
# controls which extra rows are prepended before the core 6-agent table.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE="$DOTFILES_DIR/.claude/_shared/responsibility-boundaries.md"
EXTRAS="$DOTFILES_DIR/.claude/_shared/responsibility-boundaries-extras.md"

if [ ! -f "$CORE" ]; then
    echo "ERROR: Core boundaries file not found: $CORE" >&2
    exit 1
fi

if [ ! -f "$EXTRAS" ]; then
    echo "ERROR: Extras boundaries file not found: $EXTRAS" >&2
    exit 1
fi

count=0

while IFS= read -r target; do
    # Parse EXTRA_ROWS directive from the existing sentinel block content
    extra_keys="$(sed -n '/BEGIN RESPONSIBILITY BOUNDARIES/,/END RESPONSIBILITY BOUNDARIES/{
        /EXTRA_ROWS:/{
            s/.*EXTRA_ROWS:[[:space:]]*//
            s/[[:space:]]*-->//
            p
            q
        }
    }' "$target")"

    tmp_content="$(mktemp)"

    if [ -n "$extra_keys" ]; then
        # Preserve the EXTRA_ROWS directive as the first line inside the block
        echo "<!-- EXTRA_ROWS: $extra_keys -->" > "$tmp_content"

        # Write table header once
        echo "| Agent | Sole responsibility | NEVER does |" >> "$tmp_content"
        echo "|---|---|---|" >> "$tmp_content"

        # Append each extra row by key
        IFS=',' read -ra keys <<< "$extra_keys"
        for key in "${keys[@]}"; do
            # Trim whitespace
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"

            # Extract the table row that follows the <!-- key --> comment
            row="$(awk -v k="<!-- $key -->" '$0 == k { getline; print; exit }' "$EXTRAS")"
            if [ -n "$row" ]; then
                echo "$row" >> "$tmp_content"
            else
                echo "WARNING: No extras entry found for key '$key' in $EXTRAS" >&2
            fi
        done

        # Append core rows (skip the 2-line header — already written above)
        tail -n +3 "$CORE" >> "$tmp_content"
    else
        # No extra rows — just use the core table as-is
        cat "$CORE" > "$tmp_content"
    fi

    _replace_between_sentinels "$target" "RESPONSIBILITY BOUNDARIES" "RESPONSIBILITY BOUNDARIES" "$tmp_content"
    rm -f "$tmp_content"
    count=$((count + 1))
done < <(
    # Restrict scope to canonical SKILL.md and agent files.  Scanning all of
    # .claude/ pulls in test fixtures (which contain literal sentinels in
    # heredocs) and any leaked .claude/worktrees/ tree, which then causes
    # _replace_between_sentinels to abort or — worse — splice the table over
    # unrelated content.
    grep -l "BEGIN RESPONSIBILITY BOUNDARIES" \
        "$DOTFILES_DIR"/.claude/skills/*/SKILL.md \
        "$DOTFILES_DIR"/.claude/agents/*.md \
        2>/dev/null
)

echo "Updated responsibility boundaries in $count file(s)"
