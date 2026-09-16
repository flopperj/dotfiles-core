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

# Iterate over skill directories inside a core repo.
# Emits one absolute directory path per line; non-directory entries are skipped.
#
# Usage: while IFS= read -r skill_dir; do … done < <(_iter_core_skill_dirs "$core_dir")
_iter_core_skill_dirs() {
    local core_dir="$1"
    local d
    for d in "$core_dir/.claude/skills"/*/; do
        [ -d "$d" ] || continue
        printf '%s\n' "$d"
    done
}

# Detect how dotfiles are laid out on this machine.
#
# Prints one of:
#   local  — the overlay (or a standalone core clone) lives in its own
#            directory and the installer symlinks into ~/.claude/.
#   yadm   — the overlay's files are checked out directly into $HOME (yadm,
#            cloud workspaces). Overlay-tracked paths under ~/.claude/ are then real
#            files owned by the overlay, and core must merge around them.
#
# Signals, in order: an explicit DOTFILES_LAYOUT override (tests, operators);
# a yadm repo answering for $HOME; a tracked $HOME/.gitmodules declaring the
# dotfiles-core submodule (a yadm tree that was copied into $HOME without its
# repo directory still carries this file).
#
# Usage: layout="$(_detect_layout)"
_detect_layout() {
    if [ -n "${DOTFILES_LAYOUT:-}" ]; then
        printf '%s\n' "$DOTFILES_LAYOUT"
        return 0
    fi
    if command -v yadm >/dev/null 2>&1 && yadm rev-parse --git-dir >/dev/null 2>&1; then
        echo yadm
        return 0
    fi
    if [ -f "$HOME/.gitmodules" ] && grep -q 'dotfiles-core' "$HOME/.gitmodules" 2>/dev/null; then
        echo yadm
        return 0
    fi
    echo local
}
