#!/usr/bin/env bash
# lib-overlays.sh — fragment-and-concatenate library for dotfiles-core.
#
# Provides three functions:
#   concat_fragments target_file fragment_dir [overlay_fragment_dir]
#   apply_overlay_fragment target_file fragment_file sentinel_name
#   apply_manifest manifest_path
#
# Source this file; do not execute it directly.
# BSD-portable (macOS sed, awk, find).

set -euo pipefail

# concat_fragments <target> <core_dir> [<overlay_dir>]
#
# Concatenates all *.md files from core_dir (lexical order), then optionally
# appends *.md files from overlay_dir (lexical order), writing to target.
# Idempotent: re-running produces no diff if fragments are unchanged.
concat_fragments() {
    local target="$1"
    local core_dir="$2"
    local overlay_dir="${3:-}"

    if [ ! -d "$core_dir" ]; then
        echo "concat_fragments: core fragment dir not found: $core_dir" >&2
        return 1
    fi

    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN

    # Core fragments — lexical sort, .md only.
    while IFS= read -r -d '' frag; do
        cat "$frag" >> "$tmp"
        # Ensure trailing newline between fragments.
        printf '\n' >> "$tmp"
    done < <(find "$core_dir" -maxdepth 1 -name '*.md' -print0 | sort -z)

    # Overlay fragments — same pattern.
    if [ -n "$overlay_dir" ] && [ -d "$overlay_dir" ]; then
        while IFS= read -r -d '' frag; do
            cat "$frag" >> "$tmp"
            printf '\n' >> "$tmp"
        done < <(find "$overlay_dir" -maxdepth 1 -name '*.md' -print0 | sort -z)
    fi

    # Only write if content differs (idempotency).
    if [ -f "$target" ]; then
        if cmp -s "$tmp" "$target"; then
            return 0
        fi
    fi
    cp "$tmp" "$target"
}

# apply_overlay_fragment <target_file> <fragment_file> <sentinel_name>
#
# Injects the content of fragment_file into target_file between:
#   <!-- BEGIN OVERLAY-FRAGMENT: <sentinel_name> -->
#   <!-- END OVERLAY-FRAGMENT: <sentinel_name> -->
# Idempotent: replaces any previously injected content with current fragment.
# Exits non-zero if sentinels are missing or fragment file is absent.
apply_overlay_fragment() {
    local target="$1"
    local fragment="$2"
    local name="$3"

    if [ ! -f "$target" ]; then
        echo "apply_overlay_fragment: target not found: $target" >&2
        return 1
    fi
    if [ ! -f "$fragment" ]; then
        echo "apply_overlay_fragment: fragment not found: $fragment" >&2
        return 1
    fi

    local begin_sentinel="<!-- BEGIN OVERLAY-FRAGMENT: ${name} -->"
    local end_sentinel="<!-- END OVERLAY-FRAGMENT: ${name} -->"

    if ! grep -qF "$begin_sentinel" "$target"; then
        echo "apply_overlay_fragment: BEGIN sentinel not found for '${name}' in ${target}" >&2
        return 1
    fi
    if ! grep -qF "$end_sentinel" "$target"; then
        echo "apply_overlay_fragment: END sentinel not found for '${name}' in ${target}" >&2
        return 1
    fi

    local fragment_content
    fragment_content="$(cat "$fragment")"

    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN

    # Use awk to replace content between sentinels.
    # State machine: copying=1 (default), inside=0 (between sentinels).
    awk -v begin="$begin_sentinel" -v end="$end_sentinel" -v content="$fragment_content" '
        $0 == begin {
            print
            print content
            inside = 1
            next
        }
        $0 == end {
            inside = 0
            print
            next
        }
        !inside { print }
    ' "$target" > "$tmp"

    if ! cmp -s "$tmp" "$target"; then
        cp "$tmp" "$target"
    fi
}

# apply_manifest <manifest_path>
#
# Reads a YAML manifest at manifest_path with schema:
#   fragments:
#     - name: <sentinel_name>
#       target: <absolute or relative path to target file>
#       source: <absolute or relative path to fragment file>
# Calls apply_overlay_fragment for each entry.
# Exits non-zero on missing manifest, missing source, or apply failure.
# Empty fragments list exits 0.
apply_manifest() {
    local manifest="$1"

    if [ ! -f "$manifest" ]; then
        echo "apply_manifest: manifest not found: $manifest" >&2
        return 1
    fi

    # Parse YAML with awk. Only handles the simple list schema above.
    # Each entry is on consecutive lines; order is: name, target, source.
    local name="" target="" source=""
    local in_fragments=0

    while IFS= read -r line; do
        # Detect 'fragments:' header.
        if [[ "$line" =~ ^fragments: ]]; then
            in_fragments=1
            continue
        fi
        [ "$in_fragments" -eq 0 ] && continue

        # New list item — process previous entry if complete.
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]] && [ -n "$name" ]; then
            _apply_one_fragment "$name" "$target" "$source" "$manifest" || return 1
            name="" target="" source=""
        fi

        # Extract fields.
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*name:[[:space:]]*(.*) ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*target:[[:space:]]*(.*) ]]; then
            target="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*source:[[:space:]]*(.*) ]]; then
            source="${BASH_REMATCH[1]}"
        fi
    done < "$manifest"

    # Process final entry.
    if [ -n "$name" ]; then
        _apply_one_fragment "$name" "$target" "$source" "$manifest" || return 1
    fi
}

# Internal helper for apply_manifest.
_apply_one_fragment() {
    local name="$1" target="$2" source="$3" manifest="$4"

    if [ ! -f "$source" ]; then
        echo "apply_manifest: source not found for fragment '${name}': ${source}" >&2
        return 1
    fi
    apply_overlay_fragment "$target" "$source" "$name"
}
