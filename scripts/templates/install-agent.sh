#!/usr/bin/env bash
# install-agent.sh — Register this skill's bundled agent definition as a
# Claude Code subagent so it runs with its pinned model, maxTurns, tool
# restrictions, and persistent memory instead of the general-purpose fallback.
#
# Usage:
#   bash scripts/install-agent.sh            # → ~/.claude/agents/<name>.md
#   bash scripts/install-agent.sh --project  # → <git root>/.claude/agents/<name>.md (or ./ outside a repo)
#   bash scripts/install-agent.sh --force    # overwrite a differing existing file
#
# Reads the agent name from the `name:` frontmatter field of the sibling
# agent.md. Refuses to overwrite an existing, differing file unless --force
# is given. Restart your session afterwards — subagents load at session start.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SKILL_DIR/agent.md"
DEST_DIR="$HOME/.claude/agents"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project) DEST_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/agents" ;;
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install-agent.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -f "$SRC" ] || { echo "install-agent.sh: no agent.md next to this script ($SRC)" >&2; exit 1; }

NAME="$(awk 'NR==1 && $0 != "---" {exit} /^---/ && NR>1 {exit} /^name:/ {sub(/^name:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit}' "$SRC")"
# Trim surrounding whitespace left by the quote-strip above.
NAME="$(echo "$NAME" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
[ -n "$NAME" ] || { echo "install-agent.sh: agent.md has no name: field in its frontmatter" >&2; exit 1; }

# Reject anything that isn't a bare identifier — a name.md becomes a
# destination file path (DEST_DIR/$NAME.md), so a path-traversal or
# absolute-path value here would let a malicious agent.md write outside
# DEST_DIR (e.g. `name: ../../pwned`).
echo "$NAME" | grep -qE '^[A-Za-z0-9][A-Za-z0-9_-]*$' \
    || { echo "install-agent.sh: invalid/unsafe name: field in agent.md frontmatter: '$NAME'" >&2; exit 1; }

DEST="$DEST_DIR/$NAME.md"
mkdir -p "$DEST_DIR"

if [ -e "$DEST" ] && ! cmp -s "$SRC" "$DEST"; then
    if [ "$FORCE" -ne 1 ]; then
        echo "install-agent.sh: $DEST exists and differs from agent.md; re-run with --force to overwrite" >&2
        exit 1
    fi
fi

cp "$SRC" "$DEST"
echo "Installed agent '$NAME' → $DEST"
echo "Restart your session — subagents load at session start."
