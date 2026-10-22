---
name: scaffold-terraform
description: Bootstrap a new Terragrunt-pattern infrastructure repo (envs repo or stacks repo) with pinned tools, static analysis, git hook, CI, and Gruntwork Pipelines deployment workflows.
disable-model-invocation: true
---

# Terraform Project Scaffolding

Bootstraps an infrastructure repo to the same bar as `scaffold-project`: exact pins, `make static` as the single gate, a `make static` git hook (betterleaks included), one CI workflow. Every project follows the Terragrunt pattern of `icp-iac-bedrock` (envs repo) and `astra-iac` (stacks repo). Plain root-module Terraform is out of scope.

## The pattern

Two repo roles, always paired:

- **envs repo** (default): values only, no module code. One *account folder* per AWS account holds `account.yaml`, `root.hcl`, `providers/provider_base.hcl`, `.terraform-version`, `.terragrunt-version`. The *environment folder* (the account folder itself, or a subfolder when an account hosts several environments) holds `env-common.yaml`, `env-<domain>.yaml` files, `iam-policies/*.json` and `terragrunt.stack.hcl`.
- **stacks repo**: `modules/<name>/` (Terraform, no providers declared) and `stacks/environment/<name>/` (units as `terragrunt.hcl`, multi-unit stacks as `terragrunt.stack.hcl`). Environments consume it by release tag.

The contract between them: the envs repo's `iac_release_tag` (an exact `vX.Y.Z`) pins every stack, unit and module source with `?ref=`; each `unit`/`stack` block sets `no_dot_terragrunt_stack = true` and passes `env_filename`, `env_common_filename`, `account_filename`; each unit reads its config from those yaml files and passes `provider_aws_region` and `provider_aws_account_id`. `scripts/check-layout.sh` enforces the envs side in `make static`.

File contents (including the optional Gruntwork Pipelines workflows) live in [TEMPLATES.md](TEMPLATES.md). Read the template named in each step before writing that file.

## Rules

1. **Exact pins everywhere.** `terraform`/`terragrunt` in `.mise.toml` and the per-account `.terraform-version`/`.terragrunt-version`, providers `version = "x.y.z"` in `providers/provider_base.hcl` (no `~>`, `>=`), sources `?ref=vX.Y.Z`, GitHub Actions by commit SHA with a `# vX.Y.Z` comment. Look up current versions at scaffold time (`gh api repos/<org>/<repo>/releases/latest`, `terraform-registry` API, `mise latest <tool>`); a version from memory is stale.
2. **`make static` is the single gate**; the git hook and CI both run it, once per event. It runs `shellcheck` over every committed `*.sh`, the `betterleaks` secret scan, the `pins` check, and every check the repo role supports: envs repo `fmt`, `validate`, `unit` (layout contract); stacks repo `fmt`, `validate`, `lint`, `unit` (module `terraform test`).
3. **Every tool runs through mise.** Make targets call `mise exec -- <tool>` (the `$(MISE)` variable) and depend on an `install` target (`preflight` then `mise install`), so local, hook and CI runs use the `.mise.toml` pins. Logic beyond one command goes in an executable, shellchecked script in `scripts/`; the Makefile calls it.
4. **No credentials or state in git.** `.gitignore` covers `.terraform/`, `.terragrunt-cache/`, `.terragrunt-stack/`, `*.tfstate*`, secret `*.tfvars`, generated `backend.tf`/`versions.tf`/`.terraform.lock.hcl`, generated stack directories, `scratch.txt`.
5. **Locking is S3-native** (`use_lockfile = true`, Terraform 1.10 or newer); no DynamoDB table, since the DynamoDB lock backend is deprecated. `icp-iac-bedrock` still uses DynamoDB; new projects do not.
6. **Existing files**: read each before touching it, then ask replace / merge / skip.

## Interview

Ask one question at a time, each with a line of context. Skip questions the repo already answers.

0. **Git**: `test -d .git`. If absent, offer `git init && git config --local init.defaultBranch main` (make targets use `git ls-files`). On decline, stop.
1. **Repo role**: envs repo or stacks repo? Then the name and URL of the paired repo (for a new pair, scaffold the stacks repo first and use its URL).
2. **Cloud**: AWS (default) or other. Non-AWS drops the S3 backend and `account.yaml` keys; ask for the backend instead.
3. **Terraform version** and **Terragrunt version** (default: latest).
4. **Providers** needed (default `aws`) and primary region.
5. **Envs repo only**:
   - Account folders: name, AWS account id and name for each; and whether each hosts one environment (flat) or several (subfolders).
   - State backend: region and bucket name prefix (bucket becomes `<prefix>-<account-id>`, one per account).
   - GitHub org/repo and CODEOWNERS team (also asked for a stacks repo).
   - Initial `iac_release_tag` of the stacks repo.
6. **Deployment pipelines** (envs repo only; Gruntwork Pipelines): add plan/apply/drift/unlock workflows?
   - If yes, ask: runner label (default `ubuntu-latest`; `icp-iac-gha-runner-scale-set` for self-hosted), Slack notifications on apply (webhook secret name and channel; default none), OIDC resource prefix (default `<repo>-pipelines`), and the prod folder prefix that must not mix with non-prod in one PR (default `prod`).

## Scaffolding

Run in order; each step is done when its verification line holds.

1. **Tool pins**: `.mise.toml` (`terraform`, `terragrunt`, `tflint` for stacks repos, `betterleaks`, `shellcheck`, `awscli`, `yq` for envs repos, `pre-commit`). Done when `mise install` resolves them.
2. **Project files**
   - envs repo: per account folder `account.yaml`, `root.hcl`, `providers/provider_base.hcl`, `.terraform-version`, `.terragrunt-version`; per environment folder `env-common.yaml` and `terragrunt.stack.hcl`; `.github/CODEOWNERS`.
   - stacks repo: `modules/example/` with its test, `stacks/environment/example/terragrunt.hcl`, `.tflint.hcl`, `README.md` (release rules), `CHANGELOG.md`, `.github/CODEOWNERS`.

   Done when every provider and source reference is an exact pin.
3. **Makefile and scripts**: the repo role's Makefile plus the `scripts/*.sh` it calls (`preflight.sh`, `check-pins.sh`; envs: `check-layout.sh`, `bootstrap-state.sh`; stacks: `validate.sh`, `unit.sh`). `chmod +x` and `git add` them so `git ls-files` sees them. Done when `.DEFAULT_GOAL := help` is set, `make help` lists every target the template defines, no terraform/terragrunt/tflint/betterleaks/shellcheck call bypasses `$(MISE)`, and `make shellcheck` passes.
4. **Git hook**: `.pre-commit-config.yaml` with one local hook running `make static`, plus `.betterleaksignore`. Done when `make hooks` succeeds and `.git/hooks/pre-commit` exists.
5. **Dependabot**: `.github/dependabot.yml` with `github-actions`, Monday 09:00 America/New_York, 5 PR limit. Dependabot covers neither `.mise.toml`, provider pins nor release tags; say so in CLAUDE.md.
6. **CI**: `.github/workflows/static-check.yml` running `make static-check` on `pull_request` and pushes to `main`. Resolve every action SHA live. Done when no `uses:` line lacks a SHA and version comment.
7. **Scratch and gitignore**: `touch scratch.txt` and add it, with the rule-4 entries, to `.gitignore`.
8. **Deployment pipelines** (envs repo, if chosen), from [TEMPLATES.md](TEMPLATES.md#deployment-pipelines):
   - `scripts/detect-env.sh` (called by plan and apply).
   - `.gruntwork/repository.hcl` and one `.gruntwork/environment-<env>.hcl` per environment.
   - `.github/workflows/pipelines-plan.yaml`, `pipelines-apply.yaml`, `pipelines-drift-detection.yml`, `pipelines-unlock.yaml`, with the `pipelines-workflows` SHA resolved live.
   - One `aws-<env>-pipelines-bootstrap/` per AWS account. Done when each has `account.yaml`, `root.hcl`, `terragrunt.stack.hcl`, `plan_iam_policy.json`, `apply_iam_policy.json`.
   - Add `aws-*-pipelines-bootstrap/` to each environment's filter paths and to `paths-ignore` in plan/apply.
   - Report as manual follow-ups: run `make bootstrap-state env=<folder>` for each account, then run the bootstrap stack once per account with admin credentials (it creates the OIDC provider and the `-plan`/`-apply` roles), then tighten the policies from the `Action: "*"` starting point (plan should be read-only). Add the Slack webhook as a repo secret if enabled.
9. **CLAUDE.md**: create or append the "Keep `make static` clean", "Static Analysis & Testing Standards" and "Terragrunt pattern" sections, filling `{{REPO_ROLE_PARAGRAPH}}` (an existing CLAUDE.md gets them appended, never replaced). Done when all three headings are present. Also include: how to plan, how release tags are bumped, and the make targets.
10. **README.md**: create if missing: purpose, role and paired repo, prerequisites (mise, AWS credentials), usage, and an environment table (envs repo).

## Verification

Done when all hold; fix any miss before reporting.

- `make help` works, `make install` installs the pins, and `make static-check` passes, or each expected failure is listed (a fresh repo may lack state access).
- `grep -rnE '~>|>=' --include='*.tf' --include='*.hcl' .` returns nothing.
- Envs repo: `scripts/check-layout.sh` prints `Layout OK`, so no `.tf` files, every source `?ref=` pinned, every block carries the three values. With pipelines, every environment folder is covered by a `.gruntwork/environment-*.hcl` filter and every `uses:` is SHA-pinned.
- Stacks repo: `make unit` runs the example module's test and passes.
- `grep -nE '^\s+(terraform|terragrunt|tflint|betterleaks|shellcheck) ' Makefile` returns nothing (every call is behind `$(MISE)`).
- Files exist: `.mise.toml`, `Makefile`, `scripts/*.sh`, `.pre-commit-config.yaml`, `.betterleaksignore`, `.github/dependabot.yml`, `.github/workflows/static-check.yml`, `CLAUDE.md` (with the "Keep `make static` clean" and "Terragrunt pattern" headings), `scratch.txt`.

Report what was created, what was skipped, and the next steps: review files, `mise install`, then for an envs repo `make bootstrap-state env=<folder>` once per AWS account (before the first plan or the pipelines bootstrap), `make static`, `make hooks`, commit with `chore: add project scaffolding`; for a stacks repo, tag the first release (`v0.1.0`) so an envs repo can pin it.
