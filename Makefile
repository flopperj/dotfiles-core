.PHONY: test lint check-leakage all

all: lint check-leakage test

test:
	bats tests/

lint:
	shellcheck scripts/*.sh

check-leakage:
	bash scripts/check-no-leakage.sh .
