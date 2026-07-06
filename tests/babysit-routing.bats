#!/usr/bin/env bats
# Routing test for the /babysit-prs skill: a /loop-driven PR watcher.
#
# Belt-and-suspenders alongside the generic skill-routing-parity.bats. This
# file pins the concrete routing wiring textually so a future edit cannot
# silently drop the name-prefix row or one of the four advertised trigger
# phrases. It mirrors tests/forge-routing.bats.
#
# NOTE (RED until regeneration): the name-prefix + trigger rows are authored
# in the _shared/claude-md/ fragments (10-agent-routing.md, 20-trigger-skills.md).
# Those fragments are the SOURCE; .claude/CLAUDE.md.generated is the RENDERED
# output. These tests read the generated file, so they will be RED until a
# later step runs `bash scripts/pre-commit.sh` to regenerate CLAUDE.md.generated.
# Once regeneration lands, they turn GREEN with no edit required here.
#
# Run with: bats tests/babysit-routing.bats

# Note: we do NOT load 'test_helper' here because SKILLS_DIR and CLAUDE_MD
# must be set after DOTFILES_DIR is resolved in setup(), not at parse time.
# This mirrors the pattern used in skill-routing-parity.bats and forge-routing.bats.

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
    export BABYSIT_SKILL_MD="$SKILLS_DIR/babysit-prs/SKILL.md"
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

@test "babysit-prs SKILL.md exists with required frontmatter" {
    [ -f "$BABYSIT_SKILL_MD" ] || {
        echo "Expected $BABYSIT_SKILL_MD to exist"
        return 1
    }

    grep -q "^name: babysit-prs$" "$BABYSIT_SKILL_MD" || {
        echo "Expected 'name: babysit-prs' in frontmatter"
        return 1
    }

    grep -q "^user-invocable:[[:space:]]*true" "$BABYSIT_SKILL_MD" || {
        echo "Expected 'user-invocable: true' in frontmatter"
        return 1
    }
}

@test "babysit-prs name-prefix row is wired into CLAUDE.md" {
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md(.generated) not present"

    # The name-prefix row from _shared/claude-md/10-agent-routing.md.
    # Matches the '**Babysit, ...**' cell mapped to the /babysit-prs command.
    grep -qF -- "**Babysit, ...**" "$CLAUDE_MD" || {
        echo "Expected the '**Babysit, ...**' name-prefix row in CLAUDE.md"
        echo "(add it to _shared/claude-md/10-agent-routing.md and regenerate)"
        return 1
    }

    grep -qF -- "/babysit-prs" "$CLAUDE_MD" || {
        echo "Expected the '/babysit-prs' command reference in CLAUDE.md"
        return 1
    }
}

@test "babysit-prs advertised trigger phrases are wired into CLAUDE.md" {
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md(.generated) not present"

    local phrases=(
        "watch my PR"
        "babysit this PR"
        "watch these PRs and merge when green"
        "watch a channel for PRs"
    )

    local missing=()
    for phrase in "${phrases[@]}"; do
        # Case-insensitive word-boundary match, same semantics as
        # skill-routing-parity.bats.
        if ! grep -qiwF -- "$phrase" "$CLAUDE_MD"; then
            missing+=("$phrase")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "babysit-prs trigger phrases not wired into CLAUDE.md:"
        printf '  - "%s"\n' "${missing[@]}"
        echo "(add them to _shared/claude-md/20-trigger-skills.md and regenerate)"
        return 1
    fi
}
