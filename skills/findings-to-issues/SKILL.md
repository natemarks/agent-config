---
name: findings-to-issues
description: Read a security findings document and create one GitHub issue per finding, each labelled with its severity.
disable-model-invocation: true
---

# findings-to-issues

Read a security findings document and create one GitHub issue per finding with a severity label.

## Step 1: Read the document

The document path comes from `args` (text after the command name). If absent, ask: "Path to the security findings document?"

Read the full file. If unreadable, stop and report the error.

## Step 2: Extract findings

Identify every discrete finding: each vulnerability, misconfiguration, credential exposure, or security weakness is one finding.

For each finding record:
- **title** — one concise sentence naming the issue (no severity prefix)
- **severity** — one of: `critical`, `high`, `medium`, `low`, `informational` (see Severity Reference)
- **purge** — true if sensitive data (secrets, credentials, tokens, private keys) is present in git history (not merely in the working tree)
- **details** — full technical context: affected component, location, evidence, conditions
- **remediation** — recommended fix
- **references** — CVEs, CWEs, links, or "None"

Completion criterion: every finding in the document is captured. When severity is ambiguous, classify conservatively (higher) and note the uncertainty in details.

## Step 3: Confirm with user

Present the findings as a table:

| # | Title | Severity | Purge? |
|---|-------|----------|--------|
| 1 | ...   | high     | yes    |

Ask: "Create GitHub issues for these N findings? (yes / edit first)"

On "edit first": accept corrections and re-confirm before proceeding.

## Step 4: Detect repo

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If this fails, ask: "GitHub repo (owner/repo)?"

## Step 5: Ensure severity labels exist

For each severity level present in the confirmed findings:

```bash
gh label create "severity:LEVEL" --color COLOR --description DESC --repo REPO 2>/dev/null || true
```

| Label | Color | Description |
|-------|-------|-------------|
| `severity:critical` | `#d93f0b` | Active exploit or credential exposure |
| `severity:high` | `#e07b39` | Significant risk, near-term fix required |
| `severity:medium` | `#fbca04` | Moderate risk, scheduled remediation |
| `severity:low` | `#0075ca` | Minor risk or defense-in-depth |
| `severity:informational` | `#cccccc` | Best-practice finding, no exploit path |
| `purge` | `#b60205` | Sensitive data in git history — requires history rewrite |

## Step 6: Create issues

For each finding:

```bash
gh issue create \
  --repo REPO \
  --title "[SEVERITY_UPPER] TITLE" \
  --label "severity:SEVERITY" \
  [--label "purge"]  # add when purge: true
  --body "BODY"
```

Issue body:

```markdown
## Summary

TITLE

## Details

DETAILS

## Remediation

REMEDIATION
[> **History rewrite required.** Run `/purge-sensitive-data` to generate the rewrite script and GitHub Support case.]

## References

REFERENCES
```

The bracketed lines above are conditional: include them only when `purge: true`.

Print each created issue URL as it is created.

Completion criterion: one issue exists per confirmed finding.

---

## Severity Reference

> REFERENCE — consulted during Step 2. When in doubt, go higher.

| Severity | Assign when |
|----------|-------------|
| `critical` | Direct exploit path; credential/secret exposure; RCE; auth bypass |
| `high` | Significant risk with realistic attack path; data exposure; privilege escalation |
| `medium` | Exploitable under specific conditions; indirect risk; missing defense-in-depth |
| `low` | Minimal risk; hardening gap; no realistic exploit |
| `informational` | Best-practice gap only; no exploitability |
