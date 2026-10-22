# Terraform unit tests that detect unintended changes: what is standard?

Researched 2026-10-22. Primary sources only (vendor docs and source repos; links in each claim, full list at the end).
Labels: **[Sourced]** = taken from the cited page or file. **[Unverified]** = not confirmed in a primary source. **[Recommendation]** = my opinion.

Note on method: the WebFetch tool was unavailable (its backing model returned a 403), so docs pages were fetched with `curl` and converted to text, and repos were shallow-cloned and read (never executed). Docs pages were the "latest" versions as of the fetch date; the Terraform docs page selector listed v1.17.x as latest, while the GitHub latest release tag read was v1.16.7.

## Short answer

- **[Sourced]** There is no single standard golden-file tool for Terraform. Native `terraform test` is the first-party unit-test framework, and it asserts on named values; I found no snapshot or golden-file feature in its docs (see section 1).
- **[Sourced]** The common building block for "detect changes" is the plan JSON (`terraform plan -out` then `terraform show -json`). Terratest, tftest, Checkov, OPA/Conftest and Sentinel all consume it, but most use it for assertions or policy, not golden diffs.
- **[Sourced]** Golden-file/snapshot tools for plan JSON exist but are small community projects (`terraform-snapshot-test`, `libtftest`), not a de facto standard.

## 1. Native `terraform test`

- **[Sourced]** Introduced in Terraform v1.6.0; test files are `.tftest.hcl` / `.tftest.json` containing `run` blocks. [Tests](https://developer.hashicorp.com/terraform/language/tests)
- **[Sourced]** `command` is `apply` (default) or `plan`. `command = plan` does not create infrastructure and is described as "analogous to unit testing". [Tests](https://developer.hashicorp.com/terraform/language/tests)
- **[Sourced]** `assert` blocks have a `condition` and `error_message`, and can reference any named value in the configuration plus outputs of current and previous run blocks. `expect_failures` lists checkable objects (resources, data sources, check blocks, variables, outputs) whose custom conditions should fail. [Tests](https://developer.hashicorp.com/terraform/language/tests)
- **[Sourced]** `plan_options` supports `mode` (normal / refresh-only), `refresh`, `replace`, `target`. [Tests](https://developer.hashicorp.com/terraform/language/tests)
- **[Sourced]** `-verbose` prints the plan or state for each run block; `-json` and `-junit-xml=<file>` produce machine-readable results. [terraform test command](https://developer.hashicorp.com/terraform/cli/commands/test)
- **[Sourced]** Mocking (v1.7.0+): `mock_provider` returns the real provider's schema and "will generate fake data for all computed attributes", letting you test "without creating infrastructure or requiring credentials". [Mocks](https://developer.hashicorp.com/terraform/language/tests/mocking)
- **[Sourced]** Generated values: numbers 0, booleans false, strings a random 8-character alphanumeric string, collections empty. Mocks do not know real formats (an ARN will not look like an ARN). By default data is generated at apply and the plan shows `(known after apply)`; `override_during = plan` generates at plan time. [Mocks](https://developer.hashicorp.com/terraform/language/tests/mocking)
- **[Sourced]** Determinism controls: `mock_resource` / `mock_data` `defaults` (e.g. a fixed `arn`), shared `.tfmock.hcl` data files via `source`, and `override_resource`, `override_data`, `override_module` (module outputs overridden, no resources created). [Mocks](https://developer.hashicorp.com/terraform/language/tests/mocking)
- **[Sourced]** `command = plan` assertions on values that depend on computed attributes are limited: Terraform does not evaluate some custom conditions at plan time when they rely on computed attributes. [Tests](https://developer.hashicorp.com/terraform/language/tests)
- **What it detects:** logic regressions you explicitly assert (names, counts, tags, conditionals, validation and precondition failures). **What it cannot detect:** anything you did not write an assertion for. There is no built-in "compare the whole plan to a stored baseline". I found no snapshot/golden mention in the tests page or command reference (absence of evidence, not a documented statement that none exists).
- **Credentials [Sourced]:** with `mock_provider` none are needed. `terraform init` still has to fetch providers (the existing template uses `init -backend=false`; [init](https://developer.hashicorp.com/terraform/cli/commands/init) documents `-backend=false` to skip backend configuration).
- **Fit to the current template [Sourced]:** TEMPLATES.md has `unit` running `terraform init -backend=false -input=false` then `terraform test -filter=tests/unit.tftest.hcl`, and `unit-update-golden` echoing "no golden files" (`/home/nmarks/projects/agent-config/skills/scaffold-terraform/TEMPLATES.md`, lines ~169-175). The Terragrunt env-values template has `unit` echoing "no unit tests" (~line 523).

## 2. `terraform plan -out` + `terraform show -json`

- **[Sourced]** `-out=FILENAME` writes an opaque plan file; HashiCorp says it is "not in any standard format intended for consumption by other software". [plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
- **[Sourced]** `terraform show -json <planfile>` emits the plan, configuration and current state as JSON; with `-json`, sensitive values in state are shown in plain text; a plan viewed this way must be created without `-refresh=false`. [show](https://developer.hashicorp.com/terraform/cli/commands/show)
- **[Sourced]** The JSON has `format_version` ("1.0" as of Terraform 1.1.0), with minor versions for backward-compatible additions and a major bump for breaking changes. Top-level keys include `prior_state`, `configuration`, `planned_values`, `resource_changes` (with `change.actions`, before/after values, unknowns, `action_reason`), `resource_drift`, and checks. [JSON format](https://developer.hashicorp.com/terraform/internals/json-format)
- **[Sourced]** `-detailed-exitcode`: 0 = succeeded with empty diff, 1 = error, 2 = succeeded with non-empty diff. [plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
- **[Sourced]** `-refresh=false` skips syncing state with remote objects and "can result in an incomplete or incorrect plan". [plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
- **What it detects:** the real diff Terraform would apply, including attribute changes and replacements (`action_reason`), so it is the right input for catching unintended changes. A no-change check (`-detailed-exitcode` equals 0) works well as a drift or regression gate **against existing state**.
- **Limits:** a plan needs a provider configured for real (so credentials for cloud providers) and usually state/backend. **[Unverified]** that the AWS provider specifically requires credentials at plan time; I did not read provider docs. Computed values appear as unknown (`after_unknown`), which is what keeps real plans stable, but ids and ARNs of existing resources come from state.
- **Without a deployed environment**, a plan of a fresh root module against an empty local state shows only creates, which can still be snapshotted (that is what the snapshot tools below do).

## 3. Terratest

- **[Sourced]** Repo `gruntwork-io/terratest` at commit `107b7ed` (2026-10-21); `modules/terraform/plan.go` provides `InitAndPlan*`, `InitAndPlanAndShow*`, `InitAndPlanAndShowWithStruct*` (parses plan JSON), and `InitAndPlanWithExitCode*` / `PlanExitCode*`. Functions in this checkout carry a `Context` suffix (core v2 module layout). [plan.go](https://github.com/gruntwork-io/terratest/blob/107b7ed4db1a7b0ea9dfcf0a5576d343d5b1fe6f/modules/terraform/plan.go)
- **[Sourced]** `PlanStruct` has `ResourcePlannedValuesMap` (address to planned values), `ResourceChangesMap` (address to planned actions) and `RawPlan` (`tfjson.Plan`). [plan_struct.go](https://github.com/gruntwork-io/terratest/blob/107b7ed4db1a7b0ea9dfcf0a5576d343d5b1fe6f/modules/terraform/plan_struct.go)
- **[Sourced]** Terragrunt helpers exist in `modules/terragrunt` (`PlanAllExitCode*`, `Plan*`, `render.go`, `stack_generate.go`, `run_all.go`). [modules/terragrunt](https://github.com/gruntwork-io/terratest/tree/107b7ed4db1a7b0ea9dfcf0a5576d343d5b1fe6f/modules/terragrunt)
- **[Sourced]** An `opa` module runs `opa eval` against JSON files. [modules/opa](https://github.com/gruntwork-io/terratest/tree/107b7ed4db1a7b0ea9dfcf0a5576d343d5b1fe6f/modules/opa)
- **Golden/snapshot support:** I found none for Terraform. A repo search for "snapshot"/"golden" found only a Helm template snapshot test (`test/helm_keda_remote_example_template_snapshot_test.go`) and unrelated GCP names. Assertions are programmatic, in Go.
- **Credentials/determinism:** it shells out to the terraform binary, so it needs whatever a real plan needs. **[Unverified]** whether it can be used with mock providers; it does not itself run `terraform test`.

## 4. Policy-as-code on plan JSON

- **Conftest (OPA)** **[Sourced]**: tests structured config with Rego. The repo's `examples/hcl1` has a Makefile producing `*-plan.tfplan` and `*-show.json`, and a policy that denies when `input.resource_changes` touches prohibited resource types. Conftest also parses HCL directly (`parse_config("hcl2", ...)`). [conftest@a16df6e examples/hcl1](https://github.com/open-policy-agent/conftest/tree/a16df6ed915f42d8b7e3e49887db822bcd544269/examples/hcl1), [docs/index.md](https://github.com/open-policy-agent/conftest/blob/a16df6ed915f42d8b7e3e49887db822bcd544269/docs/index.md). The fixture JSON in that example is old (`terraform_version` 0.12.0-beta2, `format_version` 0.1).
- **Checkov** **[Sourced]**: scans plan JSON with `terraform plan --out tfplan.binary`, `terraform show -json tfplan.binary | jq > tfplan.json`, `checkov -f tfplan.json`; custom checks can read `__change_actions__` (e.g. fail if `delete` is present) and `TF_PLAN_RESOURCE_CHANGE_KEYS` (which fields changed). [Terraform Plan Scanning](https://github.com/bridgecrewio/checkov/blob/811d068/docs/7.Scan%20Examples/Terraform%20Plan%20Scanning.md) (repo HEAD 811d068, latest release 3.3.30).
- **terraform-compliance** **[Sourced]**: BDD-style policies executed against a `terraform plan`, focused on negative testing (policy), not change detection. [README](https://github.com/terraform-compliance/cli/blob/109ce2a/README.md) (latest release 1.16.0).
- **Sentinel** **[Sourced]**: runs inside HCP Terraform / Terraform Enterprise after plan and before apply, with access to plan, state and configuration. Not usable as a local offline unit test. [Sentinel Terraform](https://developer.hashicorp.com/sentinel/docs/terraform)
- All of these assert rules ("no deletes", "encryption present"); none is a baseline diff. They need a plan JSON, so the plan's credential needs apply. **[Unverified]** whether Conftest officially documents plan-JSON usage beyond the example fixture.

## 5. Snapshot / golden tools specific to Terraform

- **terraform-snapshot-test** (Python, pytest + Syrupy) **[Sourced]**: "treats Terraform plans as unit test artifacts"; snapshots generated with `pytest -m terraform --snapshot-update -s`, committed, and compared on each run so changes show as snapshot diffs in review. Its README says tests use **read-only provider credentials** to produce the plan. Repo commit `1f8d743` (2025-10-17), a single-author project. [readme.rst](https://github.com/joaorodrig/terraform-snapshot-test/blob/1f8d743/readme.rst)
- **libtftest** (Go) **[Sourced]**: `assert/snapshot` provides `JSONStrict` (byte-for-byte) and `JSONStructural` (sorts keys, strips whitespace; intended for Terraform plan JSON and IAM policies). `LIBTFTEST_UPDATE_SNAPSHOTS=1` overwrites missing/mismatched snapshots; helpers are pure functions with no network calls. It does not normalize ids or timestamps itself as far as I read. Commit `4c8b7cb` (2026-09-14), single-author. [snapshot/doc.go](https://github.com/donaldgifford/libtftest/blob/4c8b7cb/assert/snapshot/doc.go), [README](https://github.com/donaldgifford/libtftest/blob/4c8b7cb/README.md)
- **tftest** (Google Cloud Platform, Python) **[Sourced]**: wraps terraform; `plan(output=True)` returns the parsed plan (`variables`, `outputs`, `resources`, `modules`) for pytest assertions; `init`/`plan` only tests are supported. No golden mechanism. [README](https://github.com/GoogleCloudPlatform/terraform-python-testing-helper/blob/f8c79b4/README.md) (latest release v1.8.8)
- **CDKTF** **[Sourced]**: has Jest snapshot tests (`toMatchSnapshot`), but CDKTF is deprecated as of December 10, 2025, and is irrelevant to HCL projects. [CDKTF unit tests](https://developer.hashicorp.com/terraform/cdktf/test/unit-tests)
- **Hand-rolled** approach (common in practice): `terraform show -json` piped through `jq` normalisation into a committed file, diffed in CI. **[Unverified]** in a primary source: I found no vendor documentation recommending this; it is the mechanism the two tools above automate.

## 6. Terragrunt

- **[Sourced]** `terragrunt render` produces a simplified configuration "with all includes and dependencies resolved"; `--format=json` / `--json` for JSON; `--write` / `-w` writes `terragrunt.rendered.json` beside `terragrunt.hcl`; `--all` renders every discovered configuration. HCL output is the default (JSON is the "only supported format at the moment" for the format flag per the page). [render](https://docs.terragrunt.com/reference/cli/commands/render)
- **[Sourced]** `terragrunt stack generate` writes concrete unit directories (`.terragrunt-stack/<path>/terragrunt.hcl`) from `terragrunt.stack.hcl`; `terragrunt stack run plan` generates automatically and then plans each unit. [stack generate](https://docs.terragrunt.com/reference/cli/commands/stack/generate), [stack run](https://docs.terragrunt.com/reference/cli/commands/stack/run)
- **[Sourced]** `terragrunt run --all plan` runs plan over all units; `run --all` with `-detailed-exitcode` returns an aggregate code (any 1 gives 1; else any 2 gives 2; else 0). With dependencies that were never deployed, `run --all plan` fails because dependency outputs cannot be resolved without state. [run](https://docs.terragrunt.com/reference/cli/commands/run)
- **[Sourced]** `dependency` blocks accept `mock_outputs` (used when outputs are unavailable or `skip_outputs` is true) and `mock_outputs_allowed_terraform_commands` (e.g. `["apply","plan","destroy","output"]`). [blocks](https://docs.terragrunt.com/reference/hcl/blocks)
- **Fit for an env-values repo [Recommendation]:** the stable, credential-free, deterministic artifact is the *rendered/generated configuration* (inputs and unit tree), not a plan. **[Unverified]** whether `render` or `stack generate` run without cloud credentials in all cases: `--auth-provider-cmd` docs mention HCL functions such as `get_aws_account_id` that need authentication, so configs using those functions would need credentials; `render` with real dependencies may need dependency outputs (not confirmed).
- No Terragrunt-native golden test command was found in the docs read.

## 7. Non-determinism, credentials, offline summary

| Approach | Needs cloud credentials | Handles ids/ARNs/timestamps | Golden diff |
|---|---|---|---|
| `terraform test` + `mock_provider` | No [Sourced] | Fixed via `mock_*` `defaults`/`override_*`; otherwise random 8-char strings [Sourced] | No (assertions only) |
| `terraform test` + real provider, `command = plan` | Typically yes [Unverified for specific providers] | Unknown values stay unknown | No |
| `plan -out` + `show -json` | Yes for real providers [Unverified per provider]; state needed for non-create diffs | Unknowns marked in `after_unknown` [Sourced] | DIY |
| Terratest | Same as the plan it runs | Your assertions choose what to compare | None found |
| Conftest / Checkov / terraform-compliance | Only to produce the plan | n/a (rules, not baselines) | No |
| terraform-snapshot-test | Read-only provider credentials [Sourced] | Snapshot of planned values [Unverified normalisation] | Yes |
| libtftest snapshot | Whatever produces the plan | Structural JSON compare; no id scrubbing seen | Yes |
| `terragrunt render --json -w` / `stack generate` | Not for plain configs [Unverified in general] | Deterministic text | Diffable via git |

## What is the standard?

**Plain answer [Recommendation, based on the sourced facts above]:** the standard for Terraform unit tests is the native `terraform test` framework with `command = plan` plus `mock_provider` and explicit `assert` blocks. It is vendor-supported, credential-free and fast, but it asserts on named values, not on whole-plan diffs. Whole-plan baseline ("golden") testing is not part of any first-party tool; the general building block is plan JSON, and golden tooling is community-level.

### (a) Plain Terraform root module [Recommendation]

- `unit`: keep `terraform init -backend=false -input=false` and `terraform test -filter=tests/unit.tftest.hcl` with `mock_provider` and pinned mock defaults (fixed `arn`, ids) so values are deterministic. Add assertions for the things you care about: resource counts via `for_each` keys, tags, security-relevant attributes, and `expect_failures` for validations.
- `unit-update-golden`: leave as an honest no-op ("no golden files; native tests assert values") unless you adopt a baseline. If you want unintended-change detection beyond assertions, the least-dependency option is a small script: `terraform plan -out` against empty local state with a mocked or offline-safe provider config, `terraform show -json`, normalise with `jq` (keep `resource_changes[].address`, `change.actions`, and `after` values; drop sensitive and unknown), write to `tests/golden/plan.json`; `unit` diffs it, and `unit-update-golden` rewrites it. Caveat: this needs a plan, which for cloud providers needs provider configuration that may need credentials (see section 2), so it conflicts with the "no credentials" promise of `unit`. Prefer a separate target (e.g. `plan-snapshot`) that is opt-in. Adopting `terraform-snapshot-test` or `libtftest` instead trades that script for a small third-party dependency.
- Keep the `-detailed-exitcode` no-change check for a credentialed `plan` target against a real environment (drift detection), not for `unit`.

### (b) Terragrunt environment-values repo [Recommendation]

- `unit`: render the configuration tree to JSON (`terragrunt stack generate`, then `terragrunt render --all --json -w` or equivalent) and compare against the committed expected output, or just fail on `git diff --exit-code` over the generated files. This verifies that value changes only change what you meant to change, with no credentials in the common case (see the unverified caveats in section 6; avoid `get_aws_account_id`-style functions or set mock dependency outputs in test mode).
- `unit-update-golden`: regenerate those rendered files and commit them (the target's job is purely "rewrite expected output").
- Real plans (`terragrunt run --all plan -- -detailed-exitcode`) belong in the credentialed `plan` target, not `unit`.
- Note the existing template for this repo type says `unit: no unit tests`, so this would be a new behavior, and the rendered output should be checked on a real sample before committing to it.

## Sources

Terraform (HashiCorp), fetched 2026-10-22:
- https://developer.hashicorp.com/terraform/language/tests
- https://developer.hashicorp.com/terraform/language/tests/mocking
- https://developer.hashicorp.com/terraform/cli/commands/test
- https://developer.hashicorp.com/terraform/cli/commands/plan
- https://developer.hashicorp.com/terraform/cli/commands/show
- https://developer.hashicorp.com/terraform/cli/commands/init
- https://developer.hashicorp.com/terraform/internals/json-format
- https://developer.hashicorp.com/terraform/cdktf/test/unit-tests
- https://developer.hashicorp.com/sentinel/docs/terraform

Terragrunt (Gruntwork), fetched 2026-10-22 (latest release v1.2.0 per GitHub API):
- https://docs.terragrunt.com/reference/cli/commands/render
- https://docs.terragrunt.com/reference/cli/commands/stack/generate
- https://docs.terragrunt.com/reference/cli/commands/stack/run
- https://docs.terragrunt.com/reference/cli/commands/run
- https://docs.terragrunt.com/reference/hcl/blocks

Source repositories (shallow clones, read only, not executed):
- https://github.com/gruntwork-io/terratest at 107b7ed4db1a7b0ea9dfcf0a5576d343d5b1fe6f
- https://github.com/open-policy-agent/conftest at a16df6ed915f42d8b7e3e49887db822bcd544269 (release v0.71.1)
- https://github.com/bridgecrewio/checkov at 811d068 (release 3.3.30)
- https://github.com/terraform-compliance/cli at 109ce2a (release 1.16.0)
- https://github.com/GoogleCloudPlatform/terraform-python-testing-helper at f8c79b4 (release v1.8.8)
- https://github.com/joaorodrig/terraform-snapshot-test at 1f8d743
- https://github.com/donaldgifford/libtftest at 4c8b7cb

Local file: /home/nmarks/projects/agent-config/skills/scaffold-terraform/TEMPLATES.md
