---
name: scaffold-project
description: Initialize project with opinionated standards - pinned dependencies, language-specific static analysis, pre-commit hooks, Dependabot, and CI/CD. Enforces consistent project structure across Python, Go, Rust, and CDK projects.
---

# Project Scaffolding Skill

## MANDATORY REQUIREMENTS

### Rule 1: Pin All Dependency Versions

**ALL dependency versions must be pinned to exact versions:**

- **Python**: `package==1.2.3` (no `>=`, `~=`, or ranges)
- **Go**: Exact versions in `go.mod`
- **Rust**: Exact versions in `Cargo.toml` (no `^` or `~`)
- **Node.js**: No `^` or `~` in `package.json`
- **GitHub Actions**: Pin to commit SHA with version comment (e.g., `uses: actions/checkout@abc123  # v4.1.0`)

### Rule 2: Makefile Static Analysis Targets

Every project MUST have a Makefile with language-specific static analysis targets.

#### Python Projects

**Required Tools:**
1. `black` - Code formatter (`black --check --line-length=79 *.py`)
2. `pylint` - Static analyzer (`pylint *.py --max-line-length=90`)
3. `pytest` - Test runner (`pytest -v`)
4. `mypy` - Type checker (`python3 -m mypy *.py`)
5. `shellcheck` - Shell script analyzer

**Required Makefile Targets:**
- `black` - Auto-format Python files
- `black-check` - Check formatting without modifying
- `pylint` - Run pylint
- `mypy` - Run type checking
- `shellcheck` - Check shell scripts
- `unit` - Run unit tests
- `unit-update-golden` - Update golden files
- `integration` - Run integration tests (manual)
- `static` - Run all checks: `static: black-check mypy shellcheck pylint unit`
- `clean-cache` - Delete `__pycache__`, `.pyc`/`.pyo` files, and `.pytest_cache`
- `clean-venv` - Alias for `clean-cache` then re-creates `.venv`

**Required in requirements.txt:** `black`, `pylint`, `pytest`, `mypy` — exact versions (looked up in Step 2).

#### Go Projects

**Required Tools:**
1. `goimports` - Import formatter (`goimports -w .`)
2. `gofmt` - Code formatter (`go fmt ./...`)
3. `go vet` - Built-in analyzer (`go vet ./...`)
4. `staticcheck` - Static analyzer and linter (`staticcheck ./...`)
5. `gocyclo` - Complexity analyzer (`gocyclo -over 25 .`)
6. `govulncheck` - Vulnerability scanner (`govulncheck ./...`)
7. `go test` - Test runner (`go test -v ./...`)
8. `shellcheck` - Shell script analyzer

**Required Makefile Targets:**
- `goimports` - Format imports
- `fmt` - Format code
- `vet` - Run go vet
- `lint` - Run staticcheck
- `gocyclo` - Check complexity
- `govulncheck` - Scan vulnerabilities
- `unit` - Run unit tests
- `integration` - Run integration tests
- `static` - Run all checks: `static: goimports fmt vet lint gocyclo govulncheck unit`

#### Rust Projects

**Required Tools:**
1. `cargo fmt` - Code formatter (`cargo fmt -- --check`)
2. `cargo clippy` - Linter (`cargo clippy -- -D warnings`)
3. `cargo test` - Test runner (unit + integration)
4. `cargo check` - Dead code detection (`RUSTFLAGS="-D dead_code" cargo check`)
5. `cargo audit` - Vulnerability scanner (`cargo audit`)
6. `shellcheck` - Shell script analyzer

**Required Makefile Targets:**
- `fmt` - Format code
- `fmt-check` - Check formatting
- `clippy` - Run clippy
- `dead-code` - Check for dead code
- `unit` - Run tests
- `audit` - Run cargo audit
- `shellcheck` - Check shell scripts
- `static` - Run all checks: `static: fmt-check clippy dead-code unit audit shellcheck`

#### Universal Tool (All Languages)

**shellcheck** - MUST be configured for all projects:
```bash
git ls-files 'scripts/*.sh' | xargs shellcheck --severity=error --format=gcc
```

### Rule 3: Test Target Patterns

**ALL projects MUST have these test targets:**

- `make unit` - Unit tests (no external dependencies, no credentials required)
- `make unit-update-golden` - Update golden/snapshot files
- `make integration` - Integration tests (manual, requires credentials/fixtures)
- `make static` - MUST run unit tests + all static analysis

**Test Classification:**
- **Unit**: Can run with only project code, no external services
- **Integration**: Require credentials, databases, or external fixtures
- **System**: Require full deployment

### Rule 4: Pre-commit Hooks

MUST configure `.pre-commit-config.yaml` with:
1. **gitleaks** - Secret scanning (blocks commits with secrets)
2. **make static** - Runs all static checks before commit

Create `.gitleaksignore` for false positives.

### Rule 5: Dependabot Configuration

MUST create `.github/dependabot.yml` for all detected package ecosystems:
- `pip` (if Python)
- `npm` (if Node.js/CDK)
- `cargo` (if Rust)
- `gomod` (if Go)
- `github-actions` (always)

Configuration:
- Weekly schedule (Monday 9 AM ET)
- Group related packages
- Limit 5 PRs per ecosystem
- Appropriate labels

### Rule 6: CI/CD Workflow

MUST create `.github/workflows/static-check.yml` that:
- Runs `make static` **exactly once** per event
- Triggers on: PR pushes AND main branch pushes/merges
- Uses pinned GitHub Actions (commit SHA + version comment)

### Rule 7: CDK Projects (Conditional)

If CDK detected (presence of `cdk.json` or `app.py` with CDK imports), add these targets:

**Core CDK Operations:**
- `update_cdk_libs` - Install latest AWS CDK node and Python packages
- `cdk-ls` - List all CDK stacks (with `app_env` parameter)
- `cdk-diff` - Show infrastructure changes for single stack (requires `stack=<name>`)
- `cdk-diff-all` - Show infrastructure changes for ALL stacks using `'*'` wildcard
- `cdk-bootstrap` - Bootstrap account/region for environment

**Deployment & Destruction:**
- `cdk-deploy` - Deploy single stack (requires `stack=<name>` and `app_env`)
- `cdk-deploy-all` - Deploy all stacks in environment
- `cdk-destroy` - Destroy single stack with `--force` flag

**Key Details:**
- All CDK targets depend on `node_modules` and `.venv`
- CDK executable: `$(shell find . -type f -name cdk)`
- Pin Python version (e.g., `3.10.6`) and CDK version (e.g., `2.70.0`)
- All targets source `scripts/enable_pyenv.sh` for Python environment
- Default `app_env` is `dev`, overridable on command line
- Create `scripts/update_cdk_libs.sh` for syncing CDK CLI + library versions

**test-dependabot-pr Target:**
For CDK projects, add reminder to check infrastructure:
```makefile
test-dependabot-pr: clean-venv
	npm install
	$(MAKE) static-check
	@echo "⚠️  REMINDER: For CDK updates, also check infrastructure changes:"
	@echo "   make cdk-diff-all"
```

### Rule 8: Packer Projects (Conditional)

If Packer is detected (presence of `*.pkr.hcl` files), add these targets:

**Packer Version Management:**
- Pin `PACKER_VERSION` variable to exact version (e.g., `1.15.4`)
- Install packer into local `bin/packer/$(PACKER_VERSION)/packer` — never rely on system packer
- Install target fetches via pipeline-scripts: `curl --silent "https://raw.githubusercontent.com/natemarks/pipeline-scripts/v0.0.39/scripts/install_packer.sh" | bash -s -- -d bin/packer -r $(PACKER_VERSION)`
- Add `bin/packer/` to `.gitignore`

**Required Variables:**
```makefile
PACKER_VERSION := 1.15.4
PACKER_TEMPLATE := <name>.pkr.hcl
COMMIT := $(shell git rev-parse HEAD)
EC2_IP = $(shell aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=<prefix>_$(COMMIT)" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[PublicIpAddress]' \
  --output text | egrep -v 'None')
```
The `<prefix>` matches the AMI name prefix in the template (e.g., `aware`). `EC2_IP` is used by `packer_debug_ssh` to find the paused debug instance.

**Required Makefile Targets:**
- `bin/packer/$(PACKER_VERSION)/packer` — auto-download packer to local bin dir (prerequisite for other targets)
- `packer_format` — `packer fmt <template>` (auto-format)
- `packer_format_check` — `packer fmt -check <template>` (CI check, no modification)
- `packer_validate` — init plugins + `packer validate -var=... <template>`; removes plugin cache before init to avoid stale plugin issues
- `packer_debug` — debug build: depends on `git-status`; runs `PACKER_LOG=1 packer build -debug -var=... <template>`; pauses after each step and writes a `.pem` key file
- `packer_debug_ssh` — SSH into the paused debug instance: `ssh -i ./<source_name>.pem ec2-user@$(EC2_IP)`
- `packer_publish` — production build: depends on `git-status`; removes plugin cache, inits, builds with extended polling (`AWS_POLL_DELAY_SECONDS=15 AWS_MAX_ATTEMPTS=240`)
- `packer_cleanup` — dry-run cleanup of orphaned packer resources (instances, AMIs, snapshots)
- `packer_cleanup_force` — `DRY_RUN=false` cleanup
- `git-status` — guard that fails if working tree is dirty (required before builds that edit files)
- `undo_edits` — `git reset HEAD --hard && git clean -f` to restore working tree after a build

**Add to static checks:**
```makefile
static-check: black-check mypy shellcheck pylint packer_validate packer_format_check unit
static: black mypy shellcheck pylint packer_validate packer_format unit
```

**Debug Workflow (how `packer_debug` and `packer_debug_ssh` work together):**

`packer build -debug` pauses after each provisioner step and waits for the user to press Enter. When it launches the EC2 instance it writes a private key file named `<source_block_name>.pem` (e.g., `ec2_al2_ecs_optimized.pem`) to the working directory. The instance is tagged with `Name=<prefix>_$(COMMIT)` via `run_tags` in the HCL template. `EC2_IP` queries that tag to find the instance's public IP, so `make packer_debug_ssh` can connect immediately without any manual IP lookup.

Typical debug session:
1. `make packer_debug` — start the debug build (another terminal or after first pause)
2. `make packer_debug_ssh` — SSH in to inspect state between steps
3. Press Enter in the packer terminal to advance to the next step
4. `make undo_edits` — restore working tree when done

**SSH username convention:** Amazon Linux instances use `ec2-user`; Ubuntu uses `ubuntu`. Match the `ssh_username` in the HCL template.

---

## INTERVIEW PHASE

Ask user these questions **one at a time**. Provide context for each question.

### Pre-flight Check: Git Initialization

**BEFORE asking any questions, check if git is initialized:**

Run `test -d .git` to check for git repository.

**If .git exists:**
- Continue to Question 1

**If .git does NOT exist:**
- **Ask:** "Git is not initialized in this directory. The scaffolding process requires git for file operations (many make targets use `git ls-files`). Initialize git now?"
- **Options:** 
  - Yes (recommended)
  - No, I'll do it manually
- **Provide context:** "Git is required because: (1) make targets use `git ls-files` to find files, (2) pre-commit hooks need `.git/hooks/` directory, (3) better experience with one command vs. two."

**If user selects "Yes":**
```bash
git init
git config --local init.defaultBranch main
```
- Confirm: "✓ Git initialized with main as default branch"
- Continue to Question 1

**If user selects "No, I'll do it manually":**
- Show: "Please run `git init` and then re-run `/scaffold-project`"
- Exit skill (do not continue)

### Question 1: Project Language(s)
**Ask:** "What programming language(s) does this project use?"
**Options:**
- Python
- Go
- Rust
- Node.js/TypeScript
- Multiple languages (ask which ones)

**Provide context:** "This determines which static analysis tools and Makefile targets I'll configure."

### Question 2: CDK Project?
**Ask:** "Is this an AWS CDK project?"
**Options:** Yes / No

**If Yes, ask:** "Which language is the CDK app written in?" (Usually Python or TypeScript)

**Provide context:** "CDK projects get additional make targets for infrastructure management."

### Question 2b: Packer Project?
**Ask:** "Does this project build AMIs with Packer?"
**Options:** Yes / No

**If Yes, ask:**
- "What is the Packer template filename?" (e.g., `myapp.pkr.hcl`)
- "What Packer version should this project use?" (default: `1.15.4`)
- "What is the AMI name prefix used in the template?" (e.g., `myapp` — used for `EC2_IP` tag lookup during debug builds)
- "What is the SSH source block name in the template?" (e.g., `ec2_al2_ecs_optimized` — determines the `.pem` filename written during debug builds)
- "What SSH username does the base AMI use?" (default: `ec2-user` for Amazon Linux, `ubuntu` for Ubuntu)

**Provide context:** "Packer projects get targets for format, validate, debug builds (with SSH access to the build instance), and production publish."

### Question 3: Python Version (if Python detected)
**Ask:** "Which Python version should this project use?"
**Default:** 3.10.6 (or latest stable 3.x)

**Provide context:** "I'll configure pyenv and virtual environment with this version."

### Question 4: Test Framework
**Ask:** "Which test framework are you using?"
**Options:**
- Python: pytest (default)
- Go: go test (default)
- Rust: cargo test (default)
- Node.js: jest, mocha, vitest

**Provide context:** "I'll configure the unit test targets accordingly."

### Question 5: Golden File Testing
**Ask:** "Does this project use golden file / snapshot testing?"
**Options:** Yes / No / Not sure

**Provide context:** "If yes, I'll add a `unit-update-golden` target to refresh snapshots."

### Question 6: Existing Files
**Before creating anything, check:**
- Does `Makefile` exist? (Read it)
- Does `CLAUDE.md` exist? (Read it for context)
- Does `requirements.txt` / `package.json` / `Cargo.toml` / `go.mod` exist? (Read for pinning)
- Do GitHub workflows exist? (Check `.github/workflows/`)

**If files exist, ask:** "I found existing [file]. Should I:"
- Replace it with the new template
- Merge/update it with new targets
- Skip it

---

## SCAFFOLDING PHASE

Execute these steps IN ORDER. Verify each step before proceeding.

### Step 1: Create/Update Makefile

**Process:**
1. If Makefile exists, read it first
2. Identify missing required targets for detected language
3. Use appropriate template from TEMPLATES section below
4. Customize based on interview answers
5. Preserve any existing custom targets

**Verification:**
- [ ] `.DEFAULT_GOAL := help` exists
- [ ] `help` target exists and works
- [ ] All language-specific required targets present
- [ ] `static` target includes all checks
- [ ] `.PHONY` declarations present

### Step 2: Pin Dependency Versions

**For Python (requirements.txt):**
1. Read existing file
2. Get latest versions from PyPI: `curl -s https://pypi.org/pypi/<package>/json | jq -r '.info.version'`
3. Replace ranges with exact pins (`==`)
4. Ensure these are present and pinned:
   - `black==24.10.0`
   - `pylint==3.3.2`
   - `pytest==8.3.4`
   - `mypy==1.13.0`
   - `pre-commit==4.0.1`
5. Order logically (main deps first, then dev tools)

**For Node.js (package.json):**
1. Read existing file
2. Remove all `^` and `~` from versions
3. If CDK project, ensure CDK CLI and library versions match

**For Rust (Cargo.toml):**
1. Read existing file
2. Remove all `^` and `~` from versions
3. Verify exact versions

**For Go (go.mod):**
1. Read existing file
2. Verify versions are exact (Go defaults to this)

**Verification:**
- [ ] No version ranges (`^`, `~`, `>=`, `<`, etc.)
- [ ] All dependencies have exact versions

### Step 3: Create Pre-commit Configuration

**Create `.pre-commit-config.yaml`:**

Use template from TEMPLATES section. Always include:
1. gitleaks hook (pinned version)
2. Local hook for `make static`

**Create `.gitleaksignore`:**
```
# Gitleaks ignore patterns
# Add file paths or patterns for false positives
# Format: path/to/file.py:rule-name:line-number
```

**Add to requirements.txt (Python projects):**
```
pre-commit==4.0.1
```

**Verification:**
- [ ] `.pre-commit-config.yaml` exists
- [ ] `.gitleaksignore` exists
- [ ] `pre-commit` in requirements.txt (Python)

### Step 4: Create Dependabot Configuration

**Create `.github/dependabot.yml`:**

1. Detect package ecosystems present in project
2. Use template from TEMPLATES section
3. Add entry for each ecosystem: pip, npm, cargo, gomod, github-actions

**Customize groups based on project:**
- CDK projects: group `aws-cdk*` and `constructs`
- All projects: group dev tools (pytest, black, pylint, etc.)

**Verification:**
- [ ] `.github/dependabot.yml` exists
- [ ] Entries for all detected ecosystems
- [ ] Weekly schedule configured
- [ ] Appropriate grouping

### Step 5: Create GitHub Actions Workflow

**Create `.github/workflows/static-check.yml`:**

1. Use template from TEMPLATES section
2. Pin all actions to commit SHA with version comment
3. Set up language-specific environment (Python version, Go version, etc.)
4. Run `make static`

**Trigger configuration:**
```yaml
on:
  pull_request:
  push:
    branches:
      - main
```

**Verification:**
- [ ] Workflow file exists
- [ ] All actions pinned to commit SHA
- [ ] Language environment correctly configured
- [ ] Runs `make static` (not individual commands)

### Step 6: Create/Update CLAUDE.md

**If CLAUDE.md doesn't exist:**
Create it with sections:
- Repository Overview
- Technology Stack
- Code Standards
- Static Analysis Requirements (reference this skill)
- Testing Strategy
- Workflows (Git, CI/CD)
- Guidelines for Claude Code

**If CLAUDE.md exists:**
Read it and add section:
```markdown
## Static Analysis & Testing Standards

This project follows opinionated standards enforced by the `scaffold-project` skill:

1. **Pinned Dependencies**: All dependency versions are pinned to exact versions
2. **Static Analysis**: Run `make static` before committing
3. **Pre-commit Hooks**: Configured with gitleaks and make static
4. **Dependabot**: Configured for automated weekly updates
5. **CI/CD**: GitHub Actions runs static checks on PRs and main pushes

### Available Make Targets

Run `make help` to see all available targets. Key targets:
- `make static` - Run all static analysis checks
- `make unit` - Run unit tests
- `make unit-update-golden` - Update golden files
- `make integration` - Run integration tests (manual)

[Add CDK targets section if CDK project]
```

**Verification:**
- [ ] CLAUDE.md exists
- [ ] Standards section present
- [ ] Make targets documented

### Step 7: Create Scripts (if needed)

**For CDK Python projects:**

Create `scripts/enable_pyenv.sh`:
```bash
#!/usr/bin/env bash
# Enable pyenv if available
if command -v pyenv >/dev/null 2>&1; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
fi
```

Create `scripts/update_cdk_libs.sh`:
```bash
#!/usr/bin/env bash
set -e

# Get latest CDK version from PyPI
CDK_VERSION=$(curl -s https://pypi.org/pypi/aws-cdk-lib/json | jq -r '.info.version')
echo "Latest CDK version: $CDK_VERSION"

# Install CDK CLI via npm
npm install aws-cdk@$CDK_VERSION

# Update requirements.txt with pinned version
sed -i "s/aws-cdk-lib==.*/aws-cdk-lib==$CDK_VERSION/" requirements.txt
sed -i "s/constructs==.*/constructs==$(curl -s https://pypi.org/pypi/constructs/json | jq -r '.info.version')/" requirements.txt

echo "✓ CDK libraries updated to $CDK_VERSION"
```

Make scripts executable:
```bash
chmod +x scripts/*.sh
```

**Verification:**
- [ ] Scripts directory exists (if needed)
- [ ] Scripts are executable
- [ ] Scripts are shell-checked

### Step 7b: Packer Targets (if Packer project)

**Add to Makefile:**
1. Add packer variables at the top (PACKER_VERSION, PACKER_TEMPLATE, EC2_IP)
2. Add `bin/packer/$(PACKER_VERSION)/packer` download target
3. Add `packer_format`, `packer_format_check`, `packer_validate` targets
4. Add `git-status` and `undo_edits` guards
5. Add `packer_debug` and `packer_debug_ssh` targets
6. Add `packer_publish` target
7. Add `packer_cleanup` and `packer_cleanup_force` targets
8. Update `static` and `static-check` to include `packer_validate` and `packer_format_check`/`packer_format`
9. Add `.PHONY` declarations for all new targets

**Add to `.gitignore`:**
```
bin/packer/
*.pem
manifest.json
```
(`.pem` files are written by `packer build -debug` and must not be committed)

**Verification:**
- [ ] `PACKER_VERSION`, `PACKER_TEMPLATE`, `COMMIT`, `EC2_IP` variables defined
- [ ] Packer download target uses local bin dir
- [ ] `packer_debug` depends on `git-status`
- [ ] `packer_publish` depends on `git-status`
- [ ] `packer_validate` and `packer_format_check` in `static-check`
- [ ] `.pem` and `bin/packer/` in `.gitignore`

### Step 8: Install Pre-commit Hooks

**For Python projects:**
```bash
source .venv/bin/activate
pre-commit install
```

**Verification:**
- [ ] Pre-commit hooks installed in `.git/hooks/`

---

## VERIFICATION PHASE

Before reporting completion, verify ALL requirements:

### Checklist

Run through this checklist. If ANY item fails, FIX IT before completing.

**Makefile:**
- [ ] All required targets exist for detected language
- [ ] `make help` works
- [ ] `make static` target exists and includes all checks
- [ ] Test targets exist: `unit`, `unit-update-golden`, `integration`
- [ ] CDK targets exist (if CDK project)
- [ ] Packer targets exist (if Packer project): `packer_validate`, `packer_format`, `packer_format_check`, `packer_debug`, `packer_debug_ssh`, `packer_publish`, `git-status`, `undo_edits`
- [ ] `packer_validate` and `packer_format_check` included in `static-check` (if Packer project)

**Dependencies:**
- [ ] All versions pinned (no ranges)
- [ ] Required static analysis tools in requirements.txt (Python)
- [ ] `pre-commit` in requirements.txt (Python)

**Configuration Files:**
- [ ] `.pre-commit-config.yaml` exists
- [ ] `.gitleaksignore` exists
- [ ] `.github/dependabot.yml` exists
- [ ] `.github/workflows/static-check.yml` exists
- [ ] CLAUDE.md exists and documents standards

**Functional Verification:**
- [ ] Run `make static` - should work without errors (or document expected failures)
- [ ] Run `make help` - should show all targets
- [ ] Check GitHub Actions syntax: `gh workflow view static-check`

### Final Report

After verification passes, report to user:

```
✅ Project scaffolding complete!

Created/Updated:
- Makefile with [language] static analysis targets
- .pre-commit-config.yaml (gitleaks + make static)
- .github/dependabot.yml ([ecosystems])
- .github/workflows/static-check.yml
- CLAUDE.md with project standards
[- scripts/ directory with CDK helper scripts] (if CDK)
[- Packer targets: packer_debug, packer_debug_ssh, packer_publish] (if Packer)

Next steps:
1. Review the generated files
2. Run `make static` to verify setup
3. Install pre-commit hooks: `pre-commit install`
4. Commit the scaffolding: `git add . && git commit -m "chore: add project scaffolding"`

All dependencies are pinned and static analysis is configured!
```

---

## TEMPLATES

> **REFERENCE ONLY** — consult during scaffolding steps; not a checklist to run top-to-bottom.

### Python Makefile Template

```makefile
.DEFAULT_GOAL := help
SHELL := $(shell which bash)
PYTHON_VERSION := {{PYTHON_VERSION}}

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

.venv: ## create venv if it doesn't exist
	python3 -m venv .venv
	source .venv/bin/activate && pip install --upgrade pip setuptools
	source .venv/bin/activate && pip install -r requirements.txt

clean-venv: clean-cache ## re-create virtual env
	[[ -e .venv ]] && rm -rf .venv
	$(MAKE) .venv

black: .venv ## format python files
	source .venv/bin/activate && git ls-files '*.py' | xargs black --line-length=79

black-check: .venv ## check python formatting without modifying
	source .venv/bin/activate && git ls-files '*.py' | xargs black --check --line-length=79

pylint: .venv ## lint python files
	source .venv/bin/activate && git ls-files '*.py' | xargs pylint --max-line-length=90

mypy: .venv ## type check python files
	source .venv/bin/activate && python3 -m mypy $(shell git ls-files '*.py')

shellcheck: ## check shell scripts
	git ls-files 'scripts/*.sh' | xargs shellcheck --severity=error --format=gcc

unit: .venv ## run unit tests
	source .venv/bin/activate && python3 -m pytest -v -m "unit" tests/

unit-update-golden: .venv ## update golden files
	source .venv/bin/activate && python3 -m pytest -v -m "unit" tests/ --update_golden

integration: .venv ## run integration tests (requires credentials)
	source .venv/bin/activate && python3 -m pytest -v -m "integration" tests/

static-check: black-check mypy shellcheck pylint unit ## run all static checks (CI)

static: black mypy shellcheck pylint unit ## run all static checks with auto-format

clean-cache: ## clean python and pytest cache data
	@find . -type f -name "*.py[co]" -delete -not -path "./.venv/*"
	@find . -type d -name __pycache__ -not -path "./.venv/*" -exec rm -rf {} + 2>/dev/null || true
	@rm -rf .pytest_cache

.PHONY: help black black-check pylint mypy shellcheck unit unit-update-golden integration static static-check clean-cache clean-venv
```

### Python + CDK Makefile Template

```makefile
.DEFAULT_GOAL := help
SHELL := $(shell which bash)
PYTHON_VERSION := {{PYTHON_VERSION}}
CDK_VERSION := {{CDK_VERSION}}
CDK := node_modules/.bin/cdk
app_env := dev

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

.venv: ## create venv if it doesn't exist
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   python3 -m venv .venv; \
	   source .venv/bin/activate; \
	   pip install --upgrade pip setuptools; \
	   pip install -r requirements.txt; \
	)

clean-venv: clean-cache ## re-create virtual env
	[[ -e .venv ]] && rm -rf .venv
	$(MAKE) .venv

node_modules: ## create node_modules if it doesn't exist
	npm install

update_cdk_libs: .venv ## install the latest version of aws cdk node and python packages
	bash scripts/update_cdk_libs.sh
	$(MAKE) clean-venv

black: .venv ## format python files
	( \
	   source .venv/bin/activate; \
	   git ls-files '*.py' | xargs black --line-length=79; \
	)

black-check: .venv ## check python formatting without modifying
	( \
	   source .venv/bin/activate; \
	   git ls-files '*.py' | xargs black --check --line-length=79; \
	)

pylint: .venv ## lint python files
	( \
	   source .venv/bin/activate; \
	   git ls-files '*.py' | xargs pylint --max-line-length=90; \
	)

mypy: .venv ## type check python files
	( \
	   source .venv/bin/activate; \
	   python3 -m mypy $(shell git ls-files '*.py'); \
	)

shellcheck: ## check shell scripts
	git ls-files 'scripts/*.sh' | xargs shellcheck --severity=error --format=gcc

unit: .venv ## run unit tests
	( \
	   source .venv/bin/activate; \
	   python3 -m pytest -v -m "unit" tests/; \
	)

unit-update-golden: .venv ## update golden files
	( \
	   source .venv/bin/activate; \
	   python3 -m pytest -v -m "unit" tests/ --update_golden; \
	)

integration: .venv ## run integration tests (requires credentials)
	( \
	   source .venv/bin/activate; \
	   python3 -m pytest -v -m "integration" tests/; \
	)

static-check: black-check mypy shellcheck pylint unit ## run all static checks (CI)

static: black mypy shellcheck pylint unit ## run all static checks with auto-format

test-dependabot-pr: clean-venv ## test a Dependabot PR (install deps + run all checks)
	@echo "=== Installing npm packages from package.json ==="
	npm install
	@echo ""
	@echo "=== Running static checks (shellcheck, black, pylint, unit tests) ==="
	$(MAKE) static-check
	@echo ""
	@echo "✓ All checks passed!"
	@echo ""
	@echo "⚠️  REMINDER: For CDK updates, also check infrastructure changes:"
	@echo "   make cdk-diff-all"
	@echo ""
	@echo "If all looks good, merge the PR:"
	@echo "   gh pr merge <PR#> --squash"
	@echo ""

cdk-ls: node_modules .venv ## list all CDK stacks
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) ls -c app_env=$(app_env); \
	)

cdk-diff: node_modules .venv ## cdk diff a single stack (usage: make cdk-diff stack=MyStack)
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) diff $(stack) -c app_env=$(app_env); \
	)

cdk-diff-all: node_modules .venv ## cdk diff all stacks in the environment
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) diff '*' -c app_env=$(app_env); \
	)

cdk-deploy: node_modules .venv ## cdk deploy a single stack (usage: make cdk-deploy stack=MyStack)
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) deploy --require-approval never $(stack) -c app_env=$(app_env); \
	)

cdk-deploy-all: node_modules .venv ## cdk deploy all stacks in an environment
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) deploy --all -c app_env=$(app_env); \
	)

cdk-destroy: node_modules .venv ## cdk destroy a single stack (usage: make cdk-destroy stack=MyStack)
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) destroy --force $(stack) -c app_env=$(app_env); \
	)

cdk-bootstrap: node_modules .venv ## bootstrap the default account and region for an environment
	$(eval CDK := $(shell find . -type f -name cdk))
	( \
	   source scripts/enable_pyenv.sh; \
	   pyenv local $(PYTHON_VERSION); \
	   source .venv/bin/activate; \
	   $(CDK) bootstrap -c app_env=$(app_env); \
	)

clean-cache: ## clean python and pytest cache data
	@find . -type f -name "*.py[co]" -delete -not -path "./.venv/*"
	@find . -type d -name __pycache__ -not -path "./.venv/*" -exec rm -rf {} + 2>/dev/null || true
	@rm -rf .pytest_cache

.PHONY: help black black-check pylint mypy shellcheck unit unit-update-golden integration static static-check test-dependabot-pr cdk-ls cdk-diff cdk-diff-all cdk-deploy cdk-deploy-all cdk-destroy cdk-bootstrap clean-cache clean-venv update_cdk_libs
```

### Packer Makefile Additions Template

Add these variables and targets to a Python or Python+CDK Makefile when Packer is present. Substitute `{{PACKER_TEMPLATE}}` with the actual `.pkr.hcl` filename, `{{AMI_PREFIX}}` with the AMI name prefix, `{{SSH_SOURCE_NAME}}` with the source block name (determines `.pem` filename), and `{{SSH_USER}}` with the SSH username.

```makefile
PACKER_VERSION := 1.15.4
PACKER_TEMPLATE := {{PACKER_TEMPLATE}}
COMMIT := $(shell git rev-parse HEAD)
EC2_IP = $(shell aws ec2 describe-instances \
  --filters "Name=tag:Name,Values={{AMI_PREFIX}}_$(COMMIT)" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[PublicIpAddress]' \
  --output text | egrep -v 'None')

git-status: ## require clean working tree (build process edits files)
	@status=$$(git status --porcelain); \
	if [ ! -z "$${status}" ]; \
	then \
		echo "Error - working directory is dirty. Commit those changes!"; \
		exit 1; \
	fi

undo_edits: ## restore working tree after a build (reverses any file edits made during build)
	git reset HEAD --hard
	git clean -f

bin/packer/$(PACKER_VERSION)/packer: ## install packer into local bin dir
	bash -c 'curl --silent "https://raw.githubusercontent.com/natemarks/pipeline-scripts/v0.0.39/scripts/install_packer.sh" | bash -s -- -d bin/packer -r $(PACKER_VERSION)'

packer_format: bin/packer/$(PACKER_VERSION)/packer ## format packer template
	bin/packer/$(PACKER_VERSION)/packer fmt $(PACKER_TEMPLATE)

packer_format_check: bin/packer/$(PACKER_VERSION)/packer ## check packer template formatting (no modification)
	bin/packer/$(PACKER_VERSION)/packer fmt -check $(PACKER_TEMPLATE)

packer_validate: bin/packer/$(PACKER_VERSION)/packer ## validate packer template
	rm -rf $${HOME}/.config/packer/plugins/github.com/hashicorp/amazon; \
	bin/packer/$(PACKER_VERSION)/packer init $(PACKER_TEMPLATE); \
	bin/packer/$(PACKER_VERSION)/packer validate \
	-var="region=us-east-1" \
	-var="version=$(COMMIT)" $(PACKER_TEMPLATE)

packer_debug: git-status bin/packer/$(PACKER_VERSION)/packer ## debug build: pauses after each step, writes .pem key file
	PACKER_LOG=1 bin/packer/$(PACKER_VERSION)/packer build -debug \
	-var="region=us-east-1" \
	-var="version=$(COMMIT)" \
	$(PACKER_TEMPLATE)

packer_debug_ssh: ## ssh into the paused debug build instance
	ssh -i ./{{SSH_SOURCE_NAME}}.pem {{SSH_USER}}@$(EC2_IP)

packer_publish: git-status bin/packer/$(PACKER_VERSION)/packer ## build and publish the AMI (production)
	[[ -e manifest.json ]] && rm -f manifest.json; \
	rm -rf $${HOME}/.config/packer/plugins/github.com/hashicorp/amazon; \
	bin/packer/$(PACKER_VERSION)/packer init $(PACKER_TEMPLATE); \
	AWS_POLL_DELAY_SECONDS=15 \
	AWS_MAX_ATTEMPTS=240 \
	PACKER_LOG=1 bin/packer/$(PACKER_VERSION)/packer build \
	-var="region=us-east-1" \
	-var="version=$(COMMIT)" \
	$(PACKER_TEMPLATE);

packer_cleanup: ## check for orphaned packer resources (dry run)
	@echo "Checking for orphaned Packer artifacts..."
	bash scripts/cleanup_packer_artifacts.sh

packer_cleanup_force: ## delete orphaned packer resources
	@echo "Cleaning up orphaned Packer artifacts..."
	DRY_RUN=false bash scripts/cleanup_packer_artifacts.sh
```

**Update static targets to include packer checks:**
```makefile
static-check: black-check mypy shellcheck pylint packer_validate packer_format_check unit

static: black mypy shellcheck pylint packer_validate packer_format unit
```

**Add to `.PHONY`:**
```makefile
.PHONY: ... git-status undo_edits packer_format packer_format_check packer_validate packer_debug packer_debug_ssh packer_publish packer_cleanup packer_cleanup_force
```

**Notes:**
- `packer_debug` and `packer_publish` both require `git-status` because the build process edits files; `undo_edits` restores them
- The `.pem` file written by `-debug` mode is named after the HCL source block: `source "amazon-ebs" "{{SSH_SOURCE_NAME}}"` → `{{SSH_SOURCE_NAME}}.pem`
- `EC2_IP` finds the running instance by the `Name` run_tag set in the HCL template (must match `{{AMI_PREFIX}}_$(COMMIT)`)
- Plugin cache (`~/.config/packer/plugins/`) is cleared before each `init` to avoid stale plugin issues
- If CDK manages the packer build VPC, `packer_publish` should also depend on `cdk-pkr-vpc`

---

### Go Makefile Template

```makefile
.DEFAULT_GOAL := help
SHELL := $(shell which bash)

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

goimports: ## format imports
	goimports -w .

fmt: ## format code
	go fmt ./...

vet: ## run go vet
	go vet ./...

lint: ## run staticcheck
	staticcheck ./...

gocyclo: ## check cyclomatic complexity
	gocyclo -over 25 .

govulncheck: ## scan for known vulnerabilities
	govulncheck ./...

shellcheck: ## check shell scripts
	git ls-files 'scripts/*.sh' | xargs shellcheck --severity=error --format=gcc

unit: ## run unit tests
	go test -v -short ./...

unit-update-golden: ## update golden files
	go test -v -short ./... -update

integration: ## run integration tests (requires credentials)
	go test -v ./...

static: goimports fmt vet lint gocyclo govulncheck shellcheck unit ## run all static checks

clean-cache: ## clean Go test and build cache
	go clean -testcache
	go clean -cache

.PHONY: help goimports fmt vet lint gocyclo govulncheck shellcheck unit unit-update-golden integration static clean-cache
```

### Rust Makefile Template

```makefile
.DEFAULT_GOAL := help
SHELL := $(shell which bash)

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

fmt: ## format code
	cargo fmt

fmt-check: ## check code formatting
	cargo fmt -- --check

clippy: ## run clippy linter
	cargo clippy -- -D warnings

dead-code: ## check for dead code
	RUSTFLAGS="-D dead_code" cargo check

audit: ## scan for vulnerable dependencies
	cargo audit

shellcheck: ## check shell scripts
	git ls-files 'scripts/*.sh' | xargs shellcheck --severity=error --format=gcc

unit: ## run unit tests
	cargo test

unit-update-golden: ## update golden files (if using goldie or similar)
	UPDATE_GOLDENFILES=1 cargo test

integration: ## run integration tests
	cargo test --test '*'

static: fmt-check clippy dead-code audit shellcheck unit ## run all static checks

clean-cache: ## clean Rust build artifacts
	cargo clean

.PHONY: help fmt fmt-check clippy dead-code audit shellcheck unit unit-update-golden integration static clean-cache
```

### .pre-commit-config.yaml Template

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks

  - repo: local
    hooks:
      - id: make-static
        name: Run make static
        entry: make static
        language: system
        pass_filenames: false
```

### .github/dependabot.yml Template (Python)

```yaml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "America/New_York"
    groups:
      dev-tools:
        patterns:
          - "pytest"
          - "black"
          - "pylint"
          - "mypy"
          - "pre-commit"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "deps"
      include: "scope"
    labels:
      - "dependencies"
      - "python"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "America/New_York"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "ci"
      include: "scope"
    labels:
      - "dependencies"
      - "github-actions"
```

### .github/dependabot.yml Template (Python + CDK)

```yaml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "America/New_York"
    groups:
      cdk-ecosystem:
        patterns:
          - "aws-cdk*"
          - "constructs"
      dev-tools:
        patterns:
          - "pytest"
          - "black"
          - "pylint"
          - "mypy"
          - "pre-commit"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "deps"
      include: "scope"
    labels:
      - "dependencies"
      - "python"

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "America/New_York"
    groups:
      cdk-cli:
        patterns:
          - "aws-cdk"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "deps"
      include: "scope"
    labels:
      - "dependencies"
      - "npm"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "America/New_York"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "ci"
      include: "scope"
    labels:
      - "dependencies"
      - "github-actions"
```

### .github/workflows/static-check.yml Template (Python)

```yaml
name: Static Analysis

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  static-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3

      - name: Set up Python
        uses: actions/setup-python@0b93645e9fea7318ecaed2b359559ac225c90a2b  # v5.3.0
        with:
          python-version: '{{PYTHON_VERSION}}'

      - name: Run static checks
        run: make static-check
```

### .github/workflows/static-check.yml Template (Go)

```yaml
name: Static Analysis

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  static-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3

      - name: Set up Go
        uses: actions/setup-go@41dfa10bad2bb2ae585af6ee5bb4d7d973ad74ed  # v5.1.0
        with:
          go-version: '1.21'

      - name: Install tools
        run: |
          go install honnef.co/go/tools/cmd/staticcheck@latest
          go install github.com/fzipp/gocyclo/cmd/gocyclo@latest
          go install golang.org/x/vuln/cmd/govulncheck@latest
          go install golang.org/x/tools/cmd/goimports@latest

      - name: Run static checks
        run: make static
```

### .github/workflows/static-check.yml Template (Rust)

```yaml
name: Static Analysis

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  static-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3

      - name: Set up Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Install cargo-audit
        run: cargo install cargo-audit

      - name: Run static checks
        run: make static
```

---

## TIPS & TROUBLESHOOTING

### Common Issues

**Issue: make static fails on first run**
- Expected for new projects without test files
- Create minimal test file first, then run again

**Issue: GitHub Actions SHA comments missing**
- Find correct SHA: Visit action's GitHub releases, copy commit SHA for version tag
- Format: `uses: owner/action@<SHA>  # v1.2.3`

**Issue: CDK version mismatch**
- CLI and library must match exactly
- Use `scripts/update_cdk_libs.sh` to sync versions

**Issue: pre-commit hook too slow**
- Consider splitting into pre-commit (fast) and pre-push (slow) hooks
- Keep gitleaks in pre-commit, move `make static` to pre-push

**Issue: Dependabot PRs fail static checks**
- Expected if golden files need updating
- Document fix process in DEPENDABOT.md
- Consider `test-dependabot-pr` target for local testing

**Packer debug workflow:**
- `packer build -debug` pauses before each provisioner step and waits for Enter
- It writes `<source_name>.pem` to the working dir on first pause (instance is up and ready)
- While paused, `make packer_debug_ssh` connects using that PEM + the `EC2_IP` lookup
- Advance the build by pressing Enter in the packer terminal
- If `EC2_IP` returns empty: verify the `run_tags` block in the HCL uses `Name = "<prefix>_${var.version}"` and that COMMIT matches
- When done (success or abort), run `make undo_edits` to clean up edits the build made

**Packer validate fails in CI:**
- `packer validate` calls `packer init` which downloads plugins — CI runners must have internet access or pre-cached plugins
- The plugin cache purge (`rm -rf ~/.config/packer/plugins/...`) before init avoids "wrong version" errors after plugin upgrades

**Packer build stuck / orphaned resources:**
- Use `make packer_cleanup` (dry run) then `make packer_cleanup_force` to remove instances, AMIs, and snapshots left by failed builds
- Requires `scripts/cleanup_packer_artifacts.sh` to be implemented in the project

### Best Practices

1. **Start minimal, add complexity later** - Don't overwhelm new projects
2. **Test make targets immediately** - Catch issues early
3. **Document exceptions** - If skipping a required tool, explain why in CLAUDE.md
4. **Pin aggressively** - Better to update intentionally than break unexpectedly
5. **Group Dependabot updates** - Reduces PR noise, easier to review

### Language-Specific Notes

**Python:**
- Use pytest markers for test types: `@pytest.mark.unit`, `@pytest.mark.integration`
- Consider `pytest-golden` or `pytest-snapshot` for golden file testing
- mypy strict mode optional, document in CLAUDE.md if used

**Go:**
- Use `staticcheck` for comprehensive static analysis
- Build tags for integration tests: `// +build integration`
- Install tools: `go install honnef.co/go/tools/cmd/staticcheck@latest`

**Rust:**
- Dead code detection is built into `cargo check` with RUSTFLAGS
- Consider `cargo-deny` for supply chain security policies
- `cargo clippy` is the standard linter (replaces older tools)

**CDK:**
- Always keep CLI and library versions synchronized
- Test infrastructure changes: `make cdk-diff-all`
- Consider `cdk-nag` for security/compliance checks

