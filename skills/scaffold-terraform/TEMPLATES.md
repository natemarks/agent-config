# Templates

Reference for `scaffold-terraform`. Substitute `{{PLACEHOLDERS}}` from the interview.

## .mise.toml

```toml
[tools]
terraform = "{{TERRAFORM_VERSION}}"
terragrunt = "{{TERRAGRUNT_VERSION}}"   # terragrunt layout only
tflint = "{{TFLINT_VERSION}}"
betterleaks = "{{BETTERLEAKS_VERSION}}"
shellcheck = "{{SHELLCHECK_VERSION}}"
awscli = "{{AWSCLI_VERSION}}"
yq = "{{YQ_VERSION}}"                   # terragrunt layout only (reads account.yaml)
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
    bucket         = "{{STATE_BUCKET}}"
    key            = "{{PROJECT_NAME}}/terraform.tfstate"
    region         = "{{STATE_REGION}}"
    encrypt        = true
    dynamodb_table = "terraform-locks"
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

Every tool invocation goes through `$(MISE)`, so the versions pinned in `.mise.toml` are the versions that run, locally and in CI. Targets that need a tool depend on `install` (which depends on `preflight`). Logic longer than one command lives in `scripts/`.

```makefile
.DEFAULT_GOAL := help
SHELL := $(shell which bash)
MISE := mise exec --
AWS_ACCOUNT_ID := {{AWS_ACCOUNT_ID}}
STATE_BUCKET := {{STATE_BUCKET}}
STATE_REGION := {{STATE_REGION}}
LOCK_TABLE := terraform-locks

help: ## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

preflight: ## verify the non-mise tools the checks rely on (CI runners, slim images)
	bash scripts/preflight.sh

install: preflight ## install the tool versions pinned in .mise.toml
	mise trust --yes
	mise install

hooks: install ## install the git hooks (pre-commit runs make static)
	$(MISE) pre-commit install

bootstrap-state: install ## create the state bucket and lock table if missing (requires credentials; idempotent)
	$(MISE) scripts/bootstrap-state.sh $(AWS_ACCOUNT_ID) $(STATE_BUCKET) $(STATE_REGION) $(LOCK_TABLE)

fmt: install ## format terraform files
	$(MISE) terraform fmt -recursive

fmt-check: install ## check formatting without modifying
	$(MISE) terraform fmt -recursive -check

validate: install ## init (no backend) and validate every directory with .tf files
	$(MISE) scripts/validate.sh

lint: install ## run tflint
	$(MISE) tflint --init
	$(MISE) tflint --recursive

security: install ## scan the working tree for secrets (betterleaks)
	$(MISE) betterleaks dir .

shellcheck: install ## check committed shell scripts
	git ls-files -z '*.sh' | xargs -0 -r $(MISE) shellcheck --severity=error --format=gcc

pins: ## fail on version ranges (~>, >=) in .tf/.hcl files
	bash scripts/check-pins.sh

unit: install ## run terraform test (no credentials)
	$(MISE) terraform init -backend=false -input=false
	$(MISE) terraform test -filter=tests/unit.tftest.hcl

unit-update-golden: ## no golden files in terraform projects
	@echo "no golden files"

integration: install ## run integration tests (requires credentials)
	$(MISE) terraform init -input=false
	$(MISE) terraform test -filter=tests/integration.tftest.hcl

plan: install ## terraform plan (requires credentials)
	$(MISE) terraform init -input=false
	$(MISE) terraform plan -input=false

apply: install ## terraform apply (requires credentials)
	$(MISE) terraform init -input=false
	$(MISE) terraform apply

static-check: preflight fmt-check validate lint security pins shellcheck unit ## run all static checks (CI)

static: preflight fmt validate lint security pins shellcheck unit ## run all static checks with auto-format

.PHONY: help preflight install hooks pins bootstrap-state fmt fmt-check validate lint security shellcheck unit unit-update-golden integration plan apply static-check static
```

`static` and `static-check` list every available terraform check (`fmt`, `validate`, `lint`, `security`, `pins`, `unit`) plus `shellcheck`; when a new check is added to the project, add it to both. If the interview declined `terraform test`, set the `unit`/`integration` bodies to `@echo "no tests"` and keep the targets.

`scripts/validate.sh`:
```bash
#!/usr/bin/env bash
# Run terraform init (no backend) and validate in every directory with committed .tf files.
# Run via: mise exec -- scripts/validate.sh
set -euo pipefail

root=$(git rev-parse --show-toplevel)
status=0
while read -r dir; do
  echo "== validate ${dir}"
  terraform -chdir="${root}/${dir}" init -backend=false -input=false >/dev/null || { status=1; continue; }
  terraform -chdir="${root}/${dir}" validate || status=1
done < <(git -C "${root}" ls-files '*.tf' | xargs -r -n1 dirname | sort -u)
exit "${status}"
```

Make every script executable (`chmod +x scripts/*.sh`) and commit it, so `shellcheck` sees it.

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

### scripts/preflight.sh and scripts/check-pins.sh

Both layouts. `preflight.sh` reports missing non-mise tools up front (a bare CI image gets one clear message instead of a mid-run failure). `make` and `bash` cannot be checked here: `make` must exist to run the Makefile, and `SHELL := $(shell which bash)` is evaluated at parse time.

```bash
#!/usr/bin/env bash
# Verify the tools make static relies on that mise does not manage.
set -euo pipefail

missing=()
for tool in mise git bash xargs grep; do
  command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: missing required tools: ${missing[*]}" >&2
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: not inside a git work tree" >&2; exit 1; }
# BusyBox variants can lack these flags
printf '' | xargs -0 -r true 2>/dev/null || { echo "ERROR: xargs lacks -0/-r" >&2; exit 1; }
echo ab | grep -qE 'a(b)' 2>/dev/null || { echo "ERROR: grep lacks -E" >&2; exit 1; }
```

```bash
#!/usr/bin/env bash
# Fail on version ranges (~>, >=) in .tf and .hcl files, tracked or not yet committed.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
files=()
while IFS= read -r -d '' f; do
  files+=("${f}")
done < <(git ls-files -z -co --exclude-standard -- '*.tf' '*.hcl')

if [ "${#files[@]}" -eq 0 ]; then
  echo "no .tf/.hcl files to check"
  exit 0
fi
if grep -nE '(~>|>=)' "${files[@]}"; then
  echo "ERROR: version ranges found; pin exact versions" >&2
  exit 1
fi
echo "All version pins exact"
```

The array guard matters: `xargs -r` exits 0 on empty input, which would let the check pass on nothing. A `>=` inside a Terragrunt expression is a false positive; rewrite the expression.

### State bootstrap: scripts/bootstrap-state.sh

Both layouts. `make bootstrap-state` creates the remote-state bucket and lock table once per AWS account, before the first `init`. It is idempotent: re-running reconciles settings and skips what exists. It needs credentials, so it stays out of `static`. Naming convention: bucket `<prefix>-terraform-state-<account-id>` (account-suffixed, globally unique), table `terraform-locks`.

Best-practice settings applied: bucket versioning, default SSE (AES256 with bucket key), all public access blocked, bucket-owner-enforced ownership (ACLs off), TLS-only bucket policy, noncurrent versions expire after 90 days, incomplete multipart uploads abort after 7 days; table `LockID` (string) hash key, on-demand billing, point-in-time recovery, deletion protection, SSE. The script refuses to run when the caller's account differs from the expected one.

```bash
#!/usr/bin/env bash
# Create the Terraform remote-state S3 bucket and DynamoDB lock table if missing (idempotent).
# Usage: scripts/bootstrap-state.sh ACCOUNT_ID BUCKET REGION LOCK_TABLE
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "Usage: $0 ACCOUNT_ID BUCKET REGION LOCK_TABLE" >&2
  exit 2
fi
account_id=$1
bucket=$2
region=$3
table=$4

caller=$(aws sts get-caller-identity --query Account --output text)
if [ "${caller}" != "${account_id}" ]; then
  echo "ERROR: credentials are for account ${caller}, expected ${account_id}" >&2
  exit 1
fi

echo "== bucket ${bucket} (${region})"
if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
  echo "exists"
else
  if [ "${region}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${bucket}" --region "${region}"
  else
    aws s3api create-bucket --bucket "${bucket}" --region "${region}" \
      --create-bucket-configuration "LocationConstraint=${region}"
  fi
fi

aws s3api put-bucket-versioning --bucket "${bucket}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "${bucket}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-public-access-block --bucket "${bucket}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-ownership-controls --bucket "${bucket}" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
aws s3api put-bucket-policy --bucket "${bucket}" --policy "$(cat <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::${bucket}", "arn:aws:s3:::${bucket}/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
POLICY
)"
aws s3api put-bucket-lifecycle-configuration --bucket "${bucket}" \
  --lifecycle-configuration '{"Rules":[{"ID":"expire-noncurrent-and-abort-multipart","Status":"Enabled","Filter":{},"NoncurrentVersionExpiration":{"NoncurrentDays":90},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'

echo "== lock table ${table} (${region})"
if aws dynamodb describe-table --table-name "${table}" --region "${region}" >/dev/null 2>&1; then
  echo "exists"
else
  aws dynamodb create-table --table-name "${table}" --region "${region}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --deletion-protection-enabled \
    --sse-specification Enabled=true >/dev/null
  aws dynamodb wait table-exists --table-name "${table}" --region "${region}"
fi
aws dynamodb update-continuous-backups --table-name "${table}" --region "${region}" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true >/dev/null
aws dynamodb update-table --table-name "${table}" --region "${region}" \
  --deletion-protection-enabled >/dev/null 2>&1 || true

echo "state backend ready: s3://${bucket}, table ${table}"
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

Same header (`MISE := mise exec --`), `help`, `preflight`, `install`, `hooks`, `pins`, `shellcheck`, `unit`, `unit-update-golden`, `integration` and `.PHONY` shape as the terraform Makefile. Replace the terraform-specific targets with:

```makefile
bootstrap-state: install ## create an env's state bucket and lock table if missing (usage: make bootstrap-state env=<folder>; requires credentials)
	$(MISE) scripts/bootstrap-state.sh \
	  "$$($(MISE) yq '.aws_account_id' $(env)/account.yaml)" \
	  "$$($(MISE) yq '.terraform_state_bucket_name' $(env)/account.yaml)" \
	  "$$($(MISE) yq '.terraform_state_bucket_region' $(env)/account.yaml)" \
	  "$$($(MISE) yq '.terraform_state_bucket_dynamodb_table_name' $(env)/account.yaml)"

fmt: install ## format hcl files
	$(MISE) terragrunt hcl fmt

fmt-check: install ## check hcl formatting without modifying
	$(MISE) terragrunt hcl fmt --check

validate: install ## validate hcl syntax and inputs in every environment
	$(MISE) scripts/for-each-env.sh terragrunt hcl validate --inputs

security: install ## scan the working tree for secrets (betterleaks)
	$(MISE) betterleaks dir .

stack-generate: install ## generate stacks for one env (usage: make stack-generate env=<folder>)
	cd $(env) && $(MISE) terragrunt stack generate

plan: install ## plan one env (usage: make plan env=<folder>)
	cd $(env) && $(MISE) terragrunt stack run plan

unit: ## no unit tests in an env-values repo
	@echo "no unit tests"

static-check: preflight fmt-check validate security pins shellcheck ## run all static checks (CI)

static: preflight fmt validate security pins shellcheck ## run all static checks with auto-format
```

`terragrunt hcl validate` flags vary by version: confirm with `$(MISE) terragrunt hcl validate --help`, and run `make validate` without credentials. If it needs them, drop `validate` from `static` and `static-check` and leave it as a manual target. `plan` and `stack-generate` need credentials and stay out of `static`. Add `bootstrap-state stack-generate plan` to `.PHONY`. Environments sharing an account (an environment folder and its `aws-*-pipelines-bootstrap` folder) share one bucket and table, so bootstrap once per account.

`scripts/for-each-env.sh`:
```bash
#!/usr/bin/env bash
# Run a command inside every environment folder (a top-level folder holding account.yaml).
# Usage: scripts/for-each-env.sh COMMAND [ARGS...]
set -euo pipefail

root=$(git rev-parse --show-toplevel)
status=0
for account in "${root}"/*/account.yaml; do
  env_dir=$(dirname "${account}")
  case "$(basename "${env_dir}")" in aws-*-pipelines-bootstrap) continue ;; esac
  echo "== ${env_dir#"${root}"/}"
  (cd "${env_dir}" && "$@") || status=1
done
exit "${status}"
```

## .pre-commit-config.yaml

The git hook runs `make static`, which includes the betterleaks secret scan, shellcheck and the terraform checks. `make hooks` installs it.

```yaml
repos:
  - repo: local
    hooks:
      - id: make-static
        name: Run make static
        entry: make static
        language: system
        pass_filenames: false
        always_run: true
```

`.betterleaks.toml` (optional; the default ruleset applies without it). Add path allowlists or custom checks there, e.g. `[sops_check] paths = ["**/sops-secrets/**"]` as in `icp-iac-bedrock`.

`.betterleaksignore` (false positives; betterleaks also reads `.gitleaksignore`):
```
# Betterleaks ignore patterns
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
2. **Static analysis**: `make static` before committing: shellcheck on committed `*.sh`, plus fmt, validate, tflint, betterleaks and tests where the layout supports them.
3. **mise**: every make target runs its tool via `mise exec --`; add tools to `.mise.toml`, scripts to `scripts/`.
4. **Git hook**: pre-commit runs `make static` (betterleaks, shellcheck, terraform checks); `make hooks` installs it.
5. **Dependabot**: weekly for `terraform` and `github-actions`.
6. **CI**: `.github/workflows/static-check.yml` runs `make static-check` on PRs and main.

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

### scripts/detect-env.sh

Plan and apply both call this, so the logic is shellchecked and lives in one place. Arguments are passed to `git diff --name-only` (plan: `origin/$BASE_REF...HEAD`; apply: `$BEFORE $AFTER`). `PROD_REGEX` defaults to the prod folder prefix from the interview.

```bash
#!/usr/bin/env bash
# Detect the environment(s) a change touches and refuse to mix prod with non-prod.
# Usage: scripts/detect-env.sh GIT_DIFF_ARGS...   (writes environment=... to $GITHUB_OUTPUT when set)
set -euo pipefail

prod_regex="${PROD_REGEX:-{{PROD_REGEX}}}"

changed_files=$(git diff --name-only "$@")
top_level_folders=$(echo "${changed_files}" | grep -v '^$' | grep -vE '^(README\.md|\.gitignore)$|^(\.github|\.gruntwork|aws-|scripts)' | cut -d'/' -f1 | sort -u || true)

environment=""
for folder in ${top_level_folders}; do
  environment="${environment:+${environment}-}${folder}"
done
environment="${environment:-unknown}"
echo "Detected environment: ${environment}"
echo "environment=${environment}" >> "${GITHUB_OUTPUT:-/dev/stdout}"

prod_folders=$(echo "${top_level_folders}" | grep -E "${prod_regex}" || true)
nonprod_folders=$(echo "${top_level_folders}" | grep -vE "${prod_regex}" | grep -v '^$' || true)
if [ -n "${prod_folders}" ] && [ -n "${nonprod_folders}" ]; then
  echo "ERROR: prod and non-prod folders changed together; submit production changes in a separate PR." >&2
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
          scripts/detect-env.sh "origin/$BASE_REF...HEAD"

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

Branch names go through `env:` rather than direct `${{ }}` interpolation in `run:`.

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
          scripts/detect-env.sh "$BEFORE" "$AFTER"

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
