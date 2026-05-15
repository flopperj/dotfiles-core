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
#   PROTOCOL.md                   — protocol meta-doc names tokens by design (same reason as leakage-tokens.txt)

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

# PROVISIONAL — superseded by check-consult-grammar.sh in Cohort 2.
# See PROTOCOL.md § "Enforcement evolution" for the migration path.
#
# The consult-instruction sub-string is stripped from each line before token
# scanning. The grammar is: consult `## <section-name>` in `~/.claude/overlay-context.md`
# Stripping (not line-skipping) ensures free-prose tokens on the same line are
# still caught. Only the section-name portion — which may contain denylist tokens
# for legitimate reasons — is removed from consideration.
# shellcheck disable=SC2016  # sed script — single quotes are intentional; no shell expansion wanted
CONSULT_INSTRUCTION_SED='s/consult `## [^`]*` in `~\/.claude\/overlay-context.md`//g'

FOUND=0

for token in "${TOKENS[@]}"; do
    # Word-boundary pattern: character preceding/following the token must NOT
    # be an alphanumeric. Underscore (_) and hyphen (-) are NOT word chars here
    # so that "<token>_suffix" and "prefix-<token>" forms are caught.
    # For tokens containing special regex chars (. @ -), we escape them.
    escaped_token="$(printf '%s' "$token" | sed 's/[.[\*^${}()+?|]/\\&/g')"
    pattern="(^|[^a-zA-Z0-9])${escaped_token}([^a-zA-Z0-9]|$)"

    # Use find to enumerate files, excluding .git/ and the leakage test fixture.
    while IFS= read -r -d '' file; do
        # Skip binary files (git objects, images, etc.).
        # Use null-byte detection rather than `file` classification: `file` can
        # misidentify legitimate text files (e.g. files starting with ``` are
        # flagged as "Dyalog APL transfer"). grep -qI '' exits 0 for files with
        # no null bytes (safe to grep as text) and exits 1 for true binaries.
        if grep -qI '' "$file" 2>/dev/null; then
            # Strip consult-instruction sub-strings before token scanning (PROVISIONAL allowlist).
            matches="$(sed "$CONSULT_INSTRUCTION_SED" "$file" 2>/dev/null \
                | grep -inE "$pattern" 2>/dev/null || true)"
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
        -not -path "*/tests/handoff-skill.bats" \
        -not -path "*/PROTOCOL.md" \
        -type f \
        -print0 2>/dev/null)
done

if [ "$FOUND" -ne 0 ]; then
    exit 1
fi

exit 0
