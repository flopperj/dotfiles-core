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
#   bash scripts/scrub-mirror-history.sh audit <mirror-clone>
#   bash scripts/scrub-mirror-history.sh scrub  <mirror-clone>   # destructive
#
# After scrub:
#   cd <mirror-clone> && git push --force --mirror <public-mirror-url>
#   Notify fork owners; re-tag v1.15.0 if the tag pointed at pre-scrub SHAs.

set -euo pipefail

TARGET_PATH='scripts/leakage-tokens.txt'
MODE="${1:-}"
CLONE="${2:-}"

_usage() {
    cat <<EOF
Usage:
  bash scripts/scrub-mirror-history.sh audit <mirror-clone>
  bash scripts/scrub-mirror-history.sh scrub  <mirror-clone>

audit — list commits that touched ${TARGET_PATH}
scrub — run git filter-repo --invert-paths (rewrites history in <mirror-clone>)
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
    echo "Then force-push the mirror and re-apply tags as needed."
}

case "$MODE" in
    audit) [ -n "$CLONE" ] || { _usage; exit 1; }; _audit ;;
    scrub) [ -n "$CLONE" ] || { _usage; exit 1; }; _scrub ;;
    *) _usage; exit 1 ;;
esac
