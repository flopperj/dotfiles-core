#!/usr/bin/env bash
# reviewer-blocks-gen.sh — Splice shared reviewer contract fragments from
# .claude/_shared/reviewer-blocks/ into reviewer SKILL.md files that declare
# matching <!-- BEGIN/END <LABEL> --> sentinels.
#
# Usage: bash scripts/reviewer-blocks-gen.sh
#
# Idempotent: running this script multiple times produces identical output.
# Directive format inside each sentinel block:
#   <!-- REVIEWER_BLOCK: <key> -->
# where <key> matches a file .claude/_shared/reviewer-blocks/<key>.md and the
# sentinel label is the uppercased key (tone-calibration -> TONE-CALIBRATION).
#
# Unlike role-guard-gen.sh, a single target file may carry several directives
# (one per shared block), so every directive occurrence in a file is processed.

set -euo pipefail

_tmpfiles=()
trap '(( ${#_tmpfiles[@]} )) && rm -f "${_tmpfiles[@]:-}"' EXIT INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_lib.sh disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$DOTFILES_DIR/.claude/skills"
FRAGMENTS_DIR="$DOTFILES_DIR/.claude/_shared/reviewer-blocks"

# Optional --skills-dir / --fragments-dir override (for testing)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skills-dir) SKILLS_DIR="$2"; shift 2 ;;
        --fragments-dir) FRAGMENTS_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[ -d "$FRAGMENTS_DIR" ] || { echo "ERROR: fragments dir not found: $FRAGMENTS_DIR" >&2; exit 1; }

count=0
while IFS= read -r target; do
    # A file may declare several REVIEWER_BLOCK directives — process them all.
    while IFS= read -r key; do
        [ -n "$key" ] || continue

        fragment="$FRAGMENTS_DIR/${key}.md"
        if [ ! -f "$fragment" ]; then
            echo "WARNING: No fragment for key '$key' at $fragment (in $target)" >&2
            continue
        fi

        label="$(echo "$key" | tr '[:lower:]' '[:upper:]')"

        # Build the block content: preserve the directive line, then the fragment body
        tmp_content="$(mktemp)"
        _tmpfiles+=("$tmp_content")
        echo "<!-- REVIEWER_BLOCK: $key -->" > "$tmp_content"
        cat "$fragment" >> "$tmp_content"

        _replace_between_sentinels "$target" "$label" "$label" "$tmp_content"
        rm -f "$tmp_content"
        count=$((count + 1))
    done < <(sed -n 's/.*REVIEWER_BLOCK:[[:space:]]*\([a-z-]*\)[[:space:]]*-->.*/\1/p' "$target")
done < <(grep -rl "REVIEWER_BLOCK:" "$SKILLS_DIR/")

echo "Updated reviewer blocks in $count block(s)"
