#!/usr/bin/env bash
# check-no-leakage.sh — scan a directory for forbidden company tokens.
#
# Usage: bash scripts/check-no-leakage.sh [DIR]
#   DIR defaults to "." (current directory).
#
# Exit codes:
#   0 — no forbidden tokens found
#   1 — at least one forbidden token found (matches printed to stdout)
#
# Token list lives in scripts/leakage-tokens.txt (relative to this script).
# Tokens are matched case-insensitively with word-boundary anchoring.
#
# Exclusions:
#   .git/                         — version control internals
#   scripts/leakage-tokens.txt    — canonical token list (defines forbidden words, not a leak)
#   tests/leakage-check.bats      — test fixture legitimately contains tokens

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENS_FILE="$SCRIPT_DIR/leakage-tokens.txt"
SCAN_DIR="${1:-.}"

if [ ! -f "$TOKENS_FILE" ]; then
    echo "ERROR: leakage-tokens.txt not found at $TOKENS_FILE" >&2
    exit 2
fi

# Build a list of tokens from the file, skipping blank lines and comments.
mapfile -t TOKENS < <(grep -v '^\s*#' "$TOKENS_FILE" | grep -v '^\s*$')

if [ "${#TOKENS[@]}" -eq 0 ]; then
    echo "WARNING: leakage-tokens.txt is empty; nothing to check." >&2
    exit 0
fi

FOUND=0

for token in "${TOKENS[@]}"; do
    # Word-boundary pattern: character preceding/following the token must NOT
    # be in [a-zA-Z0-9_-]. We anchor by prepending/appending the boundary
    # class. For tokens containing special regex chars (. @ -), we escape them.
    escaped_token="$(printf '%s' "$token" | sed 's/[.[\*^${}()+?|]/\\&/g')"
    pattern="(^|[^a-zA-Z0-9_-])${escaped_token}([^a-zA-Z0-9_-]|$)"

    # Use find to enumerate files, excluding .git/ and the leakage test fixture.
    while IFS= read -r -d '' file; do
        # Skip binary files (git objects, images, etc.).
        # Use null-byte detection rather than `file` classification: `file` can
        # misidentify legitimate text files (e.g. files starting with ``` are
        # flagged as "Dyalog APL transfer"). grep -qI '' exits 0 for files with
        # no null bytes (safe to grep as text) and exits 1 for true binaries.
        if grep -qI '' "$file" 2>/dev/null; then
            matches="$(grep -inE "$pattern" "$file" 2>/dev/null || true)"
            if [ -n "$matches" ]; then
                FOUND=1
                echo "=== LEAKAGE FOUND in $file ===" >&2
                echo "$matches" >&2
                echo ""
                # Also print to stdout for capture in tests
                echo "=== LEAKAGE FOUND in $file ==="
                echo "$matches"
            fi
        fi
    done < <(find "$SCAN_DIR" \
        -not -path "*/.git/*" \
        -not -name ".git" \
        -not -path "*/scripts/leakage-tokens.txt" \
        -not -path "*/tests/leakage-check.bats" \
        -type f \
        -print0 2>/dev/null)
done

if [ "$FOUND" -ne 0 ]; then
    exit 1
fi

exit 0
