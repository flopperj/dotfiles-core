#!/usr/bin/env bash
# check-shared-fragment-drift.sh — sentinel-block drift guard for shared skill fragments.
#
# Usage: bash scripts/check-shared-fragment-drift.sh [SCAN_ROOT]
#   SCAN_ROOT  defaults to "." (current directory)
#
# Exit codes:
#   0 — no drift detected (or nothing to compare)
#   1 — at least one sentinel block differs between a shared fragment and a consumer
#   2 — fatal config error (unpaired sentinel or duplicate sentinel name in a file)
#
# What is checked:
#   Shared fragments:  .claude/skills/*-shared.md  (files ending in -shared.md
#                       at the top level of the skills directory — not in subdirs)
#   Consumers:         .claude/skills/*/SKILL.md   (one level deep, subdirectories only)
#
#   For each <!-- BEGIN X --> / <!-- END X --> block found in a shared fragment,
#   locate the same-named block in each consumer. If both exist, byte-compare the
#   inner content (exclusive of the sentinel lines). Any mismatch → exit 1.
#
#   Blocks that appear only in consumers and not in any shared fragment are ignored.
#   Blocks that appear in a shared fragment but no consumer references them are ignored.
#
#   Unpaired sentinels (BEGIN without END, or END without BEGIN) in any scanned file
#   → exit 2.  Duplicate sentinel names in a single file → exit 2.

set -euo pipefail

SCAN_ROOT="${1:-.}"

DRIFT=0

# ---------------------------------------------------------------------------
# sentinel_names_in <file>
#
# Prints the sentinel name from each <!-- BEGIN X --> line in <file>, one per
# line.  Names are the bare identifier between BEGIN and -->.
# ---------------------------------------------------------------------------
sentinel_names_in() {
    local file="$1"
    grep -oE '<!-- BEGIN [A-Z0-9_-]+ -->' "$file" 2>/dev/null \
        | sed 's/<!-- BEGIN \([A-Z0-9_-]*\) -->/\1/' \
        || true
}

# ---------------------------------------------------------------------------
# extract_block <file> <name> <outfile>
#
# Extracts the inner content of <!-- BEGIN name --> ... <!-- END name --> from
# <file> and writes it to <outfile>.
#
# Returns:
#   0  — block found and written
#   1  — block not present in file (caller decides if this is fine)
#   Exits 2 directly on structural errors (unpaired, duplicate).
# ---------------------------------------------------------------------------
extract_block() {
    local file="$1"
    local name="$2"
    local outfile="$3"

    local begin_count end_count
    begin_count="$(grep -cF "<!-- BEGIN ${name} -->" "$file" 2>/dev/null || true)"
    end_count="$(grep -cF "<!-- END ${name} -->" "$file" 2>/dev/null || true)"

    if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
        return 1
    fi

    if [ "$begin_count" -gt 1 ]; then
        echo "ERROR: duplicate sentinel '${name}' (BEGIN appears ${begin_count} times) in ${file}" >&2
        echo "ERROR: duplicate sentinel '${name}' (BEGIN appears ${begin_count} times) in ${file}"
        exit 2
    fi

    if [ "$end_count" -gt 1 ]; then
        echo "ERROR: duplicate sentinel '${name}' (END appears ${end_count} times) in ${file}" >&2
        echo "ERROR: duplicate sentinel '${name}' (END appears ${end_count} times) in ${file}"
        exit 2
    fi

    if [ "$begin_count" -ne "$end_count" ]; then
        if [ "$begin_count" -gt 0 ]; then
            echo "ERROR: unpaired BEGIN sentinel '${name}' (no matching END) in ${file}" >&2
            echo "ERROR: unpaired BEGIN sentinel '${name}' (no matching END) in ${file}"
        else
            echo "ERROR: unpaired END sentinel '${name}' (no matching BEGIN) in ${file}" >&2
            echo "ERROR: unpaired END sentinel '${name}' (no matching BEGIN) in ${file}"
        fi
        exit 2
    fi

    # Both BEGIN and END present exactly once — extract inner content.
    awk \
        -v begin_marker="<!-- BEGIN ${name} -->" \
        -v end_marker="<!-- END ${name} -->" \
        '
        $0 == begin_marker { inside=1; next }
        $0 == end_marker   { inside=0; next }
        inside             { print }
        ' "$file" > "$outfile"

    return 0
}

# ---------------------------------------------------------------------------
# validate_all_sentinels <file>
#
# Checks that every sentinel in <file> is properly paired (no orphan BEGIN or
# END) and not duplicated.  Exits 2 on error.
# ---------------------------------------------------------------------------
validate_all_sentinels() {
    local file="$1"

    # Collect all sentinel names from BEGIN lines.
    local begin_names end_names
    begin_names="$(grep -oE '<!-- BEGIN [A-Z0-9_-]+ -->' "$file" 2>/dev/null \
        | sed 's/<!-- BEGIN \([A-Z0-9_-]*\) -->/\1/' \
        | sort -u || true)"
    end_names="$(grep -oE '<!-- END [A-Z0-9_-]+ -->' "$file" 2>/dev/null \
        | sed 's/<!-- END \([A-Z0-9_-]*\) -->/\1/' \
        | sort -u || true)"

    # Check each name seen in BEGIN or END.
    local all_names
    all_names="$(printf '%s\n%s\n' "$begin_names" "$end_names" | grep -v '^$' | sort -u || true)"

    local name
    local tmpout
    tmpout="$(mktemp)"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        # extract_block exits 2 on structural errors.
        extract_block "$file" "$name" "$tmpout" || true
    done <<< "$all_names"
    rm -f "$tmpout"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

skills_dir="${SCAN_ROOT}/.claude/skills"
if [ ! -d "$skills_dir" ]; then
    exit 0
fi

# Discover shared fragment files: *-shared.md directly inside .claude/skills/
mapfile -t SHARED_FILES < <(
    find "$skills_dir" \
        -maxdepth 1 \
        -name "*-shared.md" \
        -type f \
        2>/dev/null | sort
)

if [ "${#SHARED_FILES[@]}" -eq 0 ]; then
    exit 0
fi

# Discover consumer SKILL.md files: one level deep in subdirectories.
mapfile -t CONSUMER_FILES < <(
    find "$skills_dir" \
        -mindepth 2 \
        -maxdepth 2 \
        -name "SKILL.md" \
        -type f \
        2>/dev/null | sort
)

# Validate all sentinels in every consumer upfront (catches orphans in
# consumers even if the name doesn't appear in any shared fragment).
for consumer in "${CONSUMER_FILES[@]}"; do
    validate_all_sentinels "$consumer"
done

# Validate all sentinels in every shared fragment.
for shared_file in "${SHARED_FILES[@]}"; do
    validate_all_sentinels "$shared_file"
done

# Working temp directory, cleaned up on exit.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fragment_tmp="${WORK_DIR}/fragment_block"
consumer_tmp="${WORK_DIR}/consumer_block"

# For each shared fragment, for each sentinel block it defines, check every
# consumer that also contains that sentinel.
for shared_file in "${SHARED_FILES[@]}"; do
    shared_name="$(basename "$shared_file")"

    sentinel_names="$(sentinel_names_in "$shared_file")"

    while IFS= read -r sentinel; do
        [ -z "$sentinel" ] && continue

        # Extract the fragment's inner content.
        extract_block "$shared_file" "$sentinel" "$fragment_tmp"

        for consumer_file in "${CONSUMER_FILES[@]}"; do
            consumer_name="$(basename "$(dirname "$consumer_file")")/SKILL.md"

            # Skip if this consumer doesn't reference this sentinel.
            extract_block "$consumer_file" "$sentinel" "$consumer_tmp" || continue

            # Both present — byte-compare.
            if ! diff -q "$fragment_tmp" "$consumer_tmp" > /dev/null 2>&1; then
                DRIFT=1
                echo "DRIFT: sentinel '${sentinel}' differs between ${shared_name} and ${consumer_name}" >&2
                echo "DRIFT: sentinel '${sentinel}' differs between ${shared_name} and ${consumer_name}"
                diff "$fragment_tmp" "$consumer_tmp" || true
            fi
        done
    done <<< "$sentinel_names"
done

if [ "$DRIFT" -ne 0 ]; then
    exit 1
fi

exit 0
