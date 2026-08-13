.PHONY: test lint check-leakage check-leakage-shapes gen-docs gen-boundaries gen-role-guards gen all

DOTFILES_DIR := $(shell realpath .)

# Discover all *.bats files in tests/ (no LLM tests in core)
TEST_FILES := $(wildcard tests/*.bats)

# Repo-root scripts plus any skill-local scripts (e.g. babysit-prs). Skill
# scripts back consequential actions, so they are shellchecked in CI too, not
# by a manual reminder. The nested glob no-ops cleanly when no skill ships one.
LINT_FILES := $(wildcard scripts/*.sh) $(wildcard .claude/skills/*/scripts/*.sh) $(wildcard .claude/evals/scripts/*.sh)

all: lint check-leakage check-consult-grammar test

test:                                   ## Run all bats tests
	DOTFILES_DIR=$(DOTFILES_DIR) bats $(TEST_FILES)

lint:                                   ## Run shellcheck on all scripts (repo-root + skill-local)
	shellcheck --severity=warning $(LINT_FILES)

check-leakage:                          ## Scan for company-specific tokens
	bash scripts/check-no-leakage.sh .

check-leakage-shapes:                   ## Secret-free structural scan (public CI / fork PRs)
	bash scripts/check-leakage-shapes.sh .

check-consult-grammar:                  ## Positive grammar check for consult-instructions
	bash scripts/check-consult-grammar.sh .

lint-agents:                            ## Run agent/skill structural linter
	bash scripts/lint-agents.sh

gen-docs:                               ## Regenerate README tables from skill/agent directory
	bash scripts/docs-gen.sh

gen-boundaries:                         ## Regenerate responsibility boundary tables in SKILL.md files
	bash scripts/boundaries-gen.sh

gen-role-guards:                        ## Regenerate role-guard blocks in agent files
	bash scripts/role-guard-gen.sh

gen: gen-docs gen-boundaries gen-role-guards   ## Run all generators
