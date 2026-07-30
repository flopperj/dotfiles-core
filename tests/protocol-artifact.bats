#!/usr/bin/env bats
# Shape validation for PROTOCOL.md — pins required headings and content markers.

load 'test_helper'

PROTOCOL_FILE="$CORE_DIR/PROTOCOL.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------

@test "PROTOCOL.md exists at repo root" {
    [ -f "$PROTOCOL_FILE" ]
}

# ---------------------------------------------------------------------------
# 2. Frontmatter
# ---------------------------------------------------------------------------

@test "PROTOCOL.md has protocol-version frontmatter" {
    grep -q "^protocol-version:" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md frontmatter specifies version v2" {
    grep -q "^protocol-version: v2" "$PROTOCOL_FILE"
}

# ---------------------------------------------------------------------------
# 3. Required top-level sections
# ---------------------------------------------------------------------------

@test "PROTOCOL.md has 'Grammar (today)' section" {
    grep -q "^## Grammar (today)" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has 'Bilateral contract' section" {
    grep -q "^## Bilateral contract" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has 'Controlled vocabulary' section" {
    grep -q "^## Controlled vocabulary" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has 'Enforcement evolution' section" {
    grep -q "^## Enforcement evolution" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has 'Why denylist is structurally weak' section" {
    grep -q "^## Why denylist is structurally weak" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has 'Versioning' section" {
    grep -q "^## Versioning" "$PROTOCOL_FILE"
}

# ---------------------------------------------------------------------------
# 4. Enforcement evolution sub-sections
# ---------------------------------------------------------------------------

@test "PROTOCOL.md has 'Cohort 0' sub-section mentioning in-tree" {
    grep -q "^### Cohort 0" "$PROTOCOL_FILE"
    sed -n '/^### Cohort 0/,/^### Cohort 1/p' "$PROTOCOL_FILE" | grep -q "in-tree"
}

@test "PROTOCOL.md has Cohort 1 sub-section with 'PROVISIONAL'" {
    grep -q "### Cohort 1" "$PROTOCOL_FILE"
    grep -q "PROVISIONAL" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has Cohort 2 sub-section with 'positive grammar'" {
    grep -q "### Cohort 2" "$PROTOCOL_FILE"
    grep -q "positive grammar" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md has Cohort 3 sub-section with 'publication'" {
    grep -q "^### Cohort 3" "$PROTOCOL_FILE"
    grep -q "publication" "$PROTOCOL_FILE"
}

# ---------------------------------------------------------------------------
# 5. Grammar content — regex must appear
# ---------------------------------------------------------------------------

@test "PROTOCOL.md Grammar section contains the consult-instruction regex" {
    grep -q 'consult.*##.*overlay-context\.md' "$PROTOCOL_FILE"
}

# ---------------------------------------------------------------------------
# 6. Bilateral contract — cites the overlay lint script
# ---------------------------------------------------------------------------

@test "PROTOCOL.md Bilateral contract cites lint-consult-blocks.sh" {
    grep -q "lint-consult-blocks.sh" "$PROTOCOL_FILE"
}

# ---------------------------------------------------------------------------
# 7. Controlled vocabulary — two known live sections present
# ---------------------------------------------------------------------------

@test "PROTOCOL.md Controlled vocabulary mentions 'Jira fallback'" {
    grep -q "Jira fallback" "$PROTOCOL_FILE"
}

@test "PROTOCOL.md Controlled vocabulary mentions 'Jenkins MCP clone URL'" {
    grep -q "Jenkins MCP clone URL" "$PROTOCOL_FILE"
}
