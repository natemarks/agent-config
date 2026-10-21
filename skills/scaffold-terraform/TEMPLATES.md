# Templates

Reference for `scaffold-terraform`. Substitute `{{PLACEHOLDERS}}` from the interview.

## .mise.toml

```toml
[tools]
terraform = "{{TERRAFORM_VERSION}}"
terragrunt = "{{TERRAGRUNT_VERSION}}"   # terragrunt layout only
tflint = "{{TFLINT_VERSION}}"
awscli = "{{AWSCLI_VERSION}}"
pre-commit = "{{PRE_COMMIT_VERSION}}"
```

## .gitignore

```
.terraform/
.terragrunt-cache/
.terragrunt-stack/
.terraform-plugin-cache/
*.tfstate
*.tfstate.*
crash.log
*.auto.tfvars
.idea/
.DS_Store
scratch.txt

# terragrunt layout: generated files
backend.tf
versions.tf
.terraform.lock.hcl
```

For the terraform layout drop the three generated entries (`backend.tf`, `versions.tf`, `.terraform.lock.hcl`): those files are committed.

## Terraform layout

### versions.tf
```hcl
terraform {
  required_version = "= {{TERRAFORM_VERSION}}"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "{{AWS_PROVIDER_VERSION}}"
    }
  }
}
```

### backend.tf
```hcl
terraform {
  backend "s3" {
    bucket       = "{{STATE_BUCKET}}"
    key          = "{{PROJECT_NAME}}/terraform.tfstate"
    region       = "{{STATE_REGION}}"
    encrypt      = true
    use_lockfile = true # or: dynamodb_table = "terraform-locks"
  }
}
```

### providers.tf
```hcl
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = var.tags
  }
}
```

### variables.tf
```hcl
variable "region" {
  type    = string
  default = "{{PRIMARY_REGION}}"
}

variable "aws_account_id" {
  type        = string
  description = "Guard: apply fails against any other account"
}

variable "tags" {
  type = map(string)
  default = {
    project = "{{PROJECT_NAME}}"
  }
}
```

`main.tf` and `outputs.tf` start empty with a one-line comment.

### .tflint.hcl
```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "{{TFLINT_AWS_RULESET_VERSION}}"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```

### Makefile (terraform)

```makefile
.DEFAULT_GOAL := help
SHELL := $(shell which bash)

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

init: ## terraform init (no backend; for validation)
	terraform init -backend=false -input=false

fmt: ## format terraform files
	terraform fmt -recursive

fmt-check: ## check formatting without modifying
	terraform fmt -recursive -check

validate: init ## validate configuration
	terraform validate

lint: ## run tflint
	tflint --init
	tflint --recursive

security: ## scan for misconfigurations
	trivy config --exit-code 1 --severity HIGH,CRITICAL .

shellcheck: ## check shell scripts
	git ls-files 'scripts/*.sh' | xargs -r shellcheck --severity=error --format=gcc

unit: init ## run terraform test (no credentials)
	terraform test -filter=tests/unit.tftest.hcl

unit-update-golden: ## no golden files in terraform projects
	@echo "no golden files"

integration: ## run integration tests (requires credentials)
	terraform test -filter=tests/integration.tftest.hcl

plan: ## terraform plan (requires credentials)
	terraform init -input=false
	terraform plan -input=false

apply: ## terraform apply (requires credentials)
	terraform init -input=false
	terraform apply

static-check: fmt-check validate lint security shellcheck unit ## run all static checks (CI)

static: fmt validate lint security shellcheck unit ## run all static checks with auto-format

.PHONY: help init fmt fmt-check validate lint security shellcheck unit unit-update-golden integration plan apply static-check static
```

If the interview declined `terraform test`, drop `unit`/`integration` bodies to `@echo "no tests"` and keep the targets. `trivy` goes in `.mise.toml` as `trivy = "{{TRIVY_VERSION}}"`.

`tests/unit.tftest.hcl` seed (plan-only, no credentials; mock the provider):
```hcl
mock_provider "aws" {}

run "plan_succeeds" {
  command = plan

  variables {
    aws_account_id = "123456789012"
  }
}
```

## Terragrunt layout

Per environment folder `<env>/`.

### account.yaml
```yaml
aws_account_id:   "{{AWS_ACCOUNT_ID}}"
aws_account_name: "{{ENV_NAME}}"

terraform_state_bucket_region: "{{STATE_REGION}}"
terraform_state_bucket_name: "{{STATE_BUCKET}}"
terraform_state_bucket_dynamodb_table_name: "terraform-locks"
```

### env-common.yaml
```yaml
root_environment: &root_env "{{ENV_NAME}}"

iac_release_tag: "{{STACKS_RELEASE_TAG}}"
iac_stacks_root: "{{STACKS_REPO_URL}}//{{STACKS_SUBPATH}}"

primary_region: &region "{{PRIMARY_REGION}}"

base-tags:
  env: *root_env
  region: *region
  applied-via: "{{REPO_NAME}}"
```

### root.hcl
```hcl
locals {
  account             = yamldecode(file("${find_in_parent_folders("account.yaml")}"))
  terraform_cache_dir = abspath("${get_repo_root()}/.terraform-plugin-cache")
}

terraform {
  before_hook "provider_cache" {
    commands = ["init", "validate", "plan", "apply"]
    execute  = ["mkdir", "-pv", local.terraform_cache_dir]
  }

  extra_arguments "plugin_cache" {
    commands  = ["init", "plan", "apply", "destroy", "refresh", "import", "validate"]
    arguments = []

    env_vars = {
      TF_PLUGIN_CACHE_DIR = local.terraform_cache_dir
    }
  }
}

errors {
  retry "transient_errors" {
    retryable_errors = concat(
      get_default_retryable_errors(),
      [
        ".*Failed to install provider.*",
        ".*Failed to load plugin schemas.*",
        ".*Failed to query available provider packages.*",
        ".*Required plugins are not installed.*",
        ".*context deadline exceeded.*",
        ".*timeout.*",
      ]
    )
    max_attempts       = 3
    sleep_interval_sec = 5
  }
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket                = local.account.terraform_state_bucket_name
    region                = local.account.terraform_state_bucket_region
    encrypt               = true
    dynamodb_table        = local.account.terraform_state_bucket_dynamodb_table_name
    key                   = "{{ENV_NAME}}/${path_relative_to_include()}/terraform.tfstate"
    disable_bucket_update = true
  }
}

generate "base_providers" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = file("providers/provider_base.hcl")
}
```

### providers/provider_base.hcl
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "{{AWS_PROVIDER_VERSION}}"
    }
  }
}

variable "provider_aws_region" {
  type      = string
  sensitive = true
}

variable "provider_aws_account_id" {
  type      = string
  sensitive = true
}

provider "aws" {
  region              = var.provider_aws_region
  allowed_account_ids = [var.provider_aws_account_id]
}
```

### terragrunt.stack.hcl
```hcl
locals {
  env_common_filename = "env-common.yaml"
  common_env          = yamldecode(file(mark_as_read(local.env_common_filename)))
  account_filename    = "account.yaml"
}

# Add one block per stack/unit. Example:
# unit "example" {
#   source = "${local.common_env.iac_stacks_root}/example?ref=${local.common_env.iac_release_tag}"
#   path   = "example"
#
#   no_dot_terragrunt_stack = true
#
#   values = {
#     env_filename        = "env-example.yaml"
#     env_common_filename = local.env_common_filename
#     account_filename    = local.account_filename
#   }
# }
```

Also write `<env>/.terraform-version` and `<env>/.terragrunt-version` containing the exact versions, and add each generated stack directory (e.g. `**/example/`) to `.gitignore` as stacks are added.

### .github/CODEOWNERS
```
* @{{GITHUB_ORG}}/{{CODEOWNERS_TEAM}}
```

### Makefile (terragrunt)

Same header, `help`, `shellcheck`, `unit`, `unit-update-golden`, `integration`, and `.PHONY` shape as the terraform Makefile. Replace the terraform-specific targets with:

```makefile
ENVS := $(patsubst %/account.yaml,%,$(wildcard */account.yaml))

fmt: ## format hcl files
	terragrunt hcl fmt

fmt-check: ## check hcl formatting without modifying
	terragrunt hcl fmt --check

validate: ## validate hcl syntax and inputs
	terragrunt hcl validate --inputs --all

security: ## scan for misconfigurations
	trivy config --exit-code 1 --severity HIGH,CRITICAL .

stack-generate: ## generate stacks for one env (usage: make stack-generate env=<folder>)
	cd $(env) && terragrunt stack generate

plan: ## plan one env (usage: make plan env=<folder>)
	cd $(env) && terragrunt stack run plan

unit: ## no unit tests in an env-values repo
	@echo "no unit tests"

static-check: fmt-check shellcheck ## run all static checks (CI)

static: fmt shellcheck ## run all static checks with auto-format
```

`terragrunt hcl validate` flags vary by version: confirm with `terragrunt hcl validate --help` and add it to `static-check` only when it runs without credentials; otherwise leave it as a manual target. `plan` and `stack-generate` need credentials and stay out of `static`. Add `ENVS stack-generate plan` to `.PHONY`.

## .pre-commit-config.yaml

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: {{GITLEAKS_VERSION}}
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

`.gitleaksignore`:
```
# Gitleaks ignore patterns
# Format: path/to/file:rule-name:line-number
```

## .github/dependabot.yml

```yaml
version: 2
updates:
  - package-ecosystem: "terraform"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "America/New_York"
    groups:
      providers:
        patterns:
          - "hashicorp/*"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "deps"
      include: "scope"
    labels:
      - "dependencies"
      - "terraform"

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

Terragrunt layout: keep only the `github-actions` entry.

## .github/workflows/static-check.yml

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
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1

      - name: Install tools from .mise.toml
        uses: jdx/mise-action@{{MISE_ACTION_SHA}}  # {{MISE_ACTION_VERSION}}

      - name: Run static checks
        run: make static-check
```

`mise-action` installs every tool pinned in `.mise.toml`, keeping CI and local versions identical. Resolve `{{MISE_ACTION_SHA}}` with `gh api repos/jdx/mise-action/git/ref/tags/<tag> --jq .object.sha` (dereference if it is an annotated tag).

## CLAUDE.md section

```markdown
## Static Analysis & Testing Standards

Enforced by the `scaffold-terraform` skill:

1. **Pinned versions**: terraform, terragrunt, providers, modules, and GitHub Actions use exact versions (tools in `.mise.toml`).
2. **Static analysis**: `make static` before committing (fmt, validate, tflint, trivy, shellcheck, tests).
3. **Pre-commit**: gitleaks + `make static`.
4. **Dependabot**: weekly for `terraform` and `github-actions`.
5. **CI**: `.github/workflows/static-check.yml` runs `make static-check` on PRs and main.

Run `make help` for all targets. `make plan` / `make apply` need AWS credentials.
```

## Deployment pipelines

Terragrunt layout only. Gruntwork Pipelines (`gruntwork-io/pipelines-workflows`) does the plan/apply; the workflows below add environment detection, a prod/non-prod mixing guard, and per-environment concurrency. Resolve `{{PIPELINES_SHA}}` with `gh api repos/gruntwork-io/pipelines-workflows/git/ref/tags/v4 --jq .object.sha` (dereference if annotated), and `{{CHECKOUT_SHA}}` as in the static-check workflow. Replace `{{PROD_PREFIX}}` with the prod folder prefix (regex, e.g. `prod` for folders named `*-prod`: use `^{{PROD_PREFIX}}`). `{{RUNNER}}` is the JSON-quoted label, e.g. `'"ubuntu-latest"'`.

### .gruntwork/repository.hcl
```hcl
repository {
  tf_binary = "terraform"

  env {
    TG_PROVIDER_CACHE = "true"
    TG_EXPERIMENT = "dependency-fetch-output-from-state,offline-cas,mutable-generate"
    PIPELINES_FEATURE_EXPERIMENT_IGNORE_UNITS_WITHOUT_ENVIRONMENT = "true"
    PIPELINES_FEATURE_EXPERIMENT_GENERATE_ALL_STACKS = "true"
  }
}
```

### .gruntwork/environment-{{ENV_NAME}}.hcl
```hcl
environment "{{ENV_NAME}}" {
  filter {
    paths = [
      "{{ENV_NAME}}/**",
      "aws-{{ENV_NAME}}-pipelines-bootstrap/**",
    ]
  }

  authentication {
    aws_oidc {
      account_id         = "{{AWS_ACCOUNT_ID}}"
      plan_iam_role_arn  = "arn:aws:iam::{{AWS_ACCOUNT_ID}}:role/{{OIDC_PREFIX}}-plan"
      apply_iam_role_arn = "arn:aws:iam::{{AWS_ACCOUNT_ID}}:role/{{OIDC_PREFIX}}-apply"
    }
  }
}
```

### Shared environment-detection script

Both plan and apply run this (plan diffs against `origin/<base_ref>...HEAD`; apply against `github.event.before github.event.after`). Set `CHANGED_FILES` first, then:

```bash
TOP_LEVEL_FOLDERS=$(echo "$CHANGED_FILES" | grep -v '^$' | grep -vE '^(README\.md|\.gitignore)$|^(\.github|\.gruntwork|aws-)' | cut -d'/' -f1 | sort -u)

ENVIRONMENT=""
for folder in $TOP_LEVEL_FOLDERS; do
  ENVIRONMENT="${ENVIRONMENT:+$ENVIRONMENT-}${folder}"
done
[ -z "$ENVIRONMENT" ] && ENVIRONMENT="unknown"
echo "environment=$ENVIRONMENT" >> "$GITHUB_OUTPUT"

PROD_FOLDERS=$(echo "$TOP_LEVEL_FOLDERS" | grep -E '{{PROD_REGEX}}' | grep -v '^$' || true)
NONPROD_FOLDERS=$(echo "$TOP_LEVEL_FOLDERS" | grep -vE '{{PROD_REGEX}}' | grep -v '^$' || true)
if [ -n "$PROD_FOLDERS" ] && [ -n "$NONPROD_FOLDERS" ]; then
  echo "ERROR: prod and non-prod folders changed together; submit production changes in a separate PR."
  exit 1
fi
```

### .github/workflows/pipelines-plan.yaml
```yaml
name: Pipelines Plan
run-name: "[GWP]: ${{ github.event.pull_request.title || 'No title' }}"

on:
  pull_request:
    types: [ready_for_review, synchronize, opened]
    paths-ignore:
      - ".github/**"
      - ".gruntwork/**"
      - "aws-*-pipelines-bootstrap/**"

concurrency:
  group: terragrunt-pipelines-plan-${{ github.event.pull_request.number }}
  cancel-in-progress: false

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  DetectEnvironment:
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.detect-env.outputs.environment }}
    steps:
      - name: Checkout code
        uses: actions/checkout@{{CHECKOUT_SHA}}  # {{CHECKOUT_VERSION}}
        with:
          fetch-depth: 0

      - name: Detect environment and guard prod/non-prod mixing
        id: detect-env
        env:
          BASE_REF: ${{ github.base_ref }}
        run: |
          git fetch origin "$BASE_REF"
          CHANGED_FILES=$(git diff --name-only "origin/$BASE_REF...HEAD")
          # <shared environment-detection script>

  AcquireEnvironmentLock:
    needs: DetectEnvironment
    runs-on: ubuntu-latest
    concurrency:
      group: terragrunt-plan-env-${{ needs.DetectEnvironment.outputs.environment }}
      cancel-in-progress: false
    steps:
      - run: echo "Plan lock acquired for ${{ needs.DetectEnvironment.outputs.environment }}"

  GruntworkPipelines:
    needs: AcquireEnvironmentLock
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines.yml@{{PIPELINES_SHA}} # v4
    with:
      runner: {{RUNNER}}
```

Inline the shared script in place of the `# <shared ...>` comment. Branch names go through `env:` rather than direct `${{ }}` interpolation in `run:`.

### .github/workflows/pipelines-apply.yaml
```yaml
name: Pipelines Apply
run-name: "[Apply]: ${{ github.event.head_commit.message || 'No commit message' }}"

on:
  push:
    branches: [main]
    paths-ignore:
      - ".github/**"
      - ".gruntwork/**"
      - "aws-*-pipelines-bootstrap/**"

concurrency:
  group: terragrunt-pipelines-apply
  cancel-in-progress: false

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  Preflight:
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.detect-env.outputs.environment }}
    steps:
      - name: Checkout code
        uses: actions/checkout@{{CHECKOUT_SHA}}  # {{CHECKOUT_VERSION}}
        with:
          fetch-depth: 0

      - name: Detect environment and guard prod/non-prod mixing
        id: detect-env
        env:
          BEFORE: ${{ github.event.before }}
          AFTER: ${{ github.event.after }}
        run: |
          CHANGED_FILES=$(git diff --name-only "$BEFORE" "$AFTER")
          # <shared environment-detection script>

  GruntworkPipelines:
    needs: Preflight
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines.yml@{{PIPELINES_SHA}} # v4
    with:
      runner: {{RUNNER}}
```

If Slack was chosen, add `notify-apply-started` (needs `Preflight`; `GruntworkPipelines` then needs it) and `notify-apply-completed` (`if: always()`, needs `[GruntworkPipelines, Preflight]`, reports `needs.GruntworkPipelines.result`). Each posts via the Slack action the user names, using `secrets.{{SLACK_SECRET}}` and `{{SLACK_CHANNEL}}`, with environment, `github.actor`, and a run URL in the message. Pin that action by SHA too.

### .github/workflows/pipelines-drift-detection.yml
```yaml
name: Pipelines Drift Detection
run-name: "[GWP]: Pipelines Drift Detection"
on:
  # Uncomment to enable scheduled drift detection
  # schedule:
  #  - cron: '15 12 * * 1'
  workflow_dispatch:
    inputs:
      pipelines_drift_detection_filter:
        description: Limit drift detection to units matching filter
        type: string
      pipelines_drift_detection_branch:
        description: The branch name used for drift remediation PRs
        default: drift-detection
        type: string
permissions:
  id-token: write

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines-drift-detection.yml@{{PIPELINES_SHA}} # v4
    with:
      pipelines_drift_detection_filter: ${{ inputs.pipelines_drift_detection_filter }}
      pipelines_drift_detection_branch: ${{ inputs.pipelines_drift_detection_branch }}
```

### .github/workflows/pipelines-unlock.yaml
```yaml
name: Pipelines Unlock
run-name: "[GWP]: Pipelines Unlock"
on:
  workflow_dispatch:
    inputs:
      lock_id:
        description: "State lock ID (from the failed run's output); not needed with unlock_all"
        required: false
        type: string
      unit_path:
        description: "Terragrunt unit directory holding the lock; not needed with unlock_all"
        required: false
        type: string
      stack_path:
        description: "Terragrunt stack directory that generates the unit"
        required: false
        type: string
      unlock_all:
        description: "Forcibly reset all locks by deleting the DynamoDB table"
        required: false
        type: boolean

permissions:
  id-token: write
  actions: read

jobs:
  GruntworkPipelines:
    uses: gruntwork-io/pipelines-workflows/.github/workflows/pipelines-unlock.yml@{{PIPELINES_SHA}} # v4
    with:
      lock_id: ${{ inputs.lock_id }}
      unit_path: ${{ inputs.unit_path }}
      unlock_all: ${{ inputs.unlock_all }}
      stack_path: ${{ inputs.stack_path }}
```

### aws-{{ENV_NAME}}-pipelines-bootstrap/

`account.yaml`: same keys as the environment's `account.yaml` (without `aws_account_name`).

`root.hcl`: the environment `root.hcl` with three changes: `terraform_cache_dir` points at this folder, the remote-state `key` is `aws-{{ENV_NAME}}-pipelines-bootstrap/${path_relative_to_include()}/terraform.tfstate`, and the `base_providers` generate block is replaced by:
```hcl
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region              = "${local.account.terraform_state_bucket_region}"
  allowed_account_ids = ["${local.account.aws_account_id}"]
}
EOF
}
```

`terragrunt.stack.hcl`:
```hcl
locals {
  account = yamldecode(file("account.yaml"))
}

stack "bootstrap" {
  source = "github.com/gruntwork-io/terragrunt-scale-catalog//stacks/aws/github/pipelines-bootstrap?ref={{SCALE_CATALOG_TAG}}"
  path   = "bootstrap"

  values = {
    terragrunt_scale_catalog_ref = "{{SCALE_CATALOG_TAG}}"

    aws_account_id = local.account.aws_account_id

    oidc_resource_prefix = "{{OIDC_PREFIX}}"

    github_org_name  = "{{GITHUB_ORG}}"
    github_repo_name = "{{REPO_NAME}}"

    state_bucket_name = local.account.terraform_state_bucket_name

    plan_iam_policy  = templatefile(mark_as_read("${get_terragrunt_dir()}/plan_iam_policy.json"), {})
    apply_iam_policy = templatefile(mark_as_read("${get_terragrunt_dir()}/apply_iam_policy.json"), {})
    oidc_provider_tags = {
      "used-by" = "terragrunt-pipelines"
    }
  }
}
```
Resolve `{{SCALE_CATALOG_TAG}}` from the latest `gruntwork-io/terragrunt-scale-catalog` release.

`plan_iam_policy.json` / `apply_iam_policy.json`: start from
```json
{
  "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Action": "*", "Resource": "*" }]
}
```
This is the working-but-broad default; tighten it after the first successful bootstrap (plan role: read-only plus state-bucket and lock-table access).
