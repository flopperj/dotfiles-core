#!/usr/bin/env bash
# pre-push.sh — dotfiles-core pre-push gate.
#
# Installed at .git/hooks/pre-push by install.sh (symlink).
# git invokes it with $1 = remote name, $2 = remote URL, and feeds one line
# per ref on stdin:  <local_ref> <local_sha> <remote_ref> <remote_sha>
#
# The publication set is every commit not already reachable from a
# remote-tracking ref: each such commit's FULL TREE and its metadata
# (author/committer identity, commit message) are scanned. `--not --remotes`
# rather than <remote_sha>..<local_sha>: the latter only excludes the target
# ref's history, and would rescan (and re-block on) commits already published
# elsewhere — pre-existing public history is out of scope by design.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

SHAS=""
# shellcheck disable=SC2034
while read -r _local_ref local_sha _remote_ref _remote_sha; do
    # Branch deletion pushes an all-zero local sha — nothing is published.
    case "$local_sha" in
        *[!0]*) ;;
        *) continue ;;
    esac
    SHAS="${SHAS}$(git rev-list "$local_sha" --not --remotes)"$'\n'
done

printf '%s' "$SHAS" | sed '/^$/d' | sort -u \
    | bash "$REPO_ROOT/scripts/check-no-leakage.sh" --commits
