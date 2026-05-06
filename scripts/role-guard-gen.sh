#!/usr/bin/env bash
# role-guard-gen.sh — Splice per-identity role-guard fragments from
# .claude/_shared/role-guards/ into agent files that declare the
# <!-- BEGIN/END ROLE GUARD --> sentinels.
#
# Usage: bash scripts/role-guard-gen.sh
#
# Idempotent: running this script multiple times produces identical output.
# Directive format inside sentinel block:
#   <!-- ROLE_GUARD: <key> -->
# where <key> matches a file .claude/_shared/role-guards/<key>.md

set -euo pipefail

_tmpfiles=()
trap 'rm -f "${_tmpfiles[@]}"' EXIT INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$DOTFILES_DIR/.claude/agents"
FRAGMENTS_DIR="$DOTFILES_DIR/.claude/_shared/role-guards"

# Optional --agents-dir / --fragments-dir override (for testing)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --agents-dir) AGENTS_DIR="$2"; shift 2 ;;
        --fragments-dir) FRAGMENTS_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[ -d "$FRAGMENTS_DIR" ] || { echo "ERROR: fragments dir not found: $FRAGMENTS_DIR" >&2; exit 1; }

count=0
while IFS= read -r target; do
    # Parse ROLE_GUARD directive from the sentinel block
    key="$(sed -n '/BEGIN ROLE GUARD/,/END ROLE GUARD/{
        /ROLE_GUARD:/{
            s/.*ROLE_GUARD:[[:space:]]*//
            s/[[:space:]]*-->//
            p
            q
        }
    }' "$target")"

    if [ -z "$key" ]; then
        echo "WARNING: No ROLE_GUARD directive found in $target" >&2
        continue
    fi

    fragment="$FRAGMENTS_DIR/${key}.md"
    if [ ! -f "$fragment" ]; then
        echo "WARNING: No fragment for key '$key' at $fragment" >&2
        continue
    fi

    # Build the block content: preserve the directive line, then the fragment body
    tmp_content="$(mktemp)"
    _tmpfiles+=("$tmp_content")
    echo "<!-- ROLE_GUARD: $key -->" > "$tmp_content"
    cat "$fragment" >> "$tmp_content"

    _replace_between_sentinels "$target" "ROLE GUARD" "ROLE GUARD" "$tmp_content"
    rm -f "$tmp_content"
    count=$((count + 1))
done < <(grep -rl "BEGIN ROLE GUARD" "$AGENTS_DIR/")

echo "Updated role guards in $count file(s)"
