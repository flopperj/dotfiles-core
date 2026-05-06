#!/usr/bin/env bash
# _lib.sh — Shared functions for documentation and content generators.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Replace content between two sentinels in a file with content from a temp file.
# The sentinel lines themselves are preserved; only the content between them changes.
#
# Usage: _replace_between_sentinels <file> <begin_label> <end_label> <content_file>
#
# Sentinel format in target file:
#   <!-- BEGIN <begin_label> -->
#   ... old content (replaced) ...
#   <!-- END <end_label> -->
_replace_between_sentinels() {
    local file="$1" begin_label="$2" end_label="$3" content_file="$4"
    local tmp
    tmp="$(mktemp)"

    awk -v begin="BEGIN $begin_label" -v end="END $end_label" -v cf="$content_file" '
        BEGIN { inside = 0 }
        $0 ~ begin {
            print $0
            while ((getline line < cf) > 0) {
                print line
            }
            close(cf)
            inside = 1
            next
        }
        $0 ~ end {
            inside = 0
            print $0
            next
        }
        !inside { print }
    ' "$file" > "$tmp"

    # Validate that both sentinels survived the rewrite before committing.
    # If either is absent the awk program silently truncated the file (e.g.
    # because the END sentinel was missing from the source).  Abort without
    # overwriting the original so data loss cannot occur.
    if ! grep -q "BEGIN $begin_label" "$tmp"; then
        echo "_replace_between_sentinels: BEGIN sentinel 'BEGIN $begin_label' missing from rewritten output — aborting to prevent data loss" >&2
        rm -f "$tmp"
        return 1
    fi
    if ! grep -q "END $end_label" "$tmp"; then
        echo "_replace_between_sentinels: END sentinel 'END $end_label' missing from rewritten output — aborting to prevent data loss" >&2
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$file"
}
