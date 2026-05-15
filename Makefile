.PHONY: test lint check-leakage gen-docs gen-boundaries gen-role-guards gen all

DOTFILES_DIR := $(shell realpath .)

# Discover all *.bats files in tests/ (no LLM tests in core)
TEST_FILES := $(wildcard tests/*.bats)

all: lint check-leakage check-consult-grammar test

test:                                   ## Run all bats tests
	DOTFILES_DIR=$(DOTFILES_DIR) bats $(TEST_FILES)

lint:                                   ## Run shellcheck on all scripts
	shellcheck --severity=warning scripts/*.sh

check-leakage:                          ## Scan for company-specific tokens
	bash scripts/check-no-leakage.sh .

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
