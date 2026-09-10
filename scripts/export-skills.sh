#!/usr/bin/env bash
# export-skills.sh — Render portable copies of the reasoning-pipeline skills
# into a plain skills repository (one that ships only `skills/<name>/SKILL.md`
# directories and is consumed by a skills CLI with no notion of ~/.claude
# agents, workflows, _shared/ or evals/).
#
# dotfiles-core stays canonical. Each managed skill directory in the target is
# fully regenerated on every run; unmanaged skills in the target are untouched.
#
# Usage:
#   bash scripts/export-skills.sh <target-repo-dir> [options]
#
# Options:
#   --check               Render to a temp dir and diff against the target;
#                         exit 1 on drift, 0 when the target is up to date.
#   --owner-team <name>   metadata.owner_team  (omitted when empty)
#   --owner-slack <chan>  metadata.owner_slack (omitted when empty)
#   --domain <value>      metadata.domain      (default: engineering-workflow)
#   --status <value>      metadata.status      (default: active)
#   --bundle <value>      metadata.bundle      (default: reasoning-pipeline)
#   -h, --help            Show this help.
#
# Environment:
#   EXPORT_SKILLS_CORE_DIR   Override the canonical dotfiles-core root this
#                            script reads skills/agents/workflows/_shared
#                            assets from (default: the repo containing this
#                            script). Tests use this to render from a scratch
#                            copy of the repo instead of the real tree.
#
# Transforms applied to every rendered markdown file:
#   1. `<!-- BEGIN CORE-ONLY -->` … `<!-- END CORE-ONLY -->` blocks are dropped.
#   2. `<!-- PORTABLE-ONLY` … `-->` wrappers are stripped so their body is live.
#   3. A fixed table of path/phrase rewrites (see _sed_program) redirects
#      ~/.claude-only references to skill-relative assets or marks them optional.
#   4. Portable notes (and, for agent-backed skills, a "Launching the agent"
#      section) are inserted from .claude/_shared/portable/ templates.
#   5. SKILL.md frontmatter gains a `metadata:` block.
#
# Exit codes: 0 ok / up to date; 1 drift (--check) or render error; 2 usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# EXPORT_SKILLS_CORE_DIR overrides the canonical dotfiles-core root this
# script reads skills/agents/workflows/_shared assets from. Tests use it to
# point at a scratch copy of the repo so a fixture (e.g. an unterminated
# CORE-ONLY marker) never touches the real canonical tree.
CORE_DIR="${EXPORT_SKILLS_CORE_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

SKILLS_SRC="$CORE_DIR/.claude/skills"
AGENTS_SRC="$CORE_DIR/.claude/agents"
SCHEMAS_SRC="$CORE_DIR/.claude/workflows/schemas"
WORKFLOWS_SRC="$CORE_DIR/.claude/workflows"
TURNCAP_SRC="$CORE_DIR/.claude/_shared/agent-turn-cap-warning.md"
HEURISTICS_SRC="$SKILLS_SRC/code-auditor/references/review-heuristics.md"
PORTABLE_DIR="$CORE_DIR/.claude/_shared/portable"
INSTALL_AGENT_TEMPLATE="$SCRIPT_DIR/templates/install-agent.sh"

README_BEGIN="REASONING PIPELINE TABLE"
README_END="REASONING PIPELINE TABLE"

# Exported skills, in README order. Kept as a single space-separated string
# (no arrays needed for iteration; bash 3.2-safe).
EXPORT_SKILLS="aristotle-deconstructor optimus-planner cyrus-tdd-engineer forge grill-me to-prd code-auditor scout-reviewer ranger-reviewer"

TARGET=""
CHECK=0
OWNER_TEAM=""
OWNER_SLACK=""
META_DOMAIN="engineering-workflow"
META_STATUS="active"
META_BUNDLE="reasoning-pipeline"

_usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --owner-team) OWNER_TEAM="${2:-}"; shift ;;
        --owner-slack) OWNER_SLACK="${2:-}"; shift ;;
        --domain) META_DOMAIN="${2:-}"; shift ;;
        --status) META_STATUS="${2:-}"; shift ;;
        --bundle) META_BUNDLE="${2:-}"; shift ;;
        -h|--help) _usage; exit 0 ;;
        -*) echo "export-skills.sh: unknown option: $1" >&2; _usage >&2; exit 2 ;;
        *)
            if [ -n "$TARGET" ]; then
                echo "export-skills.sh: unexpected extra argument: $1" >&2; exit 2
            fi
            TARGET="$1"
            ;;
    esac
    shift
done

[ -n "$TARGET" ] || { echo "export-skills.sh: missing <target-repo-dir>" >&2; _usage >&2; exit 2; }
[ -d "$TARGET" ] || { echo "export-skills.sh: target is not a directory: $TARGET" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"

for f in "$TURNCAP_SRC" "$HEURISTICS_SRC" "$INSTALL_AGENT_TEMPLATE" \
         "$PORTABLE_DIR/launch.md" "$PORTABLE_DIR/bundle-notes.md" "$PORTABLE_DIR/agent-notes.md"; do
    [ -f "$f" ] || { echo "export-skills.sh: required source missing: $f" >&2; exit 1; }
done

RENDER="$(mktemp -d)"
trap 'rm -rf "$RENDER"' EXIT INT TERM
mkdir -p "$RENDER/skills"

# ---------------------------------------------------------------------------
# Per-skill facts
# ---------------------------------------------------------------------------

# Does the skill ship an agent definition?
_has_agent() {
    case "$1" in
        aristotle-deconstructor|optimus-planner|cyrus-tdd-engineer|scout-reviewer|ranger-reviewer) return 0 ;;
        *) return 1 ;;
    esac
}

# Space-separated schema files copied into references/schemas/ (may be empty).
_schemas_for() {
    case "$1" in
        aristotle-deconstructor) echo "aristotle-to-optimus.json optimus-to-cyrus.json" ;;
        code-auditor) echo "auditor-composite.json" ;;
        *) echo "" ;;
    esac
}

# Does the skill (SKILL.md or agent) cite the turn-cap doc?
_needs_turncap() {
    case "$1" in
        aristotle-deconstructor|optimus-planner|cyrus-tdd-engineer|code-auditor|scout-reviewer|ranger-reviewer) return 0 ;;
        *) return 1 ;;
    esac
}

# Does the skill (SKILL.md or agent) cite review-heuristics.md?
_needs_heuristics() {
    case "$1" in
        code-auditor|cyrus-tdd-engineer|scout-reviewer|ranger-reviewer) return 0 ;;
        *) return 1 ;;
    esac
}

# YAML list body for metadata.tags (indented two spaces under the key).
_tags_for() {
    case "$1" in
        aristotle-deconstructor) echo "pipeline first-principles reasoning orchestrator" ;;
        optimus-planner) echo "pipeline planning execution-plan" ;;
        cyrus-tdd-engineer) echo "pipeline tdd implementation ci-fix" ;;
        forge) echo "pipeline orchestrator idea-to-pr" ;;
        grill-me) echo "design-review interview" ;;
        to-prd) echo "prd documentation" ;;
        code-auditor) echo "review routing complexity" ;;
        scout-reviewer) echo "review pr sonnet" ;;
        ranger-reviewer) echo "review pr staff-level opus" ;;
    esac
}

_tools_for() {
    case "$1" in
        aristotle-deconstructor|optimus-planner) echo "git" ;;
        cyrus-tdd-engineer) echo "git gh" ;;
        code-auditor) echo "gh rg" ;;
        scout-reviewer|ranger-reviewer) echo "gh git" ;;
        *) echo "" ;;
    esac
}

_mcp_for() {
    case "$1" in
        cyrus-tdd-engineer) echo "jenkins-mcp" ;;
        scout-reviewer|ranger-reviewer) echo "jenkins-mcp atlassian" ;;
        *) echo "" ;;
    esac
}

# Space-separated sibling-skill dependencies (install-alongside list), in the
# order they should render. Empty means standalone. A dependency is a skill
# this SKILL.md actually invokes (Skill tool or Agent tool) — a redirect in a
# "when not to use" note or a "companion" pointer is not a dependency.
_deps_for() {
    case "$1" in
        forge) echo "grill-me to-prd aristotle-deconstructor optimus-planner" ;;   # Cyrus runs inside the aristotle/optimus pipelines
        aristotle-deconstructor) echo "optimus-planner cyrus-tdd-engineer" ;;
        cyrus-tdd-engineer) echo "code-auditor scout-reviewer ranger-reviewer" ;;
        code-auditor) echo "scout-reviewer ranger-reviewer" ;;
        scout-reviewer) echo "cyrus-tdd-engineer" ;;
        ranger-reviewer) echo "cyrus-tdd-engineer" ;;
        optimus-planner) echo "cyrus-tdd-engineer aristotle-deconstructor" ;;
        grill-me) echo "to-prd" ;;
        to-prd) echo "" ;;
    esac
}

# Render the "Requires (install alongside): ..." / "Requires: none" line for
# a skill's declared dependencies.
_deps_line() {
    local skill="$1" deps dep out=""
    deps="$(_deps_for "$skill")"
    if [ -z "$deps" ]; then
        echo "**Requires:** none — this skill is standalone"
        return 0
    fi
    for dep in $deps; do
        if [ -z "$out" ]; then out="\`$dep\`"; else out="$out, \`$dep\`"; fi
    done
    echo "**Requires (install alongside):** $out"
}

# ---------------------------------------------------------------------------
# Transform primitives
# ---------------------------------------------------------------------------

# Drop CORE-ONLY blocks; unwrap PORTABLE-ONLY blocks. Reads stdin, writes stdout.
# An unterminated `<!-- BEGIN CORE-ONLY -->` (no matching END before EOF) is a
# source error, not something to silently truncate at — it means every line
# to EOF (potentially including later headings the insertion/metadata steps
# depend on) would vanish without a trace. Fail loudly instead.
_strip_markers() {
    awk '
        /^<!-- BEGIN CORE-ONLY -->[[:space:]]*$/ { skip = 1; next }
        /^<!-- END CORE-ONLY -->[[:space:]]*$/   { skip = 0; next }
        skip { next }
        /^<!-- PORTABLE-ONLY[[:space:]]*$/       { next }
        /^-->[[:space:]]*$/                      { next }
        { print }
        END {
            if (skip) {
                print "export-skills.sh: unterminated <!-- BEGIN CORE-ONLY --> marker (no matching END before EOF)" > "/dev/stderr"
                exit 1
            }
        }
    '
}

# Join the specific two-line wrap "Follow CLAUDE.md error handling\ndefaults."
# into one line before the sed rewrite table runs, so the rewrite only ever
# needs the single-line rule. A bare `s|^defaults\.$|...|` rule (no context)
# would misfire on any unrelated line that happens to read "defaults." —
# keying the join on the specific preceding line keeps this robust. Reads
# stdin, writes stdout.
_join_error_handling_wrap() {
    awk '
        prev ~ /Follow CLAUDE\.md error handling$/ && /^defaults\.$/ {
            print prev " defaults."
            prev = ""
            next
        }
        NR > 1 { print prev }
        { prev = $0 }
        END { if (NR > 0) print prev }
    '
}

# The fixed rewrite table. $1 = skill name, $2 = kind (skill|agent|ref).
_sed_program() {
    local skill="$1" kind="$2"
    # --- back-links between SKILL.md and agent file ---
    echo 's|\[`[a-z-]*\.md`\](\.\./\.\./agents/[a-z-]*\.md)|[`agent.md`](agent.md)|g'
    echo 's|\[`\.\./\.\./agents/[a-z-]*\.md`\](\.\./\.\./agents/[a-z-]*\.md)|[`agent.md`](agent.md)|g'
    echo 's|(\.\./skills/[a-z-]*/SKILL\.md)|(SKILL.md)|g'
    # --- shared docs → skill-relative references/ ---
    echo 's|`~/\.claude/_shared/agent-turn-cap-warning\.md`|`references/agent-turn-cap-warning.md`|g'
    echo 's|`~/\.claude/skills/code-auditor/references/review-heuristics\.md`|`references/review-heuristics.md`|g'
    echo 's|, and the `agent_truncated` metric to emit\.|.|g'
    # --- handoff schemas ---
    case "$skill" in
        forge)
            echo 's|\.\./\.\./workflows/schemas/|../aristotle-deconstructor/references/schemas/|g' ;;
        *)
            echo 's|\.\./\.\./workflows/schemas/|references/schemas/|g'
            echo 's|\[`\.claude/workflows/schemas/\([a-z-]*\.json\)`\]|[`references/schemas/\1`]|g'
            echo 's|(installed at `~/\.claude/workflows/schemas/`)|(shipped in this skill'"'"'s `references/schemas/`)|g' ;;
    esac
    # --- code-auditor: Workflow tool seam ---
    if [ "$skill" = "code-auditor" ] && [ "$kind" = "skill" ]; then
        echo 's|(`\.claude/workflows/code-auditor-score\.js`)|(`workflows/code-auditor-score.js`, shipped with this skill)|'
        echo 's|^1\. \*\*Invoke\.\*\* Invoke the `code-auditor-score` workflow, passing the$|1. **Invoke.** If the Workflow tool is available, invoke the workflow via `Workflow({scriptPath: "<SKILL_DIR>/workflows/code-auditor-score.js", args: ...})`, passing the|'
        echo 's|^pattern to the user instead of quietly absorbing it\.$|pattern to the user instead of quietly absorbing it. On hosts without the Workflow tool (e.g. Cursor) the fallback is the normal path, not a broken seam — say so once and continue.|'
    fi
    # --- optional personal context ---
    # The two-line wrap ("Follow CLAUDE.md error handling" / "defaults.") is
    # joined into one line by _join_error_handling_wrap before this program
    # runs, so this single rule covers both the one-line and wrapped forms.
    echo 's|Follow CLAUDE\.md error handling defaults|Follow CLAUDE.md error-handling defaults when defined (otherwise: surface the failure and stop, never retry silently)|g'
    echo 's|Check `~/\.claude/project-templates/` for|If `~/.claude/project-templates/` exists (optional personal context), check it for|g'
    # anchored so "managed via dotfiles-core" (a deliberate mention of the
    # canonical repo) is not eaten by the generic "managed via dotfiles" note.
    # Two rules (not \|-alternation) for BSD/macOS sed BRE compatibility.
    echo 's|managed via dotfiles\([^-]\)|if present\1|g'
    echo 's|managed via dotfiles$|if present|g'
    echo 's|`~/\.claude/DoD\.md`|`~/.claude/DoD.md` (if present)|g'
    echo 's|`~/\.claude/DoD\.md` (if present) (|`~/.claude/DoD.md` (if present; |g'
    echo 's|`~/\.claude/AGENTS\.md`|`~/.claude/AGENTS.md` (if present)|g'
    # the nine DoD section names are inline, so the taxonomy holds without the file
    echo 's|`~/\.claude/DoD\.md` (if present) — its 9 sections|`~/.claude/DoD.md` (if present; the 9 sections named here are the taxonomy either way) — its 9 sections|'
    # scout/ranger memory-write note: the harness only enforces disallowedTools
    # for a *registered* subagent; in fallback (general-purpose) mode it is
    # not enforced by the harness and must be self-enforced (see agent-notes.md).
    echo 's|(note: these are blocked by harness `disallowedTools`; memory writes will not persist from this agent until that constraint is lifted or routed via an orchestrator)|(note: these are blocked by `disallowedTools` when registered; in fallback mode you must refrain yourself — memory writes will not persist from this agent until that constraint is lifted or routed via an orchestrator)|g'
    echo 's|run /review-context to create one|create one (the `/review-context` skill does this, if installed)|g'
    echo 's|^- \*\*Review-context skill\*\* — |- **Review-context skill** (optional, not part of this bundle) — |'
    echo 's|not a dotfiles skill|not part of this bundle|g'
    # --- PR creation fallback ---
    echo 's|- Create PRs manually — always delegate to `/pr-create-from-commits`|- Create PRs by hand when `/pr-create-from-commits` is installed — delegate to it|'
    echo 's|Do not manually craft `gh pr create` commands — always delegate to `/pr-create-from-commits`\.|When `/pr-create-from-commits` is installed, delegate to it rather than crafting `gh pr create` by hand; otherwise run `gh pr create --draft` honouring the repository'"'"'s PR template.|'
    echo 's|Always delegate to `/pr-create-from-commits`,|Delegate to `/pr-create-from-commits` when installed (otherwise `gh pr create --draft` honouring the repository PR template),|'
    echo 's|^  never craft `gh pr create` manually\.$|  rather than crafting `gh pr create` by hand.|'
    # --- agent memory is a registered-subagent feature (SKILL.md only) ---
    if [ "$kind" = "skill" ]; then
        echo 's|`~/\.claude/agent-memory/\([a-z-]*\)/`|`~/.claude/agent-memory/\1/` (registered-subagent mode only)|g'
    else
        # Agents keep their Persistent Memory section verbatim (valid when
        # registered); only the mandatory numbered step in Optimus needs the
        # qualifier so a fallback run does not treat it as required.
        echo 's|^\*\*Step C — Check agent memory\.\*\* Consult|**Step C — Check agent memory (registered-subagent mode only).** Consult|'
    fi
    # --- project-agnostic bundle: company overlay skills never ship ---
    # The Optimus skill catalog lists the maintainer's /mc-* overlay skills
    # in table rows (a comment marker inside a markdown table would break
    # the table in core, so this is a generator rule, not a marker).
    if [ "$skill" = "optimus-planner" ] && [ "$kind" = "agent" ]; then
        echo '/^  | `\/mc-[a-z-]*` |/d'
    fi
    # --- core-only housekeeping ---
    echo '/^# parity-ignore:/d'
    echo 's|propose the change and ask me to confirm before saving it\.|propose it against the canonical source: this copy is generated from the maintainer'"'"'s dotfiles-core repository and is overwritten on the next export.|'
}

# Render a template, substituting {{AGENT}} / {{SKILL}} / {{DEPS}}.
_render_template() {
    local tpl="$1" skill="$2" deps_line
    deps_line="$(_deps_line "$skill")"
    awk -v deps="$deps_line" '{ gsub(/\{\{DEPS\}\}/, deps); print }' "$tpl" \
        | sed -e "s|{{AGENT}}|$skill|g" -e "s|{{SKILL}}|$skill|g"
}

# Insert file $2 (plus surrounding blank lines) before the first "## " heading
# of the markdown on stdin. Fails if no heading exists.
_insert_before_first_h2() {
    local insert="$1"
    awk -v ins="$insert" '
        BEGIN { done = 0 }
        /^## / && !done {
            while ((getline line < ins) > 0) print line
            close(ins)
            print ""
            done = 1
        }
        { print }
        END { if (!done) { print "export-skills.sh: no ## heading found for insertion" > "/dev/stderr"; exit 1 } }
    '
}

# Insert file $1 after the "> **Skill**:" cross-reference line (agent files).
_insert_after_skill_ref() {
    local insert="$1"
    awk -v ins="$insert" '
        BEGIN { done = 0 }
        { print }
        /^> \*\*Skill\*\*:/ && !done {
            print ""
            while ((getline line < ins) > 0) print line
            close(ins)
            done = 1
        }
        END { if (!done) { print "export-skills.sh: no > **Skill**: line found for insertion" > "/dev/stderr"; exit 1 } }
    '
}

# Emit the metadata block for a skill (YAML, 2-space indent under `metadata:`).
_metadata_block() {
    local skill="$1" v
    echo "metadata:"
    echo "  domain: $META_DOMAIN"
    echo "  status: $META_STATUS"
    echo "  bundle: $META_BUNDLE"
    [ -n "$OWNER_TEAM" ] && echo "  owner_team: $OWNER_TEAM"
    [ -n "$OWNER_SLACK" ] && echo "  owner_slack: \"$OWNER_SLACK\""
    echo "  tags:"
    for v in $(_tags_for "$skill"); do echo "    - $v"; done
    if [ -n "$(_tools_for "$skill")" ]; then
        echo "  tools:"
        for v in $(_tools_for "$skill"); do echo "    - $v"; done
    fi
    if [ -n "$(_mcp_for "$skill")" ]; then
        echo "  mcp_servers:"
        for v in $(_mcp_for "$skill"); do echo "    - $v"; done
    fi
    return 0
}

# Insert the metadata block before the closing `---` of the frontmatter.
_insert_metadata() {
    local block="$1"
    awk -v blk="$block" '
        NR == 1 && $0 ~ /^---[[:space:]]*$/ { infm = 1; print; next }
        infm && $0 ~ /^---[[:space:]]*$/ {
            while ((getline line < blk) > 0) print line
            close(blk)
            infm = 0
            print
            next
        }
        { print }
    '
}

# ---------------------------------------------------------------------------
# Render one skill into $RENDER/skills/<name>/
# ---------------------------------------------------------------------------
_render_skill() {
    local skill="$1"
    local src_dir="$SKILLS_SRC/$skill" out="$RENDER/skills/$skill"
    local sedprog tmp_insert tmp_meta

    [ -f "$src_dir/SKILL.md" ] || { echo "export-skills.sh: missing $src_dir/SKILL.md" >&2; return 1; }
    mkdir -p "$out"

    # SKILL.md
    sedprog="$(mktemp)"; _sed_program "$skill" skill > "$sedprog"
    tmp_insert="$(mktemp)"
    if _has_agent "$skill"; then
        _render_template "$PORTABLE_DIR/launch.md" "$skill" > "$tmp_insert"
        echo "" >> "$tmp_insert"
    fi
    _render_template "$PORTABLE_DIR/bundle-notes.md" "$skill" >> "$tmp_insert"
    tmp_meta="$(mktemp)"; _metadata_block "$skill" > "$tmp_meta"

    _strip_markers < "$src_dir/SKILL.md" \
        | sed -f "$sedprog" \
        | _insert_before_first_h2 "$tmp_insert" \
        | _insert_metadata "$tmp_meta" \
        > "$out/SKILL.md"
    rm -f "$sedprog" "$tmp_insert" "$tmp_meta"

    # agent.md + install-agent.sh
    if _has_agent "$skill"; then
        [ -f "$AGENTS_SRC/$skill.md" ] || { echo "export-skills.sh: missing agent $AGENTS_SRC/$skill.md" >&2; return 1; }
        sedprog="$(mktemp)"; _sed_program "$skill" agent > "$sedprog"
        tmp_insert="$(mktemp)"; _render_template "$PORTABLE_DIR/agent-notes.md" "$skill" > "$tmp_insert"
        # The memory bullet points at a Persistent Agent Memory section that
        # only agents declaring `memory:` carry (Aristotle has none by design).
        if ! grep -q '^memory:' "$AGENTS_SRC/$skill.md"; then
            # No `sed -i`: its flag syntax differs between BSD and GNU sed, and
            # CI runs on Linux. Filter through a second temp file instead.
            tmp_filtered="$(mktemp)"
            sed '/^- \*\*Memory applies only when registered\.\*\*/,/skip that section entirely\.$/d' "$tmp_insert" > "$tmp_filtered"
            mv "$tmp_filtered" "$tmp_insert"
        fi
        _strip_markers < "$AGENTS_SRC/$skill.md" \
            | _join_error_handling_wrap \
            | sed -f "$sedprog" \
            | _insert_after_skill_ref "$tmp_insert" \
            > "$out/agent.md"
        rm -f "$sedprog" "$tmp_insert"
        mkdir -p "$out/scripts"
        cp "$INSTALL_AGENT_TEMPLATE" "$out/scripts/install-agent.sh"
        chmod +x "$out/scripts/install-agent.sh"
    fi

    # references/
    if _needs_turncap "$skill"; then
        mkdir -p "$out/references"
        sedprog="$(mktemp)"; _sed_program "$skill" ref > "$sedprog"
        _strip_markers < "$TURNCAP_SRC" | sed -f "$sedprog" > "$out/references/agent-turn-cap-warning.md"
        rm -f "$sedprog"
    fi
    if _needs_heuristics "$skill"; then
        mkdir -p "$out/references"
        cp "$HEURISTICS_SRC" "$out/references/review-heuristics.md"
    fi
    local schema
    for schema in $(_schemas_for "$skill"); do
        mkdir -p "$out/references/schemas"
        [ -f "$SCHEMAS_SRC/$schema" ] || { echo "export-skills.sh: missing schema $SCHEMAS_SRC/$schema" >&2; return 1; }
        # The only rewrite applied to a shipped schema: its $comment cites the
        # core layout (.claude/workflows/…); the portable copy lives in the
        # skill's own workflows/ directory.
        sed 's|(\.claude/workflows/code-auditor-score\.js)|(workflows/code-auditor-score.js)|' \
            "$SCHEMAS_SRC/$schema" > "$out/references/schemas/$schema"
    done

    # workflows/ (code-auditor only)
    if [ "$skill" = "code-auditor" ]; then
        mkdir -p "$out/workflows"
        cp "$WORKFLOWS_SRC/code-auditor-score.js" "$out/workflows/code-auditor-score.js"
    fi

    # Guard: the skills CLI registers every SKILL.md it finds, so a nested one
    # would surface as a phantom skill.
    if [ "$(find "$out" -name SKILL.md | wc -l | tr -d ' ')" != "1" ]; then
        # Defensive only: every asset copied above has a fixed destination
        # name, so no input can currently reach this branch. It guards the
        # next person who adds a directory copy. (The checker enforces the
        # same invariant on the target, and that path is tested.)
        echo "export-skills.sh: $skill rendered more than one SKILL.md" >&2; return 1
    fi
}

# ---------------------------------------------------------------------------
# README rows (between sentinels; scaffold appended when absent)
# ---------------------------------------------------------------------------
_readme_rows() {
    local skill desc
    echo "| Skill | Description |"
    echo "|---|---|"
    for skill in $EXPORT_SKILLS; do
        desc="$(awk '/^description:/{
            line = $0
            sub(/^description:[[:space:]]*"?/, "", line)
            sub(/"$/, "", line)
            print line; exit
        }' "$RENDER/skills/$skill/SKILL.md" | sed 's/\\n.*//' | sed 's/\. Use .*//' | cut -c1-140)"
        [ -z "$desc" ] && desc="—"
        printf '| `%s` | %s |\n' "$skill" "$desc"
    done
}

_render_readme() {
    local src="$1" dst="$2" rows
    rows="$(mktemp)"; _readme_rows > "$rows"
    cp "$src" "$dst"
    if ! grep -q "BEGIN $README_BEGIN" "$dst"; then
        {
            echo ""
            echo "## Reasoning pipeline"
            echo ""
            echo "<!-- BEGIN $README_BEGIN -->"
            echo "<!-- END $README_END -->"
        } >> "$dst"
    fi
    _replace_between_sentinels "$dst" "$README_BEGIN" "$README_END" "$rows"
    rm -f "$rows"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
for skill in $EXPORT_SKILLS; do
    _render_skill "$skill"
done

if [ -f "$TARGET/README.md" ]; then
    _render_readme "$TARGET/README.md" "$RENDER/README.md"
else
    printf '# Skills\n' > "$RENDER/README.md.seed"
    _render_readme "$RENDER/README.md.seed" "$RENDER/README.md"
    rm -f "$RENDER/README.md.seed"
fi

if [ "$CHECK" -eq 1 ]; then
    drift=0
    for skill in $EXPORT_SKILLS; do
        if [ ! -d "$TARGET/skills/$skill" ]; then
            echo "DRIFT  skills/$skill — missing from target"; drift=1; continue
        fi
        if ! diff -r -q "$RENDER/skills/$skill" "$TARGET/skills/$skill" > /dev/null; then
            echo "DRIFT  skills/$skill"; drift=1
            # diff exits 1 on differences; under pipefail that would abort the report
            diff -r -q "$RENDER/skills/$skill" "$TARGET/skills/$skill" | sed 's/^/       /' || true
        fi
        # diff -q compares content only; a script that lost (or gained) its
        # executable bit reads as identical to `diff` but would silently fail
        # for a user invoking it. Check every shipped scripts/*.sh explicitly.
        while IFS= read -r rendered_script; do
            script_rel="${rendered_script#"$RENDER/skills/$skill"/}"
            target_script="$TARGET/skills/$skill/$script_rel"
            [ -f "$target_script" ] || continue
            if [ -x "$rendered_script" ] && [ ! -x "$target_script" ]; then
                echo "DRIFT  skills/$skill/$script_rel (executable bit missing)"; drift=1
            elif [ ! -x "$rendered_script" ] && [ -x "$target_script" ]; then
                # Defensive: every shipped script is rendered executable, so
                # this branch is unreachable until a non-executable .sh ships.
                echo "DRIFT  skills/$skill/$script_rel (unexpected executable bit)"; drift=1
            fi
        done < <(find "$RENDER/skills/$skill" -path '*/scripts/*.sh' 2>/dev/null)
    done
    if [ ! -f "$TARGET/README.md" ] || ! cmp -s "$RENDER/README.md" "$TARGET/README.md"; then
        echo "DRIFT  README.md (reasoning pipeline table)"; drift=1
    fi
    if [ "$drift" -eq 0 ]; then
        echo "export-skills: target is up to date ($TARGET)"
    else
        echo "export-skills: target has drifted — re-run without --check to regenerate" >&2
    fi
    exit "$drift"
fi

mkdir -p "$TARGET/skills"
for skill in $EXPORT_SKILLS; do
    rm -rf "$TARGET/skills/$skill"
    cp -R "$RENDER/skills/$skill" "$TARGET/skills/$skill"
done
cp "$RENDER/README.md" "$TARGET/README.md"

count="$(echo "$EXPORT_SKILLS" | wc -w | tr -d ' ')"
echo "export-skills: rendered $count skills into $TARGET/skills/ and updated README.md"
