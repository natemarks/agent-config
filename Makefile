.DEFAULT_GOAL := help
SHELL := $(shell which bash)
INSTALL_TARGETS := $(HOME)/.claude/skills
FORCE ?= 0

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

shellcheck: ## Check shell scripts for errors
	@if [ -d .git ]; then \
		git ls-files '*.sh' | xargs shellcheck --severity=error --format=gcc; \
	else \
		find . -name '*.sh' -type f | xargs shellcheck --severity=error --format=gcc; \
	fi

static: shellcheck ## Run all static checks

deploy: ## Deploy project-managed skills to target directories (FORCE=1 to adopt existing same-named skills)
	./install.sh $(if $(filter 1,$(FORCE)),--force) $(INSTALL_TARGETS)

.PHONY: help shellcheck static deploy
