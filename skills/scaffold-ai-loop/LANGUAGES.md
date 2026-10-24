# Goal tag wiring per language

The **goal tag** keeps a red test out of `make unit`, so the `make static` commit hook stays green, while `make goal-tests` runs it. `make goal-settle` removes the tag, and the test joins the permanent suite. Each tag sits on a line of its own, so settling is a line edit.

Each section gives the edits for one language:

- the `unit` change and the `goal-tests` target;
- the Makefile variables, already `$$`-escaped: `GOAL_TAG_PATTERN` / `GOAL_TAG_PATHS` find goal tests, and `GOAL_SETTLE_SED` / `GOAL_SETTLE_MV` settle them;
- the BDD runner wiring;
- the **probe** for `make goal-selftest`: `scripts/goal-selftest/dest` holds the path, and `scripts/goal-selftest/probe` holds the content. The path must be one that `make unit` runs.

Pin every package you add to an exact version looked up at scaffold time, matching `scaffold-project` rule 1.

The Gherkin settle lines are the same everywhere; `GHERKIN_SED` below stands for them:

```
/^[[:space:]]*@goal[[:space:]]*$$/d; s/[[:space:]]+@goal([[:space:]]|$$)/\1/g
```

## Python (pytest, pytest-bdd)

- Register the marker beside `unit` and `integration` in the pytest config: `goal: red test for the active PR goal`. Keep `--strict-markers` on if it already is.
- `unit`: `-m "unit"` becomes `-m "unit and not goal"`.
- `goal-tests` (exit 5 means nothing collected, which a checks-only goal produces):

  ```makefile
  goal-tests: .venv ## Run goal-tagged tests and scenarios only
  	source .venv/bin/activate && python3 -m pytest -v -m goal tests/; rc=$$?; [ $$rc -eq 5 ] || exit $$rc
  ```

- Variables:

  ```makefile
  GOAL_TAG_PATTERN := pytest\.mark\.goal([^_[:alnum:]]|$$)|(^|[[:space:]])@goal([[:space:]]|$$)
  GOAL_TAG_PATHS :=
  GOAL_SETTLE_SED := /^[[:space:]]*@pytest\.mark\.goal[[:space:]]*$$/d; GHERKIN_SED
  GOAL_SETTLE_MV :=
  ```

- BDD: add `pytest-bdd` to `requirements.txt`. Features go in `tests/features/`, step definitions in `tests/step_defs/test_<feature>.py` calling `scenarios("../features/<feature>.feature")`. pytest-bdd turns feature tags into markers, so a red scenario carries `@unit @goal`.
- Probe: `tests/test_goal_selftest.py`

  ```python
  import pytest


  @pytest.mark.unit
  @pytest.mark.goal
  def test_goal_selftest_probe():
      assert False, "goal selftest probe"
  ```

## Go (go test, godog)

- Goal tests live in their own `*_test.go` files that start with `//go:build goal` and a blank line. `unit` needs no change: plain `go test` skips them.
- `goal-tests`:

  ```makefile
  goal-tests: ## Run goal-tagged tests and scenarios only
  	GODOG_TAGS=@goal go test -tags goal ./...
  ```

- Variables:

  ```makefile
  GOAL_TAG_PATTERN := ^//go:build goal$$|(^|[[:space:]])@goal([[:space:]]|$$)
  GOAL_TAG_PATHS :=
  GOAL_SETTLE_SED := /^\/\/go:build goal$$/{N;d;}; GHERKIN_SED
  GOAL_SETTLE_MV :=
  ```

- BDD: add `github.com/cucumber/godog`. Features go in `features/`; the suite reads its tag filter from the environment, so `unit` skips red scenarios:

  ```go
  func TestFeatures(t *testing.T) {
  	tags := os.Getenv("GODOG_TAGS")
  	if tags == "" {
  		tags = "~@goal"
  	}
  	suite := godog.TestSuite{
  		ScenarioInitializer: InitializeScenario,
  		Options:             &godog.Options{Format: "pretty", Paths: []string{"features"}, Tags: tags, TestingT: t},
  	}
  	if suite.Run() != 0 {
  		t.Fatal("feature tests failed")
  	}
  }
  ```

- Probe: `<package dir>/goal_selftest_test.go`, in a package `make unit` tests

  ```go
  //go:build goal

  package <package>

  import "testing"

  func TestGoalSelftestProbe(t *testing.T) { t.Fatal("goal selftest probe") }
  ```

## Rust (cargo test, cucumber)

- Add `[features]` `goal = []` to `Cargo.toml`; it stays after settle as the mechanism. Each goal test or test module carries `#[cfg(feature = "goal")]` on the line above it, so it is not even compiled into `unit`. `unit` needs no change.
- `goal-tests`:

  ```makefile
  goal-tests: ## Run goal-tagged tests and scenarios only
  	cargo test --features goal
  ```

- Variables:

  ```makefile
  GOAL_TAG_PATTERN := feature[[:space:]]*=[[:space:]]*"goal"|(^|[[:space:]])@goal([[:space:]]|$$)
  GOAL_TAG_PATHS :=
  GOAL_SETTLE_SED := /^[[:space:]]*\#\[cfg\(feature = "goal"\)\][[:space:]]*$$/d; GHERKIN_SED
  GOAL_SETTLE_MV :=
  ```

- BDD: add `cucumber` (and the async runtime it needs) as a dev-dependency, with a `[[test]] name = "bdd" harness = false` target. Features go in `tests/features/`; the harness runs red scenarios only under the feature:

  ```rust
  #[tokio::main]
  async fn main() {
      World::cucumber()
          .fail_on_skipped()
          .filter_run_and_exit("tests/features", |_, _, sc| {
              sc.tags.iter().any(|t| t == "goal") == cfg!(feature = "goal")
          })
          .await;
  }
  ```

- Probe: `tests/goal_selftest.rs` (when `unit` runs integration tests; otherwise a `#[cfg(test)]` module file under `src/`)

  ```rust
  #[cfg(feature = "goal")]
  #[test]
  fn goal_selftest_probe() {
      panic!("goal selftest probe");
  }
  ```

## TypeScript (vitest or jest, @cucumber/cucumber)

- Goal tests are files named `*.goal.test.ts`. Exclude them from the unit run unless `GOAL` is set. vitest: `exclude: [...configDefaults.exclude, ...(process.env.GOAL ? [] : ["**/*.goal.test.*"])]`. jest: the same condition in `testPathIgnorePatterns`.
- `goal-tests`:

  ```makefile
  goal-tests: ## Run goal-tagged tests and scenarios only
  	GOAL=1 npx vitest run goal.test
  	npx cucumber-js --tags @goal
  ```

  With jest, replace the first line with `GOAL=1 npx jest --testPathPattern 'goal\.test'`.
- Variables:

  ```makefile
  GOAL_TAG_PATTERN := (^|[[:space:]])@goal([[:space:]]|$$)
  GOAL_TAG_PATHS := *.goal.test.*
  GOAL_SETTLE_SED := GHERKIN_SED
  GOAL_SETTLE_MV := s/\.goal\.test\./.test./
  ```

- BDD: add `@cucumber/cucumber`; features go in `features/`. The existing `unit` (or a `bdd` target inside `static`) runs `npx cucumber-js --tags "not @goal"`.
- Probe: `src/goal-selftest.goal.test.ts`

  ```ts
  import { expect, test } from "vitest";

  test("goal selftest probe", () => {
    expect("goal selftest probe").toBe("");
  });
  ```

## Terraform (scaffold-terraform)

No BDD runner: acceptance criteria become `terraform test` runs and temporary checks.

- **Stacks repo.** Goal tests go in `modules/<name>/goal-tests/*.tftest.hcl`. Add `scripts/goal-tests.sh`, a copy of `scripts/unit.sh` that runs `terraform test -test-directory=goal-tests` in each module that has that directory, through `$(MISE)`. `unit` needs no change.

  ```makefile
  goal-tests: install ## Run goal-tagged terraform tests only
  	scripts/goal-tests.sh

  GOAL_TAG_PATTERN :=
  GOAL_TAG_PATHS := modules/*/goal-tests/*
  GOAL_SETTLE_SED :=
  GOAL_SETTLE_MV := s#/goal-tests/#/tests/#
  ```

  Probe: `modules/example/goal-tests/goal_selftest.tftest.hcl`

  ```hcl
  run "goal_selftest_probe" {
    command = plan
    assert {
      condition     = false
      error_message = "goal selftest probe"
    }
  }
  ```

- **Envs repo.** No tests: the goal is temporary checks only (layout, `terragrunt hcl validate`, a rendered value). `goal-tests` is `@true`, all four variables are empty, and there is no probe fixture: `make goal-selftest` probes with a failing check instead.

## Other languages

Ask the human for the test runner, then apply the same contract: a tag or path that one command excludes from `unit` and another runs, a pattern that finds it, a settle edit that removes it, and a probe.
