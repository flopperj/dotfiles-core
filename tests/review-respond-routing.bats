#!/usr/bin/env bats
# Routing test for the /review-respond skill: the author-side review-round
# summary.
#
# Belt-and-suspenders alongside the generic skill-routing-parity.bats. This
# file pins the concrete routing wiring textually so a future edit cannot
# silently drop the name-prefix row, one of the five advertised trigger
# phrases, or the slash-command list entry. It mirrors tests/babysit-routing.bats.
#
# The name-prefix, trigger and slash-command rows are authored in the
# _shared/claude-md/ fragments (10-agent-routing.md, 20-trigger-skills.md,
# 30-compound-intents.md). Those fragments are the SOURCE; .claude/CLAUDE.md.generated
# is the RENDERED output. These tests read the generated file, so they stay RED
# until `bash scripts/pre-commit.sh` (or the pre-commit hook) regenerates it.
#
# Run with: bats tests/review-respond-routing.bats

# Note: we do NOT load 'test_helper' here because SKILLS_DIR and CLAUDE_MD
# must be set after DOTFILES_DIR is resolved in setup(), not at parse time.

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
    export RR_SKILL_MD="$SKILLS_DIR/review-respond/SKILL.md"
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

@test "review-respond SKILL.md exists with required frontmatter" {
    [ -f "$RR_SKILL_MD" ] || {
        echo "Expected $RR_SKILL_MD to exist"
        return 1
    }

    grep -q "^name: review-respond$" "$RR_SKILL_MD" || {
        echo "Expected 'name: review-respond' in frontmatter"
        return 1
    }

    grep -q "^user-invocable:[[:space:]]*true" "$RR_SKILL_MD" || {
        echo "Expected 'user-invocable: true' in frontmatter"
        return 1
    }
}

@test "review-respond name-prefix row is wired into CLAUDE.md" {
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md(.generated) not present"

    # The name-prefix row from _shared/claude-md/10-agent-routing.md.
    # Matches the '**Respond, ...**' cell mapped to the /review-respond command.
    grep -qF -- "**Respond, ...**" "$CLAUDE_MD" || {
        echo "Expected the '**Respond, ...**' name-prefix row in CLAUDE.md"
        echo "(add it to _shared/claude-md/10-agent-routing.md and regenerate)"
        return 1
    }

    grep -qF -- "/review-respond" "$CLAUDE_MD" || {
        echo "Expected the '/review-respond' command reference in CLAUDE.md"
        return 1
    }
}

@test "review-respond advertised trigger phrases are wired into CLAUDE.md" {
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md(.generated) not present"

    local phrases=(
        "respond to the review"
        "address review comments"
        "summarize this review round"
        "post a review round summary"
        "respond to PR feedback"
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
        echo "review-respond trigger phrases not wired into CLAUDE.md:"
        printf '  - "%s"\n' "${missing[@]}"
        echo "(add them to _shared/claude-md/20-trigger-skills.md and regenerate)"
        return 1
    fi
}

@test "review-respond appears in the slash-command list" {
    [ -f "$CLAUDE_MD" ] || skip "CLAUDE.md(.generated) not present"

    # The bulleted slash-command list in _shared/claude-md/30-compound-intents.md.
    grep -qE '^  - .*`/review-respond`' "$CLAUDE_MD" || {
        echo "Expected '/review-respond' in the slash-command list in CLAUDE.md"
        echo "(add it to _shared/claude-md/30-compound-intents.md and regenerate)"
        return 1
    }
}
