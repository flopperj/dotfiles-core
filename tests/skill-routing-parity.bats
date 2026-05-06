#!/usr/bin/env bats
# Parity test: SKILL.md description <-> CLAUDE.md routing tables.
# A skill that advertises a trigger phrase in its description must have
# that phrase wired into one of the four CLAUDE.md routing surfaces.
#
# Anchor keywords that define where phrase extraction begins:
#   Triggers on  — explicit trigger list (to-prd shape)
#   or mentions  — prose-embedded trigger (grill-me shape)
#   or says      — compact trigger list embedded in prose
#   starts a prompt with — name-prefix trigger documentation
#
# The zone extends from each anchor through all quoted phrases until ". "
# (period + space) or end-of-description. Any quoted phrase that falls within
# the same zone as a recognized anchor will be captured — including phrases
# introduced by "or asks to" or any other connector within the zone. "or asks
# to" is not itself an anchor, but it does not exclude phrases from capture.
#
# Note: name tokens extracted from "starts a prompt with" (e.g. "Cyrus",
# "Optimus", "Sitrep") are checked against all of CLAUDE.md, not specifically
# the name-prefix routing table. If the name-prefix table is ever moved (e.g.,
# to AGENTS.md), these checks would need to scope their grep target accordingly.
#
# The anchor set excludes "Use when" because that phrase introduces general
# invocation documentation (slash commands) rather than natural-language trigger
# phrases.

# Note: we do NOT load 'test_helper' here because SKILLS_DIR and CLAUDE_MD
# must be set after DOTFILES_DIR is resolved in setup(), not at parse time.
# Instead we replicate the minimal test_helper setup inline.

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
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# Extract the description: value (single line — descriptions in this repo
# are always single-line YAML strings, sometimes quoted, sometimes bare).
_get_description() {
    local skill_md="$1"
    awk '
        /^description:/ {
            sub(/^description:[[:space:]]*/, "")
            # Strip surrounding double quotes if present
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$skill_md"
}

# Extract trigger phrases: quoted tokens (single OR double quotes) that
# appear AFTER an anchor keyword in the description.
#
# B2 fix: single-quoted spans are extracted by a character scanner that treats
# apostrophes flanked by alphanumeric characters as word-internal (not quote
# boundaries). This prevents "let's" from closing a single-quoted span early.
# The scanner checks: a closing '\'' is only valid when NOT followed by [[:alnum:]].
_extract_triggers() {
    local description="$1"
    # Walk the description scanning for anchors; for each anchor match, set the
    # zone to the tail of the description from that anchor position. Truncate the
    # zone at the first ". " (period + space) — this avoids cutting on mid-token
    # dots like "v1.2" while still bounding the zone to one sentence. When no
    # ". " follows (e.g. the description ends with a period and no trailing space),
    # match() returns 0 and the zone runs to end-of-string, capturing all quoted
    # phrases including those after connectors like "or asks to".
    # POSIX awk only — no GNU extensions required.
    echo "$description" | awk -v anchors="$ANCHORS" '
        # Scan zone and print each double- or single-quoted token.
        # Single-quote handling: a closing quote must NOT be followed by an
        # alphanumeric character; if it is, it is a word-internal apostrophe
        # and is included verbatim in the token being accumulated.
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
                    # Open a single-quoted span only when NOT preceded by alphanumeric.
                    if (prev_c !~ /[[:alnum:]]/) {
                        in_sq = 1; token = ""; continue
                    }
                }
                if (in_sq && c == "\047") {
                    # Close the span only when NOT followed by alphanumeric.
                    if (next_c !~ /[[:alnum:]]/) {
                        print token; in_sq = 0; token = ""; continue
                    }
                    # Word-internal apostrophe (e.g. "don'\''t"): include in token.
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
                    # Truncate at first period that ends a sentence (period followed
                    # by space or end-of-string). Avoids cutting mid-URL dots like "v1.2".
                    if (match(zone, /\. /)) zone = substr(zone, 1, RSTART)
                    extract_quoted(zone)
                }
            }
        }
    ' | sort -u
}

@test "every advertised trigger phrase is wired into CLAUDE.md routing" {
    local violations=()

    for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
        local skill_name
        skill_name="$(basename "$(dirname "$skill_md")")"

        # Only check skills that are user-invocable.
        grep -q "^user-invocable:[[:space:]]*true" "$skill_md" || continue

        local description triggers ignore_list
        description="$(_get_description "$skill_md")"
        triggers="$(_extract_triggers "$description")"

        [ -z "$triggers" ] && continue  # no triggers advertised, nothing to check

        # I1: read parity-ignore lines anywhere in the SKILL.md file.
        # Format: # parity-ignore: <phrase>
        # Phrases listed here are intentionally not wired into CLAUDE.md routing
        # (e.g. quoted examples in the description that aren't actual trigger phrases).
        # Note: grep matches this pattern anywhere in the file, including inside
        # fenced code blocks. By convention, keep "# parity-ignore:" lines in the
        # YAML frontmatter so they are visually distinct from body examples.
        ignore_list="$(grep '^# parity-ignore:' "$skill_md" | sed 's/^# parity-ignore:[[:space:]]*//')"

        while IFS= read -r phrase; do
            [ -z "$phrase" ] && continue
            # Skip phrases explicitly suppressed via # parity-ignore.
            if [ -n "$ignore_list" ] && echo "$ignore_list" | grep -qxF -- "$phrase"; then
                continue
            fi
            # Case-insensitive word-boundary match against the entire CLAUDE.md.
            # -w requires non-word characters on both sides of the phrase,
            # preventing partial-word false positives (e.g. "briefing" in "briefings").
            if ! grep -qiwF -- "$phrase" "$CLAUDE_MD"; then
                violations+=("$skill_name: \"$phrase\" not found in CLAUDE.md")
            fi
        done <<< "$triggers"
    done

    if [ "${#violations[@]}" -gt 0 ]; then
        printf 'Skill-routing parity violations:\n'
        printf '  - %s\n' "${violations[@]}"
        return 1
    fi
}

@test "extractor returns empty list for skills with no triggers (regression guard)" {
    # review-context's description uses only Use when / asks to patterns (not
    # the narrow anchors), so the extractor must return empty. If this fails,
    # the parser is overfiring or review-context's description changed.
    local skill_md="$SKILLS_DIR/review-context/SKILL.md"
    [ -f "$skill_md" ] || skip "review-context not present"

    local description triggers
    description="$(_get_description "$skill_md")"
    triggers="$(_extract_triggers "$description")"

    if [ -n "$triggers" ]; then
        echo "Expected empty trigger list for review-context, got:"
        echo "$triggers"
        return 1
    fi
}

@test "extractor finds explicit-list triggers (to-prd shape)" {
    # Sanity: to-prd description ends with Triggers on "to-prd", "create a PRD", ...
    # The extractor MUST return at least one of those phrases.
    local skill_md="$SKILLS_DIR/to-prd/SKILL.md"
    [ -f "$skill_md" ] || skip "to-prd skill not present"

    local description triggers
    description="$(_get_description "$skill_md")"
    triggers="$(_extract_triggers "$description")"

    echo "$triggers" | grep -qiF "to-prd" || {
        echo "Expected 'to-prd' in extracted triggers, got:"
        echo "$triggers"
        return 1
    }
}

@test "extractor finds prose-quoted triggers (grill-me shape)" {
    # Sanity: grill-me description has 'or mentions "grill me"'.
    local skill_md="$SKILLS_DIR/grill-me/SKILL.md"
    [ -f "$skill_md" ] || skip "grill-me skill not present"

    local description triggers
    description="$(_get_description "$skill_md")"
    triggers="$(_extract_triggers "$description")"

    echo "$triggers" | grep -qiF "grill me" || {
        echo "Expected 'grill me' in extracted triggers, got:"
        echo "$triggers"
        return 1
    }
}

@test "B2: extractor does not truncate single-quoted phrase at internal apostrophe (regression guard)" {
    # A phrase like "don't trip on this" contains an apostrophe inside the quoted span.
    # The old regex \047[^\047]+\047 matches 'don' (stopping at the apostrophe in don't),
    # extracting the 3-character token "don" instead of the full phrase.
    # After the fix, the extractor must return "don't trip on this", not "don".
    local description="Use it or says things like 'don't trip on this' and 'real phrase'."
    local triggers
    triggers="$(_extract_triggers "$description")"

    # Must NOT produce the truncated token "don"
    if echo "$triggers" | grep -qxF "don"; then
        echo "B2 regression: extracted truncated token 'don' from apostrophe collision"
        echo "Full trigger list: $triggers"
        return 1
    fi

    # Must produce the full phrase "don't trip on this"
    if ! echo "$triggers" | grep -qxF "don't trip on this"; then
        echo "B2 regression: expected full phrase \"don't trip on this\" in triggers"
        echo "Full trigger list: $triggers"
        return 1
    fi
}

@test "B3: parity check uses word-boundary match not substring match (regression guard)" {
    # The old grep -qiF accepts a phrase as "wired" if it appears as any substring
    # of any word in CLAUDE.md — including as a prefix of a longer word.
    # For example, phrase "morning briefing" (singular) matches "morning briefings" (plural)
    # because the singular is a prefix-substring of the plural.
    # With -w (word-boundary), "morning briefing" must NOT match "morning briefings"
    # because "briefing" is not a standalone word in the plural form.
    # (Word boundaries apply to the first and last word of the pattern only; for
    # multi-word phrases like "what needs my attention", a CLAUDE.md containing
    # "what needs my attention now" would still pass -w. Full-phrase exact matches
    # are enforced by the CLAUDE.md content itself, not by -w alone.)
    local tmp_claude
    tmp_claude="$(mktemp)"
    # CLAUDE.md contains the plural form; skill advertises the singular
    printf '"morning briefings" triggers /briefing\n' > "$tmp_claude"

    local phrase="morning briefing"  # singular — skill description uses this

    # Old behaviour (substring, -F): singular matches as prefix of plural
    if ! grep -qiF -- "$phrase" "$tmp_claude"; then
        echo "B3 test setup error: expected -F to match 'morning briefing' inside 'morning briefings'"
        rm -f "$tmp_claude"
        return 1
    fi

    # The new -w must reject "morning briefing" (singular "briefing" is not a word boundary in "briefings")
    if grep -qiwF -- "$phrase" "$tmp_claude"; then
        echo "B3 regression: word-boundary grep matches 'morning briefing' as substring of 'morning briefings'"
        rm -f "$tmp_claude"
        return 1
    fi

    rm -f "$tmp_claude"
}

@test "I1: parity-ignore lines subtract phrases from enforcement check (regression guard)" {
    # A SKILL.md with description containing "real-trigger" and "ignored-phrase",
    # plus a body line "# parity-ignore: ignored-phrase", must produce only
    # "real-trigger" in the violations check — not "ignored-phrase".
    local tmp_skill_dir tmp_skill_md tmp_claude
    tmp_skill_dir="$(mktemp -d)"
    tmp_skill_md="$tmp_skill_dir/SKILL.md"
    tmp_claude="$(mktemp)"

    # Skill advertises two phrases; one is parity-ignored.
    # Use bare YAML (no outer quotes) so inner double-quotes are literal in the file.
    cat > "$tmp_skill_md" <<'EOF'
---
name: test-skill
description: Test skill. Triggers on "real-trigger", "ignored-phrase".
user-invocable: true
# parity-ignore: ignored-phrase
---
EOF

    # CLAUDE.md only wires real-trigger, not ignored-phrase
    printf '"real-trigger"\n' > "$tmp_claude"

    # Run the parity check logic manually using the same helpers.
    # We expect zero violations (ignored-phrase should be skipped).
    local description triggers violations=()
    description="$(_get_description "$tmp_skill_md")"

    # Read parity-ignore lines from the SKILL.md
    local ignore_list
    ignore_list="$(grep '^# parity-ignore:' "$tmp_skill_md" | sed 's/^# parity-ignore:[[:space:]]*//')"

    triggers="$(_extract_triggers "$description")"

    while IFS= read -r phrase; do
        [ -z "$phrase" ] && continue
        # Skip phrases in the ignore list
        if echo "$ignore_list" | grep -qxF -- "$phrase"; then
            continue
        fi
        if ! grep -qiwF -- "$phrase" "$tmp_claude"; then
            violations+=("test-skill: \"$phrase\" not found")
        fi
    done <<< "$triggers"

    rm -rf "$tmp_skill_dir"
    rm -f "$tmp_claude"

    if [ "${#violations[@]}" -gt 0 ]; then
        printf 'I1 regression: parity-ignore not honoured:\n'
        printf '  - %s\n' "${violations[@]}"
        return 1
    fi
}
