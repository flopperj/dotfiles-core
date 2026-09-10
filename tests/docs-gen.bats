#!/usr/bin/env bats
# Tests for scripts/docs-gen.sh — the README skills/agents table drift check.
#
# The script does not rewrite the README (curated rows beat frontmatter
# renders); it exits 1 naming any row that is missing or stale. Tests run it
# against the real README and against scratch copies with rows removed or
# invented, so both directions of drift are proven to fail.
# Run with: bats tests/docs-gen.bats

load 'test_helper'

GEN="$DOTFILES_DIR/scripts/docs-gen.sh"
README="$DOTFILES_DIR/README.md"

@test "docs-gen.sh exists and is bash 3.2-safe" {
    [ -f "$GEN" ] || return 1
    ! grep -qE 'mapfile|readarray|declare -A|\$\{[a-zA-Z_]+,,\}|\$\{[a-zA-Z_]+\^\^\}' "$GEN" || return 1
}

@test "real README tables are in step with the skill and agent directories" {
    run bash "$GEN"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"README tables in step:"* ]] || return 1
}

@test "every skill directory appears in the README skills table" {
    # Independent of the script's own logic: a plain cross-check.
    local missing=()
    for d in "$DOTFILES_DIR"/.claude/skills/*/; do
        [ -f "$d/SKILL.md" ] || continue
        local s
        s="$(basename "$d")"
        grep -qE "^\| \`/?$s\`" "$README" || missing+=("$s")
    done
    [ "${#missing[@]}" -eq 0 ] || { echo "missing: ${missing[*]}"; return 1; }
}

@test "a skill directory with no README row fails the check and is named" {
    local copy="$SCRATCH/README.md"
    grep -v '^| `/handoff` ' "$README" > "$copy"
    run bash "$GEN" "$copy"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"missing a row for skill directory: handoff"* ]] || return 1
}

@test "a README skill row with no directory fails the check and is named" {
    local copy="$SCRATCH/README.md"
    awk '{print} /^\| `\/grill-me` /{print "| `/no-such-skill` | invented |"}' "$README" > "$copy"
    run bash "$GEN" "$copy"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"names a skill with no directory: no-such-skill"* ]] || return 1
}

@test "an agent with no README row fails the check and is named" {
    local copy="$SCRATCH/README.md"
    grep -v '^| \*\*Scout\*\* ' "$README" > "$copy"
    run bash "$GEN" "$copy"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"missing a row for agent: Scout (from .claude/agents/scout-reviewer.md)"* ]] || return 1
}

@test "a README agent row with no definition file fails the check and is named" {
    local copy="$SCRATCH/README.md"
    awk '{print} /^\| \*\*Scout\*\* /{print "| **Nobody** | invented |"}' "$README" > "$copy"
    run bash "$GEN" "$copy"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"names an agent with no definition file: Nobody"* ]] || return 1
}

@test "internal skills may be listed with or without a leading slash" {
    # team-lead is not user-invocable; the README may write it either way.
    local copy="$SCRATCH/README.md"
    sed 's#^| `/team-lead` |#| `team-lead` _(internal)_ |#' "$README" > "$copy"
    run bash "$GEN" "$copy"
    [ "$status" -eq 0 ] || return 1
}

@test "a missing README path exits 1 with a clear message" {
    run bash "$GEN" "$SCRATCH/does-not-exist.md"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"README not found"* ]] || return 1
}

@test "a duplicated README skill row fails the check and is named" {
    local copy="$SCRATCH/README.md"
    awk '{print} /^\| `\/grill-me` /{print}' "$README" > "$copy"
    run bash "$GEN" "$copy"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"lists a skill more than once: grill-me"* ]] || return 1
}

@test "two agent files sharing a display name are reported, not merged" {
    # A hypothetical ranger-triage.md would also derive to **Ranger**; the
    # check must name both files rather than let one row cover two agents.
    local fake="$SCRATCH/repo"
    mkdir -p "$fake/scripts" "$fake/.claude/agents" "$fake/.claude/skills"
    cp "$GEN" "$fake/scripts/docs-gen.sh"
    cp -R "$DOTFILES_DIR"/.claude/skills/. "$fake/.claude/skills/"
    cp "$DOTFILES_DIR"/.claude/agents/*.md "$fake/.claude/agents/"
    printf -- '---\nname: ranger-triage\n---\n' > "$fake/.claude/agents/ranger-triage.md"
    run bash "$fake/scripts/docs-gen.sh" "$README"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"share the display name Ranger: ranger-reviewer.md ranger-triage.md"* ]] || return 1
}
