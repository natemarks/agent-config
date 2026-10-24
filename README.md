# Agent Config Deployment

Simple deployment tool for Claude Code skills.

## Structure

```
.
├── Makefile        # Build and deployment targets
├── install.sh      # Deployment script
└── skills/         # Skills to deploy
    ├── findings-to-issues/
    ├── purge-sensitive-data/
    ├── scaffold-ai-loop/
    ├── scaffold-project/
    └── scaffold-terraform/
```

## Skills

| Skill | Use it to |
|---|---|
| `/scaffold-project` | set up a Python, Go, Rust or CDK project: pinned deps, `make static`, commit hook, Dependabot, CI |
| `/scaffold-terraform` | set up a Terragrunt envs or stacks repo to the same bar |
| `/scaffold-ai-loop` | add the AI loop below to a project set up by either of the above |
| `/findings-to-issues` | turn a security findings document into one GitHub issue per finding |
| `/purge-sensitive-data` | remove secrets from git history |

## AI loop

`/scaffold-ai-loop` adds an issue-to-PR loop to a project. You decide what to build and you merge; agents turn each GitHub issue into a reviewed, tested PR in between.

```
plan (mattpocock skills)       groom                       drive                         you
wayfinder, to-spec,     ──►  /groom-issue 12  ──►  draft PR, goal RED  ──►  /drive-pr  ──►  PR ready  ──►  review, merge
to-tickets, triage           (one approval)        (own worktree)          (loops alone)   (goal GREEN, settled)
```

Three words carry the whole loop:

- **goal**: `make goal`, the PR's executable definition of done. It fails (red) once per unmet acceptance criterion and passes (green) when the PR is done.
- **goal map**: the table that ties each acceptance criterion to the checks that prove it. You approve it once, while grooming.
- **settle**: once the goal is green, its tests join the permanent suite and the PR's temporary files are deleted. CI blocks merging an unsettled PR.

### Set up a project (once)

1. In this repo: `make deploy`. Enable the `mattpocock-skills` plugin and run `gh auth login`.
2. In the project: `/scaffold-project` (or `/scaffold-terraform`), then `/setup-matt-pocock-skills` with GitHub as the issue tracker.
3. `/scaffold-ai-loop`. It asks three questions (language, BDD runner, security-sensitive paths), writes the loop, proves it with `make goal-selftest`, checks it with `make loop-doctor`, and shows a dry run of the branch protection it will add. Confirm it.
4. Commit (`chore: add AI loop scaffolding`), then run `make loop-doctor` until it reports no FAIL. On Bedrock it checks that `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` are pinned in `~/.claude/settings.json`; unpinned, the agents' `sonnet` alias falls back to an older model.

### Work the loop (every issue)

1. **`/loop-status`**: what needs you, each item with its next command. Merges first, then stopped loops, then issues to groom.
2. **`/groom-issue 12`**: the planner proposes fixes for any gaps in the issue and a goal map. You approve or edit them **in one reply**. The test-author then writes the failing tests, scenarios and checks, and a draft PR opens in `.claude/worktrees/12-<slug>` with the goal red.
3. **`/drive-pr`**: start it and leave it. It needs no permission prompts: the loop's commands are pre-approved and merging is denied. The implementer works the red checks, reviewers hunt for gaps (blocking ones become new failing checks), and the goal settles. The PR's **status block** shows each criterion's ✅/❌ and a round log, so you can follow along on GitHub.
4. **Review and merge** when the PR turns ready. The PR body lists the commands run, review results, risks and follow-up issue drafts. Afterwards, `/loop-status` lists the worktree to remove.

Each PR has its own worktree, so you can groom the next issue while another session drives the last one.

When `/drive-pr` stops, the status block and its report say why, what to decide, and how to resume:

| Stop | You | Resume with |
|---|---|---|
| out of rounds (default 6) | read the status block | `/drive-pr <pr> <rounds>` |
| no progress | comment the approach to take on the PR | `/drive-pr <pr>` |
| scope or criterion question | edit the issue | `/groom-issue <issue> --update`, then `/drive-pr <pr>` |
| goal files edited outside goal commits | inspect the PR's commits | `/drive-pr <pr>` |

### What keeps it honest

- **Goal-guard**: only the test-author's `goal:` commits may change the goal, so the implementer meets it instead of moving it.
- **Evidence over claims**: the skills rerun `make goal` themselves after every agent round.
- **Fresh read-only reviewers**: a reviewer on every PR, plus a security reviewer for security-sensitive paths. An LLM review is one source of findings, not a certification.
- **You hold the merge**: the loop's permissions deny `gh pr merge` and pushes to the default branch, and `goal-settled` is a required check.

### Make targets in a looped project

| Target | Does |
|---|---|
| `make goal` | the PR's definition of done: static gate, goal-guard, goal-tagged tests, `.goal/checks` |
| `make loop-status` | what needs you (the data behind `/loop-status`) |
| `make loop-doctor` | checks everything the loop depends on, with a fix for each miss |
| `make goal-selftest` | proves red, guard, settle and the hand-off to `unit` in a throwaway worktree; run it after editing the loop |
| `make loop-protect` | dry run of the required checks it would add; `APPLY=1` applies them |
| `make goal-tests`, `goal-settle`, `goal-settled` | the goal's parts, used by the skills and CI |

The agents (planner, test-author, implementer, reviewer, security-reviewer), their models, and the repo's loop facts are in the project's `CLAUDE.md` under "AI loop". All of it lives in the project, so edit it like code and re-run `/scaffold-ai-loop` to pull in template updates.

## Usage

### Deploy to default location

```bash
make deploy
```

Deploys skills to `$HOME/.claude/skills/`

### Deploy to custom location(s)

```bash
make deploy INSTALL_TARGETS="/path/to/target1 /path/to/target2"
```

Or call the script directly:

```bash
./install.sh /path/to/target1 /path/to/target2
```

### Run static checks

```bash
make static
```

Runs shellcheck on all shell scripts.

## Available Make Targets

- `make help` - Show all available targets
- `make shellcheck` - Check shell scripts for errors
- `make static` - Run all static checks (currently just shellcheck)
- `make deploy` - Deploy project-managed skills to target directories (`FORCE=1` to adopt existing same-named skills)

## How It Works

`install.sh` only writes to skill directories owned by this project, and it never deletes anything.
Ownership is recorded in `<target>/.agent-config-manifest`.

For each target directory, it:
1. Refuses to overwrite a same-named skill it doesn't own and exits with an error.
   Pass `--force` (`make deploy FORCE=1`) to take ownership of it.
2. Copies each skill in `skills/` to `<target>/<skill>/`, creating or overwriting files
3. Writes the updated manifest

At the end it prints `rm` commands for anything that should be cleaned up:
- files inside a managed skill that no longer exist in `skills/`
- managed skills that were removed from `skills/`

Review the commands and run them yourself. A removed skill stays in the manifest
until its directory is gone, so every deploy repeats the reminder.

It leaves everything else in the target alone, including skills installed by plugins or other tools.
It refuses to deploy to `/` or `$HOME`. The script finds `skills/` from its own
location, so it works from any directory.
