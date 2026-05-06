#!/usr/bin/env bash
# docs-gen.sh — Regenerate README skill/agent tables from directory contents.
# Updates content between <!-- BEGIN ... --> and <!-- END ... --> sentinels.
# Usage: bash scripts/docs-gen.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
README="$DOTFILES_DIR/README.md"

source "$SCRIPT_DIR/_lib.sh"

# --- Agents table ---
agents_tmp="$(mktemp)"
{
    echo "| Agent file | Model | Role |"
    echo "|---|---|---|"
    for agent_file in "$DOTFILES_DIR"/.claude/agents/*.md; do
        [ -f "$agent_file" ] || continue
        filename="$(basename "$agent_file")"

        model="$(awk '/^model:/{print $2; exit}' "$agent_file")"
        # Capitalize first letter
        model="$(echo "$model" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        [ -z "$model" ] && model="—"

        # Use frontmatter description's first sentence (stop at period, comma+Use, or \\n)
        role="$(awk -F'"' '/^description:/{print $2; exit}' "$agent_file" | \
            sed 's/\\n.*//' | sed 's/\. Use .*//' | sed 's/\. Examples.*//' | cut -c1-120)"
        [ -z "$role" ] && role="—"

        printf "| \`%s\` | %s | %s |\n" "$filename" "$model" "$role"
    done
} > "$agents_tmp"

_replace_between_sentinels "$README" "AGENTS TABLE" "AGENTS TABLE" "$agents_tmp"
agent_count=$(( $(wc -l < "$agents_tmp") - 2 ))
echo "Updated agents table ($agent_count agents)"
rm -f "$agents_tmp"

# --- Skills table ---
skills_tmp="$(mktemp)"
{
    echo "| Skill | Invoke | Description |"
    echo "|---|---|---|"
    for skill_dir in "$DOTFILES_DIR"/.claude/skills/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        skill_md="$skill_dir/SKILL.md"
        [ -f "$skill_md" ] || continue

        user_invocable="$(awk '/^user-invocable:/{print $2; exit}' "$skill_md")"
        if [ "$user_invocable" = "true" ]; then
            invoke="\`/$skill_name\`"
        else
            invoke="_(internal)_"
        fi

        # Extract description — handles both quoted and unquoted frontmatter values
        description="$(awk '/^description:/{
            line = $0
            sub(/^description:[[:space:]]*"?/, "", line)
            sub(/"$/, "", line)
            print line; exit
        }' "$skill_md" | sed "s/\\\\n.*//" | sed 's/\. Use .*//' | cut -c1-100)"
        [ -z "$description" ] && description="—"

        printf "| \`%s\` | %s | %s |\n" "$skill_name" "$invoke" "$description"
    done
} > "$skills_tmp"

_replace_between_sentinels "$README" "SKILLS TABLE" "SKILLS TABLE" "$skills_tmp"
skill_count=$(( $(wc -l < "$skills_tmp") - 2 ))
echo "Updated skills table ($skill_count skills)"
rm -f "$skills_tmp"

echo "README.md tables regenerated."
