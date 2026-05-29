#!/usr/bin/env bats
# Step 3 — RED-phase tests for _iter_core_skill_dirs and doubled-slash glob fix.
# Written before implementation; all tests must fail first.

load 'test_helper'

# Path to the shared lib
LIB_SH="$CORE_DIR/scripts/_lib.sh"

setup() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH

    # Build a fixture core_dir with three skill subdirs and one non-skill file
    FIXTURE_CORE="$SCRATCH/fixture_core"
    mkdir -p "$FIXTURE_CORE/.claude/skills/alpha"
    mkdir -p "$FIXTURE_CORE/.claude/skills/beta"
    mkdir -p "$FIXTURE_CORE/.claude/skills/gamma"
    # A plain file (not a directory) inside skills/ — must be skipped
    touch "$FIXTURE_CORE/.claude/skills/not-a-skill.txt"
}

teardown() {
    rm -rf "$SCRATCH"
}

# ---------------------------------------------------------------------------
# 1. Helper exists in _lib.sh
# ---------------------------------------------------------------------------

@test "_iter_core_skill_dirs function is defined in _lib.sh" {
    # shellcheck source=/dev/null
    source "$LIB_SH"
    declare -f _iter_core_skill_dirs > /dev/null
}

# ---------------------------------------------------------------------------
# 2. Emits exactly the three skill directories
# ---------------------------------------------------------------------------

@test "_iter_core_skill_dirs emits exactly three skill dirs from fixture" {
    # shellcheck source=/dev/null
    source "$LIB_SH"
    count=0
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        count=$((count + 1))
    done < <(_iter_core_skill_dirs "$FIXTURE_CORE")
    [ "$count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# 3. No doubled slashes in emitted paths
# ---------------------------------------------------------------------------

@test "_iter_core_skill_dirs emits paths without doubled slashes" {
    # shellcheck source=/dev/null
    source "$LIB_SH"
    while IFS= read -r d; do
        # A doubled slash would look like "skills//alpha/" or "skills//" etc.
        if printf '%s' "$d" | grep -q '//'; then
            echo "FAIL: doubled slash in path: $d"
            return 1
        fi
    done < <(_iter_core_skill_dirs "$FIXTURE_CORE")
}

# ---------------------------------------------------------------------------
# 4. Non-directory entries are skipped
# ---------------------------------------------------------------------------

@test "_iter_core_skill_dirs skips non-directory entries in skills/" {
    # shellcheck source=/dev/null
    source "$LIB_SH"
    while IFS= read -r d; do
        if [[ "$d" == *"not-a-skill.txt"* ]]; then
            echo "FAIL: plain file was emitted: $d"
            return 1
        fi
    done < <(_iter_core_skill_dirs "$FIXTURE_CORE")
}

# ---------------------------------------------------------------------------
# 5. lib-core-symlinks.sh call site: no doubled slash at line 94
# ---------------------------------------------------------------------------

@test "lib-core-symlinks.sh skills glob has no doubled slash" {
    # The bug was a DIRECTORY glob: "$core_dir/.claude/skills/"/*/ — the trailing
    # slash inside the quotes, followed by /*/, yielded a doubled slash (.../skills//foo/).
    # Fixed form:  "$core_dir/.claude/skills"/*/ — quote ends at the path boundary,
    # or the helper (while IFS=... _iter_core_skill_dirs).
    local symlinks_sh="$CORE_DIR/scripts/lib-core-symlinks.sh"
    [ -f "$symlinks_sh" ]
    # Reject only the directory-glob bug shape: the quoted prefix ending in
    # skills/" immediately followed by a directory glob (/, *, then /). A benign
    # FILE glob like "$core_dir/.claude/skills/"*.md is correct (single slash,
    # no doubled separator) and must NOT trip this guard.
    ! grep -qE '"\$core_dir/\.claude/skills/"/?\*?/' "$symlinks_sh"
}

# ---------------------------------------------------------------------------
# 6. core-check.sh call site: no doubled slash at line 36
# ---------------------------------------------------------------------------

@test "core-check.sh skills glob has no doubled slash" {
    local check_sh="$CORE_DIR/scripts/core-check.sh"
    [ -f "$check_sh" ]
    # Same directory-glob bug shape as the lib-core-symlinks test above; a benign
    # file glob (skills/"*.md) is correct and must not trip this guard.
    ! grep -qE '"\$core_dir/\.claude/skills/"/?\*?/' "$check_sh"
}
