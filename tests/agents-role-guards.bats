#!/usr/bin/env bats
# Tests for the role-guard-gen.sh generator and sentinel/directive structural assertions.
#
# Tests 1-7 drive generator implementation (RED until Step 4 completes).
# Tests 8-9 are post-migration assertions (RED until Step 7 completes).
#
# Run with: bats tests/agents-role-guards.bats
# Or via:   make test-agents

load 'test_helper'

GEN="$DOTFILES_DIR/scripts/role-guard-gen.sh"
AGENTS_DIR="$DOTFILES_DIR/.claude/agents"
FRAGMENTS_DIR="$DOTFILES_DIR/.claude/_shared/role-guards"

# ---------------------------------------------------------------------------
# Test 1: Generator script exists and is executable
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh exists and is executable" {
    [ -f "$GEN" ]
    [ -x "$GEN" ]
}

# ---------------------------------------------------------------------------
# Test 2: Generator runs successfully on current repo (no error exit)
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh runs successfully on current repo" {
    run bash "$GEN"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 3: Generator is idempotent — second run produces no git diff
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh is idempotent (second run produces no diff)" {
    local before after
    before="$(git -C "$DOTFILES_DIR" diff)"

    bash "$GEN"
    bash "$GEN"

    after="$(git -C "$DOTFILES_DIR" diff)"

    # Second-run stability: gen(gen(x)) == gen(x).
    # Catches non-deterministic generators (e.g. timestamp injection).
    if [ "$before" != "$after" ]; then
        echo "Second run of role-guard-gen.sh produced changes:"
        echo "$after"
        return 1
    fi

    # True idempotency from committed state: gen(committed) == committed.
    # Catches cases where fragments have drifted from what is committed — a
    # state where only the first run (not the second) changes files, so the
    # before==after check above would still pass despite real drift.
    #
    # Skip when the working tree already had changes before this test ran
    # (e.g. local development with work-in-progress).  In that context the
    # tree is never clean and the assertion would produce a false-positive.
    # CI always starts from a clean checkout, so the guard is effective there.
    if [ -z "$before" ] && [ -n "$after" ]; then
        echo "role-guard-gen.sh produced changes relative to committed state (fragments have drifted):"
        echo "$after"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 4: Generator splices reviewer fragment into scout-reviewer.md
# Requires sentinel blocks in scout-reviewer.md (passes after Step 6/7)
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh splices reviewer fragment into scout-reviewer.md" {
    local scout_file="$AGENTS_DIR/scout-reviewer.md"
    if ! grep -q "BEGIN ROLE GUARD" "$scout_file"; then
        skip "scout-reviewer.md not yet migrated (pending Step 7)"
    fi

    bash "$GEN"

    local spliced
    spliced="$(awk '/BEGIN ROLE GUARD/,/END ROLE GUARD/' "$scout_file")"
    if ! echo "$spliced" | grep -q "structured review report with confidence-scored findings"; then
        echo "reviewer fragment not found in scout-reviewer.md sentinel block:"
        echo "$spliced"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 5: Generator splices reviewer fragment into ranger-reviewer.md
# Requires sentinel blocks in ranger-reviewer.md (passes after Step 6/7)
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh splices reviewer fragment into ranger-reviewer.md" {
    local ranger_file="$AGENTS_DIR/ranger-reviewer.md"
    if ! grep -q "BEGIN ROLE GUARD" "$ranger_file"; then
        skip "ranger-reviewer.md not yet migrated (pending Step 7)"
    fi

    bash "$GEN"

    local spliced
    spliced="$(awk '/BEGIN ROLE GUARD/,/END ROLE GUARD/' "$ranger_file")"
    if ! echo "$spliced" | grep -q "structured review report with confidence-scored findings"; then
        echo "reviewer fragment not found in ranger-reviewer.md sentinel block:"
        echo "$spliced"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 6: Scout and Ranger spliced role guard blocks are byte-identical
# Requires both files migrated (passes after Step 8)
# ---------------------------------------------------------------------------
@test "Scout and Ranger spliced role guard blocks are byte-identical" {
    local scout_file="$AGENTS_DIR/scout-reviewer.md"
    local ranger_file="$AGENTS_DIR/ranger-reviewer.md"

    if ! grep -q "BEGIN ROLE GUARD" "$scout_file" || ! grep -q "BEGIN ROLE GUARD" "$ranger_file"; then
        skip "scout-reviewer.md or ranger-reviewer.md not yet migrated (pending Step 7)"
    fi

    bash "$GEN"

    local scout_block ranger_block
    scout_block="$(awk '/BEGIN ROLE GUARD/,/END ROLE GUARD/' "$scout_file")"
    ranger_block="$(awk '/BEGIN ROLE GUARD/,/END ROLE GUARD/' "$ranger_file")"

    if [ "$scout_block" != "$ranger_block" ]; then
        echo "Scout and Ranger role guard blocks differ after generation:"
        diff <(echo "$scout_block") <(echo "$ranger_block")
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 7: Generator warns on unknown directive key (fixture test — hermetic)
# ---------------------------------------------------------------------------
@test "role-guard-gen.sh warns on unknown directive key" {
    local tmp_agents_dir
    tmp_agents_dir="$(mktemp -d)"

    # Create a fixture agent file with an unknown key
    cat > "$tmp_agents_dir/fixture-agent.md" <<'EOF'
## Role Guard — Strict Boundaries

<!-- BEGIN ROLE GUARD -->
<!-- ROLE_GUARD: nonexistent -->
<!-- END ROLE GUARD -->

---
EOF

    # Run generator pointed at the fixture dir
    local stderr_out
    stderr_out="$(bash "$GEN" --agents-dir "$tmp_agents_dir" 2>&1 >/dev/null)" || true

    # Generator must emit WARNING to stderr
    if ! echo "$stderr_out" | grep -q "WARNING"; then
        echo "Generator did not emit WARNING for unknown key. stderr was:"
        echo "$stderr_out"
        rm -rf "$tmp_agents_dir"
        return 1
    fi

    # Exit code must be 0 (warn, not fail)
    run bash "$GEN" --agents-dir "$tmp_agents_dir"
    rm -rf "$tmp_agents_dir"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 8: All 5 agent files contain BEGIN/END ROLE GUARD sentinels
# (RED until Step 7 migration completes)
# ---------------------------------------------------------------------------
@test "all 5 agent files contain BEGIN/END ROLE GUARD sentinels" {
    local agents=(
        "aristotle-deconstructor"
        "optimus-planner"
        "cyrus-tdd-engineer"
        "ranger-reviewer"
        "scout-reviewer"
    )
    local missing_begin=() missing_end=()

    for agent in "${agents[@]}"; do
        local agent_file="$AGENTS_DIR/${agent}.md"
        if ! grep -q "BEGIN ROLE GUARD" "$agent_file"; then
            missing_begin+=("$agent")
        fi
        if ! grep -q "END ROLE GUARD" "$agent_file"; then
            missing_end+=("$agent")
        fi
    done

    if [ "${#missing_begin[@]}" -gt 0 ] || [ "${#missing_end[@]}" -gt 0 ]; then
        [ "${#missing_begin[@]}" -gt 0 ] && echo "Missing BEGIN ROLE GUARD in: ${missing_begin[*]}"
        [ "${#missing_end[@]}" -gt 0 ] && echo "Missing END ROLE GUARD in: ${missing_end[*]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 9: Every agent file's ROLE_GUARD directive resolves to an existing fragment
# (RED until Step 7 migration completes)
# ---------------------------------------------------------------------------
@test "every agent file ROLE_GUARD directive resolves to an existing fragment" {
    local agents=(
        "aristotle-deconstructor"
        "optimus-planner"
        "cyrus-tdd-engineer"
        "ranger-reviewer"
        "scout-reviewer"
    )
    local unresolved=()

    for agent in "${agents[@]}"; do
        local agent_file="$AGENTS_DIR/${agent}.md"

        if ! grep -q "BEGIN ROLE GUARD" "$agent_file"; then
            unresolved+=("$agent (no sentinel — not yet migrated)")
            continue
        fi

        local key
        key="$(sed -n '/BEGIN ROLE GUARD/,/END ROLE GUARD/{
            /ROLE_GUARD:/{
                s/.*ROLE_GUARD:[[:space:]]*//
                s/[[:space:]]*-->//
                p
                q
            }
        }' "$agent_file")"

        if [ -z "$key" ]; then
            unresolved+=("$agent (no ROLE_GUARD directive)")
            continue
        fi

        if [ ! -f "$FRAGMENTS_DIR/${key}.md" ]; then
            unresolved+=("$agent (key='$key', fragment missing: ${key}.md)")
        fi
    done

    if [ "${#unresolved[@]}" -gt 0 ]; then
        echo "Unresolved ROLE_GUARD directives:"
        for item in "${unresolved[@]}"; do
            echo "  - $item"
        done
        return 1
    fi
}
