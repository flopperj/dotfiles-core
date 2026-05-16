#!/usr/bin/env bash
# Claude Code statusline script
# Shows context window usage with color-coded warnings and current model name.

input=$(cat)

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# ANSI color codes (defined early so the early-exit path can use them)
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

# Try to get branch from git
branch=""
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# Get line changes from git
lines_added=0
lines_removed=0
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  [ -z "$default_branch" ] && default_branch=main
  stats=$(git diff --numstat "origin/${default_branch}" 2>/dev/null | awk '{a+=$1; r+=$2} END {print a " " r}')
  if [ -n "$stats" ]; then
    lines_added=$(echo "$stats" | awk '{print $1}')
    lines_removed=$(echo "$stats" | awk '{print $2}')
  fi
fi

# Build branch and lines part
branch_part=""
if [ -n "$branch" ]; then
  lines_display=""
  if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
    total_lines=$((lines_added + lines_removed))
    lines_display=$(printf " | +%0.0f -%0.0f (%0.0f lines)" "$lines_added" "$lines_removed" "$total_lines")
  fi
  branch_part=$(printf "\n⎇ %s%s" "$branch" "$lines_display")
fi

# If no usage data yet (before first API call), show model + cost + branch info
if [ -z "$used" ]; then
  if [ -n "$model" ]; then
    separator_early="${YELLOW}|${RESET}"
    model_prefix_early="${GREEN}🤖 ${model}${RESET}"
    cost_part_early=""
    [ -n "$cost" ] && cost_part_early="${YELLOW}💰 \$$(printf '%.2f' "$cost")${RESET}"
    printf "${model_prefix_early}${cost_part_early} ${separator_early}${branch_part}"
  fi
  exit 0
fi

# Round to integer for display
used_int=$(printf '%.0f' "$used")

# Build 10-char progress bar (each block = 10%)
filled=$(( used_int / 10 ))
bar=""
for i in $(seq 1 10); do
  if [ "$i" -le "$filled" ]; then
    bar="${bar}█"
  else
    bar="${bar}░"
  fi
done

# Color the bar based on usage level
if [ "$used_int" -ge 90 ]; then
  bar_colored="${RED}${bar}${RESET}"
elif [ "$used_int" -ge 70 ]; then
  bar_colored="${ORANGE}${bar}${RESET}"
elif [ "$used_int" -ge 50 ]; then
  bar_colored="${YELLOW}${bar}${RESET}"
else
  bar_colored="${GREEN}${bar}${RESET}"
fi

# Build colored model prefix (always shown)
model_prefix=""
if [ -n "$model" ]; then
  model_prefix="${GREEN}🤖 ${model}${RESET}"
fi

# Build cost part with color
cost_part_colored=""
if [ -n "$cost" ]; then
  cost_part_colored="${YELLOW}💰 \$$(printf '%.2f' "$cost")${RESET}"
fi

# Build colored separator
separator="${YELLOW}|${RESET}"

if [ "$used_int" -ge 90 ]; then
  printf "${model_prefix} ${separator} ${cost_part_colored} ${separator} CTX ${bar_colored} ${RED}${used_int}%% — start new session!${RESET}${branch_part}"
elif [ "$used_int" -ge 70 ]; then
  printf "${model_prefix} ${separator} ${cost_part_colored} ${separator} CTX ${bar_colored} ${ORANGE}${used_int}%% — run /compact now${RESET}${branch_part}"
elif [ "$used_int" -ge 50 ]; then
  printf "${model_prefix} ${separator} ${cost_part_colored} ${separator} CTX ${bar_colored} ${YELLOW}${used_int}%% — consider /compact${RESET}${branch_part}"
else
  printf "${model_prefix} ${separator} ${cost_part_colored} ${separator} CTX ${bar_colored} ${used_int}%%${branch_part}"
fi
