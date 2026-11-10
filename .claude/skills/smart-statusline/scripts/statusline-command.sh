#!/usr/bin/env bash
# Claude Code statusline script
# Shows context window usage with color-coded warnings and current model name.
#
# Every value from the status JSON or git is passed to printf as an argument,
# never as format text, so a % in a model or branch name prints literally.

input=$(cat)

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;208m'
RED='\033[0;31m'
RESET='\033[0m'

branch=""
lines_display=""
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  # Diff against the merge-base, not the remote tip: once origin/<default>
  # moves ahead, a tip diff would count upstream commits as this session's.
  default_branch=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  # A clone made with `git remote add` + fetch has no origin/HEAD.
  if [ -z "$default_branch" ]; then
    for candidate in main master; do
      if git rev-parse -q --verify "refs/remotes/origin/${candidate}" > /dev/null 2>&1; then
        default_branch="$candidate"
        break
      fi
    done
  fi
  if [ -n "$default_branch" ]; then
    base=$(git merge-base "origin/${default_branch}" HEAD 2>/dev/null) || base=""
    if [ -n "$base" ]; then
      stats=$(git diff --numstat "$base" 2>/dev/null | awk '{a+=$1; r+=$2} END {print a+0 " " r+0}')
      lines_added=${stats% *}
      lines_removed=${stats#* }
      if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
        lines_display=" | +${lines_added} -${lines_removed} ($((lines_added + lines_removed)) lines)"
      fi
    fi
  fi
fi

branch_part=""
if [ -n "$branch" ]; then
  branch_part=$(printf '\n⎇ %s%s' "$branch" "$lines_display")
fi

separator="${YELLOW}|${RESET}"

cost_label=""
if [ -n "$cost" ]; then
  cost_label="💰 ~\$$(printf '%.2f' "$cost")"
fi

ctx_text=""
ctx_colour=""
bar_colored=""
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")

  filled=$(( used_int / 10 ))
  bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}█"
    else
      bar="${bar}░"
    fi
  done

  if [ "$used_int" -ge 90 ]; then
    ctx_colour="$RED"; ctx_text="${used_int}% — start new session!"
  elif [ "$used_int" -ge 70 ]; then
    ctx_colour="$ORANGE"; ctx_text="${used_int}% — run /compact now"
  elif [ "$used_int" -ge 50 ]; then
    ctx_colour="$YELLOW"; ctx_text="${used_int}% — consider /compact"
  else
    ctx_colour="$GREEN"; ctx_text="${used_int}%"
  fi
  bar_colored="${ctx_colour}${bar}${RESET}"
fi

format=""
args=()
if [ -n "$model" ]; then
  format="${GREEN}🤖 %s${RESET}"
  args+=("$model")
fi
if [ -n "$cost_label" ]; then
  [ -n "$format" ] && format="${format} ${separator} "
  format="${format}${YELLOW}%s${RESET}"
  args+=("$cost_label")
fi
if [ -n "$used" ]; then
  [ -n "$format" ] && format="${format} ${separator} "
  if [ "$used_int" -ge 50 ]; then
    format="${format}CTX ${bar_colored} ${ctx_colour}%s${RESET}"
  else
    format="${format}CTX ${bar_colored} %s"
  fi
  args+=("$ctx_text")
fi

[ -n "$format" ] || exit 0
format="${format}%s"
args+=("$branch_part")

# shellcheck disable=SC2059
printf "$format" "${args[@]}"
