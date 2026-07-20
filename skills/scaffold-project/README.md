# scaffold-project Skill

Automatically scaffold a new project with opinionated, battle-tested standards for static analysis, testing, security, and CI/CD.

## What It Does

This skill creates a complete, production-ready project structure with:

- ✅ **Language-specific Makefile** with static analysis targets (Python, Go, Rust, CDK)
- ✅ **Pinned dependencies** (no version ranges that break unexpectedly)
- ✅ **Pre-commit hooks** (gitleaks secret scanning + make static)
- ✅ **Dependabot configuration** (automated weekly dependency updates)
- ✅ **GitHub Actions workflow** (runs static checks on PRs and main)
- ✅ **CLAUDE.md** project standards file
- ✅ **CDK infrastructure targets** (for AWS CDK projects)

## When to Use

### ✅ Perfect For:
- **New projects** - Starting fresh with best practices baked in
- **Standardizing existing projects** - Adding missing tooling and conventions
- **Team consistency** - Enforcing same standards across multiple projects
- **CDK projects** - Adds specialized infrastructure management targets

### ⚠️ Consider Carefully:
- **Non-standard workflows** - If your team uses different tools (e.g., poetry, gradle)
- **Monorepos** - May need customization for multi-language repos
- **Legacy projects** - Retrofitting might conflict with existing tooling

## Workflow

### Option 1: New Project (Recommended)

```bash
# 1. Create project directory
mkdir my-new-project
cd my-new-project

# 2. Initialize git (REQUIRED - skill uses git commands)
git init

# 3. Run the skill
/scaffold-project
```

### Option 2: Existing Project

```bash
# 1. Navigate to project
cd existing-project

# 2. Ensure git is initialized
git status  # If this works, you're good

# 3. Run the skill
/scaffold-project
```

The skill will:
- Detect existing files (Makefile, requirements.txt, etc.)
- Ask whether to replace, merge, or skip each one
- Preserve your custom targets while adding required ones

## What Gets Created

### All Projects
```
.github/
├── dependabot.yml              # Automated dependency updates
└── workflows/
    └── static-check.yml        # CI/CD pipeline

.pre-commit-config.yaml         # Pre-commit hooks config
.gitleaksignore                 # Secret scanning exceptions
Makefile                        # Build and validation targets
CLAUDE.md                       # Project standards documentation
```

### Python Projects
```
requirements.txt                # Pinned dependencies with static analysis tools
.venv/                          # Virtual environment (created by make .venv)
```

### Go Projects
```
go.mod                          # Pinned Go dependencies
go.sum                          # Dependency checksums
```

### Rust Projects
```
Cargo.toml                      # Pinned Rust dependencies
Cargo.lock                      # Dependency lock file
```

### CDK Projects (Python)
```
scripts/
├── enable_pyenv.sh             # Python environment setup
└── update_cdk_libs.sh          # CDK version sync script

package.json                    # CDK CLI (pinned version)
package-lock.json               # npm lock file
cdk.json                        # CDK app configuration
```

## Make Targets Reference

### Python Projects
```bash
make help                       # Show all available targets
make static                     # Run all checks (auto-format first)
make static-check               # Run all checks (CI mode, no changes)
make unit                       # Run unit tests
make unit-update-golden         # Update golden/snapshot files
make integration                # Run integration tests
make black                      # Format Python code
make pylint                     # Lint Python code
make mypy                       # Type check Python code
make shellcheck                 # Check shell scripts
```

### CDK Projects (Additional)
```bash
make cdk-ls                     # List all CDK stacks
make cdk-diff-all               # Show infrastructure changes
make cdk-deploy stack=MyStack   # Deploy a single stack
make cdk-deploy-all             # Deploy all stacks
make cdk-destroy stack=MyStack  # Destroy a stack
make update_cdk_libs            # Update CDK to latest version
make test-dependabot-pr         # Test Dependabot PRs locally
```

### Go Projects
```bash
make static                     # Run all checks
make unit                       # Run unit tests
make integration                # Run integration tests
make lint                       # Run staticcheck
make gocyclo                    # Check complexity
make govulncheck                # Scan vulnerabilities
```

### Rust Projects
```bash
make static                     # Run all checks
make unit                       # Run tests
make clippy                     # Run clippy linter
make audit                      # Scan vulnerabilities
make fmt                        # Format code
```

## After Scaffolding

### 1. Verify Setup
```bash
# Test that static checks work
make static

# Show available targets
make help

# Check pre-commit hooks
pre-commit --version
```

### 2. Install Pre-commit Hooks (Python)
```bash
# Create virtual environment
make .venv

# Install pre-commit hooks
source .venv/bin/activate
pre-commit install
```

### 3. Commit the Scaffolding
```bash
git add .
git commit -m "chore: add project scaffolding

- Add Makefile with static analysis targets
- Configure pre-commit hooks (gitleaks + make static)
- Configure Dependabot for automated updates
- Add GitHub Actions CI/CD workflow
- Pin all dependency versions"
```

### 4. Set Up GitHub Repository (Optional)
```bash
# Create GitHub repo
gh repo create

# Push code
git push -u origin main

# Verify GitHub Actions runs
gh workflow view static-check
```

### 5. Review and Customize
- **CLAUDE.md** - Add project-specific details
- **Makefile** - Add custom targets if needed
- **.gitleaksignore** - Add false positive patterns
- **.github/dependabot.yml** - Adjust update schedule or grouping

## Git Initialization

### Does the skill require git to be initialized?

**Yes, git must be initialized BEFORE running the skill.**

The skill uses git commands:
- `git ls-files '*.py'` - Find files to analyze
- `git status` - Check working tree state
- `git add .` - Stage new files

### Should the skill run `git init` automatically?

**Yes - the skill should check and offer to initialize git if needed.**

This is a reasonable enhancement. The skill should:
1. Check if `.git` directory exists
2. If not, ask: "Git is not initialized. Initialize now? (Recommended)"
3. If yes, run `git init`
4. Continue with scaffolding

## Extending the Skill: Git Init

To add git initialization to the skill, add this to the INTERVIEW PHASE:

```markdown
### Question 0: Git Initialization (Pre-flight)

**Check if .git exists:**
- Run `test -d .git`
- If exists: Continue to Question 1
- If not exists:

**Ask:** "Git is not initialized in this directory. The scaffolding process requires git for file operations. Initialize git now?"

**Options:** Yes (recommended) / No / I'll do it manually

**If Yes:**
- Run `git init`
- Run `git config --local init.defaultBranch main` (set default branch)
- Confirm: "✓ Git initialized"
- Continue to Question 1

**If No / Manual:**
- Show: "Please run `git init` and then re-run /scaffold-project"
- Exit skill

**Rationale:** 
- Many make targets use `git ls-files` for finding files to analyze
- Pre-commit hooks require `.git/hooks/` directory
- Provides better user experience (one command instead of two)
```

## Troubleshooting

### "make: command not found"
**Solution:** Install make (varies by OS)
- macOS: `xcode-select --install`
- Ubuntu/Debian: `apt-get install build-essential`
- Fedora/RHEL: `dnf install make`

### "git ls-files returns no files"
**Cause:** Files not committed to git yet
**Solution:** This is expected for new projects. Make targets will work once files are added.

### "pre-commit: command not found"
**Cause:** pre-commit not installed
**Solution:** 
```bash
pip install pre-commit  # Python
# or
brew install pre-commit  # macOS
```

### "make static fails on first run"
**Cause:** No test files exist yet
**Solution:** Expected for brand new projects. Create a minimal test file:
```python
# tests/test_example.py
import pytest

@pytest.mark.unit
def test_example():
    assert True
```

### "GitHub Actions fails with permission denied"
**Cause:** Actions need write permissions
**Solution:** Go to Settings > Actions > General > Workflow permissions > Select "Read and write permissions"

### "Dependabot PRs fail static checks"
**Cause:** Golden files need updating or formatting changes
**Solution:** See `DEPENDABOT.md` (created by /configure-dependabot skill)

## Related Skills

- **`/init-project`** - Comprehensive project interview + CLAUDE.md generation (no scaffolding)
- **`/configure-dependabot`** - Deep dive into Dependabot configuration (included in scaffold-project)
- **`/make-static`** - Analyze and add static analysis to existing Makefile

## Examples

### Example 1: Python CLI Tool
```bash
mkdir my-cli-tool
cd my-cli-tool
git init

# Run skill
/scaffold-project

# Follow prompts:
# - Language: Python
# - CDK: No
# - Python version: 3.10
# - Test framework: pytest
# - Golden files: No

# Result: Python Makefile + pre-commit + Dependabot + CI/CD
```

### Example 2: AWS CDK Infrastructure
```bash
mkdir my-infrastructure
cd my-infrastructure
git init

# Run skill
/scaffold-project

# Follow prompts:
# - Language: Python
# - CDK: Yes
# - Python version: 3.10
# - Test framework: pytest
# - Golden files: Yes

# Result: CDK Makefile + scripts/ + pre-commit + Dependabot + CI/CD
```

### Example 3: Go Microservice
```bash
mkdir my-service
cd my-service
git init

# Run skill
/scaffold-project

# Follow prompts:
# - Language: Go
# - CDK: No
# - Test framework: go test
# - Golden files: Yes

# Result: Go Makefile + pre-commit + Dependabot + CI/CD
```

### Example 4: Multi-Language Project
```bash
mkdir full-stack-app
cd full-stack-app
git init

# Run skill
/scaffold-project

# Follow prompts:
# - Language: Multiple (Python + TypeScript)
# - CDK: No
# - Python version: 3.10
# - Test framework: pytest + jest

# Result: Hybrid Makefile + pre-commit + Dependabot + CI/CD
# Note: May need manual customization for multi-language
```

## Design Philosophy

This skill enforces opinionated standards based on lessons learned:

1. **Pin everything** - Version ranges break unexpectedly. Pin to exact versions and update intentionally.

2. **Static analysis before commit** - Catch issues early, before CI/CD. Fast feedback loop.

3. **Automate dependency updates** - Dependabot keeps dependencies current without manual toil.

4. **Make as the universal interface** - Consistent commands across projects (`make static`, `make test`).

5. **Security by default** - Gitleaks prevents secret commits. Pre-commit hooks enforce standards.

6. **CI/CD from day one** - GitHub Actions configured from the start, not bolted on later.

7. **Golden file testing** - Snapshot testing reduces test maintenance burden.

## Customization

The skill creates a baseline. Customize for your needs:

### Add Custom Make Targets
```makefile
# Add to Makefile after scaffolding
deploy-dev: .venv ## deploy to dev environment
	source .venv/bin/activate && ./scripts/deploy.sh dev

benchmark: .venv ## run performance benchmarks
	source .venv/bin/activate && pytest -v -m "benchmark" tests/
```

### Adjust Static Analysis Strictness
```makefile
# Relax pylint scoring
pylint: .venv
	source .venv/bin/activate && pylint --fail-under=8.0 *.py

# Enable mypy strict mode
mypy: .venv
	source .venv/bin/activate && mypy --strict *.py
```

### Add More Pre-commit Hooks
```yaml
# .pre-commit-config.yaml
repos:
  # ... existing gitleaks hook ...
  
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
```

### Adjust Dependabot Frequency
```yaml
# .github/dependabot.yml - change from weekly to daily
schedule:
  interval: "daily"
  time: "09:00"
  timezone: "America/New_York"
```

## Feedback & Issues

This is a user-created skill. To suggest improvements:

1. **Edit the skill**: `~/.claude/skills/scaffold-project/SKILL.md`
2. **Test changes**: Run `/scaffold-project` in a test directory
3. **Share improvements**: Document patterns that work well for your team

## Version History

- **v1.0** - Initial release with Python, Go, Rust, and CDK support
- **v1.1** - Removed deprecated tool references (golint, deadcode)

---

**Last Updated:** 2026-07-17
