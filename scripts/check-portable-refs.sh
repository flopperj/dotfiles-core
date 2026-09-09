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

# An empty resolved list (no bundle skill dirs found, or an explicit empty
# argument list) is a usage error, not a vacuous "clean" pass.
if [ -z "$(echo "$CHECK_SKILLS" | tr -d '[:space:]')" ]; then
    echo "check-portable-refs: no skills to check in $SKILLS_DIR" >&2
    exit 1
fi

# shellcheck disable=SC2088 # literal tilde is the pattern we search for
FORBIDDEN='~/\.claude/_shared|~/\.claude/evals|~/\.claude/workflows|~/\.claude/skills/|\.\./\.\./agents/|\.\./\.\./workflows/|\.\./skills/|overlay-context|\.cursor/hooks\.json|parity-ignore|managed via dotfiles|CORE-ONLY|PORTABLE-ONLY|metrics-emit|ob-[0-9]'

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

        # 1b. the unqualified "Follow CLAUDE.md error handling defaults"
        # phrase must not survive export un-rewritten (grep lacks
        # lookahead, so check the qualified form's absence directly on any
        # line matching the bare phrase).
        while IFS=: read -r lineno line; do
            case "$line" in
                *"defaults when defined"*) ;;  # qualified — fine
                *) _violation "$rel: unqualified phrase (line $lineno) — Follow CLAUDE.md error handling defaults"; fail=1 ;;
            esac
        done < <(grep -noE 'Follow CLAUDE\.md error.handling defaults[^,.]*' "$md" || true)

        # 2. slash tokens must be bundle skills, or the exact token (or its
        # namespace wildcard, e.g. `/mc-*`) must literally appear in an
        # "Optional external skills" / "Skills are optional" paragraph.
        # Extract that paragraph's text once so the excuse can only match
        # what it actually names, not merely that such a paragraph exists.
        optional_para="$(awk '
            /Optional external skills|Skills are optional/ { p = 1 }
            p { print }
            p && /^[[:space:]]*$/ && NR > 1 && seen { exit }
            p { seen = 1 }
        ' "$md")"
        # shellcheck disable=SC2016 # single quotes are literal grep alternatives, not expansions
        for tok in $(grep -oE '(^|[ (`"'"'"'])/[a-z][a-z0-9-]+' "$md" | sed -E 's|^[^/]*/||' | sort -u); do
            echo "$tok" | grep -qE "^($ALLOW_SLASH)$" && continue
            case "$tok" in *-) continue ;; esac   # wildcard like /create-* in prose
            if _is_bundle_skill "$tok"; then continue; fi
            excused=0
            if [ -n "$optional_para" ]; then
                # exact token named literally
                echo "$optional_para" | grep -qF -- "/$tok" && excused=1
                # or its namespace wildcard, e.g. token mc-lint -> /mc-*
                ns="${tok%%-*}"
                if [ "$excused" -eq 0 ] && [ "$ns" != "$tok" ]; then
                    echo "$optional_para" | grep -qF -- "/$ns-*" && excused=1
                fi
            fi
            if [ "$excused" -eq 1 ]; then continue; fi
            _violation "$rel: unresolved skill reference /$tok (not in bundle; not named or wildcard-covered in the optional paragraph)"
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
