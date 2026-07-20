.DEFAULT_GOAL := help
SHELL := $(shell which bash)
INSTALL_TARGETS := $(HOME)/.claude/skills

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

shellcheck: ## Check shell scripts for errors
	@if [ -d .git ]; then \
		git ls-files '*.sh' | xargs shellcheck --severity=error --format=gcc; \
	else \
		find . -name '*.sh' -type f | xargs shellcheck --severity=error --format=gcc; \
	fi

static: shellcheck ## Run all static checks

deploy: ## Deploy skills to all target directories
	./install.sh $(INSTALL_TARGETS)

.PHONY: help shellcheck static deploy
