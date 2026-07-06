#!/usr/bin/env bats
# Unit tests for .claude/skills/babysit-prs/scripts/babysit-state.sh
#
# babysit-state.sh manages the per-run JSON state file for the /babysit-prs
# skill. It is a pure state-store CLI: JSON/args in, JSON/values out, atomic
# write-temp-then-rename, no network I/O. The SKILL.md Actor prose owns all
# gh/Slack/git calls; this script only reads and writes the run's state file.
#
# State home:   ~/.claude/tasks/<project>/babysit-prs/
#   <project> = basename(git toplevel || pwd)
#   <run_id>.json   — one file per run
#   latest.json     — symlink to the active run's file
#
# Coverage (per plan Step 4 / PRD Testing Decisions):
#   - round-trip serialize / deserialize (per-PR record + run-level fields)
#   - run isolation (two run files do not interfere)
#   - resume-matching (re-launch picks the right recent file, counters intact)
#   - atomic write (write-temp-then-rename; no partial/leftover temp files)
#
# Written before implementation (RED phase); all tests must fail first.
#
# Run with: bats tests/babysit-state.bats

setup() {
    # Absolute path to the state helper under test.
    DOTFILES_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export DOTFILES_DIR
    STATE_SH="$DOTFILES_DIR/.claude/skills/babysit-prs/scripts/babysit-state.sh"
    export STATE_SH
    SCHEMA_JSON="$DOTFILES_DIR/.claude/skills/babysit-prs/data/state-schema.json"
    export SCHEMA_JSON

    # Isolate HOME so state writes land in a scratch tree, never the real
    # ~/.claude. Mirrors the HOME-isolation guard in forge-routing.bats.
    ORIG_HOME="$HOME"
    export ORIG_HOME
    TEST_HOME="$(mktemp -d)"
    export TEST_HOME
    export HOME="$TEST_HOME"
    if [ "$HOME" = "$ORIG_HOME" ] || [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
        echo "FATAL: HOME isolation failed" >&2
        exit 99
    fi

    # A stable project name so the state dir is deterministic in tests. The
    # script accepts BABYSIT_PROJECT as an override for the git-toplevel default,
    # which keeps tests independent of the checkout path.
    export BABYSIT_PROJECT="testproj"
    STATE_DIR="$HOME/.claude/tasks/$BABYSIT_PROJECT/babysit-prs"
    export STATE_DIR
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# state-init: creates the run file + latest.json symlink under the right path
# ---------------------------------------------------------------------------
@test "state-init creates <run_id>.json and latest.json symlink under ~/.claude/tasks/<project>/babysit-prs" {
    run bash "$STATE_SH" state-init \
        --run-id run-aaa \
        --flags "--merge --fix" \
        --my-login octocat \
        --targets "482 491"
    [ "$status" -eq 0 ]

    # Run file exists at the expected path.
    [ -f "$STATE_DIR/run-aaa.json" ] || {
        echo "expected $STATE_DIR/run-aaa.json to exist"
        echo "dir listing:"; ls -la "$STATE_DIR" 2>&1
        return 1
    }

    # latest.json is a symlink pointing at the run file.
    [ -L "$STATE_DIR/latest.json" ] || {
        echo "expected latest.json to be a symlink"
        return 1
    }
    local target
    target="$(readlink "$STATE_DIR/latest.json")"
    # Accept either an absolute or a basename-relative link, as long as it
    # resolves to the run file.
    [ "$(basename "$target")" = "run-aaa.json" ] || {
        echo "latest.json should point at run-aaa.json, got: $target"
        return 1
    }

    # Run-level fields round-trip.
    run jq -r '.run_id' "$STATE_DIR/run-aaa.json"
    [ "$status" -eq 0 ]
    [ "$output" = "run-aaa" ]

    run jq -r '.my_login' "$STATE_DIR/run-aaa.json"
    [ "$output" = "octocat" ]

    run jq -r '.flags' "$STATE_DIR/run-aaa.json"
    [ "$output" = "--merge --fix" ]

    # started is a non-empty timestamp.
    run jq -r '.started' "$STATE_DIR/run-aaa.json"
    [ -n "$output" ]
    [ "$output" != "null" ]
}

@test "state-init produces valid JSON that parses with jq" {
    run bash "$STATE_SH" state-init --run-id run-json --my-login octocat --targets "1"
    [ "$status" -eq 0 ]
    run jq -e '.' "$STATE_DIR/run-json.json"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Round-trip: per-PR record serialize / deserialize
# ---------------------------------------------------------------------------
@test "state-write-pr then state-read-pr round-trips a full per-PR record" {
    bash "$STATE_SH" state-init --run-id run-rt --my-login octocat --targets "482"

    # A full per-PR record per the PRD state model.
    local record
    record='{
      "head_sha": "abc123",
      "authored_by_me": true,
      "explicitly_named": true,
      "ci_failures": {"lint": 2, "unit": 1},
      "fix_attempts": 1,
      "blocker_fingerprints": ["src/a.ts|lint|unused-var"],
      "last_review": {"sha": "abc123", "ci": "SUCCESS", "reviewDecision": "APPROVED", "blockers": 0},
      "approved": true,
      "status": "watching"
    }'

    run bash "$STATE_SH" state-write-pr --run-id run-rt --pr 482 --record "$record"
    [ "$status" -eq 0 ]

    # Read the whole record back.
    run bash "$STATE_SH" state-read-pr --run-id run-rt --pr 482
    [ "$status" -eq 0 ]

    # Every field survives the round trip.
    echo "$output" | jq -e '.head_sha == "abc123"'
    echo "$output" | jq -e '.authored_by_me == true'
    echo "$output" | jq -e '.explicitly_named == true'
    echo "$output" | jq -e '.ci_failures.lint == 2'
    echo "$output" | jq -e '.ci_failures.unit == 1'
    echo "$output" | jq -e '.fix_attempts == 1'
    echo "$output" | jq -e '.blocker_fingerprints[0] == "src/a.ts|lint|unused-var"'
    echo "$output" | jq -e '.last_review.ci == "SUCCESS"'
    echo "$output" | jq -e '.last_review.reviewDecision == "APPROVED"'
    echo "$output" | jq -e '.last_review.blockers == 0'
    echo "$output" | jq -e '.approved == true'
    echo "$output" | jq -e '.status == "watching"'
}

@test "state-read-pr on an unknown PR exits non-zero (or reports absence) without corrupting the file" {
    bash "$STATE_SH" state-init --run-id run-missing --my-login octocat --targets "1"
    run bash "$STATE_SH" state-read-pr --run-id run-missing --pr 999
    # An unknown PR must not silently succeed with a fabricated record.
    [ "$status" -ne 0 ]

    # The run file must remain valid JSON after a miss.
    run jq -e '.' "$STATE_DIR/run-missing.json"
    [ "$status" -eq 0 ]
}

@test "state-write-pr updates an existing per-PR record in place (counters advance)" {
    bash "$STATE_SH" state-init --run-id run-upd --my-login octocat --targets "482"
    bash "$STATE_SH" state-write-pr --run-id run-upd --pr 482 \
        --record '{"fix_attempts": 1, "status": "watching"}'
    bash "$STATE_SH" state-write-pr --run-id run-upd --pr 482 \
        --record '{"fix_attempts": 2, "status": "needs-human"}'

    run bash "$STATE_SH" state-read-pr --run-id run-upd --pr 482
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.fix_attempts == 2'
    echo "$output" | jq -e '.status == "needs-human"'

    # Exactly one record for PR 482 (no duplicate keys).
    run jq -r '.prs | keys | length' "$STATE_DIR/run-upd.json"
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# Run-level fields
# ---------------------------------------------------------------------------
@test "state-set-run sets run-level fields (slack block, last_seen_ts)" {
    bash "$STATE_SH" state-init --run-id run-slack --my-login octocat --targets "1"

    run bash "$STATE_SH" state-set-run --run-id run-slack \
        --set 'slack.channel_id=C12345' \
        --set 'slack.enabled=true' \
        --set 'slack.last_seen_ts=1700000000.000100'
    [ "$status" -eq 0 ]

    run jq -r '.slack.channel_id' "$STATE_DIR/run-slack.json"
    [ "$output" = "C12345" ]
    run jq -r '.slack.last_seen_ts' "$STATE_DIR/run-slack.json"
    [ "$output" = "1700000000.000100" ]
    run jq -r '.slack.enabled' "$STATE_DIR/run-slack.json"
    [ "$output" = "true" ]
}

# ---------------------------------------------------------------------------
# Run isolation: two run files do not interfere
# ---------------------------------------------------------------------------
@test "run isolation: two concurrent runs keep separate per-PR counters" {
    bash "$STATE_SH" state-init --run-id run-A --my-login octocat --targets "482"
    bash "$STATE_SH" state-init --run-id run-B --my-login octocat --targets "482"

    # Same PR number, different runs, different counters.
    bash "$STATE_SH" state-write-pr --run-id run-A --pr 482 \
        --record '{"fix_attempts": 3, "status": "needs-human"}'
    bash "$STATE_SH" state-write-pr --run-id run-B --pr 482 \
        --record '{"fix_attempts": 0, "status": "watching"}'

    run bash "$STATE_SH" state-read-pr --run-id run-A --pr 482
    echo "$output" | jq -e '.fix_attempts == 3'
    echo "$output" | jq -e '.status == "needs-human"'

    run bash "$STATE_SH" state-read-pr --run-id run-B --pr 482
    echo "$output" | jq -e '.fix_attempts == 0'
    echo "$output" | jq -e '.status == "watching"'

    # Two distinct files on disk.
    [ -f "$STATE_DIR/run-A.json" ]
    [ -f "$STATE_DIR/run-B.json" ]
}

@test "run isolation: writing run-B leaves run-A byte-identical" {
    bash "$STATE_SH" state-init --run-id run-iso-A --my-login octocat --targets "1"
    bash "$STATE_SH" state-write-pr --run-id run-iso-A --pr 1 \
        --record '{"fix_attempts": 2}'
    local before
    before="$(cat "$STATE_DIR/run-iso-A.json")"

    bash "$STATE_SH" state-init --run-id run-iso-B --my-login octocat --targets "1"
    bash "$STATE_SH" state-write-pr --run-id run-iso-B --pr 1 \
        --record '{"fix_attempts": 99}'

    local after
    after="$(cat "$STATE_DIR/run-iso-A.json")"
    [ "$before" = "$after" ] || {
        echo "run-iso-A.json changed after writing run-iso-B:"
        diff <(echo "$before") <(echo "$after")
        return 1
    }
}

# ---------------------------------------------------------------------------
# Resume-matching: re-launch picks the right recent file, counters intact
# ---------------------------------------------------------------------------
@test "state-load resumes the most recent run whose targets match" {
    # An older run on the same targets, then a newer one.
    bash "$STATE_SH" state-init --run-id run-old --my-login octocat --targets "482 491"
    bash "$STATE_SH" state-write-pr --run-id run-old --pr 482 \
        --record '{"fix_attempts": 1}'

    # Make the newer file unambiguously newer (mtime ordering).
    touch -t 202607021200 "$STATE_DIR/run-old.json"
    bash "$STATE_SH" state-init --run-id run-new --my-login octocat --targets "482 491"
    bash "$STATE_SH" state-write-pr --run-id run-new --pr 482 \
        --record '{"fix_attempts": 2}'
    touch -t 202607021300 "$STATE_DIR/run-new.json"

    # Resume on the same targets → should select the newer matching run.
    run bash "$STATE_SH" state-load --targets "482 491"
    [ "$status" -eq 0 ]
    # state-load prints the resolved run_id it matched.
    [ "$output" = "run-new" ] || {
        echo "expected state-load to resume run-new, got: $output"
        return 1
    }
}

@test "state-load preserves per-PR counters across resume" {
    bash "$STATE_SH" state-init --run-id run-resume --my-login octocat --targets "482"
    bash "$STATE_SH" state-write-pr --run-id run-resume --pr 482 \
        --record '{"fix_attempts": 2, "ci_failures": {"lint": 2}, "status": "watching"}'

    # Resume matches this run; counters must be readable and intact afterwards.
    run bash "$STATE_SH" state-load --targets "482"
    [ "$status" -eq 0 ]
    [ "$output" = "run-resume" ]

    run bash "$STATE_SH" state-read-pr --run-id run-resume --pr 482
    echo "$output" | jq -e '.fix_attempts == 2'
    echo "$output" | jq -e '.ci_failures.lint == 2'
}

@test "state-load returns non-zero when no run matches the targets" {
    bash "$STATE_SH" state-init --run-id run-other --my-login octocat --targets "111 222"
    run bash "$STATE_SH" state-load --targets "999"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Atomic write: write-temp-then-rename, no leftover temp files
# ---------------------------------------------------------------------------
@test "atomic write leaves no leftover temp files in the state dir" {
    bash "$STATE_SH" state-init --run-id run-atomic --my-login octocat --targets "1"
    bash "$STATE_SH" state-write-pr --run-id run-atomic --pr 1 \
        --record '{"fix_attempts": 1}'
    bash "$STATE_SH" state-write-pr --run-id run-atomic --pr 1 \
        --record '{"fix_attempts": 2}'

    # After a normal write, only run-atomic.json + latest.json should remain —
    # no *.tmp / *.swp / partial artifacts.
    local strays
    strays="$(find "$STATE_DIR" -maxdepth 1 -type f ! -name 'run-*.json' 2>/dev/null)"
    [ -z "$strays" ] || {
        echo "unexpected stray files in state dir:"
        echo "$strays"
        return 1
    }
}

@test "state file remains valid JSON after every write (no partial writes visible)" {
    bash "$STATE_SH" state-init --run-id run-valid --my-login octocat --targets "1"
    for i in 1 2 3; do
        bash "$STATE_SH" state-write-pr --run-id run-valid --pr 1 \
            --record "{\"fix_attempts\": $i}"
        # After each write the on-disk file must parse.
        run jq -e '.' "$STATE_DIR/run-valid.json"
        [ "$status" -eq 0 ] || {
            echo "state file invalid after write $i"
            return 1
        }
    done
    run bash "$STATE_SH" state-read-pr --run-id run-valid --pr 1
    echo "$output" | jq -e '.fix_attempts == 3'
}

# ---------------------------------------------------------------------------
# Schema fixture: the shipped schema doc is itself valid JSON and round-trips
# ---------------------------------------------------------------------------
@test "data/state-schema.json is valid JSON usable as a round-trip fixture" {
    [ -f "$SCHEMA_JSON" ] || {
        echo "expected schema doc at $SCHEMA_JSON"
        return 1
    }
    run jq -e '.' "$SCHEMA_JSON"
    [ "$status" -eq 0 ]

    # The schema documents the run-level and per-PR shapes.
    run jq -e 'has("run_id") and has("started") and has("flags") and has("my_login") and has("slack") and has("prs")' "$SCHEMA_JSON"
    [ "$status" -eq 0 ]

    # The per-PR example carries every field from the PRD state model.
    run jq -e '
        .prs
        | to_entries[0].value
        | has("head_sha") and has("authored_by_me") and has("explicitly_named")
          and has("ci_failures") and has("fix_attempts") and has("blocker_fingerprints")
          and has("last_review") and has("approved") and has("status")
    ' "$SCHEMA_JSON"
    [ "$status" -eq 0 ]

    # last_review carries its four sub-fields.
    run jq -e '
        .prs | to_entries[0].value.last_review
        | has("sha") and has("ci") and has("reviewDecision") and has("blockers")
    ' "$SCHEMA_JSON"
    [ "$status" -eq 0 ]
}

@test "a per-PR record loaded from the schema fixture round-trips through write/read" {
    bash "$STATE_SH" state-init --run-id run-fixture --my-login octocat --targets "1"
    local record
    record="$(jq -c '.prs | to_entries[0].value' "$SCHEMA_JSON")"
    [ -n "$record" ]

    run bash "$STATE_SH" state-write-pr --run-id run-fixture --pr 1 --record "$record"
    [ "$status" -eq 0 ]

    run bash "$STATE_SH" state-read-pr --run-id run-fixture --pr 1
    [ "$status" -eq 0 ]
    # Field-for-field equality with the fixture record.
    diff <(echo "$record" | jq -S '.') <(echo "$output" | jq -S '.') || {
        echo "round-tripped record differs from schema fixture"
        return 1
    }
}

# ---------------------------------------------------------------------------
# state-set-run robustness: a malformed --set must NOT corrupt the state file.
# Regression for the atomic-write invariant (header lines 64-67): a jq compile
# error on a bad --set key produced empty stdout, and _atomic_write's
# unconditional `cat >tmp; mv` then clobbered valid state with a 0-byte file.
# The fix must (a) exit non-zero and (b) leave the prior file BYTE-IDENTICAL.
# ---------------------------------------------------------------------------
@test "state-set-run with a malformed --set key exits non-zero and leaves state byte-identical" {
    bash "$STATE_SH" state-init --run-id run-badset --my-login octocat --targets "1"
    bash "$STATE_SH" state-write-pr --run-id run-badset --pr 1 \
        --record '{"status":"approved","fix_attempts":2,"approved":true}'

    local file="$STATE_DIR/run-badset.json"
    local before_sum
    before_sum="$(cksum "$file")"

    # A key containing a jq metacharacter makes the jq program fail to compile.
    run bash "$STATE_SH" state-set-run --run-id run-badset --set 'bad(key=1'
    [ "$status" -ne 0 ]

    # The file must still be valid JSON with the counters intact...
    run jq -e '.prs["1"].fix_attempts == 2 and .prs["1"].approved == true' "$file"
    [ "$status" -eq 0 ]

    # ...and byte-for-byte unchanged (the atomic-write invariant).
    [ "$(cksum "$file")" = "$before_sum" ]
}

@test "state-set-run rejects a non-dotpath key before touching the file" {
    bash "$STATE_SH" state-init --run-id run-badkey --my-login octocat --targets "1"
    local file="$STATE_DIR/run-badkey.json"
    local before_sum
    before_sum="$(cksum "$file")"

    run bash "$STATE_SH" state-set-run --run-id run-badkey --set 'a|b=1'
    [ "$status" -ne 0 ]
    [ "$(cksum "$file")" = "$before_sum" ]
}

@test "state-set-run still applies a well-formed dotted-path --set (no regression)" {
    bash "$STATE_SH" state-init --run-id run-goodset --my-login octocat --targets "1"

    run bash "$STATE_SH" state-set-run --run-id run-goodset \
        --set slack.channel_id=C123 --set slack.enabled=true
    [ "$status" -eq 0 ]

    run jq -e '.slack.channel_id == "C123" and .slack.enabled == true' \
        "$STATE_DIR/run-goodset.json"
    [ "$status" -eq 0 ]
}
