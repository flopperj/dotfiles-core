#!/usr/bin/env bats
# Tests for scripts/check-no-leakage.sh
#
# RED phase: these tests are written before the script exists.
# Each test case verifies a behavioral contract from the PRD.

load 'test_helper'

# Helper: create a scratch file with given content, run leakage check on it.
# CORE_DIR is set by test_helper.bash setup() before each test.
_check_file() {
    local content="$1"
    echo "$content" > "$SCRATCH/subject.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCRATCH"
}

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------

@test "check-no-leakage.sh exists and is executable" {
    [ -f "$CORE_DIR/scripts/check-no-leakage.sh" ]
    [ -x "$CORE_DIR/scripts/check-no-leakage.sh" ]
}

# ---------------------------------------------------------------------------
# 2. Clean tree exits 0
# ---------------------------------------------------------------------------

@test "clean directory exits 0" {
    echo "This file has no forbidden tokens — just universal content." \
        > "$SCRATCH/clean.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCRATCH"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. Each forbidden token is caught — lowercase
# ---------------------------------------------------------------------------

@test "catches 'mailchimp' (lowercase)" {
    _check_file "See the mailchimp documentation."
    [ "$status" -ne 0 ]
}

@test "catches 'intuit' (lowercase)" {
    _check_file "intuit is the company name."
    [ "$status" -ne 0 ]
}

@test "catches 'turbotax' (lowercase)" {
    _check_file "Filed with turbotax this year."
    [ "$status" -ne 0 ]
}

@test "catches 'quickbooks' (lowercase)" {
    _check_file "Track expenses in quickbooks."
    [ "$status" -ne 0 ]
}

@test "catches 'cg-tax' (lowercase)" {
    _check_file "Service name: cg-tax"
    [ "$status" -ne 0 ]
}

@test "catches 'build.intuit.com' URL" {
    _check_file "CI lives at https://build.intuit.com/jobs/123"
    [ "$status" -ne 0 ]
}

@test "catches '@intuit.com' email domain" {
    _check_file "Send mail to user@intuit.com for support."
    [ "$status" -ne 0 ]
}

@test "catches '@mailchimp.com' email domain" {
    _check_file "Contact support@mailchimp.com"
    [ "$status" -ne 0 ]
}

@test "catches 'DAST-Orch' (exact case)" {
    _check_file "Use DAST-Orch as the fallback MCP."
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 4. Case-insensitive matching
# ---------------------------------------------------------------------------

@test "catches 'Intuit' (title case)" {
    _check_file "Intuit is headquartered in Mountain View."
    [ "$status" -ne 0 ]
}

@test "catches 'INTUIT' (uppercase)" {
    _check_file "INTUIT CONFIDENTIAL"
    [ "$status" -ne 0 ]
}

@test "catches 'Mailchimp' (title case)" {
    _check_file "The Mailchimp platform."
    [ "$status" -ne 0 ]
}

@test "catches 'DAST-ORCH' (uppercase variant)" {
    _check_file "DAST-ORCH server"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 5. Word-boundary: false positives do NOT trigger
# ---------------------------------------------------------------------------

@test "word boundary: 'intuitive' does NOT match 'intuit'" {
    echo "An intuitive interface." > "$SCRATCH/ok.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCRATCH"
    [ "$status" -eq 0 ]
}

@test "word boundary: 'intuition' does NOT match 'intuit'" {
    echo "Trust your intuition here." > "$SCRATCH/ok.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCRATCH"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5b. Word-boundary: underscore and hyphen after token are NOT word chars
#     (H2 regression: old regex [^a-zA-Z0-9_-] let these slip through)
# ---------------------------------------------------------------------------

@test "word boundary: 'intuit_x' DOES match 'intuit' (underscore is not a word char)" {
    _check_file "intuit_client_secrets.json"
    [ "$status" -ne 0 ]
}

@test "word boundary: 'intuit-x' DOES match 'intuit' (hyphen is not a word char)" {
    _check_file "your-intuit-username"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 6. Tokens inside code blocks, frontmatter, comments still caught
# ---------------------------------------------------------------------------

@test "token inside markdown fenced code block is caught" {
    _check_file '```bash
# Connect to intuit services
curl https://api.intuit.com
```'
    [ "$status" -ne 0 ]
}

@test "token inside YAML frontmatter is caught" {
    _check_file '---
owner: user@intuit.com
---
Content here.'
    [ "$status" -ne 0 ]
}

@test "token inside shell comment is caught" {
    _check_file '#!/usr/bin/env bash
# Uses mailchimp MCP for campaign data'
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 7. Adding a new token to leakage-tokens.txt is picked up
# ---------------------------------------------------------------------------

@test "new token in leakage-tokens.txt is picked up without restart" {
    local tokens_file="$CORE_DIR/scripts/leakage-tokens.txt"
    local orig_content
    orig_content="$(cat "$tokens_file")"

    # Add a unique test token
    echo "xyzzy-sentinel-unique" >> "$tokens_file"

    echo "xyzzy-sentinel-unique appears in this file" > "$SCRATCH/test.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCRATCH"
    local exit_code="$status"

    # Restore original tokens file
    echo "$orig_content" > "$tokens_file"

    [ "$exit_code" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 8. Output on failure includes file path and matched line
# ---------------------------------------------------------------------------

@test "failure output includes matched file path" {
    _check_file "This contains intuit somewhere."
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "subject.txt"
}

# ---------------------------------------------------------------------------
# 9. .git/ directory is excluded from the check
# ---------------------------------------------------------------------------

@test ".git directory is excluded from leakage scan" {
    mkdir -p "$SCRATCH/.git"
    echo "intuit is here" > "$SCRATCH/.git/config_hack"
    echo "clean content only" > "$SCRATCH/clean.txt"
    run bash "$CORE_DIR/scripts/check-no-leakage.sh" "$SCRATCH"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5c. Word-boundary: DAST-Orch-fallback sentinel name form is caught
#     (H2 regression: token list included DAST-Orch; sentinel names like
#     DAST-Orch-fallback must still match because hyphen is not a word char)
# ---------------------------------------------------------------------------

@test "word boundary: 'DAST-Orch-fallback' DOES match 'DAST-Orch' (hyphen is not a word char)" {
    _check_file "<!-- BEGIN OVERLAY-FRAGMENT: DAST-Orch-fallback -->"
    [ "$status" -ne 0 ]
}
