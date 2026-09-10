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

# setup_file/teardown_file override the test_helper versions: same exports,
# plus a snapshot of the real tree so teardown_file can prove the suite
# mutated nothing. Every render happens into $SCRATCH or a scratch core copy
# (see _scratch_core), so this guard should never fire — it exists to keep
# that invariant tested, matching the pattern in reviewer-shared-blocks.bats.
setup_file() {
    CORE_DIR="$(realpath "$BATS_TEST_DIRNAME/..")"
    export CORE_DIR
    DOTFILES_DIR="$CORE_DIR"
    export DOTFILES_DIR
    git -C "$DOTFILES_DIR" status --porcelain > "$BATS_FILE_TMPDIR/tree-before" \
        && git -C "$DOTFILES_DIR" diff > "$BATS_FILE_TMPDIR/diff-before"
}

teardown_file() {
    git -C "$DOTFILES_DIR" status --porcelain > "$BATS_FILE_TMPDIR/tree-after" \
        && git -C "$DOTFILES_DIR" diff > "$BATS_FILE_TMPDIR/diff-after" \
        && cmp -s "$BATS_FILE_TMPDIR/tree-before" "$BATS_FILE_TMPDIR/tree-after" \
        && cmp -s "$BATS_FILE_TMPDIR/diff-before" "$BATS_FILE_TMPDIR/diff-after" || {
        echo "export-skills.bats mutated the real working tree:" >&2
        diff "$BATS_FILE_TMPDIR/tree-before" "$BATS_FILE_TMPDIR/tree-after" >&2 || true
        return 1
    }
}

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

# Build a scratch copy of the subset of dotfiles-core that export-skills.sh
# reads from (skills, agents, workflows, _shared/portable, turn-cap doc), so a
# test can mutate a source file (e.g. inject an unterminated CORE-ONLY marker)
# without touching the real canonical tree. Sets SCRATCH_CORE.
_scratch_core() {
    SCRATCH_CORE="$SCRATCH/core"
    mkdir -p "$SCRATCH_CORE/.claude"
    cp -R "$DOTFILES_DIR/.claude/skills" "$SCRATCH_CORE/.claude/skills"
    cp -R "$DOTFILES_DIR/.claude/agents" "$SCRATCH_CORE/.claude/agents"
    cp -R "$DOTFILES_DIR/.claude/workflows" "$SCRATCH_CORE/.claude/workflows"
    cp -R "$DOTFILES_DIR/.claude/_shared" "$SCRATCH_CORE/.claude/_shared"
}

# --- CLI surface ------------------------------------------------------------

@test "export-skills: executable, --help exits 0, missing target exits 2" {
    [ -x "$EXPORT" ]
    run bash "$EXPORT" --help
    [ "$status" -eq 0 ] && [[ "$output" == *"Usage:"* ]]
    run bash "$EXPORT"
    [ "$status" -eq 2 ] && [[ "$output" == *"missing <target-repo-dir>"* ]]
    run bash "$EXPORT" "$SCRATCH/does-not-exist"
    [ "$status" -eq 2 ] && [[ "$output" == *"target is not a directory"* ]]
}

@test "check-portable-refs: executable, usage exits 2 without a dir" {
    [ -x "$REFS" ]
    run bash "$REFS"
    [ "$status" -eq 2 ]
}

@test "render: 'managed via dotfiles' rewrite does not eat 'dotfiles-core'" {
    _scratch_core
    printf '\nThis skill is managed via dotfiles-core tooling.\nA separate note is managed via dotfiles, nothing else.\n' \
        >> "$SCRATCH_CORE/.claude/skills/to-prd/SKILL.md"
    TARGET="$SCRATCH/target-mvd"; mkdir -p "$TARGET"
    EXPORT_SKILLS_CORE_DIR="$SCRATCH_CORE" bash "$EXPORT" "$TARGET"
    grep -q 'managed via dotfiles-core tooling' "$TARGET/skills/to-prd/SKILL.md"
    grep -q 'is if present, nothing else' "$TARGET/skills/to-prd/SKILL.md"
}

@test "export-skills: unterminated CORE-ONLY marker errors instead of silently truncating" {
    _scratch_core
    printf '<!-- BEGIN CORE-ONLY -->\nnever terminated\n' >> "$SCRATCH_CORE/.claude/skills/to-prd/SKILL.md"
    TARGET="$SCRATCH/target-bad"; mkdir -p "$TARGET"
    run env EXPORT_SKILLS_CORE_DIR="$SCRATCH_CORE" bash "$EXPORT" "$TARGET"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unterminated <!-- BEGIN CORE-ONLY -->"* ]]
    # nothing was written: the render aborted before the copy step
    [ -z "$(ls -A "$TARGET/skills" 2>/dev/null)" ]
}

@test "check-portable-refs: empty resolved skill list errors instead of reporting clean" {
    mkdir -p "$SCRATCH/empty-dir"
    run bash "$REFS" "$SCRATCH/empty-dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no skills to check"* ]]
    [[ "$output" != *"clean (0 skills)"* ]]
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

@test "export-skills: _insert_before_first_h2 aborts when a skill's SKILL.md has no ## heading" {
    _scratch_core
    printf -- '---\nname: to-prd\ndescription: x\nuser-invocable: true\n---\n\nNo H2 heading anywhere in this file, only prose.\n' \
        > "$SCRATCH_CORE/.claude/skills/to-prd/SKILL.md"
    TARGET="$SCRATCH/target-noh2"; mkdir -p "$TARGET"
    run env EXPORT_SKILLS_CORE_DIR="$SCRATCH_CORE" bash "$EXPORT" "$TARGET"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no ## heading found"* ]]
}

@test "check: README table drift is detected even when every skills/ dir is up to date" {
    _render_target
    run bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' --check
    [ "$status" -eq 0 ]

    # hand-edited prose outside the sentinels is preserved, not drift (see the
    # "hand-written content preserved on re-run" README test) — but a
    # hand-edit *inside* the generated table is real drift.
    sed -i.bak 's/^| `forge` |.*$/| `forge` | tampered row |/' "$TARGET/README.md" && rm -f "$TARGET/README.md.bak"
    run bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFT  README.md"* ]]
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

@test "check: executable-bit drift on shipped scripts is detected" {
    _render_target
    chmod -x "$TARGET/skills/optimus-planner/scripts/install-agent.sh"
    run bash "$EXPORT" "$TARGET" --owner-team test-team --owner-slack '#test-chan' --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"skills/optimus-planner/scripts/install-agent.sh (executable bit missing)"* ]]
    # content-only drift must not be reported as an exec-bit problem
    [[ "$output" != *"unexpected executable bit"* ]]
}

@test "check: metadata flags are part of the rendered state (different flags = drift)" {
    _render_target
    run bash "$EXPORT" "$TARGET" --owner-team other-team --check
    [ "$status" -eq 1 ] && [[ "$output" == *"DRIFT  skills/"* ]] && [[ "$output" == *"has drifted"* ]]
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

@test "portable refs: checker catches a broken relative markdown link" {
    _render_target
    printf '\nSee [missing doc](references/does-not-exist.md) for details.\n' >> "$TARGET/skills/to-prd/SKILL.md"
    run bash "$REFS" "$TARGET/skills" to-prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"broken relative link"* ]]
    [[ "$output" == *"does-not-exist.md"* ]]
}

@test "portable refs: checker catches a nested SKILL.md (phantom skill registration)" {
    _render_target
    mkdir -p "$TARGET/skills/to-prd/nested/SKILL.md.dir"
    printf -- '---\nname: nested\ndescription: x\n---\n' > "$TARGET/skills/to-prd/nested/SKILL.md"
    run bash "$REFS" "$TARGET/skills" to-prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"2 SKILL.md files"* ]]
}

@test "portable refs: optional-paragraph excuse requires the exact token or its namespace wildcard, not mere paragraph presence" {
    mkdir -p "$SCRATCH/refs/to-prd"
    printf -- '---\nname: to-prd\ndescription: x\n---\n\nOptional external skills: /pr-create-from-commits is optional.\n\nAlso try /mc-totally-made-up.\n' \
        > "$SCRATCH/refs/to-prd/SKILL.md"
    run bash "$REFS" "$SCRATCH/refs" to-prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"unresolved skill reference /mc-totally-made-up"* ]]

    mkdir -p "$SCRATCH/refs2/mc-lint"
    printf -- '---\nname: mc-lint\ndescription: x\n---\n\nOptional external skills: /mc-* skills are optional.\n\nAlso try /mc-lint.\n' \
        > "$SCRATCH/refs2/mc-lint/SKILL.md"
    run bash "$REFS" "$SCRATCH/refs2" mc-lint
    [ "$status" -eq 0 ]
}

@test "portable refs: no export markers, metrics plumbing, or Cursor hook notes survive" {
    _render_target
    ! grep -rqE 'CORE-ONLY|PORTABLE-ONLY|metrics-emit|emit-metric\.sh|\.cursor/hooks\.json|managed via dotfiles|not a dotfiles skill' "$TARGET/skills"
    # PORTABLE-ONLY bodies became live text
    grep -q 'No editor hook is required' "$TARGET/skills/cyrus-tdd-engineer/SKILL.md"
    ! grep -q 'Metrics emit (direct invocations too)' "$TARGET/skills/optimus-planner/SKILL.md"
    ! grep -q '^## Metrics Emit' "$TARGET/skills/cyrus-tdd-engineer/agent.md"
    # the "managed via dotfiles" rewrite must not eat "dotfiles-core"
    grep -q 'dotfiles-core' "$TARGET/skills/forge/SKILL.md"
}

@test "agent.md: every rendered agent emits the <<task-complete>> sentinel instruction (portable consumers have no maintainer AGENTS.md)" {
    _render_target
    for s in $AGENT_SET; do
        f="$TARGET/skills/$s/agent.md"
        grep -q '<<task-complete>>' "$f" || { echo "no sentinel instruction in $s/agent.md"; return 1; }
    done
}

@test "turn-cap doc and cyrus SKILL.md state Cyrus's actual maxTurns (300), not the stale 100" {
    _render_target > /dev/null
    ! grep -q 'Cyrus 100' "$DOTFILES_DIR/.claude/_shared/agent-turn-cap-warning.md"
    grep -q 'Cyrus 300' "$DOTFILES_DIR/.claude/_shared/agent-turn-cap-warning.md"
    ! grep -q 'maxTurns. (100)' "$DOTFILES_DIR/.claude/skills/cyrus-tdd-engineer/SKILL.md"
    grep -q 'maxTurns. (300)' "$DOTFILES_DIR/.claude/skills/cyrus-tdd-engineer/SKILL.md"
    ! grep -q 'Cyrus 100' "$TARGET/skills/cyrus-tdd-engineer/references/agent-turn-cap-warning.md"
    grep -q 'Cyrus 300' "$TARGET/skills/cyrus-tdd-engineer/references/agent-turn-cap-warning.md"
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
    # auditor-composite.json's $comment cites the core-only path
    # `.claude/workflows/code-auditor-score.js`; the rendered copy has that
    # sed-rewritten to the shipped-alongside path, so compare after applying
    # the same rewrite rather than expecting byte-identity.
    sed 's|\.claude/workflows/code-auditor-score\.js|workflows/code-auditor-score.js|' \
        "$DOTFILES_DIR/.claude/workflows/schemas/auditor-composite.json" \
        | cmp - "$TARGET/skills/code-auditor/references/schemas/auditor-composite.json"
    cmp "$DOTFILES_DIR/.claude/workflows/schemas/aristotle-to-optimus.json" "$TARGET/skills/aristotle-deconstructor/references/schemas/aristotle-to-optimus.json"
    cmp "$DOTFILES_DIR/.claude/workflows/schemas/optimus-to-cyrus.json" "$TARGET/skills/aristotle-deconstructor/references/schemas/optimus-to-cyrus.json"
    cmp "$DOTFILES_DIR/.claude/skills/code-auditor/references/review-heuristics.md" "$TARGET/skills/code-auditor/references/review-heuristics.md"
    for s in $AGENT_SET; do
        cmp "$INSTALL_TPL" "$TARGET/skills/$s/scripts/install-agent.sh" && [ -x "$TARGET/skills/$s/scripts/install-agent.sh" ] || return 1
    done
    # forge links to the sibling copy of the schemas, which exists post-render
    grep -q '](../aristotle-deconstructor/references/schemas/optimus-to-cyrus.json)' "$TARGET/skills/forge/SKILL.md"
}

@test "rendered auditor-composite.json: \$comment no longer cites the core-only .claude/workflows/ path" {
    _render_target
    ! grep -q '(\.claude/workflows/code-auditor-score\.js)' "$TARGET/skills/code-auditor/references/schemas/auditor-composite.json"
    grep -q '(workflows/code-auditor-score\.js)' "$TARGET/skills/code-auditor/references/schemas/auditor-composite.json"
}

@test "shipped assets: review-heuristics.md is duplicated into every skill whose agent cites it, not just code-auditor" {
    _render_target
    for s in cyrus-tdd-engineer scout-reviewer ranger-reviewer; do
        f="$TARGET/skills/$s/references/review-heuristics.md"
        [ -f "$f" ] || { echo "missing review-heuristics.md in $s"; return 1; }
        cmp "$DOTFILES_DIR/.claude/skills/code-auditor/references/review-heuristics.md" "$f" || return 1
        grep -q 'references/review-heuristics.md' "$TARGET/skills/$s/agent.md" \
            || { echo "$s agent.md does not cite the local copy"; return 1; }
    done
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

@test "SKILL_DIR resolution is stated explicitly and user-facing install snippets use <SKILL_DIR>" {
    _render_target
    for s in $AGENT_SET; do
        f="$TARGET/skills/$s/SKILL.md"
        grep -q 'Base directory for this skill' "$f" \
            || { echo "no SKILL_DIR resolution instruction in $s/SKILL.md"; return 1; }
        grep -q '<SKILL_DIR>/scripts/install-agent.sh' "$f" \
            || { echo "install snippet not using <SKILL_DIR> in $s/SKILL.md"; return 1; }
        grep -q 'substitute the resolved path' "$f" \
            || { echo "no substitution note in $s/SKILL.md"; return 1; }
    done
    for s in forge grill-me to-prd code-auditor; do
        f="$TARGET/skills/$s/SKILL.md"
        grep -q 'Base directory for this skill' "$f" \
            || { echo "no SKILL_DIR resolution instruction in $s/SKILL.md (bundle-notes)"; return 1; }
    done
}

@test "fallback mode: launch.md instructs enforcing disallowedTools; agent-notes.md carries the enforcement bullet; the harness-blocked phrase is rewritten" {
    _render_target
    for s in $AGENT_SET; do
        f="$TARGET/skills/$s/SKILL.md"
        grep -q 'disallowedTools' "$f" && grep -q 'Treat them as unavailable' "$f" \
            || { echo "no fallback tool-restriction instruction in $s/SKILL.md"; return 1; }
        af="$TARGET/skills/$s/agent.md"
        grep -q 'Tool restrictions in this file.s frontmatter' "$af" \
            || { echo "no disallowedTools enforcement bullet in $s/agent.md"; return 1; }
    done
    for s in scout-reviewer ranger-reviewer; do
        af="$TARGET/skills/$s/agent.md"
        grep -q 'blocked by .disallowedTools. when registered' "$af" \
            || { echo "harness-blocked phrase not rewritten in $s/agent.md"; return 1; }
        ! grep -q 'blocked by harness' "$af" || { echo "old phrase survived in $s/agent.md"; return 1; }
    done
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

@test "optional context: the two-line 'error handling'/'defaults.' wrap is joined and qualified, no unqualified phrase survives" {
    _render_target
    for s in scout-reviewer ranger-reviewer; do
        f="$TARGET/skills/$s/agent.md"
        grep -q 'Follow CLAUDE.md error-handling defaults when defined (otherwise: surface the failure and stop, never retry silently)' "$f" \
            || { echo "qualified phrase missing in $s"; return 1; }
    done
    run bash "$REFS" "$TARGET/skills" $EXPORT_SET
    [ "$status" -eq 0 ] && [[ "$output" == *"clean (9 skills)"* ]]
}

@test "portable refs: checker flags an unqualified 'Follow CLAUDE.md error handling defaults' phrase" {
    mkdir -p "$SCRATCH/unq/to-prd"
    printf -- '---\nname: to-prd\ndescription: x\n---\n\nFollow CLAUDE.md error handling defaults for everything.\n' \
        > "$SCRATCH/unq/to-prd/SKILL.md"
    run bash "$REFS" "$SCRATCH/unq" to-prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"unqualified phrase"* ]]
}

# --- README -------------------------------------------------------------------

@test "bundle-notes: per-skill dependency declarations replace the generic Sibling-skills bullet" {
    _render_target
    f="$TARGET/skills/forge/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `grill-me`, `to-prd`, `aristotle-deconstructor`, `optimus-planner`$' "$f" \
        || { echo "forge deps line wrong or missing"; return 1; }

    f="$TARGET/skills/to-prd/SKILL.md"
    grep -q '^\*\*Requires:\*\* none — this skill is standalone$' "$f" \
        || { echo "to-prd standalone line wrong or missing"; return 1; }

    f="$TARGET/skills/aristotle-deconstructor/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `optimus-planner`, `cyrus-tdd-engineer`$' "$f" \
        || { echo "aristotle deps line wrong or missing"; return 1; }

    f="$TARGET/skills/cyrus-tdd-engineer/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `code-auditor`, `scout-reviewer`, `ranger-reviewer`$' "$f" \
        || { echo "cyrus deps line wrong or missing"; return 1; }

    f="$TARGET/skills/code-auditor/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `scout-reviewer`, `ranger-reviewer`$' "$f" \
        || { echo "code-auditor deps line wrong or missing"; return 1; }

    f="$TARGET/skills/scout-reviewer/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `cyrus-tdd-engineer`$' "$f" \
        || { echo "scout deps line wrong or missing"; return 1; }

    f="$TARGET/skills/ranger-reviewer/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `cyrus-tdd-engineer`$' "$f" \
        || { echo "ranger deps line wrong or missing"; return 1; }

    f="$TARGET/skills/optimus-planner/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `cyrus-tdd-engineer`, `aristotle-deconstructor`$' "$f" \
        || { echo "optimus deps line wrong or missing"; return 1; }

    f="$TARGET/skills/grill-me/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `to-prd`$' "$f" \
        || { echo "grill-me deps line wrong or missing"; return 1; }

    # stopping-with-install-hint sentence is retained
    grep -q 'install it from the same skills repository' "$TARGET/skills/forge/SKILL.md"
    ! grep -rq '\*\*Sibling skills\.\*\*' "$TARGET/skills"
}

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

@test "install-agent.sh: fails clearly when name: is missing from agent.md frontmatter" {
    export HOME="$SCRATCH/home"; mkdir -p "$HOME"
    mkdir -p "$SCRATCH/nameless/scripts"
    printf -- '---\ndescription: x\n---\nbody\n' > "$SCRATCH/nameless/agent.md"
    cp "$INSTALL_TPL" "$SCRATCH/nameless/scripts/install-agent.sh"
    run bash "$SCRATCH/nameless/scripts/install-agent.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no name:"* ]]
}

@test "install-agent.sh: rejects a path-traversal name and trims/quote-strips a valid one" {
    export HOME="$SCRATCH/home"; mkdir -p "$HOME"

    mkdir -p "$SCRATCH/pwned/scripts"
    printf -- '---\nname: ../../pwned\ndescription: x\n---\nbody\n' > "$SCRATCH/pwned/agent.md"
    cp "$INSTALL_TPL" "$SCRATCH/pwned/scripts/install-agent.sh"
    run bash "$SCRATCH/pwned/scripts/install-agent.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid"* ]] || [[ "$output" == *"unsafe"* ]]
    [ ! -e "$HOME/.claude/agents/pwned.md" ]
    [ ! -e "$SCRATCH/home/.claude/pwned" ]

    mkdir -p "$SCRATCH/trimmed/scripts"
    printf -- '---\nname:   "my-agent"   \ndescription: x\n---\nbody\n' > "$SCRATCH/trimmed/agent.md"
    cp "$INSTALL_TPL" "$SCRATCH/trimmed/scripts/install-agent.sh"
    run bash "$SCRATCH/trimmed/scripts/install-agent.sh"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.claude/agents/my-agent.md" ]
}

@test "optimus agent.md: the mandatory memory step is qualified for fallback runs" {
    _render_target
    grep -q '^\*\*Step C — Check agent memory (registered-subagent mode only)\.\*\*' "$TARGET/skills/optimus-planner/agent.md"
    # the agent'"'"'s Persistent Memory section itself is left verbatim
    grep -q 'persistent memory directory at `~/.claude/agent-memory/optimus-planner/`' "$TARGET/skills/optimus-planner/agent.md"
}

@test "install-agent.sh --project: resolves the git root from a subdirectory" {
    _render_target
    export HOME="$SCRATCH/home"; mkdir -p "$HOME"
    mkdir -p "$SCRATCH/repo/deep/er" && git -C "$SCRATCH/repo" init -q
    cd "$SCRATCH/repo/deep/er"
    run bash "$TARGET/skills/optimus-planner/scripts/install-agent.sh" --project
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/repo/.claude/agents/optimus-planner.md" ]
    [ ! -e "$SCRATCH/repo/deep/er/.claude" ]
}

@test "agent.md: memory bullet appears only for agents that declare memory:" {
    _render_target
    ! grep -q 'Memory applies only when registered' "$TARGET/skills/aristotle-deconstructor/agent.md"
    grep -q 'Memory applies only when registered' "$TARGET/skills/optimus-planner/agent.md"
    grep -q 'Memory applies only when registered' "$TARGET/skills/ranger-reviewer/agent.md"
}

@test "Requires lists name only skills the SKILL.md actually invokes (reviewers → cyrus only; grill-me → to-prd only)" {
    _render_target
    grep -q '^\*\*Requires (install alongside):\*\* `cyrus-tdd-engineer`$' "$TARGET/skills/scout-reviewer/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `cyrus-tdd-engineer`$' "$TARGET/skills/ranger-reviewer/SKILL.md"
    grep -q '^\*\*Requires (install alongside):\*\* `to-prd`$' "$TARGET/skills/grill-me/SKILL.md"
    grep -q 'Everything up to the' "$TARGET/skills/grill-me/SKILL.md"
}
