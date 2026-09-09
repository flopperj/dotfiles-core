#!/usr/bin/env bash
# check-portable-refs.sh — Verify that an exported skills directory is
# self-contained: no reference escapes the bundle except through the
# documented "optional" paragraph.
#
# Usage: bash scripts/check-portable-refs.sh <skills-dir> [skill ...]
#   <skills-dir>  the target repo's skills/ directory (or a render dir)
#   [skill ...]   names to check; default: every bundle skill present in the dir
#
# Checks, per skill directory:
#   1. Forbidden tokens are absent from every .md file — core-only paths
#      (~/.claude/_shared, ~/.claude/evals, ~/.claude/workflows,
#      ~/.claude/skills/), repo-relative escapes (../../agents/,
#      ../../workflows/, ../skills/), overlay plumbing (overlay-context,
#      .cursor/hooks.json, parity-ignore, "managed via dotfiles"), and the
#      export markers themselves (CORE-ONLY, PORTABLE-ONLY).
#   2. Every `/skill-name` token resolves to a bundle skill, or the file
#      carries the "Optional external skills" / "Skills are optional" paragraph that declares
#      everything else optional.
#   3. Every markdown link to a relative path resolves to a file that exists
#      (inside this skill or a sibling skill directory).
#
# Exit codes: 0 clean; 1 violations; 2 usage.
set -euo pipefail

SKILLS_DIR="${1:-}"
[ -n "$SKILLS_DIR" ] && [ -d "$SKILLS_DIR" ] || { echo "usage: check-portable-refs.sh <skills-dir> [skill ...]" >&2; exit 2; }
SKILLS_DIR="$(cd "$SKILLS_DIR" && pwd)"
shift || true

BUNDLE="aristotle-deconstructor optimus-planner cyrus-tdd-engineer forge grill-me to-prd code-auditor scout-reviewer ranger-reviewer"

if [ $# -gt 0 ]; then
    CHECK_SKILLS="$*"
else
    # Default scope: bundle skills present in the dir. Unmanaged sibling skills
    # (hand-written by the target repo's owners) are not held to bundle rules.
    CHECK_SKILLS=""
    for s in $BUNDLE; do
        [ -f "$SKILLS_DIR/$s/SKILL.md" ] && CHECK_SKILLS="$CHECK_SKILLS $s"
    done
fi

# shellcheck disable=SC2088 # literal tilde is the pattern we search for
FORBIDDEN='~/\.claude/_shared|~/\.claude/evals|~/\.claude/workflows|~/\.claude/skills/|\.\./\.\./agents/|\.\./\.\./workflows/|\.\./skills/|overlay-context|\.cursor/hooks\.json|parity-ignore|managed via dotfiles|CORE-ONLY|PORTABLE-ONLY|metrics-emit'

# Slash tokens that are paths or prose, never skill names.
ALLOW_SLASH='skill|plans|prds|archive|dev|tmp|llms|repos|metrics|wrong|api|users|app|data|src|test|tests|lib|bin|etc|usr|home|var|opt|Users|claude|cursor|agents|skills|workflows|schemas|references|scripts|or|and|to|from|the|a|an|in|on|by|per|of|with|then|else|ip|i|r|p|x|n|y|g|s|d|c|e|f|dist|node_modules|build|docs|components|styles|pages|hooks|utils|mv|rm'

fail=0
_violation() { echo "FAIL  $1"; fail=1; }

_is_bundle_skill() {
    local name="$1" s
    for s in $BUNDLE; do [ "$s" = "$name" ] && return 0; done
    return 1
}

for skill in $CHECK_SKILLS; do
    dir="$SKILLS_DIR/$skill"
    [ -f "$dir/SKILL.md" ] || { _violation "$skill: no SKILL.md"; continue; }

    while IFS= read -r md; do
        rel="${md#"$SKILLS_DIR"/}"

        # 1. forbidden tokens
        if grep -nE -- "$FORBIDDEN" "$md" > /dev/null; then
            grep -nE -- "$FORBIDDEN" "$md" | cut -c1-140 | while IFS= read -r hit; do
                _violation "$rel: forbidden reference — $hit"
            done
            fail=1
        fi

        # 2. slash tokens must be bundle skills unless the optional paragraph is present
        has_optional=0
        grep -qE 'Optional external skills|Skills are optional' "$md" && has_optional=1
        # shellcheck disable=SC2016 # single quotes are literal grep alternatives, not expansions
        for tok in $(grep -oE '(^|[ (`"'"'"'])/[a-z][a-z0-9-]+' "$md" | sed -E 's|^[^/]*/||' | sort -u); do
            echo "$tok" | grep -qE "^($ALLOW_SLASH)$" && continue
            case "$tok" in *-) continue ;; esac   # wildcard like /create-* in prose
            echo "$tok" | grep -qE '^(pr-create-from-commits|review-context|swarm-retro|smart-compact|briefing|create-[a-z-]+|mc-[a-z-]+|google-[a-z-]+|mermaid-diagrams|code-review|handoff)$' && optional_kind=1 || optional_kind=0
            if _is_bundle_skill "$tok"; then continue; fi
            if [ "$optional_kind" -eq 1 ] && [ "$has_optional" -eq 1 ]; then continue; fi
            _violation "$rel: unresolved skill reference /$tok (not in bundle; optional paragraph $( [ "$has_optional" -eq 1 ] && echo present || echo absent ))"
        done

        # 3. relative markdown links must resolve
        for link in $(grep -oE '\]\([^)#:]+\)' "$md" | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?:|mailto:|/)' | sort -u); do
            case "$link" in
                *.md|*.json|*.js|*.sh)
                    if [ ! -e "$(dirname "$md")/$link" ]; then
                        _violation "$rel: broken relative link ($link)"
                    fi ;;
            esac
        done
    done < <(find "$dir" -name '*.md' | sort)

    # nested SKILL.md guard
    n="$(find "$dir" -name SKILL.md | wc -l | tr -d ' ')"
    [ "$n" = "1" ] || _violation "$skill: $n SKILL.md files (the skills CLI would register each as a skill)"
done

if [ "$fail" -eq 0 ]; then
    echo "check-portable-refs: clean ($(echo "$CHECK_SKILLS" | wc -w | tr -d ' ') skills)"
fi
exit "$fail"
