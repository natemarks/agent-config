---
name: scaffold-ai-loop
description: Add the issue-to-PR AI loop to a scaffolded project - make goal and its scripts, /loop-status, /groom-issue and /drive-pr skills, five agents, loop permissions, a goal-settled merge gate, and self-test and doctor targets.
disable-model-invocation: true
---

# AI Loop Scaffolding

Adds an issue-to-PR loop on top of a project that `scaffold-project` or `scaffold-terraform` already set up. Planning stays upstream, with `wayfinder`, `to-spec`, `to-tickets` and `triage` producing GitHub issues; this loop takes each issue to a mergeable PR:

1. `/loop-status` shows what needs the human and the next command for each item.
2. `/groom-issue <issue>`: the planner finds contract gaps and maps each acceptance criterion to a check, the human approves it all in one screen, the test-author writes Gherkin scenarios, goal-tagged failing tests and temporary checks, and a draft PR opens in its own worktree with `make goal` **red**.
3. `/drive-pr`: the implementer loops until `make goal` is **green**, fresh read-only reviewers hunt for gaps (blocking ones become new failing checks), `make goal-settle` folds the goal's tests into the permanent suite, and the PR is marked ready. The PR's status block shows progress, and a stop names the decision needed and the command that resumes.
4. The human reviews and merges. The required `goal-settled` check blocks an unsettled PR, and the loop's permissions deny merging to agents.

Everything written into the project is a project file under version control, so the team reviews and edits it like code. Re-running this skill updates it.

## Rules

1. **The goal is the definition of done.** `make goal` runs the static gate, goal-guard, goal-tagged tests and `.goal/checks/*.sh`, and is green only when the PR is done. On the default branch, with no `.goal/`, it is the static gate plus goal-guard and passes.
2. **The static gate stays green throughout.** Red tests carry the language's goal tag ([LANGUAGES.md](LANGUAGES.md)), which keeps them out of `make unit` and the commit hook and puts them in `make goal-tests`.
3. **The goal is fixed while it is being met.** Goal-owned files change only in `goal: ...` commits; `scripts/goal-guard.sh` turns `make goal` red otherwise.
4. **Deterministic steps are scripts.** Settling, worktrees, the PR status block, protection, status, the self-test and the doctor are `scripts/*.sh` behind make targets, so the agents run them rather than re-derive them.
5. **Pins and tools follow the base scaffold.** Exact versions looked up live (BDD runners, the `actions/checkout` SHA); tools run the way the base Makefile already runs them (`.venv`, `$(MISE)`).
6. **Existing files**: read each before touching it, then ask replace / merge / skip. On a re-run, diff each project file against its template and show the human what would change.

## Preconditions

Check each one; on a miss, name the skill or command that fixes it and stop.

- Git repo with a GitHub `origin`, and `gh auth status` passes.
- A Makefile with `help`, `unit` and a static gate (`static-check`, else `static`), a CI workflow running it, and the `make static` commit hook: run `scaffold-project` or `scaffold-terraform`.
- `docs/agents/issue-tracker.md` names GitHub: run `/setup-matt-pocock-skills`.

## Interview

Ask one question at a time, each with a line of context and the recommended answer first. Skip what the repo already answers.

1. **Language**: detect from the repo and confirm. Picks the section of [LANGUAGES.md](LANGUAGES.md) to apply.
2. **BDD runner**: add the language's runner from LANGUAGES.md (recommended), or none. Without one, the planner maps criteria to tests and checks only. Terraform has none.
3. **Security-sensitive paths**: propose a list from a repo scan (auth, request and input parsing, secrets and config, IAM and policy files, crypto, migrations, dependency manifests) and let the human edit it.

Settle the rest from the repo without asking: the static gate (`static-check` when the Makefile has it, else `static`), its CI job name (the `jobs:` key in the static-check workflow), the default branch, and the agent-ready label (`ready-for-agent`, or its string in `docs/agents/triage-labels.md`).

## Scaffolding

Run in order; each step is done when its line holds.

1. **Scripts**: copy `templates/scripts/*.sh` to `scripts/`, `chmod +x` all but `goal-lib.sh`, `git add`. Done when `make shellcheck` passes.
2. **Goal tag and BDD**: apply the language's section of LANGUAGES.md: the marker, feature, build tag or config exclusion; the `unit` change; the BDD runner and its pinned package. Done when `make unit` still passes.
3. **Self-test probe**: write `scripts/goal-selftest/dest` and `scripts/goal-selftest/probe` from the language's probe (none for a Terraform envs repo).
4. **Makefile**: append the block from [TEMPLATES.md](TEMPLATES.md#makefile-block) with the language's values. Done when `make help` lists `goal`, `goal-tests`, `goal-settle`, `goal-settled`, `goal-selftest`, `loop-doctor`, `loop-protect` and `loop-status`.
5. **Gitignore**: add `.goal/*.log` and `.claude/worktrees/`.
6. **Permissions**: merge `templates/claude/settings.json` into `.claude/settings.json` with `{{DEFAULT_BRANCH}}` filled, keeping existing entries. It pre-approves the loop's commands, so `/drive-pr` runs without prompts, and denies merging, skipping the commit hook, force pushes and pushes to the default branch. Show the human the merged `permissions` before writing.
7. **CI**: copy `templates/ci/goal-settled.yml` to `.github/workflows/`, with the latest `actions/checkout` release SHA resolved live (`gh api repos/actions/checkout/releases/latest`, then the tag's commit). Done when its `uses:` line carries a SHA and a `# vX.Y.Z` comment.
8. **Agents**: copy `templates/agents/*.md` to `.claude/agents/`.
9. **Skills**: copy `templates/skills/<name>/SKILL.md.tmpl` to `.claude/skills/<name>/SKILL.md` for `loop-status`, `groom-issue` and `drive-pr`.
10. **CLAUDE.md**: append the "AI loop" section from [TEMPLATES.md](TEMPLATES.md#claudemd-section), filled from the interview and LANGUAGES.md. Done when no `{{` remains in it.
11. **Merge gate**: run `make loop-protect` and show the human its dry run. On their confirmation, run `make loop-protect APPLY=1`. It adds the required checks and removes none. GitHub only offers a check as required after it has run once, so on a fresh repo this step may need a first PR; say so when it applies.

## Verification

Done when all hold; fix any miss before reporting.

- `make goal-selftest` ends `goal-selftest: OK` (it proves red, guard, settle and the unit hand-off in a throwaway worktree).
- `make loop-doctor` reports no FAIL. Report each WARN, and any FAIL that waits on the human (a Bedrock pin, the merge gate before its first CI run).
- `grep -rn '{{' CLAUDE.md .claude/ Makefile .github/workflows/goal-settled.yml` returns nothing.

Report what was created, skipped and merged, then the human's next steps:

- review the files, then commit with `chore: add AI loop scaffolding`;
- apply whatever `make loop-doctor` still fails on;
- run `/loop-status` and groom the first issue it lists.
