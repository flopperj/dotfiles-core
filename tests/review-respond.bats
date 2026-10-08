#!/usr/bin/env bats
# Unit and integration tests for the /review-respond deterministic helper:
#   .claude/skills/review-respond/scripts/review-respond.sh
#
# CLI CONTRACT these tests pin:
#   review-respond.sh <subcommand> [flags]
#
#   threads        --graphql <file> | --rest <file>
#                    -> JSON array of normalized threads (all reviews)
#   select-review  --reviews <file> --threads <file> --author <login> [--review <id>]
#                    -> "<review_id>" | "NONE:no-qualifying-review" | "NONE:review-not-found"
#   commits        --base <sha> [--head <ref>] [--repo-dir <dir>]
#                    -> JSON array of commits | "ERROR:base-missing" | "ERROR:base-not-ancestor" (exit 3)
#   map-threads    --threads <file> --review <id> --commits <file> [--window <n>]
#                    -> {"threads":[...], "unlinked_commits":[...], "commits":[...]}
#   classify       --map <file>
#                    -> same JSON, each thread gains "class", "proposed", optional "suggested"
#   dismissed      --reviews <file> --head <sha> [--timeline <file>] [--review-decision <s>]
#                    -> "NEEDS_LOOK:<login>[,<login>]" | "OK"
#   find-prior     --comments <file> --review <id> --me <login>
#                    -> "<issue_comment_id>" | "NONE"
#   detect-checks  --dir <dir>
#                    -> JSON array [{kind,label,cmd,runner}]
#   parse-test-output --runner <vitest|jest|pytest|bats|phpunit|go>   (log on stdin)
#                    -> {"runner","files","tests_passed","tests_failed","parsed"}
#   render         --input <file>
#                    -> markdown on stdout (exit 0) | "REFUSE:<reason>" (exit 2)
#
#   Exit codes: 0 ok/decision token; 1 usage or malformed input; 2 render refusal;
#   3 git precondition. No subcommand calls gh or the network; only `commits`
#   reads git, read-only.
#
# Fixtures are neutral: github.example.com, acme/widgets, alice (author),
# bob/carol (reviewers). Pure subcommands get inline JSON; `commits` runs
# against a real scratch git repo and `detect-checks` against real scratch
# manifest directories.
#
# Run with: bats tests/review-respond.bats

setup() {
    TEST_HOME="$(mktemp -d)"
    ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    export RR="$DOTFILES_DIR/.claude/skills/review-respond/scripts/review-respond.sh"

    # Scratch git repos must not see the developer's git config.
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1

    # A PATH holding only bash, to prove the jq guard without uninstalling jq.
    NOJQ_PATH="$TEST_HOME/nojq-bin"
    export NOJQ_PATH
    mkdir -p "$NOJQ_PATH"
    ln -sf "$(command -v bash)" "$NOJQ_PATH/bash"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Skeleton: usage, dispatch, jq guard
# ---------------------------------------------------------------------------

@test "no subcommand prints usage and exits 1" {
    run "$RR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"review-respond.sh <subcommand>"* ]]
}

@test "unknown subcommand exits 1 naming it" {
    run "$RR" frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown subcommand: frobnicate"* ]]
}

@test "unknown flag exits 1 naming it" {
    run "$RR" threads --bogus x
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown argument: --bogus"* ]]
}

@test "a flag without a value exits 1 with a clear message" {
    run "$RR" threads --graphql
    [ "$status" -eq 1 ]
    [[ "$output" == *"--graphql needs a value"* ]]
}

@test "missing jq on PATH exits 1 with a clear message" {
    run bash -c 'PATH="$NOJQ_PATH" bash "$RR" threads --graphql /dev/null'
    [ "$status" -eq 1 ]
    [[ "$output" == *"jq is required"* ]]
}

@test "every contract subcommand is dispatched (not reported as unknown)" {
    [ -x "$RR" ] || {
        echo "helper script missing or not executable: $RR"
        return 1
    }
    local sub
    for sub in threads select-review commits map-threads classify dismissed find-prior detect-checks parse-test-output render; do
        run "$RR" "$sub"
        [[ "$output" != *"unknown subcommand"* ]] || {
            echo "subcommand not wired into dispatch: $sub"
            return 1
        }
    done
}
