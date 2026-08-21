---
name: purge-sensitive-data
description: Remove sensitive data (secrets, credentials, files) from git history using git-filter-repo. Generates an auditable bash script and a GitHub Support case document for backend purge requests.
---

# Purge Sensitive Data from Git History

This skill removes sensitive data from git history using `git-filter-repo`, produces a complete audit log of every command and its output, and generates a formatted GitHub Support case document with all required technical details for requesting a backend cache purge.

## CRITICAL PRE-FLIGHT WARNING

**Before doing anything else, tell the user:**

```
BEFORE rewriting history, you must:

1. ROTATE ALL EXPOSED CREDENTIALS IMMEDIATELY — assume they are compromised.
   Rewriting git history does NOT protect you if the secret was ever cloned or cached.

2. GitHub Support will ONLY assist with sensitive data removal when the risk cannot be
   mitigated by rotating credentials alone. If rotation is possible, do that first.

3. This process rewrites commit hashes. All collaborators must re-clone after the purge.
   Open PRs may lose their diff views. Signatures will be invalidated.
```

Ask: "Have all exposed credentials already been rotated/revoked? (yes / not yet)"

- If "not yet": Stop and tell them to rotate credentials first, then return.
- If "yes": Proceed to the interview.

---

## INTERVIEW PHASE

Ask these questions one at a time.

### Question 1: Repository Identity

**Ask:** "What is the GitHub repository to purge? (format: owner/repo-name)"

Store as `REPO_OWNER_REPO`.

### Question 2: Working Directory

**Ask:** "Are you working in a fresh clone of this repository, or an existing working directory?"

**Context:** GitHub docs require starting from a fresh clone so local uncommitted changes don't interfere.

- If existing directory: "I strongly recommend running this from a fresh clone. The script will warn you and ask for confirmation if you proceed from an existing clone."
- If fresh clone or they accept the risk: proceed.

### Question 3: What to Remove

**Ask:** "What type of sensitive data needs to be purged? Select all that apply:
1. Specific files or directories (e.g., `secrets.env`, `logs/`, `config/prod.yaml`)
2. Text patterns / secret values in files (e.g., API keys, passwords, tokens embedded in code)
3. Both"

**If option 1 or 3 — ask for file/directory paths:**
"List each file or directory path as it appears in the repository (one per line). Include any paths the file may have been moved from or renamed — git-filter-repo must be run once per historical path."

Store as `PURGE_PATHS` (array).

**If option 2 or 3 — ask for replacement patterns:**
"For each secret, I need:
- A short label (e.g., `STRIPE_KEY`, `DB_PASSWORD`) — used in the log and support case
- The exact string to remove from history

I will NOT log the actual secret values. They go into a replacements file that git-filter-repo reads."

Collect pairs: label → actual_value. Store as `REPLACEMENTS` array.

### Question 4: Replacement Placeholder

**Ask (if text replacements):** "What placeholder should replace the removed values in history? Default: `***REMOVED***`"

Store as `REPLACEMENT_PLACEHOLDER`. Default: `***REMOVED***`

### Question 5: Output Location

**Ask:** "Where should the purge script and log directory be written? Default: current directory (`./purge-YYYYMMDD/`)"

Store as `OUTPUT_DIR`. Default is a timestamped subdirectory in the current directory, created by the script.

---

## ENVIRONMENT VERIFICATION

Before generating the script, check the actual environment:

```bash
# Check git-filter-repo is installed
git-filter-repo --version 2>/dev/null || echo "NOT INSTALLED"

# Check we're in a git repo
git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT A GIT REPO"

# Check current remote
git remote get-url origin 2>/dev/null || echo "NO REMOTE"

# Check for uncommitted changes
git status --short
```

If `git-filter-repo` is not installed, tell the user:
```
git-filter-repo is not installed. Install it with:
  brew install git-filter-repo        # macOS
  pip install git-filter-repo         # or via pip
  apt install git-filter-repo         # Debian/Ubuntu
```

If not in a git repo, stop and tell them to navigate to the repository.

Warn if there are uncommitted changes (`git status --short` is non-empty).

---

## SCRIPT GENERATION PHASE

Generate a bash script named `purge-sensitive-data.sh` in the user's specified output directory (or current directory). The script must:

1. Create a timestamped log directory
2. Log every command and its full output to a log file
3. Run the appropriate `git-filter-repo` commands
4. Extract GitHub Support required data post-run
5. Generate a formatted GitHub Support case document
6. Require explicit confirmation before force-pushing
7. Print collaborator instructions after push

### Script Template

Generate the following script, substituting values from the interview:

```bash
#!/usr/bin/env bash
# Generated by purge-sensitive-data skill
# Repository: {{REPO_OWNER_REPO}}
# Generated: (filled in at generation time)
#
# PURPOSE: Remove sensitive data from git history and generate GitHub Support case.
# USAGE:   bash purge-sensitive-data.sh
#
# IMPORTANT: Run from the root of a FRESH CLONE of {{REPO_OWNER_REPO}}.

set -euo pipefail

REPO="{{REPO_OWNER_REPO}}"
LOG_DIR="purge-log-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/purge-commands.log"
SUPPORT_CASE_FILE="${LOG_DIR}/github-support-case.md"
REPLACEMENTS_FILE="${LOG_DIR}/replacements.txt"

# ── Helpers ─────────────────────────────────────────────────────────────────

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_section() {
    local bar="════════════════════════════════════════════════════════════════"
    log ""
    log "$bar"
    log "  $*"
    log "$bar"
}

run_cmd() {
    log "COMMAND: $*"
    local output exit_code
    output=$("$@" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    echo "$output"
    echo "$output" >> "$LOG_FILE"
    log "EXIT CODE: $exit_code"
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: command failed with exit code $exit_code"
        return $exit_code
    fi
}

confirm() {
    local prompt="$1"
    echo ""
    echo "────────────────────────────────────────"
    echo "$prompt"
    echo "Type 'yes' to continue, anything else to abort:"
    read -r response
    if [[ "$response" != "yes" ]]; then
        log "ABORTED by user at confirmation prompt: $prompt"
        echo "Aborted."
        exit 1
    fi
    log "CONFIRMED: $prompt"
}

# ── Setup ────────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"
log_section "PURGE STARTED"
log "Repository:     $REPO"
log "Operator:       $(git config user.name 2>/dev/null || echo unknown) <$(git config user.email 2>/dev/null || echo unknown)>"
log "Working dir:    $(pwd)"
log "Hostname:       $(hostname)"

# ── Prerequisites ─────────────────────────────────────────────────────────────

log_section "PREREQUISITES"

# git-filter-repo version
run_cmd git-filter-repo --version

# Confirm inside a git repo
run_cmd git rev-parse --is-inside-work-tree

# Show current remote(s)
run_cmd git remote -v

# Show current HEAD
run_cmd git log --oneline -5

# Check for uncommitted changes
DIRTY=$(git status --short 2>/dev/null || true)
if [[ -n "$DIRTY" ]]; then
    log "WARNING: working tree has uncommitted changes:"
    log "$DIRTY"
    confirm "Uncommitted changes detected. Proceeding may produce unexpected results. Continue?"
fi

# Confirm we are on the right repo
run_cmd git remote get-url origin
confirm "Verify the remote above matches '$REPO'. Is this the correct repository?"

# ── Build replacements file (if text patterns) ────────────────────────────────

{{IF_REPLACEMENTS_BLOCK}}
log_section "BUILDING REPLACEMENTS FILE"
log "Writing replacements to: $REPLACEMENTS_FILE"
log "NOTE: Actual secret values are in the replacements file but are NOT logged here."
log "Replacement labels targeted (labels only, not values):"
{{REPLACEMENT_LABELS_LOG}}

cat > "$REPLACEMENTS_FILE" << 'REPLACEMENTS_EOF'
{{REPLACEMENTS_CONTENT}}
REPLACEMENTS_EOF

log "Replacements file written: $(wc -l < "$REPLACEMENTS_FILE") entries"
{{END_IF_REPLACEMENTS_BLOCK}}

# ── Run git-filter-repo ────────────────────────────────────────────────────────

log_section "RUNNING GIT-FILTER-REPO"

{{FILTER_REPO_COMMANDS}}

# ── Post-run analysis ─────────────────────────────────────────────────────────

log_section "POST-RUN ANALYSIS"

# Count affected pull requests
AFFECTED_PR_COUNT=0
if [[ -f ".git/filter-repo/changed-refs" ]]; then
    AFFECTED_PR_COUNT=$(grep -c '^refs/pull/.*/head$' .git/filter-repo/changed-refs 2>/dev/null || echo 0)
    log "Affected pull request refs: $AFFECTED_PR_COUNT"
    log "Full changed-refs:"
    cat .git/filter-repo/changed-refs >> "$LOG_FILE"
else
    log "WARNING: .git/filter-repo/changed-refs not found — run may have had no effect or failed."
fi

# Extract first changed commits (from commit-map: old-hash new-hash, sorted by position)
FIRST_CHANGED_COMMITS="N/A"
if [[ -f ".git/filter-repo/commit-map" ]]; then
    log "Commit map (first 20 entries):"
    head -20 .git/filter-repo/commit-map >> "$LOG_FILE"
    # The first line that is not the header gives the earliest rewritten commit
    FIRST_CHANGED_COMMITS=$(grep -v '^old' .git/filter-repo/commit-map 2>/dev/null | head -5 | awk '{print $1}' | tr '\n' ' ' || echo "N/A")
    log "First changed commit(s): $FIRST_CHANGED_COMMITS"
fi

# Check for LFS orphans file
LFS_ORPHANS="none"
if [[ -f ".git/filter-repo/filter-repo/lfs-objects-to-delete" ]] || \
   [[ -f "$(git rev-parse --show-toplevel)/.git/filter-repo/lfs-objects-to-delete" ]]; then
    LFS_ORPHANS_FILE=$(find .git/filter-repo -name '*lfs*' 2>/dev/null | head -1)
    if [[ -n "$LFS_ORPHANS_FILE" ]]; then
        LFS_ORPHANS="$LFS_ORPHANS_FILE"
        log "LFS orphans file found: $LFS_ORPHANS_FILE"
        cat "$LFS_ORPHANS_FILE" >> "$LOG_FILE"
    fi
fi

# ── Generate GitHub Support case document ─────────────────────────────────────

log_section "GENERATING GITHUB SUPPORT CASE DOCUMENT"

OPERATOR_NAME=$(git config user.name 2>/dev/null || echo "unknown")
OPERATOR_EMAIL=$(git config user.email 2>/dev/null || echo "unknown")
FILTER_REPO_VERSION=$(git-filter-repo --version 2>/dev/null || echo "unknown")
PURGE_TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

cat > "$SUPPORT_CASE_FILE" << EOF
# GitHub Support Case: Sensitive Data Purge Request

## Repository
- **Repository:** $REPO
- **URL:** https://github.com/$REPO

## Request
Please dereference and garbage collect all cached views and objects for the
rewritten history in this repository. We have used git-filter-repo with the
--sensitive-data-removal flag to remove sensitive data from the full commit
history and have force-pushed the rewritten history.

Specifically, please:
1. Dereference and delete any cached pull request refs affected by this rewrite
2. Run garbage collection on the repository
3. Purge any cached commit views or diff pages for the affected commits
4. Remove any orphaned LFS objects (if applicable, see below)

## Purge Details

| Field                          | Value                                      |
|--------------------------------|--------------------------------------------|
| Purge Date/Time                | $PURGE_TIMESTAMP                           |
| Operator                       | $OPERATOR_NAME <$OPERATOR_EMAIL>           |
| git-filter-repo Version        | $FILTER_REPO_VERSION                       |
| Affected Pull Request Refs     | $AFFECTED_PR_COUNT                         |
| First Changed Commit(s)        | $FIRST_CHANGED_COMMITS                     |
| LFS Orphans File               | $LFS_ORPHANS                               |

## Data Removed

{{SUPPORT_CASE_DATA_DESCRIPTION}}

## Commands Executed

See attached log file: \`purge-commands.log\` (in the same directory as this file).
This log contains every command run with its full output, timestamps, and exit codes.

## Post-Purge Actions Taken

- [x] Exposed credentials have been rotated/revoked
- [x] git-filter-repo run with --sensitive-data-removal flag
- [x] History force-pushed to origin with --mirror
- [ ] All collaborators notified to re-clone (pending)
- [ ] Branch protections re-enabled if temporarily disabled (verify)

## Collaborator Instructions

All collaborators must delete their local clones and re-clone fresh:

\`\`\`bash
# Each collaborator runs:
git clone https://github.com/$REPO
\`\`\`

They must NOT run \`git pull\` or \`git fetch\` — this would reintroduce old objects.
If a collaborator has local branches, they must rebase (NOT merge) onto the new history.
EOF

log "GitHub Support case written to: $SUPPORT_CASE_FILE"
log "Attach both $SUPPORT_CASE_FILE and $LOG_FILE to your GitHub Support ticket at:"
log "  https://support.github.com"

# ── Confirm force push ────────────────────────────────────────────────────────

log_section "FORCE PUSH"
log "About to force-push all refs to origin."
log "This is IRREVERSIBLE and will affect all collaborators."
echo ""
echo "Affected pull request refs: $AFFECTED_PR_COUNT"
echo "First changed commit(s):    $FIRST_CHANGED_COMMITS"
echo ""
echo "Review the support case document at: $SUPPORT_CASE_FILE"
echo "Review the full command log at:      $LOG_FILE"
echo ""
confirm "Ready to force-push to origin? This cannot be undone."

run_cmd git push --force --mirror origin
log "Force push completed. Ignore any failures for refs/pull/ entries — GitHub marks those read-only."

# ── Done ─────────────────────────────────────────────────────────────────────

log_section "PURGE COMPLETE"
log ""
log "NEXT STEPS:"
log "1. Submit a GitHub Support ticket at https://support.github.com"
log "   Attach: $SUPPORT_CASE_FILE"
log "   Attach: $LOG_FILE"
log ""
log "2. Notify all collaborators to re-clone the repository:"
log "   git clone https://github.com/$REPO"
log ""
log "3. Re-enable any branch protections you temporarily disabled."
log ""
log "4. Add the sensitive data to .gitignore / secrets management to prevent recurrence."
log ""
echo "All output is in: $LOG_DIR/"
echo "  - $LOG_FILE          — full command log for GitHub Support"
echo "  - $SUPPORT_CASE_FILE — GitHub Support case document"
```

### Filling in the Template Placeholders

When generating the script, substitute:

**`{{REPO_OWNER_REPO}}`** — the `owner/repo` value from the interview.

**`{{IF_REPLACEMENTS_BLOCK}}` / `{{END_IF_REPLACEMENTS_BLOCK}}`** — include this block only if the user is doing text pattern replacement (modes 2 or 3). Remove the block entirely for path-only purges.

**`{{REPLACEMENT_LABELS_LOG}}`** — one `log` line per replacement label (NOT the value). Example:
```bash
log "  - STRIPE_API_KEY"
log "  - DB_PASSWORD_STAGING"
```

**`{{REPLACEMENTS_CONTENT}}`** — the actual `replacements.txt` content, one line per entry:
```
LITERAL:actual_secret_value==>***REMOVED***
LITERAL:another_secret==>***REMOVED***
```
Use `LITERAL:` prefix (not `regex:`) for exact secret strings. If the user wants regex, use `regex:pattern==>replacement`.

**`{{FILTER_REPO_COMMANDS}}`** — the actual `git-filter-repo` invocations. Generate based on what the user needs:

For path removal only:
```bash
# Remove each path from history
# If a file was renamed, run once per historical path
run_cmd git-filter-repo --sensitive-data-removal \
    --invert-paths \
    --path "path/to/file.txt"
```

For multiple paths, use multiple `--path` arguments in a single call:
```bash
run_cmd git-filter-repo --sensitive-data-removal \
    --invert-paths \
    --path "secrets.env" \
    --path "config/prod.yaml" \
    --path "logs/"
```

For text replacement only:
```bash
run_cmd git-filter-repo --sensitive-data-removal \
    --replace-text "$REPLACEMENTS_FILE"
```

For both path removal AND text replacement, run as two separate commands:
```bash
# First: remove files from history
run_cmd git-filter-repo --sensitive-data-removal \
    --invert-paths \
    --path "secrets.env"

# Second: replace any remaining text patterns
run_cmd git-filter-repo --sensitive-data-removal \
    --replace-text "$REPLACEMENTS_FILE"
```

**`{{SUPPORT_CASE_DATA_DESCRIPTION}}`** — a human-readable description of what was removed. Use labels, not actual values. Example:
```
The following types of sensitive data were removed from all commits in the repository history:

- File path `secrets.env` (contained hardcoded AWS credentials)
- File path `logs/staging/logs.txt` (contained KMS key ARNs and account IDs)
- Text pattern: STRIPE_API_KEY — replaced with placeholder in all commits
- Text pattern: DB_PASSWORD_STAGING — replaced with placeholder in all commits
```

---

## REVIEW & EXECUTION PHASE

After generating the script:

1. Write the script to `purge-sensitive-data.sh` in the current directory (or the user's specified output dir).
2. Make it executable: `chmod +x purge-sensitive-data.sh`
3. Present the script to the user:
   ```
   Script written to: purge-sensitive-data.sh

   REVIEW IT CAREFULLY before running. Key things to verify:
   - The REPO variable matches your repository
   - All target paths are correct
   - The replacements file will contain the right values

   Run it with:
       bash purge-sensitive-data.sh

   The script will pause for confirmation before force-pushing.
   ```

4. Tell the user what the script will produce:
   ```
   When run, the script creates a `purge-log-TIMESTAMP/` directory containing:
   - purge-commands.log        — full audit log of every command + output
   - github-support-case.md    — pre-filled support case for GitHub
   - replacements.txt          — the replacements file (if text patterns used)

   Both files should be attached to your GitHub Support ticket at:
     https://support.github.com
   ```

---

## POST-EXECUTION GUIDANCE

After the user runs the script, guide them through:

### Step 1: Submit GitHub Support Ticket

Tell the user to go to https://support.github.com and:
- Subject: "Sensitive data purge - please garbage collect [owner/repo]"
- Describe: what was removed (using labels, not actual values)
- Attach: `github-support-case.md` and `purge-commands.log`
- GitHub Support needs: repo identifier, number of affected PRs, first changed commit hashes, LFS orphans file (if any)

Note: GitHub Support only assists when the risk cannot be mitigated by rotating credentials. If credentials can be rotated, they may decline. Include evidence of credential rotation in your ticket.

### Step 2: Notify Collaborators

Every person with a clone of the repository must:
1. Delete their local clone
2. Re-clone fresh: `git clone https://github.com/OWNER/REPO`

They must NOT use `git pull` — this re-introduces old objects.

If they have local branches, they must rebase (not merge) onto the new history using the old-to-new commit mapping in `.git/filter-repo/commit-map`.

### Step 3: Re-enable Branch Protections

If branch protections were temporarily disabled for the force push, re-enable them now via: Settings → Branches → Branch protection rules.

### Step 4: Prevent Recurrence

Recommend:
- Add the sensitive path(s) to `.gitignore`
- Use GitHub secret scanning / push protection
- Add a pre-commit hook with `gitleaks` (see `scaffold-project` skill)
- Use environment variables or AWS Secrets Manager / GitHub Actions secrets instead of hardcoded values

---

## EDGE CASES

**File was renamed:** Run `git-filter-repo --invert-paths` once per historical path name. The script should include a separate `--path` argument for each alias.

**Multiple independent secrets in text:** All can go into a single `replacements.txt` file. `git-filter-repo --replace-text` processes all patterns in one pass.

**Branch protections blocking force push:** The user must temporarily disable branch protection rules in GitHub → Settings → Branches for the `main`/`master` branch, force push, then re-enable.

**`refs/pull/` push failures:** These are expected — GitHub marks PR refs read-only. The script logs and ignores them. GitHub Support handles the actual PR cleanup.

**LFS objects:** If the repository uses Git LFS, git-filter-repo may produce an `lfs-objects-to-delete` file. Include this file path in the GitHub Support ticket so they can remove the orphaned LFS objects from storage.

**Fork contamination:** GitHub cannot remove sensitive data from public forks. The user should contact the fork owners, or request that GitHub disable forks temporarily before the purge window. This is out of scope for the script but worth noting in the support case.
