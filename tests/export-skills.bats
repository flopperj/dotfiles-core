#!/usr/bin/env bats
# Tests for scripts/export-skills.sh, scripts/check-portable-refs.sh and the
# scripts/templates/install-agent.sh template.
#
# The exporter renders portable copies of the reasoning-pipeline skills into a
# plain skills repo. Every test renders into $SCRATCH (never the real tree) and
# asserts on the rendered output: idempotency, self-containment, preserved
# agent frontmatter, and the inserted portable sections.
#
# bash 3.2 note: assertions are &&-chained into each test's final command, and
# every extraction is guarded with a non-empty check so a mistyped pattern
# cannot produce a vacuous pass.
#
# Run with: bats tests/export-skills.bats

load 'test_helper'

EXPORT="$DOTFILES_DIR/scripts/export-skills.sh"
REFS="$DOTFILES_DIR/scripts/check-portable-refs.sh"
INSTALL_TPL="$DOTFILES_DIR/scripts/templates/install-agent.sh"

EXPORT_SET="aristotle-deconstructor optimus-planner cyrus-tdd-engineer forge grill-me to-prd code-auditor scout-reviewer ranger-reviewer"
AGENT_SET="aristotle-deconstructor optimus-planner cyrus-tdd-engineer scout-reviewer ranger-reviewer"

# Seed a target repo with an unmanaged skill and a README carrying hand-written
# content, then render into it. Sets TARGET.
_render_target() {
    TARGET="$SCRATCH/target"
    mkdir -p "$TARGET/skills/hand-written-skill"
    printf -- '---\nname: hand-written-skill\ndescription: untouched\n---\n' > "$TARGET/skills/hand-written-skill/SKILL.md"
    printf '# Team Skills\n\nIntro prose kept verbatim.\n' > "$TARGET/README.md"
    bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' "$@"
}

# --- CLI surface ------------------------------------------------------------

@test "export-skills: executable, --help exits 0, missing target exits 2" {
    [ -x "$EXPORT" ]
    run bash "$EXPORT" --help
    [ "$status" -eq 0 ] && [[ "$output" == *"Usage:"* ]]
    run bash "$EXPORT"
    [ "$status" -eq 2 ]
    run bash "$EXPORT" "$SCRATCH/does-not-exist"
    [ "$status" -eq 2 ]
}

@test "check-portable-refs: executable, usage exits 2 without a dir" {
    [ -x "$REFS" ]
    run bash "$REFS"
    [ "$status" -eq 2 ]
}

# --- Render shape -------------------------------------------------------------

@test "render: exactly one SKILL.md per exported skill, none nested, unmanaged skill untouched" {
    _render_target
    local n
    n="$(find "$TARGET/skills" -name SKILL.md | wc -l | tr -d ' ')"
    # 9 exported + 1 unmanaged
    [ "$n" = "10" ]
    for s in $EXPORT_SET; do
        [ "$(find "$TARGET/skills/$s" -name SKILL.md | wc -l | tr -d ' ')" = "1" ] || return 1
    done
    grep -q '^description: untouched$' "$TARGET/skills/hand-written-skill/SKILL.md"
}

@test "render: every SKILL.md keeps name/description/user-invocable and gains a metadata block" {
    _render_target
    for s in $EXPORT_SET; do
        f="$TARGET/skills/$s/SKILL.md"
        head -1 "$f" | grep -q '^---$' \
            && grep -q "^name: $s$" "$f" \
            && grep -q '^description:' "$f" \
            && grep -q '^user-invocable:' "$f" \
            && grep -q '^metadata:$' "$f" \
            && grep -q '^  bundle: reasoning-pipeline$' "$f" \
            && grep -q '^  owner_team: test-team$' "$f" \
            && grep -q '^  owner_slack: "#test-chan"$' "$f" \
            && grep -q '^  tags:$' "$f" || { echo "frontmatter incomplete: $s"; return 1; }
        # metadata sits inside the frontmatter (before the closing ---)
        [ "$(awk 'NR>1 && /^---$/ {print NR; exit}' "$f")" -gt "$(grep -n '^metadata:$' "$f" | cut -d: -f1)" ] \
            || { echo "metadata outside frontmatter: $s"; return 1; }
    done
}

@test "render: owner flags omitted → no owner_* keys" {
    TARGET="$SCRATCH/t2"; mkdir -p "$TARGET"
    bash "$EXPORT" "$TARGET"
    ! grep -rq 'owner_team\|owner_slack' "$TARGET/skills"
    grep -q '^  domain: engineering-workflow$' "$TARGET/skills/forge/SKILL.md"
}

@test "render: parity-ignore frontmatter comments are removed" {
    _render_target
    ! grep -rq 'parity-ignore' "$TARGET/skills"
}

# --- Idempotency / --check -----------------------------------------------------

@test "check: clean after render; drift after mutation; drift when a skill dir is missing" {
    _render_target
    run bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' --check
    [ "$status" -eq 0 ] && [[ "$output" == *"up to date"* ]]

    echo "tampered" >> "$TARGET/skills/forge/SKILL.md"
    run bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' --check
    [ "$status" -eq 1 ] && [[ "$output" == *"DRIFT  skills/forge"* ]]

    rm -rf "$TARGET/skills/to-prd"
    run bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' --check
    [ "$status" -eq 1 ] && [[ "$output" == *"skills/to-prd — missing"* ]]
}

@test "check: metadata flags are part of the rendered state (different flags = drift)" {
    _render_target
    run bash "$EXPORT" "$TARGET" --owner-team other-team --check
    [ "$status" -eq 1 ]
}

@test "render twice: byte-identical (idempotent)" {
    _render_target
    cp -R "$TARGET" "$SCRATCH/first"
    bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan'
    diff -r "$SCRATCH/first" "$TARGET"
}

# --- Self-containment ---------------------------------------------------------

@test "portable refs: rendered bundle passes check-portable-refs" {
    _render_target
    run bash "$REFS" "$TARGET/skills" $EXPORT_SET
    [ "$status" -eq 0 ] && [[ "$output" == *"clean (9 skills)"* ]]
}

@test "portable refs: checker catches a core-only path and a dangling skill reference" {
    _render_target
    printf '\nSee `~/.claude/_shared/agent-turn-cap-warning.md` and run /not-a-bundle-skill.\n' >> "$TARGET/skills/to-prd/SKILL.md"
    run bash "$REFS" "$TARGET/skills" to-prd
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"forbidden reference"* ]] \
        && [[ "$output" == *"unresolved skill reference /not-a-bundle-skill"* ]]
}

@test "portable refs: no export markers, metrics plumbing, or Cursor hook notes survive" {
    _render_target
    ! grep -rqE 'CORE-ONLY|PORTABLE-ONLY|metrics-emit|emit-metric\.sh|\.cursor/hooks\.json|managed via dotfiles|not a dotfiles skill' "$TARGET/skills"
    # PORTABLE-ONLY bodies became live text
    grep -q 'No editor hook is required' "$TARGET/skills/cyrus-tdd-engineer/SKILL.md"
    ! grep -q 'Metrics emit (direct invocations too)' "$TARGET/skills/optimus-planner/SKILL.md"
    ! grep -q '^## Metrics Emit' "$TARGET/skills/cyrus-tdd-engineer/agent.md"
}

@test "shared assets: turn-cap doc is duplicated (transformed) into every citing skill; links resolve" {
    _render_target
    for s in aristotle-deconstructor optimus-planner cyrus-tdd-engineer code-auditor scout-reviewer ranger-reviewer; do
        f="$TARGET/skills/$s/references/agent-turn-cap-warning.md"
        [ -f "$f" ] || { echo "missing turn-cap doc in $s"; return 1; }
        grep -q '^3\. \*\*Wait for user direction\.\*\*' "$f" || { echo "portable renumbering missing in $s"; return 1; }
        ! grep -q 'agent_truncated. metric' "$f" || { echo "metric step survived in $s"; return 1; }
        grep -q 'references/agent-turn-cap-warning.md' "$TARGET/skills/$s/SKILL.md" || { echo "SKILL.md does not cite the local copy: $s"; return 1; }
    done
    ! grep -rq '_shared/agent-turn-cap-warning' "$TARGET/skills"
}

@test "shipped assets: workflow, schemas, heuristics byte-identical to core; scripts executable" {
    _render_target
    cmp "$DOTFILES_DIR/.claude/workflows/code-auditor-score.js" "$TARGET/skills/code-auditor/workflows/code-auditor-score.js"
    cmp "$DOTFILES_DIR/.claude/workflows/schemas/auditor-composite.json" "$TARGET/skills/code-auditor/references/schemas/auditor-composite.json"
    cmp "$DOTFILES_DIR/.claude/workflows/schemas/aristotle-to-optimus.json" "$TARGET/skills/aristotle-deconstructor/references/schemas/aristotle-to-optimus.json"
    cmp "$DOTFILES_DIR/.claude/workflows/schemas/optimus-to-cyrus.json" "$TARGET/skills/aristotle-deconstructor/references/schemas/optimus-to-cyrus.json"
    cmp "$DOTFILES_DIR/.claude/skills/code-auditor/references/review-heuristics.md" "$TARGET/skills/code-auditor/references/review-heuristics.md"
    for s in $AGENT_SET; do
        cmp "$INSTALL_TPL" "$TARGET/skills/$s/scripts/install-agent.sh" && [ -x "$TARGET/skills/$s/scripts/install-agent.sh" ] || return 1
    done
    # forge links to the sibling copy of the schemas, which exists post-render
    grep -q '](../aristotle-deconstructor/references/schemas/optimus-to-cyrus.json)' "$TARGET/skills/forge/SKILL.md"
}

@test "code-auditor: Workflow seam uses scriptPath, keeps the legacy fallback, notes hosts without the tool" {
    _render_target
    f="$TARGET/skills/code-auditor/SKILL.md"
    grep -q 'scriptPath: "<SKILL_DIR>/workflows/code-auditor-score.js"' "$f"
    grep -q 'LEGACY FALLBACK' "$f"
    grep -q 'references/schemas/auditor-composite.json' "$f"
    grep -q 'hosts without the Workflow tool' "$f"
    ! grep -q '\.claude/workflows/' "$f"
}

# --- Agent bundling -----------------------------------------------------------

@test "agent.md: frontmatter preserved (name, model, maxTurns); memory only where core declares it; role guard intact" {
    _render_target
    for s in $AGENT_SET; do
        src="$DOTFILES_DIR/.claude/agents/$s.md"; f="$TARGET/skills/$s/agent.md"
        [ -f "$f" ] || { echo "missing agent.md: $s"; return 1; }
        head -1 "$f" | grep -q '^---$' || return 1
        grep -q "^name: $s$" "$f" || return 1
        model="$(awk '/^model:/{print $2; exit}' "$src")"; [ -n "$model" ] || return 1
        grep -q "^model: $model$" "$f" || return 1
        turns="$(awk '/^maxTurns:/{print $2; exit}' "$src")"; [ -n "$turns" ] || return 1
        grep -q "^maxTurns: $turns$" "$f" || return 1
        if grep -q '^memory:' "$src"; then grep -q '^memory:' "$f" || return 1; else ! grep -q '^memory:' "$f" || return 1; fi
        grep -q 'BEGIN ROLE GUARD' "$f" && grep -q 'END ROLE GUARD' "$f" || return 1
        grep -q '^> \*\*Skill\*\*: \[`/'"$s"'`\](SKILL.md)$' "$f" || { echo "skill back-link not rewritten: $s"; return 1; }
        grep -q '^## Portable bundle notes$' "$f" || return 1
    done
    ! grep -q '^memory:' "$TARGET/skills/aristotle-deconstructor/agent.md"
    grep -q '^memory: user$' "$TARGET/skills/optimus-planner/agent.md"
}

@test "SKILL.md: agent-backed skills get the launch section and install hint; others get notes only" {
    _render_target
    for s in $AGENT_SET; do
        f="$TARGET/skills/$s/SKILL.md"
        grep -q '^## Launching the agent$' "$f" \
            && grep -q "subagent_type: \"$s\"" "$f" \
            && grep -q 'subagent_type: "general-purpose"' "$f" \
            && grep -q 'scripts/install-agent.sh' "$f" \
            && grep -q '^## Portable bundle notes$' "$f" \
            && grep -q '^> \*\*Agent definition\*\*: \[`agent.md`\](agent.md)$' "$f" || { echo "launch block incomplete: $s"; return 1; }
    done
    for s in forge grill-me to-prd code-auditor; do
        f="$TARGET/skills/$s/SKILL.md"
        grep -q '^## Portable bundle notes$' "$f" && ! grep -q '^## Launching the agent$' "$f" || { echo "notes wrong for $s"; return 1; }
    done
    # inserted sections land before the first original H2, after the frontmatter
    first_h2="$(grep -n '^## ' "$TARGET/skills/forge/SKILL.md" | head -1 | cut -d: -f2-)"
    [ "$first_h2" = "## Portable bundle notes" ]
}

@test "optional context: personal-file citations are marked, PR-creation fallback stated" {
    _render_target
    grep -q '`~/.claude/DoD.md` (if present' "$TARGET/skills/scout-reviewer/agent.md"
    ! grep -q '(if present) (' "$TARGET/skills/scout-reviewer/SKILL.md"
    grep -q '`~/.claude/AGENTS.md` (if present)' "$TARGET/skills/cyrus-tdd-engineer/agent.md"
    grep -q 'If `~/.claude/project-templates/` exists' "$TARGET/skills/optimus-planner/agent.md"
    grep -q 'otherwise run `gh pr create --draft`' "$TARGET/skills/cyrus-tdd-engineer/agent.md"
    ! grep -q 'always delegate to `/pr-create-from-commits`' "$TARGET/skills/cyrus-tdd-engineer/agent.md"
    grep -q 'registered-subagent mode only' "$TARGET/skills/optimus-planner/SKILL.md"
    grep -q 'canonical source' "$TARGET/skills/forge/SKILL.md"
    ! grep -rq 'ask me to confirm before saving it' "$TARGET/skills"
}

# --- README -------------------------------------------------------------------

@test "README: sentinel block appended on first run with 9 rows; hand-written content preserved on re-run" {
    _render_target
    grep -q '^# Team Skills$' "$TARGET/README.md"
    grep -q '^Intro prose kept verbatim\.$' "$TARGET/README.md"
    grep -q '<!-- BEGIN REASONING PIPELINE TABLE -->' "$TARGET/README.md"
    rows="$(awk '/BEGIN REASONING PIPELINE TABLE/{f=1;next} /END REASONING PIPELINE TABLE/{f=0} f && /^\| `/' "$TARGET/README.md" | wc -l | tr -d ' ')"
    [ "$rows" = "9" ]
    # user adds prose around the block; re-render keeps it and the block count
    printf '\nHand-written pipeline notes.\n' >> "$TARGET/README.md"
    bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan'
    grep -q '^Hand-written pipeline notes\.$' "$TARGET/README.md"
    [ "$(grep -c 'BEGIN REASONING PIPELINE TABLE' "$TARGET/README.md")" = "1" ]
}

# --- install-agent.sh template -----------------------------------------------

@test "install-agent.sh: installs to HOME, refuses differing overwrite, --force and --project work" {
    _render_target
    export HOME="$SCRATCH/home"; mkdir -p "$HOME"
    skill_dir="$TARGET/skills/optimus-planner"

    run bash "$skill_dir/scripts/install-agent.sh"
    [ "$status" -eq 0 ] && [ -f "$HOME/.claude/agents/optimus-planner.md" ]
    cmp "$skill_dir/agent.md" "$HOME/.claude/agents/optimus-planner.md"

    # identical re-run is fine
    run bash "$skill_dir/scripts/install-agent.sh"
    [ "$status" -eq 0 ]

    # differing existing file → refuse without --force
    echo "local edit" >> "$HOME/.claude/agents/optimus-planner.md"
    run bash "$skill_dir/scripts/install-agent.sh"
    [ "$status" -eq 1 ] && [[ "$output" == *"--force"* ]]
    run bash "$skill_dir/scripts/install-agent.sh" --force
    [ "$status" -eq 0 ]
    cmp "$skill_dir/agent.md" "$HOME/.claude/agents/optimus-planner.md"

    # --project targets ./.claude/agents
    mkdir -p "$SCRATCH/proj" && cd "$SCRATCH/proj"
    run bash "$skill_dir/scripts/install-agent.sh" --project
    [ "$status" -eq 0 ] && [ -f "$SCRATCH/proj/.claude/agents/optimus-planner.md" ]

    run bash "$skill_dir/scripts/install-agent.sh" --bogus
    [ "$status" -eq 2 ]
}

@test "install-agent.sh: fails clearly when agent.md is absent" {
    _render_target
    export HOME="$SCRATCH/home"; mkdir -p "$HOME"
    mkdir -p "$SCRATCH/lonely/scripts"
    cp "$INSTALL_TPL" "$SCRATCH/lonely/scripts/install-agent.sh"
    run bash "$SCRATCH/lonely/scripts/install-agent.sh"
    [ "$status" -eq 1 ] && [[ "$output" == *"no agent.md"* ]]
}
