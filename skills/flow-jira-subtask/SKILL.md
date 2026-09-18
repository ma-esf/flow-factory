---
name: flow-jira-subtask
description: Turn a local tracker issue that just shipped, or a feature folder's already-done issues, into paste-ready Jira sub-tasks — an action-verb title, an Implement bullet, verifiable Done when bullets, and a GitHub link. Use right after a PR merges, when closing out a feature at a sprint boundary, or whenever the user says "add this to Jira," "list these as sub-tasks," "turn these into Jira items," or invokes /flow-jira-subtask.
---

# flow-jira-subtask

Local work (issue files, PRs, GitHub issues) never reaches Jira on its own. This
skill is the one-way bridge: read what already shipped, write Jira-ready text. It
never touches Jira itself — there is no API access — so the output is always a
block the user copies by hand.

Before anything else, read `jira.enabled` in this project's settings, as
`~/.flow-factory/settings-contract.md` says. When it is false, this project has no
Jira: say that `jira.enabled` is false, print no block, and stop. Read it on every
run, not once at install. One machine's skills serve every project, so the same
machine holds a Jira project and a non-Jira one at the same time, and a gate
settled at install would answer for the wrong one.

Two modes. Ask which one if it isn't obvious from what the user just said.

## Mode: single issue

Use right after one PR merges. `/flow-close-out` owns where this sits in the
post-merge sequence.

1. Resolve the issue file: the one just shipped, from session context, or ask
   for the feature and number.
2. If its `Status:` line isn't `done` (`~/.flow-factory/tracker-contract.md` pins
   that value, lowercase), ask before continuing — this skill reports
   finished work, it doesn't decide when something is finished.
3. If it already carries a `Jira:` marker (see below), say so and ask whether to
   regenerate anyway before doing it again.
4. Extract and print one block (format below), as the turn's one ask. Do not bury
   it above an unrelated question, and do not report the run finished while the
   paste is still outstanding.
5. Ask whether it is now in Jira, as a numbered choice the user can answer with a
   number (`1. In Jira now` / `2. Not yet`). Only on the "In Jira now" answer, add
   the marker (below) to the issue file. Printing a block is not reporting it, and
   a premature marker hides the issue from every future batch run.

## Mode: batch

Use when closing out a feature folder at a sprint boundary — a group of
already-done issues that need to become sub-tasks together.

1. Resolve the feature slug (from context, or ask).
2. Scan `.flow/issues/<feature>/*.md` (skip `PRD.md`) for `Status: done`
   files with no `Jira:` marker. If none, say so and stop.
3. Extract and print one block per file (format below).
4. Ask "Mark these N as reported?" as a numbered choice (`1. Yes, mark all N` /
   `2. Not yet`). On the "Yes" answer, add the marker to each.

This mode only lists already-done work. Drafting a new issue for what's still
open is a separate conversation, not something this skill does.

## Extracting a block

Each block is:

```
Title:
<action verb> <specific outcome>

Description:

Implement:
- <what the work changed or delivered>

Done when:
- <objectively verifiable condition>
- <second condition, only when the first does not cover it>

Link: <url>
```

Keep those labels exactly as shown. The user pastes the block into Jira without
editing it, so a renamed or reordered label costs them a hand edit every time.

Every field is written for the **Jira-only reader**: someone who runs the sprint
board and never opens this repo. Two kinds of wording fail that reader.
Identifiers that resolve only in these docs: an ADR number, a PRD reference, a
slice id. And engineer vocabulary: test-type names (unit, component, contract),
protocol acronyms (SSE, ASGI), mechanism words (framing, fixtures, seams). Name
the product surface and what the work buys ("a signed-in user stays signed in when the
page reloads, and a break fails the build"), not the mechanism that produced it
("session-refresh tests, split into unit and contract"). The link carries the
detail for whoever wants it.

- **Title** starts from the file's H1 and keeps it only when the H1 already reads
  as an action. Lead with a verb. The board shows the title and nothing else, so
  an H1 that names a test type or a protocol gets rewritten into the outcome.
  Ten words or fewer.
- **Implement** is one bullet on what the work changed or delivered, in
  ASD-STE100 Simplified Technical English: short words, one idea, active voice.
  Draw it from the file's Goal, not its Problem section — the problem is why the
  work existed, not what shipped. Two bullets only when the slice genuinely
  delivered two separable things.
- **Done when** is one bullet per condition a reader can check without opening
  the repo. Take them from the file's acceptance criteria, rewritten as outcomes
  rather than in the criteria's own wording. Drop any criterion only a developer
  can verify, such as a falsification run or a suite count. Two bullets is the
  usual count; needing more than three means the slice was too big for one
  sub-task, so say that instead of padding the list.
- **Link**, in priority order: a GitHub issue the file says this closed, a
  GitHub issue it references, or the merged PR. If none of those exist (a
  docs-only or audit slice can ship with no code diff), omit the line and say
  so rather than guessing.

Include nothing else. No background, no estimates, no assignees, and no
implementation detail unless a `Done when` bullet cannot be checked without it.

One blank line between blocks.

## The `Jira:` marker

A one-line marker, added right after the `Status:` line: `Jira: reported
<YYYY-MM-DD>`. Its only job is to stop batch mode re-listing something already
copied into Jira. Without it, every batch run would repeat every prior run's
output.

## Hard rules

- Redact when the project says to. When `privacy.redact_client_data` is true in
  this project's settings, read as `~/.flow-factory/settings-contract.md` says,
  strip any real company name and any real figure a file's Goal or Comments
  section carries before printing. The key defaults to true and this text leaves
  the repository, so the default is the safe one.
- Never invent a link. An issue with no GitHub reference gets no `Link:` line,
  not a guessed one.
- Every `Done when` bullet must be objectively verifiable. If you cannot say how
  a reader would check it, it is a restatement of the title and belongs nowhere.
