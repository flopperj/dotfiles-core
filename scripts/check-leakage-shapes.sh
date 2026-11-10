#!/usr/bin/env bash
# check-leakage-shapes.sh — secret-free structural leakage scan for public CI.
#
# Runs on every PR/push where the real company-token list is unavailable.
# Detects publication-risk *shapes* (in-tree denylist files, guard dirs,
# corporate email addresses in agent/skill prose) without embedding any
# company-specific token values.
#
# Usage: bash scripts/check-leakage-shapes.sh [DIR]   (default ".")
#   Inside a git work tree only committable files are scanned (tracked plus
#   untracked-but-not-ignored); elsewhere every file under DIR.
#
# Exit codes:
#   0 — clean
#   1 — at least one shape violation (file/line only, matched content withheld)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

SCAN_DIR="${1:-.}"
[ "$SCAN_DIR" = "/" ] || SCAN_DIR="${SCAN_DIR%/}"

# Domains that are safe fixtures in docs and tests — not publication risks.
SAFE_EMAIL_DOMAINS='example\.com|example\.org|test\.com|localhost|users\.noreply\.github\.com'

FOUND=0

_report() {
    FOUND=1
    echo "LEAKAGE-SHAPE: $1 — line(s): ${2}(content withheld)" >&2
}

# --- Shape 1: in-tree denylist or guard material must never be committed ---
while IFS= read -r -d '' path; do
    case "$path" in
        */leakage-tokens.txt|*/portable-ticket-prefixes.txt|*/dotfiles-guard/*) ;;
        *) continue ;;
    esac
    _report "$path" "entire file "
done < <(_scan_files "$SCAN_DIR")

# --- Shape 2: corporate email addresses in Claude publication surfaces ---
# Scan agent markdown, every markdown file and every scripts/ file inside a
# skill, and everything under _shared; withhold matched content in output.
EMAIL_PATTERN='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
while IFS= read -r -d '' file; do
    case "$file" in
        */agents/*.md|*/skills/*/*.md|*/skills/*/scripts/*|*/_shared/*) ;;
        *) continue ;;
    esac
    grep -qI '' "$file" 2>/dev/null || continue
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        lineno="${line%%:*}"
        rest="${line#*:}"
        domain="$(printf '%s' "$rest" | grep -ioE "$EMAIL_PATTERN" | head -1 | cut -d@ -f2 | tr '[:upper:]' '[:lower:]')" || true
        [ -n "$domain" ] || continue
        if printf '%s' "$domain" | grep -qiE "^(${SAFE_EMAIL_DOMAINS})$"; then
            continue
        fi
        _report "$file" "${lineno} "
    done < <(grep -inE "$EMAIL_PATTERN" "$file" 2>/dev/null || true)
done < <(_scan_files "$SCAN_DIR/.claude")

if [ "$FOUND" -ne 0 ]; then
    echo "" >&2
    echo "Leakage shape check FAILED. Matched content is withheld by design." >&2
    exit 1
fi
exit 0
