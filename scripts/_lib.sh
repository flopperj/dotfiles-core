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

# Physical path of an existing directory (every symlinked component
# resolved); prints nothing and returns 1 when it does not exist.
#
# Usage: phys="$(_phys_dir "$dir")" || …
_phys_dir() {
    (cd -P "$1" 2>/dev/null && pwd -P)
}

# True when <path> sits inside <dir> physically: the directory holding <path>
# resolves to <dir> or below it. Symlinked ancestors are followed, the final
# component is not, and <path> itself need not exist. A ~/.claude that is a
# symlink into the core checkout therefore puts every entry under it inside
# core, while a symlink *at* <path> pointing into core does not.
#
# Usage: if _path_inside "$dst" "$core_dir"; then …
_path_inside() {
    local path="$1" dir="$2" phys_parent phys_dir
    [ -n "$path" ] && [ -n "$dir" ] || return 1
    phys_dir="$(_phys_dir "$dir")" || return 1
    phys_parent="$(_phys_dir "$(dirname "$path")")" || return 1
    case "$phys_parent" in
        "$phys_dir"|"$phys_dir"/*) return 0 ;;
    esac
    return 1
}

# True when the symlink at <link> resolves into <dir>, or dangles with a
# literal target under <dir>. Tells a whole-directory link an older core left
# at ~/.claude/_shared from one that somebody else created.
#
# Usage: if _symlink_targets "$link" "$core_dir"; then …
_symlink_targets() {
    local link="$1" dir="$2" phys_dir phys_target literal
    [ -L "$link" ] || return 1
    phys_dir="$(_phys_dir "$dir")" || return 1
    if phys_target="$(_phys_dir "$link")"; then
        case "$phys_target" in
            "$phys_dir"|"$phys_dir"/*) return 0 ;;
        esac
        return 1
    fi
    literal="$(readlink "$link")"
    case "$literal" in
        "$dir"/*|"$phys_dir"/*) return 0 ;;
    esac
    return 1
}
