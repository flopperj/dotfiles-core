#!/usr/bin/env bats
# Pin harness-level safety/capability frontmatter and settings env vars.
#
# Three concerns, one file:
#   1. Every agent declares a sane `maxTurns` cap.
#   2. The three review/analysis agents declare `disallowedTools` to block edits.
#   3. Both settings.json templates opt into experimental agent-teams mode.

load 'test_helper'

AGENTS_DIR="$DOTFILES_DIR/.claude/agents"
# settings.json template files live only in the overlay repo; skip these checks
# when running in dotfiles-core where no template files are present.
SETTINGS_TEMPLATE="$DOTFILES_DIR/.claude/settings.json.template"
SETTINGS_PERSONAL="$DOTFILES_DIR/.claude/settings.json.personal.example"

# Per-agent expected maxTurns values. If you change one, update the PR body too.
declare_expected() {
    expected_max_turns_aristotle=20
    expected_max_turns_optimus=30
    expected_max_turns_cyrus=60
    expected_max_turns_ranger=40
    expected_max_turns_scout=35
}

# Extract a top-level frontmatter key value. Frontmatter is the block between
# the first two `---` delimiters at the top of the file.
_frontmatter_value() {
    local file="$1" key="$2"
    awk -v k="^${key}:" '
        /^---$/ { delim++; if (delim == 2) exit; next }
        delim == 1 && $0 ~ k {
            sub(/^[^:]+:[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

# ---------------------------------------------------------------------------
# Assertion 1: All 5 agents declare maxTurns with the per-agent expected value
# ---------------------------------------------------------------------------
@test "every agent declares per-agent expected maxTurns" {
    declare_expected
    for short in aristotle:aristotle-deconstructor optimus:optimus-planner \
                 cyrus:cyrus-tdd-engineer ranger:ranger-reviewer \
                 scout:scout-reviewer; do
        IFS=: read -r tag fname <<< "$short"
        local file="$AGENTS_DIR/${fname}.md"
        local expected_var="expected_max_turns_${tag}"
        local actual
        actual="$(_frontmatter_value "$file" maxTurns)"
        [ -n "$actual" ] || { echo "no maxTurns key in $fname.md"; false; }
        [ "$actual" = "${!expected_var}" ] || {
            echo "$fname.md maxTurns: expected ${!expected_var}, got $actual"
            false
        }
    done
}

# ---------------------------------------------------------------------------
# Assertion 2: maxTurns value is a positive integer (no quotes, no decimals)
# ---------------------------------------------------------------------------
@test "maxTurns is a positive integer for every agent" {
    for fname in aristotle-deconstructor optimus-planner cyrus-tdd-engineer \
                 ranger-reviewer scout-reviewer; do
        local file="$AGENTS_DIR/${fname}.md"
        local val
        val="$(_frontmatter_value "$file" maxTurns)"
        [[ "$val" =~ ^[1-9][0-9]*$ ]] || {
            echo "$fname.md maxTurns is not a positive integer: '$val'"
            false
        }
    done
}

# ---------------------------------------------------------------------------
# Assertion 3: Aristotle, Ranger, Scout declare exact disallowedTools string
# ---------------------------------------------------------------------------
@test "aristotle, ranger, scout declare disallowedTools: Write, Edit, NotebookEdit" {
    local expected="Write, Edit, NotebookEdit"
    for fname in aristotle-deconstructor ranger-reviewer scout-reviewer; do
        local file="$AGENTS_DIR/${fname}.md"
        local val
        val="$(_frontmatter_value "$file" disallowedTools)"
        [ "$val" = "$expected" ] || {
            echo "$fname.md disallowedTools: expected '$expected', got '$val'"
            false
        }
    done
}

# ---------------------------------------------------------------------------
# Assertion 4: Cyrus and Optimus do NOT declare disallowedTools
# ---------------------------------------------------------------------------
@test "cyrus and optimus do not declare disallowedTools" {
    for fname in cyrus-tdd-engineer optimus-planner; do
        local file="$AGENTS_DIR/${fname}.md"
        local val
        val="$(_frontmatter_value "$file" disallowedTools)"
        [ -z "$val" ] || {
            echo "$fname.md should not have disallowedTools, got '$val'"
            false
        }
    done
}

# ---------------------------------------------------------------------------
# Assertion 5: Both fields live inside YAML frontmatter (not the body).
#              Frontmatter is the block between the first two `---` delimiters.
# ---------------------------------------------------------------------------
@test "maxTurns and disallowedTools live inside frontmatter, not body" {
    for fname in aristotle-deconstructor optimus-planner cyrus-tdd-engineer \
                 ranger-reviewer scout-reviewer; do
        local file="$AGENTS_DIR/${fname}.md"
        # Lines below the closing --- of frontmatter must NOT match these keys.
        local body_match
        body_match="$(awk '
            /^---$/ { delim++; next }
            delim >= 2 && /^(maxTurns|disallowedTools):/ { print FILENAME; exit }
        ' "$file")"
        [ -z "$body_match" ] || {
            echo "$fname.md has maxTurns/disallowedTools in body, must be frontmatter"
            false
        }
    done
}

# ---------------------------------------------------------------------------
# Assertion 6: Existing keys (name, description, model, color) remain intact
# ---------------------------------------------------------------------------
@test "pre-existing frontmatter keys remain intact for every agent" {
    for fname in aristotle-deconstructor optimus-planner cyrus-tdd-engineer \
                 ranger-reviewer scout-reviewer; do
        local file="$AGENTS_DIR/${fname}.md"
        for key in name description model color; do
            local val
            val="$(_frontmatter_value "$file" "$key")"
            [ -n "$val" ] || { echo "$fname.md missing $key"; false; }
        done
    done
}

# ---------------------------------------------------------------------------
# Assertion 7: Both settings.json templates declare env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# ---------------------------------------------------------------------------
@test "both settings.json templates declare env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" {
    [ -f "$SETTINGS_TEMPLATE" ] || skip "settings.json.template not present (overlay-only)"
    command -v jq >/dev/null || skip "jq not installed"
    for f in "$SETTINGS_TEMPLATE" "$SETTINGS_PERSONAL"; do
        local val
        val="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' "$f")"
        [ -n "$val" ] || { echo "$f missing env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"; false; }
    done
}

# ---------------------------------------------------------------------------
# Assertion 8: env value is the STRING "1" — not boolean true, not number 1
# ---------------------------------------------------------------------------
@test "env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is the string \"1\"" {
    [ -f "$SETTINGS_TEMPLATE" ] || skip "settings.json.template not present (overlay-only)"
    command -v jq >/dev/null || skip "jq not installed"
    for f in "$SETTINGS_TEMPLATE" "$SETTINGS_PERSONAL"; do
        local type val
        type="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS | type' "$f")"
        val="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$f")"
        [ "$type" = "string" ] || { echo "$f: env var type is $type, want string"; false; }
        [ "$val" = "1" ] || { echo "$f: env var value is '$val', want '1'"; false; }
    done
}
