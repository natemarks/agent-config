# Agent Config Deployment

Simple deployment tool for Claude Code skills.

## Structure

```
.
├── Makefile        # Build and deployment targets
├── install.sh      # Deployment script
└── skills/         # Skills to deploy
    ├── scaffold-project/
    └── scaffold-terraform/
```

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
