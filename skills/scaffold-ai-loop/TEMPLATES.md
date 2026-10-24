# Templates

Fill each `{{PLACEHOLDER}}` from the interview and [LANGUAGES.md](LANGUAGES.md). The scripts, agents, skills, settings and CI workflow are files under [templates/](templates/), copied as described in `SKILL.md`.

## Makefile block

Append to the project Makefile and add its targets to `.PHONY`. Take `goal-tests` and the four `GOAL_*` language lines from the language's section of LANGUAGES.md, with `GHERKIN_SED` expanded.

```makefile
# AI loop: see "AI loop" in CLAUDE.md
GOAL_STATIC ?= {{STATIC_TARGET}}
GOAL_TAG_PATTERN := {{GOAL_TAG_PATTERN}}
GOAL_TAG_PATHS := {{GOAL_TAG_PATHS}}
GOAL_SETTLE_SED := {{GOAL_SETTLE_SED}}
GOAL_SETTLE_MV := {{GOAL_SETTLE_MV}}
LOOP_REQUIRED_CHECKS := {{STATIC_CHECK_JOB}} goal-settled
LOOP_READY_LABEL := {{READY_LABEL}}
GOAL_ENV = GOAL_STATIC=$(GOAL_STATIC) GOAL_TAG_PATTERN='$(GOAL_TAG_PATTERN)' GOAL_TAG_PATHS='$(GOAL_TAG_PATHS)' GOAL_SETTLE_SED='$(GOAL_SETTLE_SED)' GOAL_SETTLE_MV='$(GOAL_SETTLE_MV)'
LOOP_ENV = GOAL_STATIC=$(GOAL_STATIC) LOOP_REQUIRED_CHECKS='$(LOOP_REQUIRED_CHECKS)' LOOP_READY_LABEL='$(LOOP_READY_LABEL)'

goal: ## Run the PR goal: static gate, goal guard, goal-tagged tests, .goal/checks (red until the PR is done)
	@$(GOAL_ENV) scripts/goal.sh

{{GOAL_TESTS_TARGET}}

goal-settle: ## Retire the goal: untag goal tests, delete .goal/, commit "goal: settle"
	@$(GOAL_ENV) scripts/goal-settle.sh

goal-settled: ## Fail while goal scaffolding (.goal/, goal tags) remains; required check in CI
	@$(GOAL_ENV) scripts/goal-settled.sh

goal-selftest: ## Prove the loop's mechanics end to end in a throwaway worktree
	@$(GOAL_ENV) scripts/goal-selftest.sh

loop-doctor: ## Check everything the AI loop depends on, with a fix for each miss
	@$(LOOP_ENV) scripts/loop-doctor.sh

loop-protect: ## Require the loop's checks on the default branch (dry run; APPLY=1 to apply)
	@$(LOOP_ENV) scripts/loop-protect.sh $(if $(filter 1,$(APPLY)),--apply)

loop-status: ## Show what needs you: stopped loops, PRs to merge, issues to groom, worktrees to remove
	@$(LOOP_ENV) scripts/loop-status.sh
```

## CLAUDE.md section

Append to `CLAUDE.md` (create it if missing). Every agent and loop skill reads this section, so it is the one place for this repo's loop facts.

````markdown
## AI loop

Each GitHub issue is a contract for one change. The human owns its goal, priority, acceptance criteria and acceptable risk, and merges the PR. Agents draft, implement and review.

1. `/loop-status` (or `make loop-status`): what needs the human, with the next command for each item.
2. `/groom-issue <issue>`: one approval of the contract and goal map, then a draft PR in `.claude/worktrees/<branch>` whose goal is red.
3. `/drive-pr [pr] [rounds]`: agents loop until `make goal` is green, review, settle, and mark the PR ready. Progress shows in the PR's status block.
4. The human reviews the diff and CI, merges, and turns follow-ups into issues.

Each PR works in its own worktree under `.claude/worktrees/`; skills switch into it with `EnterWorktree`.

### Goal

The **goal** is the PR's executable definition of done.

- `make goal`: `{{STATIC_TARGET}}`, goal-guard, goal-tagged tests and scenarios, and `.goal/checks/*.sh`. The last line reads `GOAL GREEN` or `GOAL RED: <gates>`.
- `make goal-tests`: goal-tagged tests and scenarios only.
- `make goal-settle`: untag the goal's tests so they join `make unit`, delete `.goal/`, commit `goal: settle #<issue>`.
- `make goal-settled`: fails while goal scaffolding remains. A required CI check on ready PRs.
- `make goal-selftest` and `make loop-doctor`: prove the loop works, and check what it depends on.
- **Goal tag**: {{GOAL_TAG}}, on a line of its own. It keeps a red test out of `make unit`, so the commit hook stays green.
- **BDD**: {{BDD_RUNNER}}. Features in `{{FEATURES_DIR}}`; red scenarios are tagged `@goal`.

`.goal/` exists only on a PR branch and is deleted at settle:

| Path | Holds |
|---|---|
| `ISSUE` | the issue number |
| `plan.md` | the approved plan and goal map (criterion → checks) |
| `locked` | goal-owned paths outside `.goal/`, one per line |
| `checks/*.sh` | temporary completeness checks |
| `last-run.log` | latest `make goal` output (untracked) |

Goal-owned files (`.goal/` and every path in `locked`) change only in `goal: ...` commits; goal-guard enforces it.

### PR status block

`/groom-issue` and `/drive-pr` keep this block in the PR body through `scripts/goal-pr-status.sh <pr>`; `make loop-status` reads its first line.

```markdown
<!-- goal-state: red | green | stopped:<budget|no-progress|scope|guard> | ready -->
**Goal: RED** · round 2 · updated 2026-10-24

| # | Acceptance criterion | Checks | Status |
|---|---|---|---|
| 1 | Given …, when …, then … | `tests/test_x.py::test_y` | ❌ |

**Stopped:** <reason>. <the decision needed>. Resume: `<command>`

<details><summary>Round log</summary>

| Round | Red before | Agent (model) | Commits | Note |
|---|---|---|---|---|

</details>
```

The **Stopped** line appears only in a `stopped:` state.

### Agents

| Agent | Model | Tools | Role |
|---|---|---|---|
| planner | opus | read-only | contract gaps, goal map, approach, risks |
| test-author | sonnet | edit | writes and corrects the goal |
| implementer | sonnet | edit | makes the goal green |
| reviewer | sonnet | read-only | bugs, acceptance, missing cases |
| security-reviewer | opus | read-only | threat model and scanners |

`/drive-pr` raises the implementer and reviewer to opus for cross-cutting changes and after a round without progress. On Bedrock, the aliases resolve through `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`; `make loop-doctor` checks they are pinned.

### Security-sensitive paths

{{SECURITY_PATHS}}

A diff touching these, or an issue labelled `security`, gets the security-reviewer as well as the reviewer. An LLM review is one source of findings: security exceptions and consequential security calls stay with a qualified human.
````
