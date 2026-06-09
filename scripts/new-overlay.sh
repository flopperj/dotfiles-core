#!/usr/bin/env bash
# new-overlay.sh — deterministic overlay scaffold engine.
#
# Usage: new-overlay.sh <target-dir> [overlay-name] [--force] [--core-url <url>]
#
# Scaffolds a new dotfiles-core overlay at <target-dir>:
#   - Copies the static skeleton from scripts/overlay-skeleton/
#   - Runs git init, adds dotfiles-core as a submodule
#   - Stages all files (does NOT commit)
#   - Runs bash install.sh --check as a final smoke signal
#
# BSD-portable (macOS awk/find).
set -euo pipefail

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
_usage() {
    echo "Usage: new-overlay.sh <target-dir> [overlay-name] [--force] [--core-url <url>]" >&2
    echo "" >&2
    echo "  target-dir    Directory to scaffold into (default: ~/dotfiles)" >&2
    echo "  overlay-name  Name for the overlay (default: basename of target-dir)" >&2
    echo "  --force       Overwrite an existing non-empty target directory" >&2
    echo "  --core-url    Submodule remote URL (required if core origin is a local path)" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# URL resolution — testability seam (plan Step 6 test 4 / Open Question 2)
#
# _resolve_submodule_url <origin_value>
#
# Prints the validated URL to stdout and exits 0 on success.
# Exits non-zero if the origin is empty, a local path, or a resolvable local
# directory — do NOT bake a local path into .gitmodules.
# ---------------------------------------------------------------------------
_resolve_submodule_url() {
    local origin="$1"

    # Empty URL
    if [ -z "$origin" ]; then
        echo "new-overlay: core 'origin' is empty. Pass --core-url <url>." >&2
        return 1
    fi

    # Local-path guard via pattern matching
    case "$origin" in
        /*|./*|../*|file://*|~*)
            echo "new-overlay: core 'origin' is a local path ('$origin'). Pass --core-url <url>." >&2
            return 1
            ;;
    esac

    # Reject if it resolves to an existing local directory
    if [ -d "$origin" ]; then
        echo "new-overlay: core 'origin' resolves to a local dir ('$origin'). Pass --core-url <url>." >&2
        return 1
    fi

    printf '%s' "$origin"
}

# ---------------------------------------------------------------------------
# Main — only runs when executed directly (not when sourced for testing)
# ---------------------------------------------------------------------------
_main() {
    # -------------------------------------------------------------------------
    # 1. Parse args
    # -------------------------------------------------------------------------
    local target=""
    local overlay_name=""
    local force=false
    local core_url=""
    local positional_count=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                force=true
                ;;
            --core-url)
                shift
                [ $# -gt 0 ] || { echo "new-overlay: --core-url requires an argument" >&2; _usage; }
                core_url="$1"
                ;;
            --*)
                echo "new-overlay: unknown option: $1" >&2
                _usage
                ;;
            *)
                positional_count=$(( positional_count + 1 ))
                if [ "$positional_count" -eq 1 ]; then
                    target="$1"
                elif [ "$positional_count" -eq 2 ]; then
                    overlay_name="$1"
                else
                    echo "new-overlay: unexpected argument: $1" >&2
                    _usage
                fi
                ;;
        esac
        shift
    done

    # Apply defaults
    if [ -z "$target" ]; then
        target="$HOME/dotfiles"
    fi
    if [ -z "$overlay_name" ]; then
        overlay_name="$(basename "$target")"
    fi

    # -------------------------------------------------------------------------
    # 2. Resolve CORE_DIR — script lives in scripts/, core root is its parent
    # -------------------------------------------------------------------------
    CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local skel_dir="$CORE_DIR/scripts/overlay-skeleton"

    # -------------------------------------------------------------------------
    # 3. No-clobber guard
    # -------------------------------------------------------------------------
    if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ] && [ "$force" = false ]; then
        echo "new-overlay: target directory '$target' is non-empty. Pass --force to overwrite." >&2
        exit 1
    fi

    # -------------------------------------------------------------------------
    # 4. Submodule URL resolution
    # -------------------------------------------------------------------------
    local url
    if [ -n "$core_url" ]; then
        # --core-url always wins
        url="$core_url"
        echo "new-overlay: using --core-url override: $url"
    else
        local derived_origin
        derived_origin="$(git -C "$CORE_DIR" remote get-url origin 2>/dev/null || true)"
        url="$(_resolve_submodule_url "$derived_origin")" || exit 1
        echo "new-overlay: resolved submodule URL from core origin: $url"
    fi

    # -------------------------------------------------------------------------
    # 5. Create target dir and git init
    # -------------------------------------------------------------------------
    mkdir -p "$target"
    git -C "$target" init -q

    # -------------------------------------------------------------------------
    # 6. Copy skeleton
    #
    # For each file under scripts/overlay-skeleton/:
    #   - Strip the .template suffix from the filename
    #   - Rename dotclaude/ directory prefix to .claude/
    #   - Substitute {{OVERLAY_NAME}} and {{CORE_URL}} in README.md (BSD-safe awk via tmp)
    #   - chmod +x install.sh and scripts/install-overlay.sh
    # -------------------------------------------------------------------------
    local file rel dest dest_dir basename_file

    while IFS= read -r -d '' file; do
        # Compute path relative to skeleton dir
        rel="${file#"$skel_dir/"}"

        # Rename dotclaude/ directory prefix to .claude/ BEFORE stripping suffix
        case "$rel" in
            dotclaude/*)
                rel=".claude/${rel#dotclaude/}"
                ;;
        esac

        # Strip .template suffix
        rel="${rel%.template}"

        # Special case: gitignore (stored without leading dot to avoid acting as a
        # real .gitignore in the core repo) becomes .gitignore in the overlay.
        case "$rel" in
            gitignore)   rel=".gitignore" ;;
            .claude/*)   : ;;  # already correct
        esac

        dest="$target/$rel"
        dest_dir="$(dirname "$dest")"
        mkdir -p "$dest_dir"

        # Substitute {{OVERLAY_NAME}} and {{CORE_URL}} in README.md.
        # ENVIRON[] passes values without any escape-sequence processing (unlike
        # awk -v, which interprets \-escapes in the value). The replace_all
        # helper uses index/substr — a plain string operation with no
        # metacharacter interpretation (unlike gsub, where & expands to the
        # matched text). Together these make / & \ : in URLs and names safe (B1).
        basename_file="$(basename "$file")"
        if [ "$basename_file" = "README.md.template" ]; then
            local tmp_readme
            tmp_readme="$(mktemp)"
            OVERLAY_NAME="$overlay_name" CORE_URL="$url" awk '
                function replace_all(str, from, to,    result, i, len_from) {
                    result = ""
                    len_from = length(from)
                    while ((i = index(str, from)) > 0) {
                        result = result substr(str, 1, i - 1) to
                        str = substr(str, i + len_from)
                    }
                    return result str
                }
                BEGIN {
                    overlay_name = ENVIRON["OVERLAY_NAME"]
                    core_url     = ENVIRON["CORE_URL"]
                }
                {
                    line = $0
                    line = replace_all(line, "{{OVERLAY_NAME}}", overlay_name)
                    line = replace_all(line, "{{CORE_URL}}",     core_url)
                    print line
                }
            ' "$file" > "$tmp_readme"
            cp "$tmp_readme" "$dest"
            rm -f "$tmp_readme"
        else
            cp "$file" "$dest"
        fi
    done < <(find "$skel_dir" -type f -print0)

    # Set execute permission on the copied shell scripts
    chmod +x "$target/install.sh"
    chmod +x "$target/scripts/install-overlay.sh"

    # -------------------------------------------------------------------------
    # 7. Add submodule
    #
    # Under --force: if .claude/dotfiles-core is already registered in
    # .gitmodules, skip the add to avoid "already exists" errors. Just
    # re-copy of the skeleton files (done above) is sufficient for idempotency.
    # -------------------------------------------------------------------------
    local add_submodule=true
    if [ -f "$target/.gitmodules" ] && grep -q "dotfiles-core" "$target/.gitmodules" 2>/dev/null; then
        # Submodule already registered — skip add under --force.
        # The existing .gitmodules URL is RETAINED; any --core-url passed on
        # this re-run was NOT applied to the existing submodule entry.
        echo "new-overlay: submodule already registered in .gitmodules — skipping submodule add (existing URL retained; --core-url not applied to existing submodule)."
        add_submodule=false
    fi

    if [ "$add_submodule" = true ]; then
        git -C "$target" submodule add -q "$url" .claude/dotfiles-core
    fi

    # -------------------------------------------------------------------------
    # 8. Stage all; do NOT commit
    # -------------------------------------------------------------------------
    git -C "$target" add -A

    echo ""
    echo "new-overlay: scaffold complete for overlay '$overlay_name' at $target"
    echo ""
    echo "Next steps:"
    echo "  cd $target"
    echo "  git commit -m \"chore: initial overlay scaffold\""
    echo "  git remote add origin <your-overlay-repo-url>"
    echo "  git push -u origin main"
    echo "  bash install.sh"

    # -------------------------------------------------------------------------
    # 9. Self-verification: run bash install.sh --check
    #
    # This validates the CURRENT ~/.claude install state (not the freshly-
    # scaffolded dir in isolation). On failure: report but leave skeleton in
    # place (non-destructive) and exit non-zero.
    # -------------------------------------------------------------------------
    echo ""
    echo "new-overlay: running install.sh --check to verify current ~/.claude health (not the scaffolded dir in isolation)..."
    if bash "$target/install.sh" --check; then
        echo "new-overlay: --check passed (current ~/.claude install is healthy)."
    else
        echo "new-overlay: --check failed (skeleton left in place)." >&2
        echo "  This may mean the submodule was not fully initialized or" >&2
        echo "  ~/.claude symlinks are not yet set up. Run:" >&2
        echo "    git -C $target submodule update --init --recursive" >&2
        echo "    bash $target/install.sh" >&2
        exit 1
    fi
}

# Run main only when executed, not when sourced (enables test 4's seam).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _main "$@"
fi
