#!/usr/bin/env bash
# scrub-mirror-history.sh — audit and scrub the public mirror's git history.
#
# Two things are scrubbed:
#   1. scripts/leakage-tokens.txt — HEAD no longer contains the file (removed in
#      v1.15.0), but past commits still expose the denylist.
#   2. Author/committer identities — commits made on a company workstation, and
#      merge commits stamped by the internal GitHub host, carry company email
#      addresses. A git mailmap rewrites them to the public identity.
#
# The mailmap is data, not code: like the token list it lives OUTSIDE every repo
# working tree (the addresses it maps are themselves leakage tokens). Default
# location: ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-guard/mirror-mailmap,
# override with SCRUB_MAILMAP_FILE. Standard git mailmap syntax:
#   Public Name <public@example.com> <company@example.com>
# When the file is absent, scrub falls back to the path-only rewrite and warns.
#
# The audit has two identity passes. The mailmap pass counts what the mailmap
# will (or did) rewrite. The allowlist pass is the one to trust before a push:
# it flags every author, committer, and tagger email whose domain is not in
# SCRUB_ALLOWED_EMAIL_DOMAINS (default: users.noreply.github.com github.com),
# so an address the mailmap forgot still fails the audit. Domains and addresses
# are withheld from output; set SCRUB_SHOW_UNLISTED=1 to print the offending
# domains when diagnosing locally.
#
# Run this against a fresh mirror clone on a machine that may force-push to the
# public host (some corporate environments block github.com pushes from managed
# workstations — run locally if needed). Every sync to the mirror must go
# through scrub — the internal host keeps stamping company identities on merges.
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
GUARD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-guard"
MAILMAP_FILE="${SCRUB_MAILMAP_FILE:-$GUARD_DIR/mirror-mailmap}"
ALLOWED_DOMAINS="${SCRUB_ALLOWED_EMAIL_DOMAINS:-users.noreply.github.com github.com}"
MODE="${1:-}"
CLONE="${2:-}"
REMOTE="${3:-}"

_usage() {
    cat <<EOF
Usage:
  bash scripts/scrub-mirror-history.sh audit <clone>
  bash scripts/scrub-mirror-history.sh scrub  <clone>
  bash scripts/scrub-mirror-history.sh push   <clone> <remote-url>

audit — list commits that touched ${TARGET_PATH}; count identity fields that
        match a mailmap source, and identity fields outside the allowed email
        domains (addresses withheld). Non-zero exit while either count is > 0.
scrub — run git filter-repo --invert-paths, plus --mailmap when the mailmap
        file is present (rewrites history in <clone>)
Mailmap: ${MAILMAP_FILE}
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
    echo ""
    # Identity passes last so their exit status is the function's exit status.
    local rc=0
    _audit_identities || rc=1
    echo ""
    _audit_unlisted_domains || rc=1
    return "$rc"
}

# Every identity email in the clone: author and committer of every commit on
# every ref, plus the tagger of every annotated tag. One address per line.
_identity_emails() {
    git -C "$CLONE" log --all --format='%ae%n%ce'
    git -C "$CLONE" for-each-ref --format='%(taggeremail)' refs/tags \
        | sed -e 's/^<//' -e 's/>$//' -e '/^$/d'
}

# Source addresses of a mailmap: the LAST <...> on each mapping line, i.e. a
# line with at least two <...> groups. (A single <...> maps by name only and
# carries no source address.) Comments are whole lines starting with '#', as in
# git's own parser. CRLF files are tolerated. Prints nothing when there are no
# mapping lines; exit status is always 0 so callers count the output instead.
_mailmap_sources() {
    tr -d '\r' < "$MAILMAP_FILE" \
        | grep -vE '^[[:space:]]*#' \
        | grep -E '<[^>]+>.*<[^>]+>' \
        | grep -oE '<[^>]+>[[:space:]]*$' \
        | tr -d '<> \t' \
        || true
}

# Count identity fields (author, committer, tagger) per mailmap source address.
# Addresses are never printed — they are leakage tokens. Exit status 0 when the
# mailmap has at least one source and all counts are 0.
_audit_identities() {
    echo "=== Identity audit — mailmap pass (mailmap: ${MAILMAP_FILE}) ==="
    if [ ! -f "$MAILMAP_FILE" ]; then
        echo "no mailmap file — mailmap pass skipped, scrub will rewrite paths only"
        return 0
    fi
    local total=0 i=0 addr n fields
    fields=$(_identity_emails)
    while IFS= read -r addr; do
        [ -n "$addr" ] || continue
        i=$((i + 1))
        n=$(printf '%s\n' "$fields" | grep -cxF -- "$addr" || true)
        echo "mailmap source $i: $n identity field(s) match (address withheld)"
        total=$((total + n))
    done < <(_mailmap_sources)
    if [ "$i" -eq 0 ]; then
        echo "ERROR: mailmap has no mapping lines (name <new> <old>) — nothing would be rewritten" >&2
        return 1
    fi
    echo "total matching identity fields: $total"
    [ "$total" -eq 0 ]
}

# Flag every identity email whose domain is not allowlisted. This is the pass
# that catches what the mailmap forgot. Domains are withheld unless
# SCRUB_SHOW_UNLISTED=1. Exit status 0 when nothing is unlisted.
_audit_unlisted_domains() {
    echo "=== Identity audit — allowlist pass (allowed: ${ALLOWED_DOMAINS}) ==="
    local domains unlisted n_fields n_domains
    # lower-cased domain of each identity field, one per line
    domains=$(_identity_emails | sed -e 's/.*@//' | tr '[:upper:]' '[:lower:]')
    unlisted=$domains
    local d
    for d in $ALLOWED_DOMAINS; do
        unlisted=$(printf '%s\n' "$unlisted" | grep -vxF -- "$(printf '%s' "$d" | tr '[:upper:]' '[:lower:]')" || true)
    done
    unlisted=$(printf '%s\n' "$unlisted" | sed '/^$/d')
    if [ -z "$unlisted" ]; then
        echo "all identity fields use allowed domains"
        return 0
    fi
    n_fields=$(printf '%s\n' "$unlisted" | wc -l | tr -d ' ')
    n_domains=$(printf '%s\n' "$unlisted" | sort -u | wc -l | tr -d ' ')
    echo "$n_fields identity field(s) across $n_domains unlisted domain(s) (withheld; SCRUB_SHOW_UNLISTED=1 to print)"
    if [ "${SCRUB_SHOW_UNLISTED:-0}" = "1" ]; then
        printf '%s\n' "$unlisted" | sort | uniq -c | sort -rn
    fi
    return 1
}

_scrub() {
    if ! command -v git-filter-repo >/dev/null 2>&1; then
        echo "ERROR: git-filter-repo not found. Install: pip install git-filter-repo" >&2
        exit 1
    fi
    local -a mailmap_args=()
    if [ -f "$MAILMAP_FILE" ]; then
        mailmap_args=(--mailmap "$MAILMAP_FILE")
        echo "Rewriting history in $CLONE — removes ${TARGET_PATH} and remaps identities."
    else
        echo "WARNING: no mailmap at ${MAILMAP_FILE} — identities will NOT be rewritten." >&2
        echo "Rewriting history in $CLONE — removes ${TARGET_PATH} from all commits."
    fi
    # ${arr[@]+"${arr[@]}"} — empty-array-safe under bash 3.2 with set -u.
    git -C "$CLONE" filter-repo --path "$TARGET_PATH" --invert-paths --force \
        ${mailmap_args[@]+"${mailmap_args[@]}"}
    echo ""
    echo "Done. Verify with: git -C \"$CLONE\" log --oneline --all -- $TARGET_PATH"
    # The post-scrub audit is advisory here: the rewrite succeeded, and an
    # unlisted domain the mailmap does not cover is reported, not fatal.
    _audit || echo "NOTE: audit still reports identities — extend the mailmap and re-run before push." >&2
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
