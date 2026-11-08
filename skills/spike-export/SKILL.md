---
name: spike-export
description: Review this project as a throwaway spike and write SPIKE.md, a findings handoff that seeds a new project without carrying the spike's implementation.
disable-model-invocation: true
---

# Spike export

Write `SPIKE.md` at the repo root: what this spike **learned** and **delivered**, for an agent that will build a new project from scratch and never sees this code. The spike is thrown away; its knowledge is kept. Keep it to one or two pages, in prose and tables.

## The filter

Run every candidate sentence through four tests. It enters `SPIKE.md` only when it passes the first three and fails the fourth.

- **Rewrite**: would it stay true if the spike were rewritten in another language and framework?
- **Cause**: does its cause sit outside our code (a vendor, protocol, hardware, user, regulation)?
- **Choice**: does the new agent need it to *choose* a design, not to *reproduce* one?
- **Code-readable**: can the new agent derive it from this code? Then a pointer to the code suffices.

A measured number is a fact (the API caps at 5 requests/s). A tuned value is implementation (a 250 ms backoff).

| Keep | Drop |
|---|---|
| "Vendor API returns stale data for about 30 s after writes" | The retry class and its constants |
| "Polling over webhooks: webhooks need a public endpoint the target network lacks" | Module layout, function names, config schema |
| "Parsing fails on files over 2 GB; split first" | The parsing snippet |
| "Operator drops a file and sees the report within 10 s" | The script that runs the demo |

## 1. Survey the spike

Read the repo, its README, git log, tests and logs. List the **delivered features**: behaviours a human can observe working today, not planned or half-built ones. Done when each feature is traced to something you ran or read, and each one carries an observation date and environment.

## 2. Interview the human

Ask one question at a time, recommended answer first, for what the repo cannot tell you: the question the spike set out to answer, the verdict, the decisions made and options rejected, what cost time, and what stayed untested. Skip what the survey already answers. Done when each section below has its facts, or the human has said there are none.

## 3. Write SPIKE.md

Write these sections in order. Each states behaviour, facts and reasons.

1. **Question and verdict**: the one falsifiable sentence the spike tested; proved, disproved or partial.
2. **Delivered features**: one row per feature: what an operator does, what they see, and the observation date and environment.
3. **Facts learned**: constraints of the problem, environment and external systems that hold regardless of implementation.
4. **Decisions**: context, decision and consequence, with one line per rejected option and why.
5. **Gotchas**: what cost time or contradicted expectation.
6. **Open unknowns**: what the spike left untested, kept apart so a guess never reads as a fact.
7. **Shortcuts**: the corners cut on purpose (barest tests, minimal logging, hardcoded values), each marked as a spike expedient the new project replaces with its own standard.
8. **Acceptance scenarios**: one behavioural scenario per delivered feature, stated without implementation, as pass/fail checks the new project's first feature list can adopt.
9. **Pointers**: the spike's archived repo or tag, plus any logs or recordings, marked reference only. Pin to a tag or commit.

Done when every delivered feature appears in sections 2 and 8, and every sentence has passed the filter.

## 4. Audit

Reread `SPIKE.md` for leaks: code blocks, file paths, class and function names, config keys and tuned constants. Rewrite each as the behaviour or fact it stood for, or delete it. Done when none remain. Then show the human the file and apply their edits.

Report the path. The next step is the new project's first session, which reads `SPIKE.md` at start; the project's `CLAUDE.md` names the file and does not copy it.
