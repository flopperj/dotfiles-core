#!/usr/bin/env bats
# Layout contract between dotfiles-core's installer and overlays.
#
# Two layouts (PROTOCOL.md § Path ownership under ~/.claude):
#   local — repo in its own directory; core symlinks into ~/.claude/.
#   yadm  — overlay checked out straight into $HOME (yadm on a cloud workspace); the
#           overlay's tracked files are real entries under ~/.claude/ and core
#           must merge around them, never back them up or replace them.

load 'test_helper'

setup() {
    # Never start a real Homebrew install from a test; tests/install-brew.bats covers it.
    export DOTFILES_SKIP_BREW=1
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    TEST_HOME="$SCRATCH/home"
    mkdir -p "$TEST_HOME"
    export _SKIP_PRECOMMIT_INSTALL=1
    # tests/stubs/claude answers the installer's plugin step offline; see the
    # header of that file.
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

teardown() {
    rm -rf "$SCRATCH"
}

_run_install() {
    HOME="$TEST_HOME" run bash "$CORE_DIR/install.sh" "$@"
}

# An overlay-style $HOME in the yadm layout: .gitmodules declares the core
# submodule, the overlay owns fragment dirs, context, tokens, an eval script,
# an overlay-only skill and an out-of-date copy of one core skill.
_make_yadm_home() {
    printf '[submodule ".claude/dotfiles-core"]\n\tpath = .claude/dotfiles-core\n\turl = https://example.invalid/dotfiles-core.git\n' > "$TEST_HOME/.gitmodules"
    mkdir -p "$TEST_HOME/.claude/_shared/claude-md.d" "$TEST_HOME/.claude/_shared/agents-md.d"
    echo "# overlay routing rows" > "$TEST_HOME/.claude/_shared/claude-md.d/60-routing.md"
    echo "# overlay agents fragment" > "$TEST_HOME/.claude/_shared/agents-md.d/45-fallback.md"
    echo "## Jira fallback" > "$TEST_HOME/.claude/_shared/overlay-context.md"
    echo "xyzzy-corp" > "$TEST_HOME/.claude/_shared/leakage-tokens.txt"
    mkdir -p "$TEST_HOME/.claude/evals/scripts"
    echo "echo overlay eval" > "$TEST_HOME/.claude/evals/scripts/x.sh"
    mkdir -p "$TEST_HOME/.claude/skills/overlay-only-skill"
    echo "# overlay-only" > "$TEST_HOME/.claude/skills/overlay-only-skill/SKILL.md"
    mkdir -p "$TEST_HOME/.claude/skills/to-prd"
    echo "# stale overlay copy of a core skill" > "$TEST_HOME/.claude/skills/to-prd/SKILL.md"
}

# Snapshot every overlay-owned file as "path<TAB>sha" for a byte-for-byte check.
_overlay_snapshot() {
    ( cd "$TEST_HOME" && find .claude/_shared/claude-md.d .claude/_shared/agents-md.d \
        .claude/_shared/overlay-context.md .claude/_shared/leakage-tokens.txt \
        .claude/evals/scripts/x.sh .claude/skills/overlay-only-skill .claude/skills/to-prd \
        -type f -print0 | sort -z | xargs -0 shasum )
}

# Sibling-shaped backups in the directories the host scans. The backup store
# (~/.claude/.backups) is excluded: relocated entries keep their names there.
_bak_count() {
    find "$TEST_HOME/.claude" -path "$TEST_HOME/.claude/.backups" -prune -o -name '*.bak.*' -print 2>/dev/null | wc -l | tr -d ' '
}

# A throwaway copy of core (only what install.sh reads), so a destructive
# installer bug damages the copy and not this checkout.
_make_scratch_core() {
    mkdir -p "$SCRATCH/core"
    cp -R "$CORE_DIR/.claude" "$CORE_DIR/scripts" "$CORE_DIR/_shared" "$SCRATCH/core/"
    cp "$CORE_DIR/install.sh" "$CORE_DIR/plugins.txt" "$SCRATCH/core/"
}

# Every path under a core .claude tree plus a checksum of every regular file,
# for a before/after comparison. agent-memory is skipped: the seeding step
# legitimately writes there when ~/.claude resolves into the checkout.
_core_tree_snapshot() {
    ( cd "$1" && find . -path ./agent-memory -prune -o -print | sort
      find . -path ./agent-memory -prune -o -type f -print0 | sort -z | xargs -0 shasum )
}

# ---------------------------------------------------------------------------
# _detect_layout
# ---------------------------------------------------------------------------

@test "_detect_layout: local when nothing marks the home as a yadm tree" {
    run bash -c "HOME='$TEST_HOME'; source '$CORE_DIR/scripts/_lib.sh'; _detect_layout"
    [ "$output" = "local" ]
}

@test "_detect_layout: yadm when \$HOME/.gitmodules declares dotfiles-core" {
    _make_yadm_home
    run bash -c "HOME='$TEST_HOME'; source '$CORE_DIR/scripts/_lib.sh'; _detect_layout"
    [ "$output" = "yadm" ]
}

@test "_detect_layout: DOTFILES_LAYOUT override wins" {
    _make_yadm_home
    run bash -c "HOME='$TEST_HOME'; DOTFILES_LAYOUT=local; source '$CORE_DIR/scripts/_lib.sh'; _detect_layout"
    [ "$output" = "local" ]
}

# ---------------------------------------------------------------------------
# yadm layout: acceptance criteria from the cloud-workspace incident
# ---------------------------------------------------------------------------

@test "yadm layout: install twice preserves overlay files byte-for-byte and links core files" {
    _make_yadm_home
    local before after
    before="$(_overlay_snapshot)"

    _run_install
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "layout: yadm"
    _run_install
    [ "$status" -eq 0 ]

    after="$(_overlay_snapshot)"
    [ "$before" = "$after" ]

    # overlay-owned entries are still real files/dirs, not symlinks
    [ ! -L "$TEST_HOME/.claude/_shared/claude-md.d" ]
    [ ! -L "$TEST_HOME/.claude/_shared/overlay-context.md" ]
    [ ! -L "$TEST_HOME/.claude/evals/scripts" ]
    [ ! -L "$TEST_HOME/.claude/evals/scripts/x.sh" ]
    [ ! -L "$TEST_HOME/.claude/skills/overlay-only-skill" ]
    [ ! -L "$TEST_HOME/.claude/skills/to-prd" ]

    # core entries are linked beside them
    [ -L "$TEST_HOME/.claude/_shared/role-guards" ]
    [ -L "$TEST_HOME/.claude/_shared/agent-turn-cap-warning.md" ]
    [ -L "$TEST_HOME/.claude/evals/scripts/emit-metric.sh" ]
    [ -L "$TEST_HOME/.claude/evals/schemas" ]
    [ -L "$TEST_HOME/.claude/skills/forge" ]
    [ -L "$TEST_HOME/.claude/agents/optimus-planner.md" ]
}

@test "yadm layout: zero *.bak.* entries and no backup store after two installs" {
    _make_yadm_home
    _run_install
    _run_install
    [ "$status" -eq 0 ]
    [ "$(_bak_count)" = "0" ]
    [ ! -e "$TEST_HOME/.claude/.backups" ]
}

@test "yadm layout: an overlay copy that differs from core is kept and flagged" {
    _make_yadm_home
    _run_install
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "WARNING: $TEST_HOME/.claude/skills/to-prd is overlay-owned and differs from core"
    grep -q "stale overlay copy" "$TEST_HOME/.claude/skills/to-prd/SKILL.md"
}

@test "yadm layout: second install is a no-op (no WARNING, no Backed up, no Removed)" {
    _make_yadm_home
    _run_install
    # Replace the stale copy with an identical one so nothing is left to warn about.
    rm -rf "$TEST_HOME/.claude/skills/to-prd"
    cp -R "$CORE_DIR/.claude/skills/to-prd" "$TEST_HOME/.claude/skills/to-prd"
    _run_install
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING"* ]] || return 1
    [[ "$output" != *"Backed up"* ]] || return 1
    [[ "$output" != *"Removed stale"* ]] || return 1
    echo "$output" | grep -q "Kept overlay-owned entry (identical to core): $TEST_HOME/.claude/skills/to-prd"
}

@test "yadm layout: install --check is clean and reports overlay-owned entries as ok" {
    _make_yadm_home
    _run_install
    _run_install --check
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "layout: yadm"
    echo "$output" | grep -q "ok    to-prd (overlay-owned, yadm layout)"
    echo "$output" | grep -q "ok    _shared/role-guards"
    echo "$output" | grep -q "ok    evals/scripts/emit-metric.sh"
}

# ---------------------------------------------------------------------------
# local layout: collisions are backed up out of scanned dirs, or replaced
# ---------------------------------------------------------------------------

@test "local layout: a differing real skill dir is moved to ~/.claude/.backups, not a sibling .bak" {
    mkdir -p "$TEST_HOME/.claude/skills/forge"
    echo "# not core" > "$TEST_HOME/.claude/skills/forge/SKILL.md"
    HOME="$TEST_HOME" _BACKUP_SUFFIX_OVERRIDE=forced run bash "$CORE_DIR/install.sh"
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/skills/forge" ]
    [ "$(_bak_count)" = "0" ]
    [ -f "$TEST_HOME/.claude/.backups/forced/.claude/skills/forge/SKILL.md" ]
    grep -q "not core" "$TEST_HOME/.claude/.backups/forced/.claude/skills/forge/SKILL.md"
}

@test "local layout: a real skill dir identical to core is replaced without any backup" {
    mkdir -p "$TEST_HOME/.claude/skills"
    cp -R "$CORE_DIR/.claude/skills/forge" "$TEST_HOME/.claude/skills/forge"
    _run_install
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/skills/forge" ]
    [ ! -e "$TEST_HOME/.claude/.backups" ]
    [[ "$output" != *"Backed up"* ]] || return 1
}

@test "local layout: install --check is clean and second install is a no-op" {
    _run_install
    _run_install
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING"* ]] || return 1
    _run_install --check
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "layout: local"
}

@test "local layout: --check flags a whole-directory _shared symlink as STALE" {
    _run_install
    rm -rf "$TEST_HOME/.claude/_shared"
    ln -s "$CORE_DIR/.claude/_shared" "$TEST_HOME/.claude/_shared"
    _run_install --check
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "STALE _shared is a whole-directory symlink"
}

# ---------------------------------------------------------------------------
# merged directories: stale-link cleanup is scoped to core targets
# ---------------------------------------------------------------------------

@test "merged _shared: a dead symlink pointing outside core is left for its owner" {
    mkdir -p "$TEST_HOME/.claude/_shared"
    ln -s "$SCRATCH/overlay/gone.md" "$TEST_HOME/.claude/_shared/overlay-owned-dead.md"
    ln -s "$CORE_DIR/.claude/_shared/no-longer-shipped.md" "$TEST_HOME/.claude/_shared/no-longer-shipped.md"
    _run_install
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/_shared/overlay-owned-dead.md" ]
    [ ! -L "$TEST_HOME/.claude/_shared/no-longer-shipped.md" ]
    echo "$output" | grep -q "Removed stale symlink: no-longer-shipped.md"
}

# ---------------------------------------------------------------------------
# legacy sibling backups (pre-v1.21.0 shape) are moved out of scanned dirs
# ---------------------------------------------------------------------------

@test "legacy *.bak.* siblings in skills/agents and _shared/evals backups move to the backup store" {
    mkdir -p "$TEST_HOME/.claude/skills/forge.bak.1700000000" "$TEST_HOME/.claude/agents" \
             "$TEST_HOME/.claude/_shared.bak.1700000000/claude-md.d" "$TEST_HOME/.claude/evals.bak.1700000000/scripts"
    echo "# old forge" > "$TEST_HOME/.claude/skills/forge.bak.1700000000/SKILL.md"
    echo "old agent" > "$TEST_HOME/.claude/agents/optimus-planner.md.bak.1700000000"
    echo "# overlay fragment" > "$TEST_HOME/.claude/_shared.bak.1700000000/claude-md.d/60-routing.md"
    echo "echo x" > "$TEST_HOME/.claude/evals.bak.1700000000/scripts/x.sh"

    HOME="$TEST_HOME" _BACKUP_SUFFIX_OVERRIDE=forced run bash "$CORE_DIR/install.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Moved 4 legacy backup(s)"
    [ "$(_bak_count)" = "0" ]
    local store="$TEST_HOME/.claude/.backups/legacy-forced/.claude"
    grep -q "old forge" "$store/skills/forge.bak.1700000000/SKILL.md"
    grep -q "old agent" "$store/agents/optimus-planner.md.bak.1700000000"
    grep -q "overlay fragment" "$store/_shared.bak.1700000000/claude-md.d/60-routing.md"
    [ -f "$store/evals.bak.1700000000/scripts/x.sh" ]
    # the live entries are installed normally
    [ -L "$TEST_HOME/.claude/skills/forge" ]
    [ -L "$TEST_HOME/.claude/agents/optimus-planner.md" ]
}

@test "legacy relocation is a no-op when nothing matches" {
    _run_install
    [ "$status" -eq 0 ]
    [[ "$output" != *"legacy backup"* ]] || return 1
    [ ! -e "$TEST_HOME/.claude/.backups" ]
}

# ---------------------------------------------------------------------------
# backup retention
# ---------------------------------------------------------------------------

@test "_prune_backups removes backup sets older than the retention window" {
    mkdir -p "$TEST_HOME/.claude/.backups/1000000000/.claude/skills/old" \
             "$TEST_HOME/.claude/.backups/fresh/.claude/skills/new"
    touch -t 200001010000 "$TEST_HOME/.claude/.backups/1000000000"
    _run_install
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Pruned backup set: 1000000000"
    [ ! -e "$TEST_HOME/.claude/.backups/1000000000" ]
    [ -d "$TEST_HOME/.claude/.backups/fresh" ]
}

# ---------------------------------------------------------------------------
# same-object guard: a destination that *is* the core file (through a
# symlinked ~/.claude or ~/.claude/skills) must never be removed or backed up
# ---------------------------------------------------------------------------

@test "_link_dir: a destination that is the source itself (via a symlinked ~/.claude) is left in place" {
    mkdir -p "$SCRATCH/core/.claude/skills/demo"
    echo "# demo" > "$SCRATCH/core/.claude/skills/demo/SKILL.md"
    ln -s "$SCRATCH/core/.claude" "$TEST_HOME/.claude"
    run bash -c "HOME='$TEST_HOME'; DOTFILES_LAYOUT=local; source '$CORE_DIR/scripts/lib-core-symlinks.sh'; _link_dir '$SCRATCH/core/.claude/skills/demo' '$TEST_HOME/.claude/skills/demo'"
    [ "$status" -eq 0 ]
    [ ! -L "$SCRATCH/core/.claude/skills/demo" ]
    [ -f "$SCRATCH/core/.claude/skills/demo/SKILL.md" ]
    [[ "$output" == *"already the core file itself"* ]] || return 1
    [[ "$output" != *"Backed up"* ]] || return 1
}

@test "_link_entry: a missing destination whose parent resolves into the core checkout is not created" {
    mkdir -p "$SCRATCH/core/.claude"
    echo "# rendered" > "$SCRATCH/core/.claude/CLAUDE.md.generated"
    ln -s "$SCRATCH/core/.claude" "$TEST_HOME/.claude"
    run bash -c "HOME='$TEST_HOME'; DOTFILES_LAYOUT=local; source '$CORE_DIR/scripts/lib-core-symlinks.sh'; _link_entry '$SCRATCH/core/.claude/CLAUDE.md.generated' '$TEST_HOME/.claude/CLAUDE.md' '$SCRATCH/core'"
    [ "$status" -eq 0 ]
    [ ! -e "$SCRATCH/core/.claude/CLAUDE.md" ]
    [ ! -L "$SCRATCH/core/.claude/CLAUDE.md" ]
    [[ "$output" == *"inside the core checkout"* ]] || return 1
}

@test "same-object guard: ~/.claude symlinked into the core checkout leaves every core file in place" {
    _make_scratch_core
    ln -s "$SCRATCH/core/.claude" "$TEST_HOME/.claude"
    local before after
    before="$(_core_tree_snapshot "$SCRATCH/core/.claude")"

    HOME="$TEST_HOME" run bash "$SCRATCH/core/install.sh"
    [ "$status" -eq 0 ]

    after="$(_core_tree_snapshot "$SCRATCH/core/.claude")"
    [ "$before" = "$after" ]
    [ ! -L "$SCRATCH/core/.claude/skills/forge" ]
    [ -f "$SCRATCH/core/.claude/skills/forge/SKILL.md" ]
    [ ! -L "$SCRATCH/core/.claude/agents/optimus-planner.md" ]
    [ ! -L "$SCRATCH/core/.claude/_shared/role-guards" ]
    [ ! -L "$SCRATCH/core/.claude/evals/scripts" ]
    [ ! -e "$SCRATCH/core/.claude/CLAUDE.md" ]
    [ ! -e "$SCRATCH/core/.claude/.backups" ]
    [[ "$output" == *"already the core file itself"* ]] || return 1
    [[ "$output" == *"already the core directory itself"* ]] || return 1
    [[ "$output" != *"Backed up"* ]] || return 1
    [[ "$output" != *"WARNING"* ]] || return 1
}

@test "same-object guard: ~/.claude/skills symlinked into core's skills dir is left alone and the rest installs" {
    _make_scratch_core
    mkdir -p "$TEST_HOME/.claude"
    ln -s "$SCRATCH/core/.claude/skills" "$TEST_HOME/.claude/skills"
    HOME="$TEST_HOME" run bash "$SCRATCH/core/install.sh"
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/skills" ]
    [ ! -L "$SCRATCH/core/.claude/skills/forge" ]
    [ -f "$SCRATCH/core/.claude/skills/forge/SKILL.md" ]
    [ -L "$TEST_HOME/.claude/agents/optimus-planner.md" ]
    [ -L "$TEST_HOME/.claude/_shared/role-guards" ]
    [[ "$output" != *"Backed up"* ]] || return 1
}

# ---------------------------------------------------------------------------
# merge roots: only a whole-directory symlink into core is migrated; anything
# else at ~/.claude/_shared or ~/.claude/evals is not core's to touch
# ---------------------------------------------------------------------------

@test "merged _shared: a whole-directory symlink into the core checkout is migrated silently" {
    mkdir -p "$TEST_HOME/.claude"
    ln -s "$CORE_DIR/.claude/_shared" "$TEST_HOME/.claude/_shared"
    _run_install
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_HOME/.claude/_shared" ]
    [ -d "$TEST_HOME/.claude/_shared" ]
    [ -L "$TEST_HOME/.claude/_shared/role-guards" ]
    [[ "$output" != *"WARNING"* ]] || return 1
}

@test "merged _shared: a whole-directory symlink pointing outside core is left alone with a WARNING; --check reports COLLISION" {
    mkdir -p "$SCRATCH/elsewhere" "$TEST_HOME/.claude"
    echo "theirs" > "$SCRATCH/elsewhere/theirs.md"
    ln -s "$SCRATCH/elsewhere" "$TEST_HOME/.claude/_shared"
    _run_install
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/_shared" ]
    [ "$(readlink "$TEST_HOME/.claude/_shared")" = "$SCRATCH/elsewhere" ]
    [ -f "$SCRATCH/elsewhere/theirs.md" ]
    [ ! -e "$SCRATCH/elsewhere/role-guards" ]
    [[ "$output" == *"WARNING: $TEST_HOME/.claude/_shared is a symlink to $SCRATCH/elsewhere"* ]] || return 1
    [ -L "$TEST_HOME/.claude/evals/scripts" ]

    _run_install --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"COLLISION _shared (symlink to $SCRATCH/elsewhere, not managed by core)"* ]] || return 1
}

@test "_link_dir on ~/.claude/_shared or ~/.claude/evals never collapses the merged directory" {
    mkdir -p "$TEST_HOME/.claude/_shared/claude-md.d" "$TEST_HOME/.claude/evals/scripts"
    echo "# overlay rows" > "$TEST_HOME/.claude/_shared/claude-md.d/60-routing.md"
    echo "echo overlay eval" > "$TEST_HOME/.claude/evals/scripts/x.sh"
    run bash -c "HOME='$TEST_HOME'; DOTFILES_LAYOUT=local; source '$CORE_DIR/scripts/lib-core-symlinks.sh'; _link_dir '$CORE_DIR/.claude/_shared' '$TEST_HOME/.claude/_shared'; _link_dir '$CORE_DIR/.claude/evals' '$TEST_HOME/.claude/evals'"
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_HOME/.claude/_shared" ]
    [ ! -L "$TEST_HOME/.claude/evals" ]
    [ -f "$TEST_HOME/.claude/_shared/claude-md.d/60-routing.md" ]
    [ -f "$TEST_HOME/.claude/evals/scripts/x.sh" ]
    [ ! -e "$TEST_HOME/.claude/.backups" ]
    [[ "$output" == *"Left in place"*"_shared"* ]] || return 1
    [[ "$output" == *"Left in place"*"evals"* ]] || return 1
}

# ---------------------------------------------------------------------------
# backup retention: only installer-created set names are pruned
# ---------------------------------------------------------------------------

@test "_prune_backups leaves aged directories that are not installer-created sets" {
    local root="$TEST_HOME/.claude/.backups"
    mkdir -p "$root/keep-me/x" "$root/1000000000.1/x" "$root/legacy-1000000000/x"
    touch -t 200001010000 "$root/keep-me" "$root/1000000000.1" "$root/legacy-1000000000"
    _run_install
    [ "$status" -eq 0 ]
    [ -d "$root/keep-me" ]
    [ ! -e "$root/1000000000.1" ]
    [ ! -e "$root/legacy-1000000000" ]
    [[ "$output" == *"Pruned backup set: 1000000000.1"* ]] || return 1
    [[ "$output" == *"Pruned backup set: legacy-1000000000"* ]] || return 1
    [[ "$output" != *"Pruned backup set: keep-me"* ]] || return 1
}

@test "DOTFILES_BACKUP_RETENTION_DAYS=never disables pruning" {
    local root="$TEST_HOME/.claude/.backups"
    mkdir -p "$root/1000000000/x"
    touch -t 200001010000 "$root/1000000000"
    HOME="$TEST_HOME" DOTFILES_BACKUP_RETENTION_DAYS=never run bash "$CORE_DIR/install.sh"
    [ "$status" -eq 0 ]
    [ -d "$root/1000000000" ]
    [[ "$output" != *"Pruned"* ]] || return 1
}

@test "_prune_backups: 0 and off disable pruning; another non-numeric value warns and prunes nothing" {
    local root="$TEST_HOME/.claude/.backups"
    mkdir -p "$root/1000000000/x"
    touch -t 200001010000 "$root/1000000000"
    local v
    for v in 0 off; do
        run bash -c "HOME='$TEST_HOME'; DOTFILES_BACKUP_RETENTION_DAYS=$v; source '$CORE_DIR/scripts/lib-core-symlinks.sh'; _prune_backups"
        [ "$status" -eq 0 ]
        [ -d "$root/1000000000" ]
        [ -z "$output" ]
    done
    run bash -c "HOME='$TEST_HOME'; DOTFILES_BACKUP_RETENTION_DAYS=soon; source '$CORE_DIR/scripts/lib-core-symlinks.sh'; _prune_backups"
    [ "$status" -eq 0 ]
    [ -d "$root/1000000000" ]
    [[ "$output" == *"WARNING"*"DOTFILES_BACKUP_RETENTION_DAYS"* ]] || return 1
}
