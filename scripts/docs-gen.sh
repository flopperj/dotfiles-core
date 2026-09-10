#!/usr/bin/env bash
# docs-gen.sh — keep the README's curated skill and agent tables in step with
# the directories they describe.
#
# The tables under "## Skills" and "## Agents" in README.md are hand-written:
# each row carries a one-line summary edited for a public audience. Rendering
# them from frontmatter was tried and rejected — descriptions truncate
# mid-sentence and agent descriptions open with "Use this agent when…". So
# this script does not rewrite the README. It checks it:
#
#   - every directory under .claude/skills/ with a SKILL.md has a row in the
#     skills table, and every row names a real skill directory;
#   - every agent file under .claude/agents/ has a row in the agents table
#     (matched on the bold display name, e.g. **Aristotle** for
#     aristotle-deconstructor.md), and every row names a real agent.
#
# Exit 0 when both tables are in step, 1 on any drift, with one line per
# problem naming the row to add or remove. `make gen-docs` and `make all`
# run it; fix drift by editing the README row by hand.
#
# Usage: bash scripts/docs-gen.sh [README]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
README="${1:-$DOTFILES_DIR/README.md}"
SKILLS_DIR="$DOTFILES_DIR/.claude/skills"
AGENTS_DIR="$DOTFILES_DIR/.claude/agents"

[ -f "$README" ] || { echo "docs-gen: README not found: $README" >&2; exit 1; }

# Print the body rows of the first markdown table that follows the heading
# whose text matches $1 (regex on the heading line). Stops at the next heading
# or the first non-table line after the table began.
_table_rows() {
    awk -v heading="$1" '
        $0 ~ heading { in_section = 1; next }
        in_section && /^## /  { exit }
        in_section && /^\|/   { in_table = 1; print; next }
        in_section && in_table && !/^\|/ { exit }
    ' "$README" | tail -n +3
}

# First cell of each row, with surrounding backticks, slashes, bold markers,
# and whitespace stripped: "| `/ticket-swarm` | ..." -> ticket-swarm,
# "| **Aristotle** | ..." -> Aristotle.
_first_cells() {
    sed -E 's/^\| *([^|]*) *\|.*$/\1/' \
        | sed -E 's/_\(internal\)_//; s/[`*]//g; s#^/##; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

drift=0

# --- Skills ---
readme_skills="$(_table_rows '^## Skills' | _first_cells | sort -u)"
dir_skills="$(for d in "$SKILLS_DIR"/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done | sort -u)"

while IFS= read -r s; do
    [ -n "$s" ] || continue
    if ! printf '%s\n' "$readme_skills" | grep -qxF -- "$s"; then
        echo "README skills table is missing a row for skill directory: $s"
        drift=1
    fi
done <<EOF
$dir_skills
EOF

while IFS= read -r s; do
    [ -n "$s" ] || continue
    if ! printf '%s\n' "$dir_skills" | grep -qxF -- "$s"; then
        echo "README skills table names a skill with no directory: $s"
        drift=1
    fi
done <<EOF
$readme_skills
EOF

# --- Agents ---
readme_agents="$(_table_rows '^## Agents' | _first_cells | sort -u)"
# Display name = first hyphen-separated segment of the file name, capitalised
# (aristotle-deconstructor.md -> Aristotle, cyrus-tdd-engineer.md -> Cyrus).
dir_agents="$(for f in "$AGENTS_DIR"/*.md; do [ -f "$f" ] || continue; n="$(basename "$f" .md)"; n="${n%%-*}"; printf '%s\n' "$(printf '%s' "$n" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"; done | sort -u)"

while IFS= read -r a; do
    [ -n "$a" ] || continue
    if ! printf '%s\n' "$readme_agents" | grep -qxF -- "$a"; then
        echo "README agents table is missing a row for agent: $a"
        drift=1
    fi
done <<EOF
$dir_agents
EOF

while IFS= read -r a; do
    [ -n "$a" ] || continue
    if ! printf '%s\n' "$dir_agents" | grep -qxF -- "$a"; then
        echo "README agents table names an agent with no definition file: $a"
        drift=1
    fi
done <<EOF
$readme_agents
EOF

if [ "$drift" -ne 0 ]; then
    echo "docs-gen: README tables have drifted from .claude/skills and .claude/agents — edit the rows above by hand." >&2
    exit 1
fi

echo "README tables in step: $(printf '%s\n' "$dir_skills" | grep -c .) skills, $(printf '%s\n' "$dir_agents" | grep -c .) agents."
