#!/usr/bin/env bats
# RED-phase unit tests for the /babysit-prs deterministic decision core:
#   .claude/skills/babysit-prs/scripts/babysit-gate.sh
#
# Written BEFORE the implementation exists — every test here MUST fail until
# Step 3 (GREEN) implements babysit-gate.sh. The script is intentionally absent
# in this commit; each test builds an absolute path to it from DOTFILES_DIR and
# runs it, so the failures are "no such file / status 127", which is the RED
# proof this phase requires.
#
# CLI CONTRACT these tests pin (implementer honors this in Step 3):
#   babysit-gate.sh <subcommand> [flags]
#   Every subcommand is a PURE function: JSON/args in, a decision token + reason
#   on stdout, exit 0, NO side effects (no gh/Slack/git — the SKILL.md Actor
#   prose owns all I/O). jq is available.
#
#   decide       --action <comment|approve|fix|merge> --pr <facts> --flags <flags>
#                 -> "ALLOW" | "HOLD:<reason>"
#   merge-gate   --pr <facts>            -> "ALLOW" | "HOLD:<condition>"  (6-condition)
#   blast-radius --pr <facts> --flags <flags>
#                 -> "high:<reason>" | "low"   (authorship is ONE OR-clause)
#   flake-tick   --check <name> --conclusion <SUCCESS|FAILURE|PENDING|NEUTRAL> \
#                --prior <state-json> [--new-sha]
#                 -> updated count for that check (e.g. "0" / "1" / "2"), and
#                    on new SHA prints "0" for the queried check (all reset)
#   fingerprint  --file <path> --category <cat> --claim <text> [--line <n>]
#                 -> a stable normalized token (line-number-independent;
#                    --line is accepted but DELIBERATELY IGNORED)
#   converged?   --prior <fingerprints-json> --surviving <fingerprints-json>
#                 -> "CONVERGED" | "STOP:non-convergence"
#   settle?      --pr <facts> --flags <flags>
#                 -> "SETTLE" | "WATCHING"
#   rearm?       --last <last_review-json> --pr <facts>
#                 -> "REARM:<signal>" | "STAY-SETTLED"
#   auto-approve? --pr <facts> --flags <flags> --approved-sha <sha> --head-sha <sha>
#                 -> "APPROVE" | "SKIP:<reason>"
#   defer?       --pr <facts>
#                 -> "HOLD:human-engaged:<why>" | "PROCEED"
#   stop?        --flags <flags> --now <epoch> --until <epoch|empty> \
#                --all-terminal <true|false>
#                 -> "STOP:<reason>" | "CONTINUE"
#
# Run with: bats tests/babysit-gate.bats

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
    export GATE="$DOTFILES_DIR/.claude/skills/babysit-prs/scripts/babysit-gate.sh"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Fixture builders — small JSON snapshots. A "clean" PR is green CI, zero
# blockers valid for head, no human changes-requested, MERGEABLE, not draft,
# OPEN. Small (below thresholds). Override fields with jq for each scenario.
# ---------------------------------------------------------------------------

# A clean, small, OWN PR.
_pr_clean_own() {
    cat <<'JSON'
{
  "authored_by_me": true,
  "explicitly_named": false,
  "additions": 40,
  "deletions": 10,
  "changedFiles": 3,
  "ci": "SUCCESS",
  "blockers": 0,
  "review_valid_for_head": true,
  "human_changes_requested": false,
  "mergeable": "MERGEABLE",
  "draft": false,
  "state": "OPEN"
}
JSON
}

# A clean, small, FOREIGN PR (not mine, not explicitly named — discovered).
_pr_clean_foreign() {
    _pr_clean_own | jq '.authored_by_me = false | .explicitly_named = false'
}

# All capabilities on; default thresholds (size 400, files 20); hold_above on.
_flags_all() {
    cat <<'JSON'
{
  "review_only": false,
  "fix": true,
  "approve": true,
  "merge": true,
  "size_threshold": 400,
  "files_threshold": 20,
  "hold_above": true
}
JSON
}

# Default (safe) flags: review-only, everything else off.
_flags_review_only() {
    cat <<'JSON'
{
  "review_only": true,
  "fix": false,
  "approve": false,
  "merge": false,
  "size_threshold": 400,
  "files_threshold": 20,
  "hold_above": true
}
JSON
}

# Run the gate with --action / --pr / --flags. Args: action, pr-json, flags-json.
_decide() {
    run "$GATE" decide --action "$1" --pr "$2" --flags "$3"
}

# ===========================================================================
# 0. HEADLINE PRECEDENCE-FLIP TESTS (mandatory)
#    Merge eligibility WAS "authored_by_me OR explicitly_named".
#    It is NOW "six-condition gate AND blast-radius != high", with authorship
#    folded into blast-radius. Prove (a) a foreign CLEAN PR is HELD for merge
#    via the blast-radius clause, with the reason attributing to blast-radius,
#    and (b) the OLD standalone-authorship merge path is GONE.
# ===========================================================================

@test "HEADLINE flip (a)+(b): foreign CLEAN PR merge HOLD reason is EXACTLY blast-radius-foreign-author" {
    # Rewritten from a `grep -qi 'blast'` positive check plus a separate 5-spelling
    # negative blocklist. Both were weak: `grep blast` would pass even if the
    # reason were e.g. "HOLD:blast-radius-size" (wrong sub-reason for THIS PR),
    # and a negative blocklist only rules out the specific old spellings it
    # enumerates. An EXACT match on the full token pins the mechanism precisely:
    # authorship reaches the merge decision ONLY as the blast-radius sub-reason
    # "foreign-author", under ANY spelling of a standalone authorship veto —
    # because an exact match leaves no room for one to sneak in alongside it.
    _decide merge "$(_pr_clean_foreign)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "HOLD:blast-radius-foreign-author" ]
}

@test "HEADLINE flip (c): a foreign CLEAN PR still gets APPROVE (approving others' PRs is the point)" {
    # The flip must NOT lock foreign PRs out of approve — only merge. Approve is
    # held only by the SIZE signal, never by foreign-authorship.
    _decide approve "$(_pr_clean_foreign)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

# ===========================================================================
# 0b. FAIL-OPEN REGRESSION TESTS (CRITICAL — unattended merge gate)
#    set -euo pipefail turns `[ "$x" -gt N ]` on a non-numeric/empty $x into a
#    silently-false condition (status 2, but `if` swallows it under set -e), so
#    the veto is SKIPPED and the gate falls through to ALLOW. Every one of these
#    MUST hold closed: unparseable/absent safety-relevant input holds, it never
#    allows an unattended merge.
# ===========================================================================

@test "FAIL-OPEN merge: blockers=\"\" (empty/unparseable) on an otherwise-clean own PR => HOLD (not ALLOW)" {
    local pr
    pr="$(_pr_clean_own | jq '.blockers = ""')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'block' || {
        echo "Expected the HOLD reason to name the blockers condition; got: $output"
        return 1
    }
}

@test "FAIL-OPEN merge: blockers=\"abc\" (non-numeric) on an otherwise-clean own PR => HOLD (not ALLOW)" {
    local pr
    pr="$(_pr_clean_own | jq '.blockers = "abc"')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'block' || {
        echo "Expected the HOLD reason to name the blockers condition; got: $output"
        return 1
    }
}

@test "FAIL-OPEN merge: size_threshold=\"abc\" (unparseable) in --flags on a small own PR => HOLD" {
    local flags
    flags="$(_flags_all | jq '.size_threshold = "abc"')"
    _decide merge "$(_pr_clean_own)" "$flags"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "FAIL-OPEN blast-radius: size_threshold=\"abc\" directly => high (unparseable fails closed, not silently low)" {
    local flags
    flags="$(_flags_all | jq '.size_threshold = "abc"')"
    run "$GATE" blast-radius --pr "$(_pr_clean_own)" --flags "$flags"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
}

@test "FAIL-OPEN merge: size fields (additions/deletions/changedFiles) ABSENT from --pr on a genuinely large PR => HOLD" {
    # A large PR whose size fields were never populated by the Actor must not
    # default to 0/low — absent size data fails closed to high-blast, not ALLOW.
    local pr
    pr="$(_pr_clean_own | jq 'del(.additions) | del(.deletions) | del(.changedFiles)')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'blast\|size\|unparseable' || {
        echo "Expected HOLD to cite the unparseable/blast-radius signal; got: $output"
        return 1
    }
}

@test "FAIL-OPEN blast-radius: size fields ABSENT => high (never silently 0/low)" {
    local pr
    pr="$(_pr_clean_own | jq 'del(.additions) | del(.deletions) | del(.changedFiles)')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
}

@test "FAIL-OPEN merge: additions/deletions non-numeric => HOLD (not a tick crash, not ALLOW)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = "NaN" | .deletions = "oops"')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "FAIL-OPEN blast-radius: additions non-numeric => high (arithmetic guarded before use, fails closed)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = "NaN"')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
}

@test "FAIL-OPEN merge: review_valid_for_head ABSENT from --pr => HOLD (absent must not default to true)" {
    local pr
    pr="$(_pr_clean_own | jq 'del(.review_valid_for_head)')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'stale\|review' || {
        echo "Expected HOLD to cite the stale-review/blockers condition; got: $output"
        return 1
    }
}

@test "FAIL-OPEN merge-gate: review_valid_for_head ABSENT => HOLD naming stale review (direct six-condition check)" {
    local pr
    pr="$(_pr_clean_own | jq 'del(.review_valid_for_head)')"
    run "$GATE" merge-gate --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'stale\|review' || {
        echo "Expected HOLD to cite the stale-review condition; got: $output"
        return 1
    }
}

# ===========================================================================
# 0c. FAIL-OPEN OCTAL-LEADING-ZERO REGRESSION TESTS (CRITICAL)
#    `$(( additions + deletions ))` is bash ARITHMETIC EXPANSION, which parses
#    a leading-zero digit string as OCTAL, not decimal. The digit-only
#    validation loop above accepts "0450" (it IS all digits) but the
#    arithmetic then reads it as octal 0450 = 296 decimal, UNDER the 400
#    threshold, when the true decimal value 450 is over it -> a large PR
#    fails open as "low"/ALLOW. Worse, "0800" is not a valid octal literal at
#    all and CRASHES the arithmetic (bash: value too great for base), which
#    breaks the gate's own contract that every subcommand exits 0 with a
#    token, never a bare crash.
# ===========================================================================

@test "FAIL-OPEN blast-radius: additions=\"0450\" (leading-zero digit string) => high:size (not octal-misparsed as low)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = "0450" | .deletions = "0"')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "high:size" ]
}

@test "FAIL-OPEN blast-radius: additions=\"0800\" (invalid octal literal) => high:size, exit 0 (must not crash)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = "0800" | .deletions = "0"')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "high:size" ]
}

@test "FAIL-OPEN blast-radius: additions=\"450\" (no leading zero) still => high:size (happy-path regression guard)" {
    # Pins that the base-10 fix does not change behavior on the normal
    # (non-leading-zero) path — same true value, decimal-literal spelling.
    local pr
    pr="$(_pr_clean_own | jq '.additions = "450" | .deletions = "0"')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "high:size" ]
}

@test "FAIL-OPEN merge: additions=\"0450\" on an otherwise-clean OWN PR => HOLD:blast-radius-size (not ALLOW)" {
    # End-to-end proof: the octal fail-open must not let a large PR merge
    # unattended just because its digit string happens to have a leading zero.
    local pr
    pr="$(_pr_clean_own | jq '.additions = "0450" | .deletions = "0"')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "HOLD:blast-radius-size" ]
}

@test "FAIL-OPEN approve: additions=\"0450\" on an otherwise-clean PR => HOLD (blast-radius size), not ALLOW" {
    # approve is gated by _blast_high_by_size, which reuses the same
    # _blast_radius computation — the octal fail-open must not slip an
    # oversized PR past approve either.
    local pr
    pr="$(_pr_clean_own | jq '.additions = "0450" | .deletions = "0"')"
    _decide approve "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'blast\|size' || {
        echo "Expected approve HOLD to cite the size/blast-radius signal; got: $output"
        return 1
    }
}

@test "FAIL-OPEN flake-tick: prior_count=\"010\" (leading-zero digit string) increments via base-10, not octal" {
    # Second, lower-risk instance of the same footgun: prior_count is
    # digit-validated above but `$(( prior_count + 1 ))` would still
    # octal-misparse a leading-zero value without the base-10 fix. Octal 010
    # = 8 decimal; a naive +1 would print "9" instead of the true decimal
    # successor "11".
    run "$GATE" flake-tick --check build --conclusion FAILURE --prior '{"build":"010"}'
    [ "$status" -eq 0 ]
    [ "$output" = "11" ]
}

# ===========================================================================
# 1. REVERSIBILITY × BLAST-RADIUS GATE TRUTH TABLE
#    action tier (comment/approve/fix/merge) × below/above size threshold
#    × foreign/own × six-condition vetoes.
# ===========================================================================

# --- comment tier: ALLOW whenever the flag is set; blast-radius never gates it.
@test "comment: ALLOW on own clean PR when review capability present" {
    _decide comment "$(_pr_clean_own)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "comment: ALLOW on FOREIGN PR (reversible; blast-radius does not gate comment)" {
    _decide comment "$(_pr_clean_foreign)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "comment: ALLOW even on a huge PR (size does not gate a reversible comment)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = 5000 | .changedFiles = 80')"
    _decide comment "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

# --- fix tier: ALLOW whenever the fix flag is set (reversible working-copy
#     mutation). The flake/attempt/convergence guards are applied by the Actor
#     BEFORE calling the gate, so the gate's fix decision is flag-only.
@test "fix: ALLOW on own PR when --fix flag set" {
    _decide fix "$(_pr_clean_own)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "fix: ALLOW on FOREIGN PR when --fix flag set (reversible mutation of PR's own copy)" {
    _decide fix "$(_pr_clean_foreign)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "fix: ALLOW even above size threshold (fix is reversible; size does not gate it)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = 5000 | .changedFiles = 80')"
    _decide fix "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "fix: HOLD when the --fix capability flag is NOT set" {
    local flags
    flags="$(_flags_all | jq '.fix = false')"
    _decide fix "$(_pr_clean_own)" "$flags"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

# --- approve tier: ALLOW iff clean AND blast-radius not high FOR THE SIZE
#     REASON. Foreign-authorship alone must NOT block approve.
@test "approve: ALLOW own clean small PR" {
    _decide approve "$(_pr_clean_own)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "approve: HOLD when above SIZE threshold even if clean (size valve)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = 401')"
    _decide approve "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'blast\|size' || {
        echo "Expected approve HOLD to cite the size/blast-radius signal; got: $output"
        return 1
    }
}

@test "approve: HOLD when above FILES threshold even if clean" {
    local pr
    pr="$(_pr_clean_own | jq '.changedFiles = 21')"
    _decide approve "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "approve: foreign-authorship ALONE does NOT hold approve (size ok)" {
    _decide approve "$(_pr_clean_foreign)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "approve: HOLD when NOT clean (has blockers) regardless of size" {
    local pr
    pr="$(_pr_clean_own | jq '.blockers = 2')"
    _decide approve "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "approve: HOLD when the --approve capability flag is NOT set" {
    local flags
    flags="$(_flags_all | jq '.approve = false')"
    _decide approve "$(_pr_clean_own)" "$flags"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

# --- merge tier: ALLOW iff six-condition gate holds AND blast-radius != high.
@test "merge: ALLOW own clean small PR (all six conditions + low blast-radius)" {
    _decide merge "$(_pr_clean_own)" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "merge: HOLD own clean PR above size threshold (size valve wants explicit OK)" {
    # Tightened from `grep -qi 'blast\|size'`, which a `HOLD:blast-radius-foreign-author`
    # (wrong sub-reason, from an unrelated mutation) would ALSO satisfy — the
    # regex can't tell "size" from "foreign-author" apart since both start with
    # "blast". An exact match on the full token pins THIS PR's hold to the size
    # sub-reason specifically, on an otherwise-OWN PR (own => authorship OR-clause
    # is satisfied, so only the size OR-clause can be firing here).
    local pr
    pr="$(_pr_clean_own | jq '.additions = 350 | .deletions = 100')"  # 450 > 400
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "HOLD:blast-radius-size" ]
}

@test "merge: explicitly-named foreign PR still HELD if above size threshold" {
    local pr
    pr="$(_pr_clean_foreign | jq '.explicitly_named = true | .additions = 5000')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "merge: explicitly-named small clean PR ALLOWS (named demotes authorship blast-radius input)" {
    local pr
    pr="$(_pr_clean_foreign | jq '.explicitly_named = true')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "merge: HOLD when the --merge capability flag is NOT set" {
    local flags
    flags="$(_flags_all | jq '.merge = false')"
    _decide merge "$(_pr_clean_own)" "$flags"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

# --- merge tier crossed with each six-condition veto (own small PR base).
@test "merge: HOLD when CI is red" {
    local pr
    pr="$(_pr_clean_own | jq '.ci = "FAILURE"')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'ci' || { echo "Expected CI condition cited; got: $output"; return 1; }
}

@test "merge: HOLD when there are blockers valid for head" {
    local pr
    pr="$(_pr_clean_own | jq '.blockers = 1')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "merge: HOLD when human CHANGES_REQUESTED (never overridden)" {
    local pr
    pr="$(_pr_clean_own | jq '.human_changes_requested = true')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'change' || { echo "Expected changes-requested cited; got: $output"; return 1; }
}

@test "merge: HOLD when not MERGEABLE (conflict)" {
    local pr
    pr="$(_pr_clean_own | jq '.mergeable = "CONFLICTING"')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "merge: HOLD when draft" {
    local pr
    pr="$(_pr_clean_own | jq '.draft = true')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'draft' || { echo "Expected draft cited; got: $output"; return 1; }
}

@test "merge: HOLD when review is stale for head SHA" {
    local pr
    pr="$(_pr_clean_own | jq '.review_valid_for_head = false')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "merge: HOLD when PR is closed/merged (terminal)" {
    local pr
    pr="$(_pr_clean_own | jq '.state = "CLOSED"')"
    _decide merge "$pr" "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

# ===========================================================================
# 2. FLAKE GUARD COUNTER-RESET MATRIX
#    flake-tick --check <name> --conclusion <c> --prior <state> [--new-sha]
#    Prior state = {"<check>": <count>} map. Arms (reaches 2) only on two
#    consecutive same-name FAILUREs. Resets on green/pending; new SHA resets
#    ALL. Name-matched (NOT run-ID matched).
# ===========================================================================

@test "flake-tick: first FAILURE arms count to 1" {
    run "$GATE" flake-tick --check build --conclusion FAILURE --prior '{}'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "flake-tick: fail->fail arms count to 2 (fixable threshold)" {
    run "$GATE" flake-tick --check build --conclusion FAILURE --prior '{"build":1}'
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "flake-tick: fail->green resets to 0" {
    run "$GATE" flake-tick --check build --conclusion SUCCESS --prior '{"build":1}'
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "flake-tick: fail->pending resets to 0 (was re-run)" {
    run "$GATE" flake-tick --check build --conclusion PENDING --prior '{"build":1}'
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "flake-tick: new SHA resets the queried check to 0 even after a FAILURE" {
    # New commit landed: all counters reset. The just-observed FAILURE does not
    # arm because the SHA changed this tick.
    run "$GATE" flake-tick --check build --conclusion FAILURE --prior '{"build":1,"lint":1}' --new-sha
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "flake-tick: NEUTRAL conclusion does not arm (treated as non-failure)" {
    run "$GATE" flake-tick --check build --conclusion NEUTRAL --prior '{"build":1}'
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "flake-tick: name-matching — a different check's count is independent" {
    # 'build' failing must not advance 'lint'. Querying lint after a build
    # failure leaves lint's own history untouched.
    run "$GATE" flake-tick --check lint --conclusion FAILURE --prior '{"build":1,"lint":0}'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "flake-tick: two DIFFERENT check names each fail once => neither arms (proves per-name keying, not a shared counter)" {
    # DELETED the old "name match holds across changing run IDs" test: the CLI
    # has no --run-id, so it could not represent a run-ID at all — it was
    # byte-identical to "fail->fail arms count to 2" and would pass unchanged
    # even if the implementation secretly keyed on something other than name
    # (e.g. a single global counter). This test actually distinguishes that:
    # two DIFFERENT check names, each failing once against a shared prior map,
    # must land at count 1 EACH (not one incrementing the other, and not a
    # shared/global tally reaching 2). That is only true if the counter is
    # genuinely keyed per check-name.
    local prior='{"build":0,"lint":0}'

    run "$GATE" flake-tick --check build --conclusion FAILURE --prior "$prior"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    run "$GATE" flake-tick --check lint --conclusion FAILURE --prior "$prior"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ===========================================================================
# 3. FINGERPRINT MATCHER / CONVERGENCE
#    fingerprint --file --category --claim  -> stable token (NOT line number)
#    converged? --prior <fps> --surviving <fps> -> CONVERGED | STOP:non-convergence
# ===========================================================================

@test "fingerprint: same file+category+claim on a DIFFERENT line => SAME token" {
    # Rewritten: the old version issued two byte-identical calls (no --line was
    # even passable), so it proved nothing about line-independence — it would
    # pass even if line WERE folded into the token. --line is now accepted (and
    # deliberately ignored) by the implementation specifically so this can be
    # tested for real: same file+category+claim at two DIFFERENT line numbers
    # must still produce the SAME fingerprint.
    run "$GATE" fingerprint --file "src/app.ts" --category "null-deref" --claim "user may be null before use" --line 12
    [ "$status" -eq 0 ]
    local a="$output"
    run "$GATE" fingerprint --file "src/app.ts" --category "null-deref" --claim "user may be null before use" --line 87
    [ "$status" -eq 0 ]
    [ "$output" = "$a" ]
}

@test "fingerprint: genuinely different claim => DIFFERENT token" {
    run "$GATE" fingerprint --file "src/app.ts" --category "null-deref" --claim "user may be null before use"
    local a="$output"
    run "$GATE" fingerprint --file "src/app.ts" --category "type-error" --claim "return type mismatch on line"
    [ "$status" -eq 0 ]
    [ "$output" != "$a" ]
}

@test "fingerprint: fuzzy claim match — trivial wording drift => SAME token" {
    # The claim is normalized (lowercased, whitespace/punct collapsed) so trivial
    # rewording of the same core claim collapses to the same fingerprint.
    run "$GATE" fingerprint --file "src/app.ts" --category "null-deref" --claim "User may be null before use."
    local a="$output"
    run "$GATE" fingerprint --file "src/app.ts" --category "null-deref" --claim "user   may be  null before use"
    [ "$status" -eq 0 ]
    [ "$output" = "$a" ]
}

@test "converged?: >=1 surviving fingerprint => STOP (non-convergence early stop)" {
    # A blocker present before the fix is STILL present after => it survived a
    # dispatch => stop immediately.
    run "$GATE" converged? --prior '["fp-abc","fp-def"]' --surviving '["fp-abc"]'
    [ "$status" -eq 0 ]
    [[ "$output" == STOP:* ]]
}

@test "converged?: zero surviving fingerprints => CONVERGED" {
    run "$GATE" converged? --prior '["fp-abc"]' --surviving '[]'
    [ "$status" -eq 0 ]
    [ "$output" = "CONVERGED" ]
}

@test "converged?: a brand-new blocker (not in prior) does NOT trip the stop" {
    # Rewritten: the old fixture used --surviving '[]', i.e. NO blocker survived
    # at all — it didn't actually include a "brand-new" blocker, so it never
    # exercised the prior-set INTERSECTION logic (it's identical in shape to the
    # "zero surviving fingerprints => CONVERGED" test above). The faithful case:
    # the OLD blocker is gone, but a genuinely NEW, never-before-seen fingerprint
    # is present in --surviving. Since "fp-brand-new" was never in --prior, it
    # is not a SURVIVOR of the prior set — this is progress, not non-convergence.
    run "$GATE" converged? --prior '["fp-old"]' --surviving '["fp-brand-new"]'
    [ "$status" -eq 0 ]
    [ "$output" = "CONVERGED" ]
}

@test "converged?: the SAME prior fingerprint surviving => STOP (distinct from the brand-new-blocker case above)" {
    # Contrast case proving the intersection actually matters: when the
    # surviving fingerprint IS a member of the prior set, that is non-convergence
    # and must STOP — unlike the brand-new-fingerprint case immediately above,
    # which CONVERGEs. The only difference between the two tests is whether the
    # surviving fingerprint matches an entry in --prior.
    run "$GATE" converged? --prior '["fp-old"]' --surviving '["fp-old"]'
    [ "$status" -eq 0 ]
    [[ "$output" == STOP:* ]]
}

# ===========================================================================
# 4. SIX-CONDITION MERGE GATE TRUTH TABLE (the strict end, reused verbatim)
#    merge-gate --pr <facts>  -> ALLOW | HOLD:<condition>
#    (1) authorship/explicit folded into blast-radius, (2) CI green,
#    (3) zero blockers valid for head, (4) no human CHANGES_REQUESTED,
#    (5) MERGEABLE, (6) not draft / not closed. Report WHICH condition blocked.
# ===========================================================================

@test "merge-gate: ALLOW on a fully clean own PR" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own)"
    [ "$status" -eq 0 ]
    [ "$output" = "ALLOW" ]
}

@test "merge-gate: single veto — CI red => HOLD naming the CI condition" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.ci = "FAILURE"')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'ci' || { echo "Expected CI condition; got: $output"; return 1; }
}

@test "merge-gate: single veto — blockers => HOLD naming blockers" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.blockers = 3')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'block' || { echo "Expected blockers condition; got: $output"; return 1; }
}

@test "merge-gate: single veto — human CHANGES_REQUESTED => HOLD naming it" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.human_changes_requested = true')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'change' || { echo "Expected changes-requested; got: $output"; return 1; }
}

@test "merge-gate: single veto — conflict (not MERGEABLE) => HOLD naming conflict" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.mergeable = "CONFLICTING"')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'conflict\|mergeable' || { echo "Expected conflict/mergeable; got: $output"; return 1; }
}

@test "merge-gate: single veto — mergeable=UNKNOWN => HOLD (breadth check: the condition is != MERGEABLE, not == CONFLICTING)" {
    # Added to widen coverage beyond the single CONFLICTING value: the real
    # condition is "must equal MERGEABLE", so ANY other value (UNKNOWN, unset,
    # etc.) must veto. A mutation from `!= "MERGEABLE"` to `== "CONFLICTING"`
    # would still pass the CONFLICTING-only test above but must be caught here,
    # since UNKNOWN would then wrongly fall through to ALLOW.
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.mergeable = "UNKNOWN"')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'conflict\|mergeable' || { echo "Expected conflict/mergeable; got: $output"; return 1; }
}

@test "merge-gate: single veto — draft => HOLD naming draft" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.draft = true')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'draft' || { echo "Expected draft; got: $output"; return 1; }
}

@test "merge-gate: single veto — stale-SHA review => HOLD naming stale review" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.review_valid_for_head = false')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'stale\|review\|sha' || { echo "Expected stale-review; got: $output"; return 1; }
}

@test "merge-gate: single veto — closed/merged state => HOLD" {
    run "$GATE" merge-gate --pr "$(_pr_clean_own | jq '.state = "MERGED"')"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "merge-gate: human CHANGES_REQUESTED is never overridden even with green CI" {
    # Everything else perfect, but a human objected. Must still HOLD.
    local pr
    pr="$(_pr_clean_own | jq '.human_changes_requested = true | .ci = "SUCCESS" | .blockers = 0')"
    run "$GATE" merge-gate --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'change' || { echo "Expected changes-requested to be the cited veto; got: $output"; return 1; }
}

# ===========================================================================
# 5. AUTHORSHIP AS ONE BLAST-RADIUS INPUT (Guardrail B — demoted, not deleted)
#    blast-radius --pr <facts> --flags <flags> -> "high:<reason>" | "low"
#    high iff (NOT authored AND NOT named) OR (adds+dels > SIZE) OR (files > FILES).
# ===========================================================================

@test "blast-radius: own small PR => low" {
    run "$GATE" blast-radius --pr "$(_pr_clean_own)" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "low" ]
}

@test "blast-radius: foreign + not-named small PR => high (authorship OR-clause)" {
    run "$GATE" blast-radius --pr "$(_pr_clean_foreign)" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
    echo "$output" | grep -qi 'author\|foreign' || {
        echo "Expected the authorship blast-radius reason; got: $output"; return 1; }
}

@test "blast-radius: foreign but EXPLICITLY NAMED small PR => low (named satisfies the authorship clause)" {
    local pr
    pr="$(_pr_clean_foreign | jq '.explicitly_named = true')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "low" ]
}

@test "blast-radius: own PR above SIZE threshold => high (size OR-clause, independent of authorship)" {
    local pr
    pr="$(_pr_clean_own | jq '.additions = 300 | .deletions = 200')"  # 500 > 400
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
    echo "$output" | grep -qi 'size\|line' || { echo "Expected the size reason; got: $output"; return 1; }
}

@test "blast-radius: own PR above FILES threshold => high (files OR-clause)" {
    local pr
    pr="$(_pr_clean_own | jq '.changedFiles = 25')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
    echo "$output" | grep -qi 'file' || { echo "Expected the files reason; got: $output"; return 1; }
}

@test "blast-radius: authorship is ONE input, not the whole gate — own+huge is still high" {
    # Proves authorship low-contribution can be overridden by a size signal:
    # own PR (authorship => low contribution) but huge => high overall.
    local pr
    pr="$(_pr_clean_own | jq '.additions = 5000')"
    run "$GATE" blast-radius --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
}

@test "blast-radius: custom thresholds via flags are honored (not hard-coded inline)" {
    # Lower the size threshold to 100 via flags; a 150-line own PR now trips high.
    local pr flags
    pr="$(_pr_clean_own | jq '.additions = 120 | .deletions = 30')"  # 150
    flags="$(_flags_all | jq '.size_threshold = 100')"
    run "$GATE" blast-radius --pr "$pr" --flags "$flags"
    [ "$status" -eq 0 ]
    [[ "$output" == high:* ]]
}

# ===========================================================================
# 6. SETTLED RE-ARM
#    settle? --pr --flags  -> SETTLE | WATCHING
#    rearm? --last <last_review> --pr <facts> -> REARM:<signal> | STAY-SETTLED
# ===========================================================================

@test "settle?: clean-but-can't-advance foreign PR (merge on) => SETTLE" {
    # Foreign clean PR: can't be merged (blast-radius high via authorship),
    # nothing left to do this tick => settle to cheap poll.
    run "$GATE" settle? --pr "$(_pr_clean_foreign)" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "SETTLE" ]
}

@test "settle?: own mergeable clean PR under --merge => WATCHING (it can still advance -> merge)" {
    run "$GATE" settle? --pr "$(_pr_clean_own)" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "WATCHING" ]
}

@test "settle?: merge-authorized PR blocked ONLY by human CHANGES_REQUESTED => SETTLE (park)" {
    local pr
    pr="$(_pr_clean_own | jq '.human_changes_requested = true')"
    run "$GATE" settle? --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "SETTLE" ]
}

@test "rearm?: no change signal => STAY-SETTLED (cheap poll no-op)" {
    local last pr
    last='{"sha":"aaa111","ci":"SUCCESS","reviewDecision":"APPROVED","draft":false}'
    pr="$(_pr_clean_own | jq '.head_sha = "aaa111" | .ci = "SUCCESS" | .reviewDecision = "APPROVED" | .draft = false')"
    run "$GATE" rearm? --last "$last" --pr "$pr"
    [ "$status" -eq 0 ]
    [ "$output" = "STAY-SETTLED" ]
}

@test "rearm?: new head SHA => REARM (SHA signal)" {
    local last pr
    last='{"sha":"aaa111","ci":"SUCCESS","reviewDecision":"APPROVED","draft":false}'
    pr="$(_pr_clean_own | jq '.head_sha = "bbb222" | .ci = "SUCCESS" | .reviewDecision = "APPROVED" | .draft = false')"
    run "$GATE" rearm? --last "$last" --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == REARM:* ]]
    echo "$output" | grep -qi 'sha' || { echo "Expected SHA signal; got: $output"; return 1; }
}

@test "rearm?: CI conclusion changed => REARM (CI signal)" {
    local last pr
    last='{"sha":"aaa111","ci":"SUCCESS","reviewDecision":"APPROVED","draft":false}'
    pr="$(_pr_clean_own | jq '.head_sha = "aaa111" | .ci = "FAILURE" | .reviewDecision = "APPROVED" | .draft = false')"
    run "$GATE" rearm? --last "$last" --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == REARM:* ]]
    echo "$output" | grep -qi 'ci' || { echo "Expected CI signal; got: $output"; return 1; }
}

@test "rearm?: review decision changed => REARM (reviewDecision signal)" {
    local last pr
    last='{"sha":"aaa111","ci":"SUCCESS","reviewDecision":"CHANGES_REQUESTED","draft":false}'
    pr="$(_pr_clean_own | jq '.head_sha = "aaa111" | .ci = "SUCCESS" | .reviewDecision = "APPROVED" | .draft = false')"
    run "$GATE" rearm? --last "$last" --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == REARM:* ]]
}

@test "rearm?: draft->ready => REARM (draft signal)" {
    local last pr
    last='{"sha":"aaa111","ci":"SUCCESS","reviewDecision":"APPROVED","draft":true}'
    pr="$(_pr_clean_own | jq '.head_sha = "aaa111" | .ci = "SUCCESS" | .reviewDecision = "APPROVED" | .draft = false')"
    run "$GATE" rearm? --last "$last" --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == REARM:* ]]
    echo "$output" | grep -qi 'draft\|ready' || { echo "Expected draft signal; got: $output"; return 1; }
}

@test "settle-then-merge: after a human clears CHANGES_REQUESTED, settle? flips to WATCHING (merge next tick)" {
    # The tick AFTER the human clears: human_changes_requested now false, PR
    # otherwise clean and own -> it can advance, so it must not stay settled.
    local pr
    pr="$(_pr_clean_own | jq '.human_changes_requested = false')"
    run "$GATE" settle? --pr "$pr" --flags "$(_flags_all)"
    [ "$status" -eq 0 ]
    [ "$output" = "WATCHING" ]
}

# ===========================================================================
# 7. AUTO-APPROVE GATE
#    auto-approve? --pr --flags --approved-sha <sha> --head-sha <sha>
#    Fires on merge-predicate MINUS authorship; once per head SHA;
#    re-arm on new SHA; no-op on own PR under --merge.
# ===========================================================================

@test "auto-approve?: fires on a clean FOREIGN PR (clean-minus-authorship)" {
    local pr
    pr="$(_pr_clean_foreign | jq '.head_sha = "sha-1"')"
    run "$GATE" auto-approve? --pr "$pr" --flags "$(_flags_all)" --approved-sha "" --head-sha "sha-1"
    [ "$status" -eq 0 ]
    [ "$output" = "APPROVE" ]
}

@test "auto-approve?: SKIP when already approved for this head SHA (once per SHA)" {
    local pr
    pr="$(_pr_clean_foreign | jq '.head_sha = "sha-1"')"
    run "$GATE" auto-approve? --pr "$pr" --flags "$(_flags_all)" --approved-sha "sha-1" --head-sha "sha-1"
    [ "$status" -eq 0 ]
    [[ "$output" == SKIP:* ]]
}

@test "auto-approve?: re-arms and fires again when the head SHA moves" {
    local pr
    pr="$(_pr_clean_foreign | jq '.head_sha = "sha-2"')"
    run "$GATE" auto-approve? --pr "$pr" --flags "$(_flags_all)" --approved-sha "sha-1" --head-sha "sha-2"
    [ "$status" -eq 0 ]
    [ "$output" = "APPROVE" ]
}

@test "auto-approve?: no-op (SKIP) on OWN PR under --merge (self-approval blocked by GitHub)" {
    local pr
    pr="$(_pr_clean_own | jq '.head_sha = "sha-1"')"
    run "$GATE" auto-approve? --pr "$pr" --flags "$(_flags_all)" --approved-sha "" --head-sha "sha-1"
    [ "$status" -eq 0 ]
    [[ "$output" == SKIP:* ]]
    echo "$output" | grep -qi 'own\|self\|author' || { echo "Expected own/self reason; got: $output"; return 1; }
}

@test "auto-approve?: SKIP when PR is not clean (has blockers)" {
    local pr
    pr="$(_pr_clean_foreign | jq '.head_sha = "sha-1" | .blockers = 1')"
    run "$GATE" auto-approve? --pr "$pr" --flags "$(_flags_all)" --approved-sha "" --head-sha "sha-1"
    [ "$status" -eq 0 ]
    [[ "$output" == SKIP:* ]]
}

@test "auto-approve?: SKIP when --approve flag is off" {
    local pr flags
    pr="$(_pr_clean_foreign | jq '.head_sha = "sha-1"')"
    flags="$(_flags_all | jq '.approve = false')"
    run "$GATE" auto-approve? --pr "$pr" --flags "$flags" --approved-sha "" --head-sha "sha-1"
    [ "$status" -eq 0 ]
    [[ "$output" == SKIP:* ]]
}

# ===========================================================================
# 8. HUMAN-DEFERENCE GATE
#    defer? --pr <facts>  -> HOLD:human-engaged:<why> | PROCEED
#    Holds on in-flight human review / human non-bot non-self reply / existing
#    human approval. Does NOT fire on the loop's own ack or a bot reply.
#    Distinct from CHANGES_REQUESTED (a permanent merge veto).
# ===========================================================================

@test "defer?: HOLD when a human review is in flight" {
    local pr
    pr="$(_pr_clean_own | jq '.human_review_in_flight = true')"
    run "$GATE" defer? --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
    echo "$output" | grep -qi 'human' || { echo "Expected human-engaged reason; got: $output"; return 1; }
}

@test "defer?: HOLD when a human (non-bot, non-self) replied on the thread" {
    local pr
    pr="$(_pr_clean_own | jq '.human_thread_reply = true')"
    run "$GATE" defer? --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "defer?: HOLD when a human approval already exists" {
    local pr
    pr="$(_pr_clean_own | jq '.human_approval_exists = true')"
    run "$GATE" defer? --pr "$pr"
    [ "$status" -eq 0 ]
    [[ "$output" == HOLD:* ]]
}

@test "defer?: PROCEED when the only thread activity is the loop's OWN ack" {
    local pr
    pr="$(_pr_clean_own | jq '.own_ack_present = true | .human_thread_reply = false')"
    run "$GATE" defer? --pr "$pr"
    [ "$status" -eq 0 ]
    [ "$output" = "PROCEED" ]
}

@test "defer?: PROCEED when the only thread reply is a BOT reply" {
    local pr
    pr="$(_pr_clean_own | jq '.bot_thread_reply = true | .human_thread_reply = false')"
    run "$GATE" defer? --pr "$pr"
    [ "$status" -eq 0 ]
    [ "$output" = "PROCEED" ]
}

@test "defer?: PROCEED on a plain PR with no human engagement" {
    run "$GATE" defer? --pr "$(_pr_clean_own)"
    [ "$status" -eq 0 ]
    [ "$output" = "PROCEED" ]
}

@test "defer?: is DISTINCT from CHANGES_REQUESTED — a human CHANGES_REQUESTED with no in-flight engagement PROCEEDs the deference check" {
    # CHANGES_REQUESTED hard-blocks MERGE (tested in merge-gate), but the
    # deference gate is about not racing an in-flight human. A submitted
    # changes-requested (with no in-flight review/reply/approval) does not
    # itself make defer? hold — the merge gate is what stops the merge.
    local pr
    pr="$(_pr_clean_own | jq '.human_changes_requested = true | .human_review_in_flight = false | .human_thread_reply = false | .human_approval_exists = false')"
    run "$GATE" defer? --pr "$pr"
    [ "$status" -eq 0 ]
    [ "$output" = "PROCEED" ]
}

# ===========================================================================
# 9. STOP CONDITIONS
#    stop? --flags --now <epoch> --until <epoch|empty> --all-terminal <bool>
#    --until uses the REAL wall-clock read at tick start (incl. late-tick past
#    boundary). --until-empty stops when all watched PRs terminal/settled.
# ===========================================================================

@test "stop?: --until in the future => CONTINUE" {
    run "$GATE" stop? --flags "$(_flags_all)" --now 1000 --until 2000 --all-terminal false
    [ "$status" -eq 0 ]
    [ "$output" = "CONTINUE" ]
}

@test "stop?: --until exactly reached => STOP" {
    run "$GATE" stop? --flags "$(_flags_all)" --now 2000 --until 2000 --all-terminal false
    [ "$status" -eq 0 ]
    [[ "$output" == STOP:* ]]
}

@test "stop?: late tick — real now already PAST the --until boundary => STOP (does not sail past)" {
    # A late/skipped tick fires with the real clock already beyond --until. The
    # gate reads the true 'now' (passed at tick start) and must stop, never
    # 'sail past' because the tick was late.
    run "$GATE" stop? --flags "$(_flags_all)" --now 5000 --until 2000 --all-terminal false
    [ "$status" -eq 0 ]
    [[ "$output" == STOP:* ]]
    echo "$output" | grep -qi 'until\|time' || { echo "Expected an --until/time stop reason; got: $output"; return 1; }
}

@test "stop?: --until-empty with all watched PRs terminal/settled => STOP" {
    local flags
    flags="$(_flags_all | jq '.until_empty = true')"
    run "$GATE" stop? --flags "$flags" --now 1000 --until empty --all-terminal true
    [ "$status" -eq 0 ]
    [[ "$output" == STOP:* ]]
    echo "$output" | grep -qi 'empty\|terminal\|done' || { echo "Expected an empty/terminal stop reason; got: $output"; return 1; }
}

@test "stop?: --until-empty with work still remaining => CONTINUE" {
    local flags
    flags="$(_flags_all | jq '.until_empty = true')"
    run "$GATE" stop? --flags "$flags" --now 1000 --until empty --all-terminal false
    [ "$status" -eq 0 ]
    [ "$output" = "CONTINUE" ]
}

@test "stop?: no stop condition set => CONTINUE (runs until session end)" {
    run "$GATE" stop? --flags "$(_flags_all)" --now 1000 --until "" --all-terminal true
    [ "$status" -eq 0 ]
    [ "$output" = "CONTINUE" ]
}
