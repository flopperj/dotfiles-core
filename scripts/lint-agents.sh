#!/usr/bin/env bash
# lint-agents.sh — Deterministic structural linter for agent and skill prompt files.
#
# Checks that every agent/skill file contains required structural sections.
# Exits 0 if all checks pass, 1 if any fail.
#
# Usage:
#   bash scripts/lint-agents.sh                          # scan default dirs
#   bash scripts/lint-agents.sh --agents-dir <dir> --skills-dir <dir> --workflows-dir <dir>  # custom dirs (for testing)
#
# Required sections enforced by this linter:
#
#   Agent files (.claude/agents/*.md):
#     - YAML frontmatter (starts with ---)
#     - model: field in frontmatter
#     - ## Role Guard section
#     - **You NEVER:** list
#     - > **Skill**: cross-reference
#     - ## Tool Usage section
#
#   Skill files (.claude/skills/*/SKILL.md) that are pipeline skills
#   (have ## Responsibility boundaries section):
#     - YAML frontmatter
#     - description: field in frontmatter
#     - user-invocable: field in frontmatter
#     - ## Responsibility boundaries section
#     - BEGIN RESPONSIBILITY BOUNDARIES sentinel
#     - END RESPONSIBILITY BOUNDARIES sentinel
#     - Table header: "Sole responsibility" AND "NEVER does"
#
#   Checklist-driven skill files (opt-in via "<!-- shape: checklist-v1 -->" marker):
#     - ## When to Use heading (3-5 bullets)
#     - ## Workflow heading (~5 numbered steps)
#     - ## Checklist heading (copy-pasteable - [ ] items)
#     - ## Tools heading (list of MCP tools / CLI commands used)
#     - ## Resources heading (files, links)
#     - ## Examples heading (>= 1 concrete example)
#
#   Checklist-v1 checks are SOFT — they emit WARN, not FAIL, and never affect exit code.
#   Skills opt in by adding the marker; until then they continue under the existing rules.
#
#   Workflow files (.claude/workflows/*.js):
#     - export const meta block
#     - name: field in meta
#     - description: field in meta
#     - name matches the filename stem (workflows are invoked by name,
#       so a mismatch makes the slash command resolve unpredictably)
#     - node --input-type=module --check parses the file — ONLY when node
#       is installed; node is not a core dependency, so its absence emits
#       WARN, never FAIL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default directories (overridable for testing)
AGENTS_DIR="$DOTFILES_DIR/.claude/agents"
SKILLS_DIR="$DOTFILES_DIR/.claude/skills"
WORKFLOWS_DIR="$DOTFILES_DIR/.claude/workflows"

# Parse optional --agents-dir, --skills-dir, and --workflows-dir flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --agents-dir)
            AGENTS_DIR="$2"
            shift 2
            ;;
        --skills-dir)
            SKILLS_DIR="$2"
            shift 2
            ;;
        --workflows-dir)
            WORKFLOWS_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

pass_count=0
fail_count=0
warn_count=0

# Print a check result and update counters
_check() {
    local status="$1" file="$2" description="$3"
    if [ "$status" = "pass" ]; then
        echo "PASS  $file — $description"
        pass_count=$((pass_count + 1))
    else
        echo "FAIL  $file — $description"
        fail_count=$((fail_count + 1))
    fi
}

# Soft check: emit WARN on missing structure but never affect exit code.
# Used for opt-in conventions (e.g., checklist-v1 shape).
_check_soft() {
    local status="$1" file="$2" description="$3"
    if [ "$status" = "pass" ]; then
        echo "PASS  $file — $description"
        pass_count=$((pass_count + 1))
    else
        echo "WARN  $file — $description"
        warn_count=$((warn_count + 1))
    fi
}

# Check if a file contains a pattern
_has() {
    local file="$1" pattern="$2"
    grep -qE "$pattern" "$file"
}

# Check YAML frontmatter presence (file must start with --- on line 1)
_has_frontmatter() {
    local file="$1"
    head -1 "$file" | grep -q "^---"
}

# -----------------------------------------------------------------------
# Lint agent files
# -----------------------------------------------------------------------
for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    filename="$(basename "$agent_file")"

    # 1. YAML frontmatter
    if _has_frontmatter "$agent_file"; then
        _check pass "$filename" "YAML frontmatter"
    else
        _check fail "$filename" "YAML frontmatter"
    fi

    # 2. model: field
    if _has "$agent_file" "^model:"; then
        _check pass "$filename" "model: field in frontmatter"
    else
        _check fail "$filename" "model: field in frontmatter"
    fi

    # 3. Role Guard section
    if _has "$agent_file" "^## Role Guard"; then
        _check pass "$filename" "Role Guard section"
    else
        _check fail "$filename" "Role Guard section"
    fi

    # 4. You NEVER: list
    if _has "$agent_file" '\*\*You NEVER:\*\*'; then
        _check pass "$filename" "You NEVER: list"
    else
        _check fail "$filename" "You NEVER: list"
    fi

    # 5. Skill cross-reference
    if _has "$agent_file" '> \*\*Skill\*\*:'; then
        _check pass "$filename" "Skill cross-reference"
    else
        _check fail "$filename" "Skill cross-reference"
    fi

    # 6. Tool Usage section
    if _has "$agent_file" "^## Tool Usage"; then
        _check pass "$filename" "Tool Usage section"
    else
        _check fail "$filename" "Tool Usage section"
    fi

    # 7. BEGIN/END ROLE GUARD sentinels
    if _has "$agent_file" "BEGIN ROLE GUARD" && _has "$agent_file" "END ROLE GUARD"; then
        _check pass "$filename" "BEGIN/END ROLE GUARD sentinels"
    else
        _check fail "$filename" "BEGIN/END ROLE GUARD sentinels"
    fi

    # 8. ROLE_GUARD: <key> directive
    key="$(sed -n '/BEGIN ROLE GUARD/,/END ROLE GUARD/{
        /ROLE_GUARD:/{
            s/.*ROLE_GUARD:[[:space:]]*//
            s/[[:space:]]*-->//
            p
            q
        }
    }' "$agent_file")"
    if [ -n "$key" ]; then
        _check pass "$filename" "ROLE_GUARD directive present (key=$key)"

        # 9. Fragment file exists
        if [ -f "$DOTFILES_DIR/.claude/_shared/role-guards/${key}.md" ]; then
            _check pass "$filename" "ROLE_GUARD fragment exists (${key}.md)"
        else
            _check fail "$filename" "ROLE_GUARD fragment exists (${key}.md)"
        fi
    else
        _check fail "$filename" "ROLE_GUARD directive present"
    fi
done

# -----------------------------------------------------------------------
# Lint skill files
# -----------------------------------------------------------------------
for skill_dir in "$SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    # 1. YAML frontmatter
    if _has_frontmatter "$skill_file"; then
        _check pass "$skill_name/SKILL.md" "YAML frontmatter"
    else
        _check fail "$skill_name/SKILL.md" "YAML frontmatter"
    fi

    # 2. description: field
    if _has "$skill_file" "^description:"; then
        _check pass "$skill_name/SKILL.md" "description: field"
    else
        _check fail "$skill_name/SKILL.md" "description: field"
    fi

    # 3. user-invocable: field
    if _has "$skill_file" "^user-invocable:"; then
        _check pass "$skill_name/SKILL.md" "user-invocable: field"
    else
        _check fail "$skill_name/SKILL.md" "user-invocable: field"
    fi

    # 4-6. Only check boundary sentinels for pipeline skills
    #      (skills that have a "## Responsibility boundaries" section)
    if _has "$skill_file" "^## Responsibility boundaries"; then

        # 4. BEGIN sentinel
        if _has "$skill_file" "BEGIN RESPONSIBILITY BOUNDARIES"; then
            _check pass "$skill_name/SKILL.md" "BEGIN RESPONSIBILITY BOUNDARIES sentinel"
        else
            _check fail "$skill_name/SKILL.md" "BEGIN RESPONSIBILITY BOUNDARIES sentinel"
        fi

        # 5. END sentinel
        if _has "$skill_file" "END RESPONSIBILITY BOUNDARIES"; then
            _check pass "$skill_name/SKILL.md" "END RESPONSIBILITY BOUNDARIES sentinel"
        else
            _check fail "$skill_name/SKILL.md" "END RESPONSIBILITY BOUNDARIES sentinel"
        fi

        # 6. Table header integrity
        if _has "$skill_file" "Sole responsibility.*NEVER does"; then
            _check pass "$skill_name/SKILL.md" "boundary table header"
        else
            _check fail "$skill_name/SKILL.md" "boundary table header"
        fi
    fi
done

# -----------------------------------------------------------------------
# Lint workflow files
# -----------------------------------------------------------------------
for workflow_file in "$WORKFLOWS_DIR"/*.js; do
    [ -f "$workflow_file" ] || continue
    wf_filename="$(basename "$workflow_file")"
    wf_stem="${wf_filename%.js}"

    # 1. export const meta block
    if _has "$workflow_file" '^export const meta'; then
        _check pass "$wf_filename" "export const meta block"
    else
        _check fail "$wf_filename" "export const meta block"
    fi

    # 2. name: field in meta
    if _has "$workflow_file" "^[[:space:]]*name:"; then
        _check pass "$wf_filename" "meta name: field"
    else
        _check fail "$wf_filename" "meta name: field"
    fi

    # 3. description: field in meta
    if _has "$workflow_file" "^[[:space:]]*description:"; then
        _check pass "$wf_filename" "meta description: field"
    else
        _check fail "$wf_filename" "meta description: field"
    fi

    # 4. meta name matches the filename stem
    wf_meta_name="$(sed -n "s/^[[:space:]]*name:[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "$workflow_file" | head -1)"
    if [ -n "$wf_meta_name" ] && [ "$wf_meta_name" = "$wf_stem" ]; then
        _check pass "$wf_filename" "meta name matches filename stem"
    else
        _check fail "$wf_filename" "meta name matches filename stem (name='$wf_meta_name', stem='$wf_stem')"
    fi

    # 5. Syntax check — only when node is installed (not a core dependency).
    #    --input-type=module via stdin: workflow files are ESM, and plain
    #    `node --check <file>` parses .js as CommonJS on some node versions.
    if command -v node > /dev/null 2>&1; then
        if node --input-type=module --check < "$workflow_file" > /dev/null 2>&1; then
            _check pass "$wf_filename" "node syntax check"
        else
            _check fail "$wf_filename" "node syntax check"
        fi
    else
        _check_soft fail "$wf_filename" "node syntax check skipped (node not installed)"
    fi
done

# -----------------------------------------------------------------------
# SOFT CHECKS — checklist-v1 shape (opt-in via marker)
# -----------------------------------------------------------------------
# Skills bearing "<!-- shape: checklist-v1 -->" are validated for the six
# canonical headings. Missing headings emit WARN, never FAIL.
for skill_dir in "$SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    if ! _has "$skill_file" "<!-- shape: checklist-v1 -->"; then
        continue
    fi

    for heading in "When to Use" "Workflow" "Checklist" "Tools" "Resources" "Examples"; do
        # Use explicit "end-of-word" pattern (whitespace OR end-of-line) instead
        # of \b — \b is a GNU grep extension and behavior is undefined under
        # strict POSIX grep on some platforms (e.g. minimal CWS images).
        if _has "$skill_file" "^## ${heading}(\s|$)"; then
            _check_soft pass "$skill_name/SKILL.md" "checklist-v1: ## ${heading}"
        else
            _check_soft fail "$skill_name/SKILL.md" "checklist-v1: ## ${heading}"
        fi
    done
done

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo "---"
echo "$pass_count checks passed, $fail_count failed, $warn_count warnings"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
