#!/usr/bin/env bats
# Tests for the /forge skill: a five-stage sense-making + build pipeline
# orchestrator that chains grill-me -> to-prd -> aristotle-deconstructor
# -> optimus-planner -> cyrus-tdd-engineer.
#
# These tests pin the SKILL.md contract textually so future edits cannot
# silently drop a stage, gate, or entry point. They do NOT exercise runtime
# orchestration — that requires an LLM harness which does not exist in this
# repo.
#
# Run with: bats tests/forge-routing.bats

# Note: we do NOT load 'test_helper' here because SKILLS_DIR and CLAUDE_MD
# must be set after DOTFILES_DIR is resolved in setup(), not at parse time.
# This mirrors the pattern used in skill-routing-parity.bats.

ANCHORS='Triggers on|or mentions|or says|starts a prompt with'

setup() {
    TEST_HOME="$(mktemp -d)"
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi
    export DOTFILES_DIR
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export SKILLS_DIR="$DOTFILES_DIR/.claude/skills"
    # In dotfiles-core the rendered file is CLAUDE.md.generated; in the overlay
    # it is CLAUDE.md.  Accept whichever form is present.
    if [ -f "$DOTFILES_DIR/.claude/CLAUDE.md" ]; then
        export CLAUDE_MD="$DOTFILES_DIR/.claude/CLAUDE.md"
    else
        export CLAUDE_MD="$DOTFILES_DIR/.claude/CLAUDE.md.generated"
    fi
    export FORGE_SKILL_MD="$SKILLS_DIR/forge/SKILL.md"
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# Extract the description: value (single line — descriptions in this repo
# are always single-line YAML strings, sometimes quoted, sometimes bare).
# Copied from skill-routing-parity.bats; deduplication is a future concern.
_get_description() {
    local skill_md="$1"
    awk '
        /^description:/ {
            sub(/^description:[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$skill_md"
}

# Extract trigger phrases from a skill description.
# Copied from skill-routing-parity.bats; deduplication is a future concern.
_extract_triggers() {
    local description="$1"
    echo "$description" | awk -v anchors="$ANCHORS" '
        function extract_quoted(zone,    i, c, prev_c, next_c, in_dq, in_sq, token) {
            in_dq = 0; in_sq = 0; token = ""
            for (i = 1; i <= length(zone); i++) {
                c      = substr(zone, i, 1)
                prev_c = (i > 1)              ? substr(zone, i-1, 1) : " "
                next_c = (i < length(zone))   ? substr(zone, i+1, 1) : " "

                if (!in_dq && !in_sq && c == "\"") {
                    in_dq = 1; token = ""; continue
                }
                if (in_dq && c == "\"") {
                    print token; in_dq = 0; token = ""; continue
                }
                if (!in_dq && !in_sq && c == "\047") {
                    if (prev_c !~ /[[:alnum:]]/) {
                        in_sq = 1; token = ""; continue
                    }
                }
                if (in_sq && c == "\047") {
                    if (next_c !~ /[[:alnum:]]/) {
                        print token; in_sq = 0; token = ""; continue
                    }
                }
                if (in_dq || in_sq) token = token c
            }
        }
        BEGIN {
            n = split(anchors, A, "|")
        }
        {
            line = $0
            for (i = 1; i <= n; i++) {
                lline = tolower(line)
                lanchor = tolower(A[i])
                pos = index(lline, lanchor)
                if (pos > 0) {
                    zone = substr(line, pos)
                    if (match(zone, /\. /)) zone = substr(zone, 1, RSTART)
                    extract_quoted(zone)
                }
            }
        }
    ' | sort -u
}

# ---------------------------------------------------------------------------
# Step 1 (Red) — three failing tests that drive SKILL.md authoring
# ---------------------------------------------------------------------------

@test "forge SKILL.md exists with required frontmatter" {
    [ -f "$FORGE_SKILL_MD" ] || {
        echo "Expected $FORGE_SKILL_MD to exist"
        return 1
    }

    grep -q "^name: forge$" "$FORGE_SKILL_MD" || {
        echo "Expected 'name: forge' in frontmatter"
        return 1
    }

    grep -q "^user-invocable:[[:space:]]*true" "$FORGE_SKILL_MD" || {
        echo "Expected 'user-invocable: true' in frontmatter"
        return 1
    }

    # description must be a single line (the parity-extractor reads only one)
    local description
    description="$(_get_description "$FORGE_SKILL_MD")"
    [ -n "$description" ] || {
        echo "description: line not found or empty"
        return 1
    }
}

@test "forge SKILL.md declares all five pipeline stages" {
    [ -f "$FORGE_SKILL_MD" ] || skip "forge SKILL.md not yet authored"

    local missing=()
    for stage in grill-me to-prd aristotle-deconstructor optimus-planner cyrus-tdd-engineer; do
        if ! grep -qF -- "$stage" "$FORGE_SKILL_MD"; then
            missing+=("$stage")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "forge SKILL.md must reference all five pipeline stages."
        echo "Missing: ${missing[*]}"
        return 1
    fi
}

@test "forge advertised trigger phrases are wired into CLAUDE.md" {
    [ -f "$FORGE_SKILL_MD" ] || skip "forge SKILL.md not yet authored"

    local description triggers ignore_list violations=()
    description="$(_get_description "$FORGE_SKILL_MD")"
    triggers="$(_extract_triggers "$description")"

    [ -n "$triggers" ] || {
        echo "forge SKILL.md description must advertise at least one trigger phrase"
        echo "(under 'Triggers on', 'or mentions', 'or says', or 'starts a prompt with')"
        return 1
    }

    ignore_list="$(grep '^# parity-ignore:' "$FORGE_SKILL_MD" | sed 's/^# parity-ignore:[[:space:]]*//')"

    while IFS= read -r phrase; do
        [ -z "$phrase" ] && continue
        if [ -n "$ignore_list" ] && echo "$ignore_list" | grep -qxF -- "$phrase"; then
            continue
        fi
        if ! grep -qiwF -- "$phrase" "$CLAUDE_MD"; then
            violations+=("\"$phrase\" not found in CLAUDE.md")
        fi
    done <<< "$triggers"

    if [ "${#violations[@]}" -gt 0 ]; then
        echo "forge trigger phrases not wired into CLAUDE.md:"
        printf '  - %s\n' "${violations[@]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Step 6 — contract-pinning smoke tests
#
# These tests pin the orchestration contract textually so future edits cannot
# silently drop a downstream invocation, gate, or entry-point flag. They are
# regression guards, not a runtime harness — the pipeline is only exercised
# by the LLM at session time.
# ---------------------------------------------------------------------------

@test "forge SKILL.md invokes all four downstream skills by slash-command name" {
    [ -f "$FORGE_SKILL_MD" ] || skip "forge SKILL.md not yet authored"

    local missing=()
    # The orchestrator must explicitly invoke each downstream skill by its
    # slash-command form. Bare stage names (e.g. "grill-me") satisfy Test 2
    # but do not pin the invocation contract — only "/grill-me" does.
    for slash in /grill-me /to-prd /aristotle-deconstructor /optimus-planner; do
        if ! grep -qF -- "$slash" "$FORGE_SKILL_MD"; then
            missing+=("$slash")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "forge SKILL.md must invoke all four downstream skills by slash-command name."
        echo "Missing: ${missing[*]}"
        return 1
    fi
}

@test "forge SKILL.md documents both orchestrator-owned gates" {
    [ -f "$FORGE_SKILL_MD" ] || skip "forge SKILL.md not yet authored"

    grep -qF "Gate 1" "$FORGE_SKILL_MD" || {
        echo "forge SKILL.md must document 'Gate 1' (after grill-me)"
        return 1
    }
    grep -qF "Gate 2" "$FORGE_SKILL_MD" || {
        echo "forge SKILL.md must document 'Gate 2' (after to-prd)"
        return 1
    }
}

@test "forge SKILL.md documents the --from prd entry point" {
    [ -f "$FORGE_SKILL_MD" ] || skip "forge SKILL.md not yet authored"

    grep -qF -- "--from prd" "$FORGE_SKILL_MD" || {
        echo "forge SKILL.md must document the '--from prd <path>' entry point"
        echo "(skips grill-me + to-prd, jumps to Aristotle handoff)"
        return 1
    }
}

@test "forge SKILL.md documents the --skip-aristotle flag" {
    [ -f "$FORGE_SKILL_MD" ] || skip "forge SKILL.md not yet authored"

    grep -qF -- "--skip-aristotle" "$FORGE_SKILL_MD" || {
        echo "forge SKILL.md must document the '--skip-aristotle' flag"
        echo "(hands the PRD straight to /optimus-planner)"
        return 1
    }
}
