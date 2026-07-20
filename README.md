# Agent Config Deployment

Simple deployment tool for Claude Code skills.

## Structure

```
.
├── Makefile        # Build and deployment targets
├── install.sh      # Deployment script
└── skills/         # Skills to deploy
    └── scaffold-project/
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
- `make deploy` - Deploy skills to target directories

## How It Works

The `install.sh` script:
1. Takes one or more target directories as arguments
2. Creates each target directory if it doesn't exist
3. Uses `rsync` (or `cp` as fallback) to copy `skills/` contents to each target
4. Reports deployment status

The `--delete` flag in rsync ensures the target is synchronized (removes files that no longer exist in source).
