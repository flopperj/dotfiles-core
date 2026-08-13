.PHONY: test lint lint-agents check-leakage check-leakage-shapes gen-docs gen-boundaries gen-role-guards gen eval all

DOTFILES_DIR := $(shell realpath .)

# Discover all *.bats files in tests/ (no LLM tests in core)
TEST_FILES := $(wildcard tests/*.bats)

# Repo-root scripts plus any skill-local scripts (e.g. babysit-prs). Skill
# scripts back consequential actions, so they are shellchecked in CI too, not
# by a manual reminder. The nested glob no-ops cleanly when no skill ships one.
LINT_FILES := $(wildcard scripts/*.sh) $(wildcard .claude/skills/*/scripts/*.sh) $(wildcard .claude/evals/scripts/*.sh)

all: lint lint-agents check-leakage check-consult-grammar test

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

EVAL_SET := .claude/evals/sets/classifier-v1.jsonl

# eval — score the classifier answer key under the mechanical ratchet
# (< 30 records: warn-only report; >= 30: blocking exit code; the runner
# prints the arm taken and the count that decided it).
#
# CI has no model access, so no fresh classifier predictions exist here. This
# target runs the deterministic self-check: a perfect predictions file derived
# from the key itself must score 100%, proving set-file integrity and runner
# self-consistency. Prediction-scoring runs against real classifier output are
# local, human/agent-driven:
#   bash .claude/evals/scripts/eval-run.sh --set $(EVAL_SET) --predictions <file>
#
# set -e keeps this fail-closed: a jq failure aborts the target instead of
# handing the runner an empty predictions file (which would read as 0% and
# sail through the warn-only arm).
eval:                                   ## Ratcheted self-check of the classifier answer key
	@set -e; tmp="$$(mktemp)"; trap 'rm -f "$$tmp"' EXIT; \
	jq -c '{id: .id, predicted: .expected}' "$(EVAL_SET)" > "$$tmp"; \
	bash .claude/evals/scripts/eval-run.sh --ratchet --set "$(EVAL_SET)" --predictions "$$tmp"
