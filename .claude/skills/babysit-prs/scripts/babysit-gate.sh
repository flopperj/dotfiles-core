#!/usr/bin/env bash
# babysit-gate.sh — the deterministic decision core for the /babysit-prs skill.
#
# Every subcommand is a PURE function: JSON/args in, a decision token + reason on
# stdout, exit 0, NO side effects. The script never touches gh / Slack / git —
# the SKILL.md Actor prose owns all I/O. This file only decides. jq is required.
#
# WHY the gate is shaped this way (the precedence flip — read before editing):
#   Merge eligibility USED to be "authored_by_me OR explicitly_named". It is NOW
#   "the strict six-condition merge gate holds AND blast-radius != high", with
#   authorship folded in as exactly ONE of three blast-radius OR-clauses. Because
#   "high" blast-radius includes foreign-authorship, a teammate's PR can never
#   merge unattended — but that conclusion is now DERIVED from the reversibility ×
#   blast-radius gate, not a bolted-on standalone authorship predicate. Approve is
#   held only by the SIZE blast-radius signal (never by foreign-authorship), since
#   approving others' PRs is the entire point.
#
# Subcommands (each pure; token + reason on stdout; exit 0):
#   decide        --action <comment|approve|fix|merge> --pr <facts> --flags <flags>
#                   -> "ALLOW" | "HOLD:<reason>"
#   merge-gate    --pr <facts>            -> "ALLOW" | "HOLD:<condition>"
#   blast-radius  --pr <facts> --flags <flags>
#                   -> "high:<reason>" | "low"
#   flake-tick    --check <name> --conclusion <SUCCESS|FAILURE|PENDING|NEUTRAL> \
#                 --prior <state-json> [--new-sha]   -> updated count for the check
#   fingerprint   --file <path> --category <cat> --claim <text> [--line <n>]
#                   -> a stable normalized token (line-number-independent;
#                      --line is accepted for caller convenience and is
#                      DELIBERATELY IGNORED — it never affects the token)
#   converged?    --prior <fps-json> --surviving <fps-json>
#                   -> "CONVERGED" | "STOP:non-convergence"
#   settle?       --pr <facts> --flags <flags>   -> "SETTLE" | "WATCHING"
#   rearm?        --last <last_review-json> --pr <facts>
#                   -> "REARM:<signal>" | "STAY-SETTLED"
#   auto-approve? --pr <facts> --flags <flags> --approved-sha <sha> --head-sha <sha>
#                   -> "APPROVE" | "SKIP:<reason>"
#   defer?        --pr <facts>            -> "HOLD:human-engaged:<why>" | "PROCEED"
#   stop?         --flags <flags> --now <epoch> --until <epoch|empty> \
#                 --all-terminal <true|false>   -> "STOP:<reason>" | "CONTINUE"
#
# shellcheck shell=bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Tunable constants — the blast-radius thresholds. Named here (NOT buried
# inline) so they are legible and overridable via --flags at call time.
# ---------------------------------------------------------------------------
SIZE_THRESHOLD_DEFAULT=400   # additions+deletions above this => high blast-radius
FILES_THRESHOLD_DEFAULT=20   # changedFiles above this        => high blast-radius

# Action reversibility tiers — a FIXED, hard-coded total order (a constant, not
# configurable): comment(0) < approve(1) < fix(2) < merge(3). The gate uses the
# action name directly; this table documents the ordering the rules assume.
# comment/fix  : reversible mutation of the PR's own working copy -> flag-gated only.
# approve      : reversible (dismissable) -> clean + not size-high.
# merge        : effectively irreversible -> six-condition gate + not blast-high.

_die() {
    echo "babysit-gate: $*" >&2
    exit 1
}

_require_jq() {
    command -v jq >/dev/null 2>&1 || _die "jq is required but not found on PATH"
}

# ---------------------------------------------------------------------------
# Long-flag parser. Sets FLAG_<name> shell vars; --new-sha is a boolean switch.
# ---------------------------------------------------------------------------
FLAG_action=""
FLAG_pr=""
FLAG_flags=""
FLAG_check=""
FLAG_conclusion=""
FLAG_prior=""
FLAG_new_sha="false"
FLAG_file=""
FLAG_category=""
FLAG_claim=""
FLAG_surviving=""
FLAG_last=""
FLAG_approved_sha=""
FLAG_head_sha=""
FLAG_now=""
FLAG_until=""
FLAG_all_terminal=""

_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --action)       FLAG_action="${2:-}";       shift 2 ;;
            --pr)           FLAG_pr="${2:-}";            shift 2 ;;
            --flags)        FLAG_flags="${2:-}";         shift 2 ;;
            --check)        FLAG_check="${2:-}";         shift 2 ;;
            --conclusion)   FLAG_conclusion="${2:-}";    shift 2 ;;
            --prior)        FLAG_prior="${2:-}";         shift 2 ;;
            --new-sha)      FLAG_new_sha="true";         shift 1 ;;
            --file)         FLAG_file="${2:-}";          shift 2 ;;
            --category)     FLAG_category="${2:-}";      shift 2 ;;
            --claim)        FLAG_claim="${2:-}";         shift 2 ;;
            # --line is accepted for CALLER CONVENIENCE (a blocker's line number
            # is natural to pass alongside file/category/claim) but is DELIBERATELY
            # IGNORED by fingerprint: the token is defined to be line-independent
            # (a finding that moved lines after an edit is the same finding), so
            # accepting the value without using it lets tests actually exercise
            # and prove that independence instead of asserting it by omission.
            # --line's value is intentionally discarded, not stored: fingerprint
            # accepts --line for caller convenience but never reads it — the
            # token is defined to be line-independent (see cmd_fingerprint).
            --line)         shift 2 ;;
            --surviving)    FLAG_surviving="${2:-}";     shift 2 ;;
            --last)         FLAG_last="${2:-}";          shift 2 ;;
            --approved-sha) FLAG_approved_sha="${2:-}";  shift 2 ;;
            --head-sha)     FLAG_head_sha="${2:-}";      shift 2 ;;
            --now)          FLAG_now="${2:-}";           shift 2 ;;
            --until)        FLAG_until="${2:-}";         shift 2 ;;
            --all-terminal) FLAG_all_terminal="${2:-}";  shift 2 ;;
            *) _die "unknown argument: $1" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# JSON field helpers — read a field from a JSON blob with a default. Booleans
# and numbers come back as their literal text ("true" / "42").
# ---------------------------------------------------------------------------
_pr_field() {
    # $1 = json, $2 = jq filter, $3 = default when null/missing.
    # NOTE: we do NOT use jq's `//` alternative operator — it also swallows a
    # literal `false`, which would corrupt boolean reads (e.g. draft:false would
    # come back as the default). Explicit null-check preserves `false` verbatim.
    printf '%s' "$1" \
        | jq -r --arg d "$3" "($2) as \$v | if \$v == null then \$d else \$v end" \
            2>/dev/null || printf '%s' "$3"
}

# ---------------------------------------------------------------------------
# Blast-radius score. high iff:
#   (NOT authored_by_me AND NOT explicitly_named)      -- authorship OR-clause
#   OR (additions + deletions > SIZE_THRESHOLD)        -- size OR-clause
#   OR (changedFiles > FILES_THRESHOLD)                -- files OR-clause
# Authorship is exactly ONE of three OR-clauses — demoted, not deleted.
# Emits "low", or the reason as one of high:size / high:files / high:foreign-author.
# ---------------------------------------------------------------------------
_blast_radius() {
    local pr="$1" flags="$2"
    local authored named additions deletions files size_thr files_thr

    authored="$(_pr_field "$pr" '.authored_by_me' "false")"
    named="$(_pr_field "$pr" '.explicitly_named' "false")"
    # NOTE: the default here is deliberately the string "" (not "0"). Absent
    # size fields must fail CLOSED to high-blast below, never silently read as
    # a real 0 (which would make an unpopulated large PR look small).
    additions="$(_pr_field "$pr" '.additions' "")"
    deletions="$(_pr_field "$pr" '.deletions' "")"
    files="$(_pr_field "$pr" '.changedFiles' "")"

    size_thr="$(_pr_field "$flags" '.size_threshold' "$SIZE_THRESHOLD_DEFAULT")"
    files_thr="$(_pr_field "$flags" '.files_threshold' "$FILES_THRESHOLD_DEFAULT")"

    # Validate every numeric operand BEFORE any arithmetic or comparison. Under
    # set -euo pipefail, `[ "$x" -gt N ]` on a non-numeric $x prints "integer
    # expression expected" and returns status 2 — but as an `if` condition
    # set -e does NOT abort, the test is silently treated as FALSE, and the
    # size/files veto is skipped, falling through to ALLOW. Absent fields
    # default to "" above and land in the same non-numeric bucket. ANY
    # unparseable operand (additions, deletions, files, or either threshold)
    # fails CLOSED to high-blast — never crash, never silently pass as low.
    # NOTE: this loop only proves each operand is DIGIT-ONLY — a leading-zero
    # digit string (e.g. "0450") passes it but is not yet decimal-safe; the
    # `$(( ))` arithmetic below forces base-10 via `10#` to defeat bash's
    # octal interpretation of such values (see the churn calc's comment).
    local v
    for v in "$additions" "$deletions" "$files" "$size_thr" "$files_thr"; do
        case "$v" in
            ''|*[!0-9]*)
                printf 'high:unparseable-size-input\n'
                return 0
                ;;
        esac
    done

    # Size OR-clause (independent of authorship). Safe now: all operands
    # validated numeric above. Force base-10 with `10#` — bash arithmetic
    # expansion otherwise reads a leading-zero digit string (e.g. "0450") as
    # OCTAL, silently misreading it as a smaller decimal value (0450 octal =
    # 296 decimal, under a 400 threshold when the true value 450 is over it),
    # or outright crashing on an invalid octal literal like "0800". Both
    # additions and deletions are guaranteed non-empty here (the validation
    # loop above already rejected '' via the digit-only case), so `10#$var`
    # is safe.
    local churn=$(( 10#$additions + 10#$deletions ))
    if [ "$churn" -gt "$size_thr" ]; then
        printf 'high:size\n'
        return 0
    fi

    # Files OR-clause.
    if [ "$files" -gt "$files_thr" ]; then
        printf 'high:files\n'
        return 0
    fi

    # Authorship OR-clause: high only when neither authored nor explicitly named.
    if [ "$authored" != "true" ] && [ "$named" != "true" ]; then
        printf 'high:foreign-author\n'
        return 0
    fi

    printf 'low\n'
}

# Is the blast-radius high FOR A SIZE/FILES reason (not merely foreign-author)?
# Used by approve, which must ignore the authorship signal. Unparseable size
# input is a size-family failure (not an authorship signal) and must also
# fail closed here, or a garbled size field would let approve slip through.
_blast_high_by_size() {
    local br="$1"
    case "$br" in
        high:size|high:files|high:unparseable-size-input) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# The strict six-condition merge gate (reused verbatim; authorship is NOT here —
# it lives in blast-radius). Prints ALLOW, or HOLD:<condition> naming the first
# failing condition. Checked in a fixed, legible order.
#   (2) CI green (SUCCESS)          (3) zero blockers valid for head
#   (4) no human CHANGES_REQUESTED  (5) MERGEABLE
#   (6) not draft / not closed(terminal)   (+) review valid for head SHA
# (Condition 1 — authorship/explicit — is folded into blast-radius by `decide`.)
# ---------------------------------------------------------------------------
_merge_gate() {
    local pr="$1"
    local ci blockers changes_req mergeable draft state review_valid

    ci="$(_pr_field "$pr" '.ci' "PENDING")"
    blockers="$(_pr_field "$pr" '.blockers' "0")"
    changes_req="$(_pr_field "$pr" '.human_changes_requested' "false")"
    mergeable="$(_pr_field "$pr" '.mergeable' "UNKNOWN")"
    draft="$(_pr_field "$pr" '.draft' "false")"
    state="$(_pr_field "$pr" '.state' "OPEN")"
    # Fail CLOSED on absence: the field must be explicitly present AND "true"
    # to count as valid. Defaulting an ABSENT field to "true" would fail-open
    # on a stale review whenever the Actor simply omits it. The sentinel
    # "__absent__" can never equal the JSON boolean "true", so a missing field
    # falls through to the != "true" branch below exactly like an explicit
    # `false` does.
    review_valid="$(_pr_field "$pr" '.review_valid_for_head' "__absent__")"

    # (6a) terminal state — closed or merged can never merge.
    if [ "$state" != "OPEN" ]; then
        printf 'HOLD:state-terminal-%s\n' "$state"
        return 0
    fi
    # (6b) draft PRs are never merged.
    if [ "$draft" = "true" ]; then
        printf 'HOLD:draft\n'
        return 0
    fi
    # (4) a human CHANGES_REQUESTED is a permanent veto, never overridden.
    if [ "$changes_req" = "true" ]; then
        printf 'HOLD:human-changes-requested\n'
        return 0
    fi
    # (2) CI must be fully green.
    if [ "$ci" != "SUCCESS" ]; then
        printf 'HOLD:ci-not-green-%s\n' "$ci"
        return 0
    fi
    # (3) no blockers valid for the current head SHA. `blockers` is
    # Actor-COMPUTED (not a native gh field); an empty/garbled value is
    # realistic. Fail CLOSED: an unparseable count is treated as "there IS a
    # blocker" (never silently skip the veto), so the gate HOLDs.
    case "$blockers" in
        ''|*[!0-9]*) blockers=1 ;;
    esac
    if [ "$blockers" -gt 0 ]; then
        printf 'HOLD:blockers-%s\n' "$blockers"
        return 0
    fi
    # (+) the review must be valid for the current head SHA (stale review veto).
    if [ "$review_valid" != "true" ]; then
        printf 'HOLD:stale-review-sha\n'
        return 0
    fi
    # (5) must be MERGEABLE (no conflicts).
    if [ "$mergeable" != "MERGEABLE" ]; then
        printf 'HOLD:not-mergeable-conflict-%s\n' "$mergeable"
        return 0
    fi

    printf 'ALLOW\n'
}

# ---------------------------------------------------------------------------
# The clean predicate for approve / auto-approve: a PR is "clean" when the same
# strict gate would pass EXCEPT that authorship (blast-radius) is not consulted.
# Reuses the six-condition gate exactly.
# ---------------------------------------------------------------------------
_is_clean() {
    local pr="$1" g
    g="$(_merge_gate "$pr")"
    [ "$g" = "ALLOW" ]
}

# ===========================================================================
# Subcommand: decide  (the reversibility × blast-radius gate)
# ===========================================================================
cmd_decide() {
    _parse_args "$@"
    [ -n "$FLAG_action" ] || _die "decide requires --action"
    local pr="$FLAG_pr" flags="$FLAG_flags"

    local review_only fix_on approve_on merge_on
    review_only="$(_pr_field "$flags" '.review_only' "false")"
    fix_on="$(_pr_field "$flags" '.fix' "false")"
    approve_on="$(_pr_field "$flags" '.approve' "false")"
    merge_on="$(_pr_field "$flags" '.merge' "false")"

    case "$FLAG_action" in
        comment)
            # Reversible: a comment on the PR is always cheap to undo. Gated only
            # by the review capability, which is the baseline (present in both
            # full mode and review-only mode). Blast-radius never gates comment.
            printf 'ALLOW\n'
            ;;

        fix)
            # Reversible mutation of the PR's own working copy. Flag-gated only;
            # the flake guard + attempt bound + convergence stop are applied by
            # the Actor BEFORE calling the gate. Blast-radius does NOT gate fix.
            if [ "$fix_on" != "true" ]; then
                printf 'HOLD:fix-capability-off\n'
                return 0
            fi
            printf 'ALLOW\n'
            ;;

        approve)
            # Reversible (dismissable). ALLOW iff clean AND blast-radius is not
            # high FOR THE SIZE/FILES reason. Foreign-authorship alone must NOT
            # block approve — approving others' PRs is the point.
            if [ "$approve_on" != "true" ]; then
                printf 'HOLD:approve-capability-off\n'
                return 0
            fi
            if ! _is_clean "$pr"; then
                local g
                g="$(_merge_gate "$pr")"
                # Re-emit the clean-predicate failure as the approve hold reason.
                printf 'HOLD:not-clean-%s\n' "${g#HOLD:}"
                return 0
            fi
            local br
            br="$(_blast_radius "$pr" "$flags")"
            if _blast_high_by_size "$br"; then
                printf 'HOLD:blast-radius-%s\n' "${br#high:}"
                return 0
            fi
            printf 'ALLOW\n'
            ;;

        merge)
            # Effectively irreversible. ALLOW iff the strict six-condition merge
            # gate holds AND blast-radius != high. Authorship is folded into
            # blast-radius, so a foreign PR is HELD via the blast-radius clause,
            # never via a standalone authorship predicate (the precedence flip).
            if [ "$merge_on" != "true" ]; then
                printf 'HOLD:merge-capability-off\n'
                return 0
            fi
            local mg
            mg="$(_merge_gate "$pr")"
            if [ "$mg" != "ALLOW" ]; then
                printf '%s\n' "$mg"
                return 0
            fi
            local brm
            brm="$(_blast_radius "$pr" "$flags")"
            if [ "$brm" != "low" ]; then
                # Attribute the hold to blast-radius (size/files OR foreign-author).
                printf 'HOLD:blast-radius-%s\n' "${brm#high:}"
                return 0
            fi
            printf 'ALLOW\n'
            ;;

        *)
            _die "unknown --action: $FLAG_action (want comment|approve|fix|merge)"
            ;;
    esac
    # review_only is read for completeness / future use; it does not change the
    # per-action decisions above (capability flags already encode the mode).
    : "$review_only"
}

# ===========================================================================
# Subcommand: merge-gate  (the six-condition gate, exposed directly)
# ===========================================================================
cmd_merge_gate() {
    _parse_args "$@"
    _merge_gate "$FLAG_pr"
}

# ===========================================================================
# Subcommand: blast-radius
# ===========================================================================
cmd_blast_radius() {
    _parse_args "$@"
    _blast_radius "$FLAG_pr" "$FLAG_flags"
}

# ===========================================================================
# Subcommand: flake-tick
#   A red check is only actionable after the SAME name-matched check FAILs on two
#   consecutive ticks. Any non-FAILURE conclusion resets the count to 0; a new
#   commit (--new-sha) resets ALL counters, so even the just-observed FAILURE
#   does not arm this tick. State keys on the check NAME (not run ID), so a second
#   FAILURE of a same-named check arms it even as the underlying run ID changes.
# ===========================================================================
cmd_flake_tick() {
    _parse_args "$@"
    [ -n "$FLAG_check" ] || _die "flake-tick requires --check"

    # New SHA landed this tick: all counters reset, so the queried check is 0.
    if [ "$FLAG_new_sha" = "true" ]; then
        printf '0\n'
        return 0
    fi

    # Any non-FAILURE conclusion (green / pending / neutral) resets to 0.
    if [ "$FLAG_conclusion" != "FAILURE" ]; then
        printf '0\n'
        return 0
    fi

    # A FAILURE increments this check's prior consecutive-fail count by 1.
    local prior_json="$FLAG_prior"
    [ -n "$prior_json" ] || prior_json='{}'
    local prior_count
    prior_count="$(printf '%s' "$prior_json" \
        | jq -r --arg c "$FLAG_check" '.[$c] // 0' 2>/dev/null || echo 0)"
    case "$prior_count" in
        ''|*[!0-9]*) prior_count=0 ;;
    esac
    # Force base-10 with `10#` for the same reason as the churn calc in
    # _blast_radius above: a leading-zero digit string (e.g. "010") would
    # otherwise be misread as octal by arithmetic expansion. prior_count is
    # guaranteed non-empty here (defaulted to 0 above when empty/non-numeric).
    printf '%s\n' "$(( 10#$prior_count + 1 ))"
}

# ===========================================================================
# Subcommand: fingerprint
#   A stable token for a blocker: file + category + NORMALIZED claim. Line number
#   is deliberately NOT part of the token (a finding that moved lines is the same
#   finding). The claim is lowercased, punctuation stripped, and whitespace
#   collapsed, so trivial wording drift collapses to the same fingerprint.
# ===========================================================================
_normalize_claim() {
    # lowercase -> strip non-alphanumeric-or-space -> collapse whitespace -> trim
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c '[:alnum:] ' ' ' \
        | tr -s ' ' \
        | sed 's/^ //; s/ $//'
}

cmd_fingerprint() {
    _parse_args "$@"
    [ -n "$FLAG_file" ]     || _die "fingerprint requires --file"
    [ -n "$FLAG_category" ] || _die "fingerprint requires --category"

    local norm token
    norm="$(_normalize_claim "$FLAG_claim")"
    # A short, stable hash keeps the token compact and line-number-independent.
    token="$(printf '%s\037%s\037%s' "$FLAG_file" "$FLAG_category" "$norm" \
        | cksum | awk '{print $1}')"
    printf 'fp-%s\n' "$token"
}

# ===========================================================================
# Subcommand: converged?
#   A blocker present BEFORE a fix that is STILL present after survived the
#   dispatch. >=1 surviving prior fingerprint => STOP (non-convergence). A fresh
#   blocker not in the prior set is progress, not non-convergence.
# ===========================================================================
cmd_converged() {
    _parse_args "$@"
    local prior="${FLAG_prior:-[]}" surviving="${FLAG_surviving:-[]}"

    # Count surviving fingerprints that were also in the prior set.
    local overlap
    overlap="$(jq -n \
        --argjson prior "$prior" \
        --argjson surviving "$surviving" \
        '[ $surviving[] | select( . as $s | $prior | index($s) ) ] | length' \
        2>/dev/null || echo 0)"
    case "$overlap" in
        ''|*[!0-9]*) overlap=0 ;;
    esac

    if [ "$overlap" -ge 1 ]; then
        printf 'STOP:non-convergence\n'
        return 0
    fi
    printf 'CONVERGED\n'
}

# ===========================================================================
# Subcommand: settle?
#   Clean-but-can't-advance => SETTLE (drop to a cheap poll). A PR that can still
#   advance toward merge stays WATCHING. Concretely: if --merge is on and the PR
#   would merge (merge decide == ALLOW), it is still advancing => WATCHING. If it
#   is blocked in a way this tick cannot change (foreign blast-radius, or a human
#   CHANGES_REQUESTED park), it settles.
# ===========================================================================
cmd_settle() {
    _parse_args "$@"
    local pr="$FLAG_pr" flags="$FLAG_flags"
    local merge_on
    merge_on="$(_pr_field "$flags" '.merge' "false")"

    if [ "$merge_on" = "true" ]; then
        # Would a merge fire? Reuse the merge decision.
        local d
        d="$(cmd_decide --action merge --pr "$pr" --flags "$flags")"
        if [ "$d" = "ALLOW" ]; then
            printf 'WATCHING\n'
            return 0
        fi
    fi
    # Not advancing this tick -> settle to a cheap poll.
    printf 'SETTLE\n'
}

# ===========================================================================
# Subcommand: rearm?
#   From a settled state, re-arm to watching when any watched signal changed
#   since the last recorded review: head SHA, CI conclusion, review decision, or
#   draft->ready. No change => STAY-SETTLED (the cheap poll is a no-op).
# ===========================================================================
cmd_rearm() {
    _parse_args "$@"
    local last="$FLAG_last" pr="$FLAG_pr"
    [ -n "$last" ] || last='{}'

    local last_sha last_ci last_review last_draft
    last_sha="$(_pr_field "$last" '.sha' "")"
    last_ci="$(_pr_field "$last" '.ci' "")"
    last_review="$(_pr_field "$last" '.reviewDecision' "")"
    last_draft="$(_pr_field "$last" '.draft' "")"

    local cur_sha cur_ci cur_review cur_draft
    cur_sha="$(_pr_field "$pr" '.head_sha' "")"
    cur_ci="$(_pr_field "$pr" '.ci' "")"
    cur_review="$(_pr_field "$pr" '.reviewDecision' "")"
    cur_draft="$(_pr_field "$pr" '.draft' "")"

    if [ "$cur_sha" != "$last_sha" ]; then
        printf 'REARM:sha\n'
        return 0
    fi
    if [ "$cur_ci" != "$last_ci" ]; then
        printf 'REARM:ci\n'
        return 0
    fi
    if [ "$cur_review" != "$last_review" ]; then
        printf 'REARM:reviewDecision\n'
        return 0
    fi
    # draft -> ready is the re-arm direction of interest.
    if [ "$last_draft" = "true" ] && [ "$cur_draft" = "false" ]; then
        printf 'REARM:draft-to-ready\n'
        return 0
    fi

    printf 'STAY-SETTLED\n'
}

# ===========================================================================
# Subcommand: auto-approve?
#   Fires on the merge predicate MINUS authorship (clean-minus-authorship), once
#   per head SHA. Re-arms when the head SHA moves. No-op on own PRs (GitHub blocks
#   self-approval). SKIP if unclean or the --approve flag is off.
# ===========================================================================
cmd_auto_approve() {
    _parse_args "$@"
    local pr="$FLAG_pr" flags="$FLAG_flags"
    local approve_on authored
    approve_on="$(_pr_field "$flags" '.approve' "false")"
    authored="$(_pr_field "$pr" '.authored_by_me' "false")"

    if [ "$approve_on" != "true" ]; then
        printf 'SKIP:approve-capability-off\n'
        return 0
    fi
    # Own PR: self-approval is impossible on GitHub, so auto-approve is a no-op.
    if [ "$authored" = "true" ]; then
        printf 'SKIP:own-pr-self-approval-blocked\n'
        return 0
    fi
    # Already approved for this head SHA => once-per-SHA dedup.
    if [ -n "$FLAG_approved_sha" ] && [ "$FLAG_approved_sha" = "$FLAG_head_sha" ]; then
        printf 'SKIP:already-approved-this-sha\n'
        return 0
    fi
    # Clean-minus-authorship: reuse the six-condition gate (authorship not in it).
    if ! _is_clean "$pr"; then
        printf 'SKIP:not-clean\n'
        return 0
    fi
    printf 'APPROVE\n'
}

# ===========================================================================
# Subcommand: defer?
#   Human-deference: before review/approve/merge, hold if a human is engaged —
#   an in-flight human review, a human (non-bot, non-self) thread reply, or an
#   existing human approval. Must NOT fire on the loop's own ack or a bot reply.
#   Distinct from CHANGES_REQUESTED (which is the merge gate's permanent veto).
# ===========================================================================
cmd_defer() {
    _parse_args "$@"
    local pr="$FLAG_pr"
    local in_flight human_reply human_approval

    in_flight="$(_pr_field "$pr" '.human_review_in_flight' "false")"
    human_reply="$(_pr_field "$pr" '.human_thread_reply' "false")"
    human_approval="$(_pr_field "$pr" '.human_approval_exists' "false")"

    if [ "$in_flight" = "true" ]; then
        printf 'HOLD:human-engaged:review-in-flight\n'
        return 0
    fi
    if [ "$human_reply" = "true" ]; then
        printf 'HOLD:human-engaged:thread-reply\n'
        return 0
    fi
    if [ "$human_approval" = "true" ]; then
        printf 'HOLD:human-engaged:approval-exists\n'
        return 0
    fi
    # own ack / bot reply / CHANGES_REQUESTED-with-no-engagement all PROCEED here.
    printf 'PROCEED\n'
}

# ===========================================================================
# Subcommand: stop?
#   --until uses the REAL wall-clock read at tick start (--now). A late tick with
#   now already >= until must STOP (never sail past). --until-empty (flags
#   .until_empty) stops when all watched PRs are terminal/settled. No condition
#   set => CONTINUE.
# ===========================================================================
cmd_stop() {
    _parse_args "$@"
    local flags="$FLAG_flags"
    [ -n "$flags" ] || flags='{}'
    local until_empty
    until_empty="$(_pr_field "$flags" '.until_empty' "false")"

    # --until <epoch>: stop when the real 'now' has reached or passed the boundary.
    if [ -n "$FLAG_until" ] && [ "$FLAG_until" != "empty" ] && [ "$FLAG_until" != "" ]; then
        case "$FLAG_until" in
            ''|*[!0-9]*) : ;;  # non-numeric (e.g. stray) — ignore as a time bound
            *)
                local now="${FLAG_now:-0}"
                case "$now" in ''|*[!0-9]*) now=0 ;; esac
                if [ "$now" -ge "$FLAG_until" ]; then
                    printf 'STOP:until-time-reached\n'
                    return 0
                fi
                printf 'CONTINUE\n'
                return 0
                ;;
        esac
    fi

    # --until-empty: stop only when everything watched is terminal/settled.
    if [ "$until_empty" = "true" ] || [ "$FLAG_until" = "empty" ]; then
        if [ "$FLAG_all_terminal" = "true" ]; then
            printf 'STOP:all-terminal-empty\n'
            return 0
        fi
        printf 'CONTINUE\n'
        return 0
    fi

    # No stop condition set — run until the session ends.
    printf 'CONTINUE\n'
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
    _require_jq
    [ "$#" -ge 1 ] || _die "usage: babysit-gate.sh <subcommand> [args]"
    local sub="$1"; shift
    case "$sub" in
        decide)         cmd_decide "$@" ;;
        merge-gate)     cmd_merge_gate "$@" ;;
        blast-radius)   cmd_blast_radius "$@" ;;
        flake-tick)     cmd_flake_tick "$@" ;;
        fingerprint)    cmd_fingerprint "$@" ;;
        converged?)     cmd_converged "$@" ;;
        settle?)        cmd_settle "$@" ;;
        rearm?)         cmd_rearm "$@" ;;
        auto-approve?)  cmd_auto_approve "$@" ;;
        defer?)         cmd_defer "$@" ;;
        stop?)          cmd_stop "$@" ;;
        *) _die "unknown subcommand: $sub" ;;
    esac
}

main "$@"
