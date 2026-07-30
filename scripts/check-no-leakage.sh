#!/usr/bin/env bash
# check-no-leakage.sh — scan for forbidden tokens without ever printing them.
#
# The token list is data, not code: it lives OUTSIDE every repo working tree
# and is materialized by a private overlay installer. This repo never commits
# the list, and this script never echoes matched content — findings are
# reported as file/line references only, because the checker's own output is
# itself a publication channel (CI logs are public).
#
# Usage:
#   bash scripts/check-no-leakage.sh [DIR]      # scan a directory tree (default ".")
#   ... | bash scripts/check-no-leakage.sh --commits
#       # read commit SHAs (one per line) from stdin; scan each commit's full
#       # tree plus its metadata (author/committer identity, commit message)
#
# Environment overrides (tests point these at fixtures):
#   LEAKAGE_TOKENS_FILE   default ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-guard/leakage-tokens.txt
#   LEAKAGE_MARKER_FILE   default ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-guard/company-context
#
# Exit codes:
#   0 — clean, or skipped (no company-context marker on this machine)
#   1 — at least one forbidden token found (locations only, content withheld)
#   2 — configuration error: marker present but token list missing or empty
#
# Token file format: one token per line; blank lines and #-comments ignored.
# Matching is case-insensitive with word-boundary anchoring where _ and - are
# treated as non-word characters (so token_suffix and prefix-token are caught).

set -euo pipefail

GUARD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-guard"
TOKENS_FILE="${LEAKAGE_TOKENS_FILE:-$GUARD_DIR/leakage-tokens.txt}"
MARKER_FILE="${LEAKAGE_MARKER_FILE:-$GUARD_DIR/company-context}"

MODE="dir"
SCAN_DIR="."
if [ "${1:-}" = "--commits" ]; then
    MODE="commits"
else
    SCAN_DIR="${1:-.}"
fi

# In --commits mode, drain stdin BEFORE any early exit. Exiting with stdin
# unread would SIGPIPE the feeding pre-push pipeline under pipefail.
SHAS=()
if [ "$MODE" = "commits" ]; then
    while IFS= read -r _sha; do
        [ -n "$_sha" ] && SHAS+=("$_sha")
    done
fi

if [ ! -f "$MARKER_FILE" ]; then
    echo "leakage check: skipped (no company-context marker at $MARKER_FILE)" >&2
    exit 0
fi

if [ ! -f "$TOKENS_FILE" ]; then
    echo "ERROR: company-context marker present but token list missing at $TOKENS_FILE" >&2
    echo "Fail-closed: re-run the overlay installer to materialize the token list." >&2
    exit 2
fi

# Build the token array. No mapfile — this repo targets macOS stock bash 3.2.
TOKENS=()
while IFS= read -r _line; do
    TOKENS+=("$_line")
done < <(grep -v '^\s*#' "$TOKENS_FILE" | grep -v '^\s*$' || true)

if [ "${#TOKENS[@]}" -eq 0 ]; then
    echo "ERROR: token list at $TOKENS_FILE has no effective tokens." >&2
    echo "Fail-closed: an empty list in a company context is a configuration error." >&2
    exit 2
fi

# One combined ERE: (^|[^a-zA-Z0-9])(tok1|tok2|...)([^a-zA-Z0-9]|$)
# Regex specials inside tokens are escaped; _ and - stay non-word chars.
ALTERNATION=""
for token in "${TOKENS[@]}"; do
    escaped="$(printf '%s' "$token" | sed 's/[.[\*^${}()+?|]/\\&/g')"
    if [ -z "$ALTERNATION" ]; then
        ALTERNATION="$escaped"
    else
        ALTERNATION="$ALTERNATION|$escaped"
    fi
done
PATTERN="(^|[^a-zA-Z0-9])(${ALTERNATION})([^a-zA-Z0-9]|$)"

FOUND=0

if [ "$MODE" = "dir" ]; then
    while IFS= read -r -d '' file; do
        # Null-byte detection: grep -qI '' exits 0 for text, 1 for binary.
        grep -qI '' "$file" 2>/dev/null || continue
        lines="$(grep -inE "$PATTERN" "$file" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')" || true
        if [ -n "$lines" ]; then
            FOUND=1
            echo "LEAKAGE: $file — line(s): ${lines}(content withheld)" >&2
        fi
    done < <(find "$SCAN_DIR" \
        -not -path "*/.git/*" \
        -not -name ".git" \
        -type f \
        -print0 2>/dev/null)
else
    for sha in "${SHAS[@]:-}"; do
        [ -n "$sha" ] || continue
        if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
            echo "ERROR: not a commit: $sha" >&2
            exit 2
        fi
        # Full tree of the pushed commit — not the diff. Content introduced in
        # one commit and removed in a later one still publishes with the push.
        tree_hits="$(git grep -I -i -n -E "$PATTERN" "$sha" -- 2>/dev/null | cut -d: -f1-3)" || true
        if [ -n "$tree_hits" ]; then
            FOUND=1
            echo "LEAKAGE in pushed commit tree (content withheld):" >&2
            echo "$tree_hits" >&2
        fi
        meta_lines="$(git log -1 --format='%an <%ae>%n%cn <%ce>%n%B' "$sha" \
            | grep -inE "$PATTERN" | cut -d: -f1 | tr '\n' ' ')" || true
        if [ -n "$meta_lines" ]; then
            FOUND=1
            echo "LEAKAGE in metadata of commit $sha — line(s): ${meta_lines}(content withheld)" >&2
        fi
    done
fi

if [ "$FOUND" -ne 0 ]; then
    echo "" >&2
    echo "Leakage check FAILED. Matched content is withheld by design;" >&2
    echo "compare the referenced locations against the local token list." >&2
    exit 1
fi
exit 0
