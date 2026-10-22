---
name: scaffold-terraform
description: Bootstrap a new Terraform or Terragrunt project with pinned tool and provider versions, static analysis, pre-commit, Dependabot, CI, and (terragrunt) Gruntwork Pipelines deployment workflows.
disable-model-invocation: true
---

# Terraform Project Scaffolding

Bootstraps a Terraform repo to the same bar as `scaffold-project`: exact pins, `make static` as the single gate, a `make static` git hook (betterleaks included), weekly Dependabot, one CI workflow. Conventions distilled from `icp-iac-bedrock`.

Two layouts:

- **terraform**: a root module (`main.tf`, `variables.tf`, ...) with an S3 backend.
- **terragrunt**: an environment-values repo. One folder per environment, each with `root.hcl`, `account.yaml`, `env-common.yaml`, `terragrunt.stack.hcl`. Module and stack code lives in a separate repo, pinned by release tag.

File contents (including the optional Gruntwork Pipelines workflows for the terragrunt layout) live in [TEMPLATES.md](TEMPLATES.md). Read the template named in each step before writing that file.

## Rules

1. **Exact pins everywhere.** `terraform`/`terragrunt` in `.mise.toml`, `required_version = "= x.y.z"`, providers `version = "x.y.z"` (no `~>`, `>=`), modules `?ref=vX.Y.Z` or `version = "x.y.z"`, GitHub Actions by commit SHA with a `# vX.Y.Z` comment. Look up current versions at scaffold time (`gh api repos/<org>/<repo>/releases/latest`, `terraform-registry` API, `mise latest <tool>`); a version from memory is stale.
2. **`make static` is the single gate**; pre-commit and CI both run it, once per event. It runs `shellcheck` over every committed `*.sh`, the `betterleaks` secret scan, the `pins` check, and every terraform check the layout supports (`fmt`, `validate`, `lint`, `unit`). The git hook calls it.
3. **Every tool runs through mise.** Make targets call `mise exec -- <tool>` (the `$(MISE)` variable) and depend on an `install` target (`preflight` then `mise install`), so local, pre-commit and CI runs use the `.mise.toml` pins. Logic beyond one command goes in an executable, shellchecked script in `scripts/`; the Makefile calls it.
4. **No credentials or state in git.** `.gitignore` covers `.terraform/`, `.terragrunt-cache/`, `.terragrunt-stack/`, `*.tfstate*`, `*.tfvars` secrets, generated `backend.tf`, `scratch.txt`. `.terraform.lock.hcl` is committed for `terraform` layout and ignored for `terragrunt` layout (providers are pinned in the generated `versions.tf`).
5. **Existing files**: read each before touching it, then ask replace / merge / skip.

## Interview

Ask one question at a time, each with a line of context. Skip questions the repo already answers.

0. **Git**: `test -d .git`. If absent, offer `git init && git config --local init.defaultBranch main` (make targets use `git ls-files`). On decline, stop.
1. **Layout**: terraform or terragrunt?
2. **Cloud**: AWS (default) or other. Non-AWS drops the S3 backend and `account.yaml` keys; ask for the backend instead.
3. **Terraform version** and, for terragrunt, **Terragrunt version** (default: latest).
4. **State backend** (AWS): region, bucket name prefix (bucket becomes `<prefix>-<account-id>`; terragrunt layout: one per account), and the AWS account id. Locking is S3-native (`use_lockfile = true`, Terraform ≥ 1.10): no DynamoDB table, since the DynamoDB lock backend is deprecated. `icp-iac-bedrock` still uses DynamoDB; new projects do not.
5. **Providers** needed (default `aws`) and primary region.
6. **Terragrunt layout only**:
   - Environment folder names, plus AWS account id and name for each.
   - Stacks repo URL, `//stacks/...` subpath, and release tag.
   - GitHub org/repo, and CODEOWNERS team for `.github/CODEOWNERS`.
7. **Deployment pipelines** (terragrunt layout only; Gruntwork Pipelines is Terragrunt-based, so the terraform layout gets none): add plan/apply/drift/unlock workflows?
   - If yes, ask: runner label (default `ubuntu-latest`; `icp-iac-gha-runner-scale-set` for self-hosted), Slack notifications on apply (webhook secret name and channel; default none), OIDC resource prefix (default `<repo>-pipelines`), and the prod folder prefix that must not mix with non-prod in one PR (default `*-prod`).
8. **Tests**: terraform layout: add `terraform test` (`tests/*.tftest.hcl`)? Default yes when the root module has variables.

## Scaffolding

Run in order; each step is done when its verification line holds.

1. **Tool pins**: `.mise.toml` (`terraform`, `terragrunt` and `yq` if used, `tflint`, `betterleaks`, `shellcheck`, `awscli`, `pre-commit`), plus `.terraform-version` (and `.terragrunt-version` per environment folder). Done when `mise ls` or `mise install` resolves them.
2. **Project files**
   - terraform: `versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `.tflint.hcl`.
   - terragrunt: per environment folder, `root.hcl`, `account.yaml`, `env-common.yaml`, `providers/provider_base.hcl`, `terragrunt.stack.hcl`; at the repo root `.github/CODEOWNERS`.

   Done when every provider and module reference is an exact pin.
3. **Makefile and scripts**, including `scripts/preflight.sh`, `scripts/check-pins.sh`, `scripts/bootstrap-state.sh` and the `bootstrap-state` target: terraform or terragrunt template, plus the `scripts/*.sh` it calls (`chmod +x`, `git add` so `git ls-files` sees them). Done when `.DEFAULT_GOAL := help` is set, `make help` lists `preflight`, `install`, `hooks`, `pins`, `bootstrap-state`, `fmt`, `fmt-check`, `validate`, `lint` (terraform), `security`, `shellcheck`, `unit`, `integration`, `static`, `static-check`, no terraform/terragrunt/tflint/trivy/shellcheck call bypasses `$(MISE)`, and `make shellcheck` passes.
4. **Git hook**: `.pre-commit-config.yaml` with one local hook running `make static`, plus `.betterleaksignore`. Done when `make hooks` succeeds and `.git/hooks/pre-commit` exists.
5. **Dependabot**: `.github/dependabot.yml` with `terraform` (terraform layout, directory `/`) and `github-actions`, Monday 09:00 America/New_York, 5 PR limit, grouped by provider. Dependabot has no terragrunt ecosystem, so terragrunt layout tracks stack release tags by hand; say so in CLAUDE.md.
6. **CI**: `.github/workflows/static-check.yml` running `make static-check` on `pull_request` and pushes to `main`. Resolve every action SHA live. Done when no `uses:` line lacks a SHA and version comment.
7. **Scratch and gitignore**: `touch scratch.txt` and add it, with the rule-4 entries, to `.gitignore`.
8. **Deployment pipelines** (terragrunt layout, if chosen), from [TEMPLATES.md](TEMPLATES.md#deployment-pipelines):
   - `scripts/detect-env.sh` (called by plan and apply).
   - `.gruntwork/repository.hcl` and one `.gruntwork/environment-<env>.hcl` per environment.
   - `.github/workflows/pipelines-plan.yaml`, `pipelines-apply.yaml`, `pipelines-drift-detection.yml`, `pipelines-unlock.yaml`, with the `pipelines-workflows` SHA resolved live.
   - One `aws-<env>-pipelines-bootstrap/` per AWS account. Done when each has `account.yaml`, `root.hcl`, `terragrunt.stack.hcl`, `plan_iam_policy.json`, `apply_iam_policy.json`.
   - Add `aws-*-pipelines-bootstrap/` to each environment's filter paths and to `paths-ignore` in plan/apply.
   - Report as manual follow-ups: run `make bootstrap-state env=<folder>` for each account, then run the bootstrap stack once per account with admin credentials (it creates the OIDC provider and the `-plan`/`-apply` roles), then tighten the policies from the `Action: "*"` starting point (plan should be read-only). Add the Slack webhook as a repo secret if enabled.
9. **CLAUDE.md**: create or append both the "Keep `make static` clean" and "Static Analysis & Testing Standards" sections (an existing CLAUDE.md gets them appended, never replaced). Done when both headings are present. Also include: layout, how to plan/apply, how stack release tags are bumped, and the make targets.
10. **README.md**: create if missing: purpose, prerequisites (mise, AWS credentials), usage, environment table (terragrunt).

## Verification

Done when all hold; fix any miss before reporting.

- `make help` works, `make install` installs the pins, and `make static-check` passes, or each expected failure is listed (a fresh repo may lack tests or state access).
- `grep -rnE '~>|>=' --include='*.tf' --include='*.hcl' .` returns nothing.
- Pipelines chosen: every environment folder is covered by a `.gruntwork/environment-*.hcl` filter, and every `uses:` is SHA-pinned.
- `grep -nE '^\s+(terraform|terragrunt|tflint|betterleaks|shellcheck) ' Makefile` returns nothing (every call is behind `$(MISE)`).
- Files exist: `.mise.toml`, `Makefile`, `scripts/*.sh`, `.pre-commit-config.yaml`, `.betterleaksignore`, `.github/dependabot.yml`, `.github/workflows/static-check.yml`, `CLAUDE.md` (with the "Keep `make static` clean" heading), `scratch.txt`.
- `terraform` layout: `terraform init -backend=false && terraform validate` succeeds.

Report what was created, what was skipped, and the next steps: review files, `mise install`, `make bootstrap-state` once per AWS account (before the first init or the pipelines bootstrap), `make static`, `make hooks`, commit with `chore: add project scaffolding`.
