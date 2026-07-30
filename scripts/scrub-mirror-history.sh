#!/usr/bin/env bash
# scrub-mirror-history.sh — audit and scrub scripts/leakage-tokens.txt from the
# public mirror's git history.
#
# HEAD no longer contains the file (removed in v1.15.0), but past commits still
# expose the denylist. Run this against a fresh mirror clone on a machine that
# may force-push to the public host (some corporate environments block github.com
# pushes from managed workstations — run locally if needed).
#
# Usage:
#   bash scripts/scrub-mirror-history.sh audit <clone>
#   bash scripts/scrub-mirror-history.sh scrub  <clone>   # destructive rewrite
#   bash scripts/scrub-mirror-history.sh push   <clone> <remote-url>
#
# Clone may be a normal working tree or a bare mirror (preferred for --mirror push).
#
# After scrub + push:
#   Notify fork owners; re-tag release SHAs if tags pointed at pre-scrub commits.

set -euo pipefail

TARGET_PATH='scripts/leakage-tokens.txt'
MODE="${1:-}"
CLONE="${2:-}"
REMOTE="${3:-}"

_usage() {
    cat <<EOF
Usage:
  bash scripts/scrub-mirror-history.sh audit <clone>
  bash scripts/scrub-mirror-history.sh scrub  <clone>
  bash scripts/scrub-mirror-history.sh push   <clone> <remote-url>

audit — list commits that touched ${TARGET_PATH}
scrub — run git filter-repo --invert-paths (rewrites history in <clone>)
push  — force-push a scrubbed bare clone (--mirror if bare, else --force --all)
EOF
}

_audit() {
    echo "=== Commits touching ${TARGET_PATH} ==="
    git -C "$CLONE" log --oneline --all -- "$TARGET_PATH"
    echo ""
    echo "=== Pickaxe sample (set SCRUB_PICKAXE=term to search) ==="
    if [ -n "${SCRUB_PICKAXE:-}" ]; then
        git -C "$CLONE" log -1 -S "$SCRUB_PICKAXE" --oneline --all -- "$TARGET_PATH" 2>/dev/null || true
    fi
    echo ""
    echo "=== Tags (re-apply after scrub if SHAs change) ==="
    git -C "$CLONE" tag -l 'v1.*' 2>/dev/null || true
}

_scrub() {
    if ! command -v git-filter-repo >/dev/null 2>&1; then
        echo "ERROR: git-filter-repo not found. Install: pip install git-filter-repo" >&2
        exit 1
    fi
    echo "Rewriting history in $CLONE — removes ${TARGET_PATH} from all commits."
    git -C "$CLONE" filter-repo --path "$TARGET_PATH" --invert-paths --force
    echo ""
    echo "Done. Verify with: git -C \"$CLONE\" log --oneline --all -- $TARGET_PATH"
    _audit
}

_push() {
    [ -n "$REMOTE" ] || { echo "ERROR: remote URL required for push" >&2; exit 1; }
    if [ -f "$CLONE/HEAD" ] && [ -d "$CLONE/objects" ]; then
        echo "Force-pushing branches and tags to $REMOTE ..."
        git -C "$CLONE" push --force "$REMOTE" 'refs/heads/*:refs/heads/*'
        git -C "$CLONE" push --force "$REMOTE" 'refs/tags/*:refs/tags/*'
    else
        echo "Force-pushing all refs from working clone to $REMOTE ..."
        git -C "$CLONE" push --force --all "$REMOTE"
        git -C "$CLONE" push --force --tags "$REMOTE"
    fi
}

case "$MODE" in
    audit) [ -n "$CLONE" ] || { _usage; exit 1; }; _audit ;;
    scrub) [ -n "$CLONE" ] || { _usage; exit 1; }; _scrub ;;
    push)  [ -n "$CLONE" ] || { _usage; exit 1; }; _push ;;
    *) _usage; exit 1 ;;
esac
