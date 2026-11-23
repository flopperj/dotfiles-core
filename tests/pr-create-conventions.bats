#!/usr/bin/env bats
# pr-create-from-commits follows the repo's own title and body conventions. The
# wording pins below keep the title checker offline, the non-draft command in
# step with the draft one, and the no-ticket path wired end to end.
# Run with: bats tests/pr-create-conventions.bats

load 'test_helper'

PR_CREATE="$DOTFILES_DIR/.claude/skills/pr-create-from-commits/SKILL.md"

@test "a title checker runs only when already installed, never fetched from the registry" {
    grep -qF 'npx --no-install' "$PR_CREATE" || return 1
    grep -qF 'node_modules/.bin' "$PR_CREATE" || return 1
    grep -qi 'never fetch' "$PR_CREATE" || return 1
    ! grep -qE 'npx commitlint' "$PR_CREATE" || return 1
}

@test "the non-draft command matches the draft one apart from --draft" {
    grep -qF 'gh pr create --title "{title}" --body-file "{body_file}"' "$PR_CREATE" || return 1
    ! grep -qF -- '--body "..."' "$PR_CREATE" || return 1
}

@test "the no-ticket path skips Jira and names the branch without a ticket" {
    grep -qF 'Without a ticket, skip this step' "$PR_CREATE" || return 1
    grep -qF '`{feature-summary}`' "$PR_CREATE" || return 1
    grep -qi "branch convention" "$PR_CREATE" || return 1
}

@test "the ticket question is resolved after the conventions are detected" {
    grep -qF 'resolve the ticket question after Step 2' "$PR_CREATE"
}

@test "evidence step names evidence by change type" {
    grep -qF '### 5b. Prove it works' "$PR_CREATE" || return 1
    grep -qF '/record-demo' "$PR_CREATE" || return 1
    grep -qF '/mermaid-diagrams' "$PR_CREATE" || return 1
    grep -qF '<details>' "$PR_CREATE"
}

@test "evidence is never fabricated and untested work is said so" {
    grep -qF 'Never fabricate evidence' "$PR_CREATE" || return 1
    grep -qF 'Not tested:' "$PR_CREATE"
}

@test "a checkbox is ticked only for something done" {
    grep -qF 'Tick a checkbox only' "$PR_CREATE"
}

@test "the Before/After table shape is fixed" {
    grep -qF '| Before | After |' "$PR_CREATE" || return 1
    grep -qF '|--------|-------|' "$PR_CREATE"
}

@test "hygiene check greps the body and the added lines for local paths and review narration" {
    grep -qF '**3c.' "$PR_CREATE" || return 1
    grep -qF '/Users/' "$PR_CREATE" || return 1
    grep -qF 'scratchpad' "$PR_CREATE" || return 1
    grep -qF 'review-history narration' "$PR_CREATE"
}
