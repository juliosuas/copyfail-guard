SHELL := /usr/bin/env bash

.PHONY: help test smoke lint format-check

help:
	@printf 'Targets:\n'
	@printf '  make test          Run local smoke tests\n'
	@printf '  make lint          Run shell/Python syntax checks and ShellCheck when available\n'
	@printf '  make format-check  Validate generated JSON fixtures through smoke tests\n'

test: smoke

smoke:
	tests/ci-smoke.sh

lint:
	bash -n bin/copyfail-guard.sh
	sh -n scripts/install.sh
	bash -n tests/ci-smoke.sh
	python3 -m py_compile tools/afalg-socket-test.py
	if command -v shellcheck >/dev/null 2>&1; then shellcheck bin/copyfail-guard.sh tests/ci-smoke.sh scripts/install.sh; else printf 'shellcheck not installed; skipped\n'; fi

format-check: smoke
