---
name: flow-ship-issue
description: Ship a ready tracker ticket through implementation, verification, review, pull request preparation, and post-merge close-out.
disable-model-invocation: true
---

# /flow-ship-issue

Conduct the ticket-to-close-out pipeline by invoking the skills below. Sequence
them; do not reimplement them.

The run is complete when the tracker ticket reads `Status: done` and, where the
work produced a change to merge, that change is merged. A pull request URL is a
handoff, not completion. Removing the worktree and branch is not part of
completion: `/flow-close-out` leaves them in place unless there is a specific
reason to run `/flow-worktree-close`.

The file shapes, the status values and the heading spellings this skill reads
come from `~/.flow-factory/tracker-contract.md`. Project settings are read as
`~/.flow-factory/settings-contract.md` says. If either file is not readable, the
factory was never installed on this machine. Say so and stop.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

## Run contract

- Auto-advance every clean stage. The user can say "stop after each" to add gates.
- Stop only for a failure, a material decision, a delegated skill's required
  approval, the commit message approval in Stage 4, `git push`, or worktree
  deletion.
- Use ASD-STE100 Simplified Technical English. When `docs.context` is set, also
  use the ubiquitous language in that file.
- On each stage result, print one line:

  ```text
  🚢 <n>/8 | <STAGE> | <PASS|WAIT|STOP|DONE> - <result or next action>
  ```

- Keep detail inside failures and decisions. Use `AskUserQuestion` for a clean
  choice. Otherwise state only the blocker, needed response, and next automatic
  step. Give commands only for work the agent cannot perform.
- Print the Stage 8 receipt at final completion only. At a handoff or a stop the
  stage line above carries the state, so do not repeat it as a receipt.

## Stage 0 - Re-ground and claim

Resolve one tracker ticket from the argument or session.

Refuse a spec before anything else. A file named `PRD.md` is a spec, and so is
any file with no `Status:` line. Both stop the run and offer `/flow-to-tickets`.
The second test is the one that matters: without it a spec has no status, falls
into the triage row below, and gets sent to a skill that has no work to do on it.

Then read `Status:` and follow exactly:

| Status | Action |
|---|---|
| `ready-for-agent` | Make the first write: set `in-progress`, without asking. Write the `Session:` line where "Header lines" in `~/.flow-factory/tracker-contract.md` puts it, holding the value of `$CLAUDE_CODE_SESSION_ID` (run `echo $CLAUDE_CODE_SESSION_ID` to get it). |
| `needs-triage`, `needs-info`, `backlog`, `blocked` | Invoke `/flow-triage`; if it returns `ready-for-agent`, claim it the same way and continue. |
| `in-triage`, `in-progress`, `in-review`, `done` | Stop; another session owns it or it shipped. |
| `ready-for-human`, `wontfix` | Stop; reversal belongs to the user. |
| anything else | Stop and ask what it means. |

Claim before re-grounding so parallel dispatch cannot start the same ticket.
An abandoned early claim intentionally blocks duplicate work.

The `Session:` line is transient and records which session holds the claim, so
a person inspecting a stuck `in-progress` file can tell an abandoned run from a
live one. `/flow-conductor` does not read it; `Status:` alone stops a second
dispatch. Remove it whenever the status leaves `in-progress`: at the Stage 6
flip to `in-review`, and at any stop that puts the status back. A file at rest
never carries it. Its position, and every other header line, is under "Header
lines" in `~/.flow-factory/tracker-contract.md`.

Invoke `/flow-reground`. Continue after a clean result or an approved mechanical
patch. On substantive staleness, stop and propose changing `Status:` to
`needs-triage`; do not apply that change without approval.

## Stage 1 - Isolate

Invoke `/flow-worktree-create`. With `Branch base:` off the default branch,
or no `## Depends on`, name no base; it resolves the default branch from this
project's settings. Off ticket N's branch, resolve that branch from the pull
request URL in N's `## Comments`:

```bash
gh pr view <url> --json headRefName,state
```

Pass `headRefName` as the base when `state` is `OPEN`. `MERGED` means it has
landed already: use the default branch and say so in the stage line. `CLOSED`
stops the run: the base was rejected.

Then call `EnterWorktree` with the new path. Verify
`git rev-parse --show-toplevel` equals that path. A mismatch stops the run; never
review or build from the original checkout. On a stacked base, run the ticket's
`Check before starting:` command here; a wrong output stops the run.

## Stage 2 - Build

Read `test.command` from this project's settings. Unset, it stops the run: name
the key and stop. A guessed test command reports a pass for a run that never
happened, and Stage 3 rests on the same key.

When `test.guide_path` is set, read that file before the handoff. It decides test
type, placement, markers, and test data, which `/flow-tdd` is generic about and
cannot know for this project. When `source.backend_dir` is set, the guide governs
work under that directory.

Print the implementation approach and test seams in one short clause, then
invoke `/flow-tdd` immediately. Run targeted tests and typechecks while building
and the full suite once at the end, all through `test.command`.

Stop only for an ambiguous requirement, unexpected architecture seam, scope
expansion, or failure. Otherwise continue directly to verification.

## Stage 3 - Verify

This stage does the checking itself. It calls no other skill.

**The criteria come from the ticket.** Match the heading `## Acceptance` and take
the checkbox lines under it. That is the whole input. Never add a criterion the
ticket does not carry: an invented criterion is the failure that looks most like
thoroughness, because it reads as care while it moves the bar the ticket set.

**Count before checking.** Count the checkboxes and print the count. Every one
gets exactly one verdict, so the number of verdicts equals that count. Reconcile
the two before the stage line. A criterion that quietly leaves the list is the
way this stage passes work nobody checked.

**How to check each one.** Read `## How to verify` by heading match.

- Commands written there: run them, and read the output against what the section
  says a pass looks like.
- The section empty or absent: check the acceptance criteria directly, using the
  commands the criteria themselves carry.

There is no third route. Do not search the file for a sentence that names a
route, and do not treat silence as a request for anything more than the criteria.

**One command, one piece of evidence.** Each criterion gets a command, and the
command and its output are kept as that criterion's evidence. A verdict without
the output in hand is a claim, not a check. Where a criterion needs the test
suite, the command is `test.command`.

**Three verdicts, and only three.**

- **Pass.** The command ran and its output means what the criterion asked for.
- **Fail.** The command ran and its output does not.
- **Needs a person.** No command can settle it, for example that a printed
  message reads clearly to a reader. Name the criterion, say what a person has to
  look at, and stop for that answer. Do not skip it and do not give it an
  invented command that checks something easier.

**A failure stops the run.** Report it with the command and the output that
produced it. Do not edit the code or the ticket to make a criterion pass: a
criterion the run rewrote is a criterion nobody met.

The stage advances to Stage 4 only when every criterion passed. Anything else is
a stop or a handoff, and the run is not verified.

## Stage 4 - Review and commit

1. Invoke `/code-review`. It is Claude Code's built-in review skill, not one
   the factory ships; if it is unavailable, stop the stage and name it rather
   than reviewing from memory. Give it an explicit effort:
   - `low` for an ordinary diff.
   - `high` for test-only changes, correctness-critical calculation, parsing of
     documents from outside the project, or a change crossing two parts of the
     stack.
   Never drop a returned finding because today's data masks it. A statement that
   the input which would trigger the defect never occurs describes the present,
   and a defect that only fires on a future input is still a defect. Test it
   under the input that triggers it, then judge.
2. Apply high-confidence, behavior-preserving fixes automatically. Re-run the
   affected checks and the review until clean.
3. Batch and ask about findings that are ambiguous, behavioral, risky, or
   scope-expanding. Stop only for those decisions.
4. Invoke `/flow-comments-review` against the uncommitted working tree, once the
   code is settled. Running it here and not earlier is deliberate: a code-review
   fix writes and rewords comments, and it changes which code the diff touches,
   so a comment pass before it judges text that is about to move.
5. Confirm the diff covers what it changed. When it changes a non-test source
   file, confirm it also adds or changes a test. A fix for a reported defect
   needs the test that reproduces it. If the diff has neither, name the untested
   change and ask before committing.
   The gate is about source files. A diff that changes only documentation,
   configuration or generated files, or a ticket whose provenance line says
   docs only, has no test to add: say so in the stage line and continue.
   When `source.backend_dir` is set, this gate applies to changes under that
   directory. Unset, the project is one tree and the gate applies to every
   non-test file the diff changes. When `test.dir` is set, a new test file lands
   there.
6. Commit after both reviews are clean. Tool attribution follows
   `~/.flow-factory/attribution-rule.md`; that rule governs this write point and
   is not restated here. The message is the subject line alone, with no body: the
   reasoning belongs in the tracker ticket, the pull request description, and
   the hosted issue when one exists, and repeating it in the commit only ages
   another copy.
   When you present the message for approval, open with it in a code block; put
   any status or file list after it, never as a lead-in before it.

A read-only review's internal stop returns its findings to this conductor. It is
a user handoff only when a finding needs the decision in step 3.

One case runs backwards: a comment rewrite that removes a suppression or makes
code unused is a code change, so test it and put it through `/code-review` again.
This is rarer than the loop the order above removes, so pay it when it happens
rather than reviewing twice by default.

After the commit, identify ticket-required files absent from it, and name any
file under `.flow/` among them. Whether a project tracks its tracker in git is
the project's choice and the factory does not settle it, so a tracker edit is
reported either way rather than assumed to be outside the commit.

## Stage 5 - Prepare the pull request

When the work produced nothing to commit, this stage and Stage 6 have no work.
Say which, and go to Stage 7.

Whether a hosted issue is opened is `github.create_issue` in this project's
settings. When it is false, the tracker ticket and the pull request carry the
reasoning: open no issue and go straight to `/flow-pr-summary`, with no
`Closes #<n>`.

When it is true, create a hosted issue by default. Skip it only when the change
is clearly mechanical and has no behavior or design rationale to preserve, such
as a typo, format-only edit, or generated-file refresh. If uncertain, create the
issue. Invoke `/flow-new-issue` without first asking whether an issue is wanted.
Its creation approval still applies. Draft from the tracker problem statement,
not the diff, and make the body readable by someone who has only the hosted
repository. Write the reasoning out. Do not point at a path under `.flow/` or at
a decision-record identifier and leave the reader to find it.

Then invoke `/flow-pr-summary`. Include `Closes #<n>` when a hosted issue exists.
Treat the summary as editable user text: only flag facts that are wrong, not
sections the user shortens or removes. Let it draft and write the body file, but
leave the clipboard copy to Stage 6, so it lands after the push and a copied pull
request URL cannot clobber it.

## Stage 6 - Push and pull request handoff

Ask once before `git push`. Push after approval and show the returned pull
request URL. Do not copy the body to the clipboard on your own: copying replaces
whatever the user is holding, so it stays their call. Stop with the stage line,
the URL, and the numbered options as the whole output.

Who opens the pull request is `pr.create_mode` in this project's settings. Under
`manual` the user opens it and this skill never runs a command that creates one.
Under `gh` the skill may run `gh pr create` after the same single approval.
Under both, `gh` has to be installed: the resume check below reads the pull
request through it.

Lead the options with the copy step: option 1 offers to copy the body file
`/flow-pr-summary` wrote to the clipboard, ready to paste as the description.
Run `pbcopy < <body file>` (confirm with `pbpaste | wc -c`) only when the user
selects it, never before, and offer the option only when `command -v pbcopy`
succeeds. `pbcopy` is macOS only and copies a file the user can already open,
so where there is none, lead with the body file's path instead.

The tracker flip happens as soon as a pull request exists, without asking, the
same way Stage 0 claims without asking: set `Status: in-review`, remove the
`Session:` line, and append the pull request URL, plus the hosted issue URL when
one exists, under `## Comments`. Under `gh` that is right after `gh pr create`
returns. Under `manual` it is on resume, once the check below shows the pull
request.

On resume, verify with:

```text
gh pr view <branch> --json url,state
```

If the pull request exists and the ticket still reads `in-progress`, make that
flip now. If none exists, report that and wait.

## Stage 7 - Close out after merge

Resume from the tracker status and the recorded pull request URL. Invoke
`/flow-close-out`; it owns merge verification, rejected-pull-request handling,
and whether `/flow-worktree-close` runs at all. It also owns the tracker update,
and the Jira text when `jira.enabled` is true. Do not duplicate those rules here.

## Stage 8 - Closing the turn

Print this once the tracker reads `Status: done` and, where there was a change to
merge, the pull request reports `MERGED` with a merge commit. Work that produced
no merge at all reaches this receipt on `Status: done` alone. The worktree and
branch staying on disk does not hold the receipt back; they are removed only when
`/flow-close-out` had a specific reason to run `/flow-worktree-close`. Until the
end state lands, the stage line is the whole output.

Use observed values only. Report this ticket's slice only. Never repeat a URL or
path the prose above already gave; the receipt carries state, not addresses.

```text
🚢 DONE
Merge: <merged state and merge commit, or "no change to merge">
Outside the change: <ticket-required files not committed, or none>
```

```text
✅ Done - the ticket is shipped and closed out.
```

Then at most three lines, one line each, no sub-points. A line earns its place
only if it changes the user's picture: the ticket was wrong about something, or
the build found something that changes what happens next. The suite counts, the
verification result, and the decisions the user just made are already in the
tracker file and are not repeated here.
