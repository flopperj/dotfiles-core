#!/usr/bin/env bats
# Tests for scripts/lib-overlays.sh
#
# RED phase: written before the library exists.
# Covers: concat_fragments, apply_overlay_fragment, apply_manifest.

load 'test_helper'

# Source the library once per test (not globally, so errors don't abort suite).
_load_lib() {
    source "$CORE_DIR/scripts/lib-overlays.sh"
}

# ---------------------------------------------------------------------------
# 0. Library exists
# ---------------------------------------------------------------------------

@test "lib-overlays.sh exists" {
    [ -f "$CORE_DIR/scripts/lib-overlays.sh" ]
}

# ---------------------------------------------------------------------------
# 1. concat_fragments — basic ordering and content
# ---------------------------------------------------------------------------

@test "concat_fragments: concatenates numbered fragments in lexical order" {
    _load_lib
    mkdir -p "$SCRATCH/frags"
    printf 'ALPHA\n' > "$SCRATCH/frags/10-alpha.md"
    printf 'BETA\n'  > "$SCRATCH/frags/20-beta.md"
    printf 'GAMMA\n' > "$SCRATCH/frags/30-gamma.md"
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/frags"
    grep -q 'ALPHA' "$SCRATCH/output.md"
    grep -q 'BETA'  "$SCRATCH/output.md"
    grep -q 'GAMMA' "$SCRATCH/output.md"
    # Ordering: ALPHA appears before BETA
    local a_line b_line
    a_line=$(grep -n 'ALPHA' "$SCRATCH/output.md" | cut -d: -f1)
    b_line=$(grep -n 'BETA'  "$SCRATCH/output.md" | cut -d: -f1)
    [ "$a_line" -lt "$b_line" ]
}

@test "concat_fragments: 10-* comes before 20-* regardless of file creation order" {
    _load_lib
    mkdir -p "$SCRATCH/frags"
    printf 'SECOND\n' > "$SCRATCH/frags/20-second.md"
    printf 'FIRST\n'  > "$SCRATCH/frags/10-first.md"
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/frags"
    local f_line s_line
    f_line=$(grep -n 'FIRST'  "$SCRATCH/output.md" | cut -d: -f1)
    s_line=$(grep -n 'SECOND' "$SCRATCH/output.md" | cut -d: -f1)
    [ "$f_line" -lt "$s_line" ]
}

@test "concat_fragments: overlay fragments appended after core fragments" {
    _load_lib
    mkdir -p "$SCRATCH/core" "$SCRATCH/overlay"
    printf 'CORE\n'    > "$SCRATCH/core/10-core.md"
    printf 'OVERLAY\n' > "$SCRATCH/overlay/50-ext.md"
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/core" "$SCRATCH/overlay"
    local c_line o_line
    c_line=$(grep -n 'CORE'    "$SCRATCH/output.md" | cut -d: -f1)
    o_line=$(grep -n 'OVERLAY' "$SCRATCH/output.md" | cut -d: -f1)
    [ "$c_line" -lt "$o_line" ]
}

@test "concat_fragments: empty overlay dir is a no-op (core only)" {
    _load_lib
    mkdir -p "$SCRATCH/core" "$SCRATCH/overlay"
    printf 'CORE\n' > "$SCRATCH/core/10-core.md"
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/core" "$SCRATCH/overlay"
    grep -q 'CORE' "$SCRATCH/output.md"
    [ "$(wc -l < "$SCRATCH/output.md")" -ge 1 ]
}

@test "concat_fragments: idempotent (re-running produces no diff)" {
    _load_lib
    mkdir -p "$SCRATCH/frags"
    printf 'HELLO\n' > "$SCRATCH/frags/10-hello.md"
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/frags"
    local first_checksum second_checksum
    first_checksum=$(md5 -q "$SCRATCH/output.md" 2>/dev/null || md5sum "$SCRATCH/output.md" | cut -d' ' -f1)
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/frags"
    second_checksum=$(md5 -q "$SCRATCH/output.md" 2>/dev/null || md5sum "$SCRATCH/output.md" | cut -d' ' -f1)
    [ "$first_checksum" = "$second_checksum" ]
}

@test "concat_fragments: missing fragment_dir exits non-zero" {
    _load_lib
    run concat_fragments "$SCRATCH/output.md" "$SCRATCH/does-not-exist"
    [ "$status" -ne 0 ]
}

@test "concat_fragments: only .md files are included (ignores .sh, .yaml, etc)" {
    _load_lib
    mkdir -p "$SCRATCH/frags"
    printf 'MDCONTENT\n' > "$SCRATCH/frags/10-good.md"
    printf 'SHCONTENT\n' > "$SCRATCH/frags/20-bad.sh"
    concat_fragments "$SCRATCH/output.md" "$SCRATCH/frags"
    grep -q 'MDCONTENT' "$SCRATCH/output.md"
    ! grep -q 'SHCONTENT' "$SCRATCH/output.md"
}

# ---------------------------------------------------------------------------
# 2. apply_overlay_fragment — sentinel insert
# ---------------------------------------------------------------------------

@test "apply_overlay_fragment: injects content between BEGIN/END sentinels" {
    _load_lib
    cat > "$SCRATCH/target.md" <<'EOF'
Before
<!-- BEGIN OVERLAY-FRAGMENT: my-ext -->
<!-- END OVERLAY-FRAGMENT: my-ext -->
After
EOF
    printf 'INJECTED CONTENT\n' > "$SCRATCH/fragment.md"
    apply_overlay_fragment "$SCRATCH/target.md" "$SCRATCH/fragment.md" "my-ext"
    grep -q 'INJECTED CONTENT' "$SCRATCH/target.md"
    # Sentinels still present
    grep -q 'BEGIN OVERLAY-FRAGMENT: my-ext' "$SCRATCH/target.md"
    grep -q 'END OVERLAY-FRAGMENT: my-ext'   "$SCRATCH/target.md"
}

@test "apply_overlay_fragment: idempotent (re-applying does not duplicate content)" {
    _load_lib
    cat > "$SCRATCH/target.md" <<'EOF'
<!-- BEGIN OVERLAY-FRAGMENT: ext -->
<!-- END OVERLAY-FRAGMENT: ext -->
EOF
    printf 'UNIQUE LINE\n' > "$SCRATCH/fragment.md"
    apply_overlay_fragment "$SCRATCH/target.md" "$SCRATCH/fragment.md" "ext"
    apply_overlay_fragment "$SCRATCH/target.md" "$SCRATCH/fragment.md" "ext"
    local count
    count=$(grep -c 'UNIQUE LINE' "$SCRATCH/target.md")
    [ "$count" -eq 1 ]
}

@test "apply_overlay_fragment: missing sentinel exits non-zero" {
    _load_lib
    printf 'No sentinel here\n' > "$SCRATCH/target.md"
    printf 'CONTENT\n' > "$SCRATCH/fragment.md"
    run apply_overlay_fragment "$SCRATCH/target.md" "$SCRATCH/fragment.md" "my-ext"
    [ "$status" -ne 0 ]
}

@test "apply_overlay_fragment: missing fragment file exits non-zero" {
    _load_lib
    cat > "$SCRATCH/target.md" <<'EOF'
<!-- BEGIN OVERLAY-FRAGMENT: ext -->
<!-- END OVERLAY-FRAGMENT: ext -->
EOF
    run apply_overlay_fragment "$SCRATCH/target.md" "$SCRATCH/no-such-fragment.md" "ext"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 3. apply_manifest — manifest parsing and application
# ---------------------------------------------------------------------------

@test "apply_manifest: applies a registered fragment to target file" {
    _load_lib
    # Create a target with sentinels
    mkdir -p "$SCRATCH/skills/myskill"
    cat > "$SCRATCH/skills/myskill/SKILL.md" <<'EOF'
# MySkill
<!-- BEGIN OVERLAY-FRAGMENT: test-ext -->
<!-- END OVERLAY-FRAGMENT: test-ext -->
EOF
    # Create fragment source
    mkdir -p "$SCRATCH/skill-fragments/myskill"
    printf 'MANIFEST INJECTED\n' > "$SCRATCH/skill-fragments/myskill/test-ext.md"
    # Create manifest
    cat > "$SCRATCH/overlay-fragments.yaml" <<EOF
fragments:
  - name: test-ext
    target: $SCRATCH/skills/myskill/SKILL.md
    source: $SCRATCH/skill-fragments/myskill/test-ext.md
EOF
    apply_manifest "$SCRATCH/overlay-fragments.yaml"
    grep -q 'MANIFEST INJECTED' "$SCRATCH/skills/myskill/SKILL.md"
}

@test "apply_manifest: errors clearly on missing source file" {
    _load_lib
    mkdir -p "$SCRATCH/skills/myskill"
    cat > "$SCRATCH/skills/myskill/SKILL.md" <<'EOF'
<!-- BEGIN OVERLAY-FRAGMENT: ghost-ext -->
<!-- END OVERLAY-FRAGMENT: ghost-ext -->
EOF
    cat > "$SCRATCH/overlay-fragments.yaml" <<EOF
fragments:
  - name: ghost-ext
    target: $SCRATCH/skills/myskill/SKILL.md
    source: $SCRATCH/no-such-file.md
EOF
    run apply_manifest "$SCRATCH/overlay-fragments.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ghost-ext"* ]] || [[ "$output" == *"no-such-file"* ]]
}

@test "apply_manifest: empty fragments list is a no-op (exit 0)" {
    _load_lib
    cat > "$SCRATCH/overlay-fragments.yaml" <<'EOF'
fragments: []
EOF
    run apply_manifest "$SCRATCH/overlay-fragments.yaml"
    [ "$status" -eq 0 ]
}

@test "apply_manifest: missing manifest file exits non-zero" {
    _load_lib
    run apply_manifest "$SCRATCH/no-manifest.yaml"
    [ "$status" -ne 0 ]
}
