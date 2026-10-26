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
