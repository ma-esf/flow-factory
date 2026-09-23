---
name: flow-close-out
description: "Close out a merged PR: confirm the merge landed and flip the ticket to done; remove the worktree and branch only when there's a reason to. Use when the user says a PR merged, says \"it's merged\", names a merged PR number, asks to close out or clean up after a merge, or invokes /flow-close-out."
---

# flow-close-out

The post-merge sequence, in one place. Run the headings below in order.
`/flow-ship-ticket` Stage 7 calls this, and so can you, directly, for a branch that
never went through that pipeline. Called from Stage 7, that skill's talk rule and
hand-back forms still apply.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

`<default branch>` below is `git.default_branch` from this project's settings.
Read it, `pr.create_mode` and `jira.enabled` the way
`~/.flow-factory/settings-contract.md` says, before the first heading. Read
`jira.enabled` on every run, not once at install: one machine's skills serve every
project, so the same machine holds a Jira project and a non-Jira one at the same
time, and a gate settled at install would answer for the wrong one. Never infer it
from whether `/flow-jira-subtask` is on disk.

The sequence ends at the `done` flip, and the worktree and branch stay. When
`jira.enabled` is true it ends one step later, at the Jira offer. Offer
`/flow-worktree-close` only on a specific reason (see the last heading). When both
run, Jira comes first: `/flow-worktree-close` and the receipt read as "run
finished", so an offer made after them gets waved off, and the work reaches Jira
never.

A merge with no ticket and no worktree (a Dependabot bump, someone else's
PR) needs the two merge checks only. Say what you skipped and why.

## Confirm the merge is real

"It's merged" is a claim, not a state.

```bash
gh pr view <n> --json state,mergedAt,mergeCommit,baseRefName,headRefName
```

`state: MERGED` plus a `mergeCommit` is the proof. The local check beside it asks
two questions in order, the pair `/flow-worktree-close` asks. No
`github.merge_strategy` read: neither question answers every strategy on its own,
asking both costs one command, and whether work landed should not rest on a
project having answered that key correctly.

`HEAD` in the commands below is the branch the pull request shipped, which holds
when the session stands in that branch's worktree. For a merge with no local
branch, someone else's PR or a dependency bump, take `headRefName` from the
reading above, `git fetch origin <headRefName>`, and run both checks against
`origin/<headRefName>` in place of `HEAD`. When that branch is already deleted
on the remote, the `gh pr view` reading is the only proof: say so in the report.
Do not run the checks against whatever `HEAD` happens to be, which proves
something about an unrelated branch.

**Ancestry**, which answers a merge commit:

```bash
git merge-base --is-ancestor HEAD origin/<default branch>
```

Exit 0 means every commit on this branch is already in the default branch's
history. That is the answer; go on to the next heading. A branch that never
diverged passes here too. This pair does not catch it; what keeps it out is the
`gh pr view` reading above, which a branch with no merged PR fails.

**Content**, which answers a squash or rebase merge. A non-zero exit above proves
nothing: those strategies rewrite the commits, so landed work is never an
ancestor. Diff only the paths this branch changed, in three separate commands,
reading each result and pasting it into the next:

```bash
git merge-base origin/<default branch> HEAD              # -> BASE
git diff --name-only <BASE> HEAD                         # -> the changed paths
git diff origin/<default branch> HEAD -- <those paths>   # must print nothing
```

- Empty output proves every file this branch touched is now identical on the
  default branch, which is what a squash merge leaves behind.
- Non-empty: STOP. Show the diff and ask. Nothing is flipped to `done`.
- No changed paths at all, having reached this question, means the branch's own
  commits cancel out. STOP: there is nothing to prove landed.

Never run the third command with nothing after the `--`. That widens it to a bare
`git diff origin/<default branch> HEAD`, which prints nothing and exits 0 whenever
the branch's content matches the default branch, so a branch that shipped nothing
reads exactly like a merge commit. It also reports commits that landed on the
default branch after you branched, and so fails while your own content is merged.

On `CLOSED` with no `mergeCommit` the PR was rejected. Delete nothing and say
so. Set the ticket to `needs-triage`, remove any `Session:` line, and
append a dated comment under `## Comments` opening
`Rejected: PR <url> closed unmerged.`, in that spelling: `/flow-triage` Step 0
matches it. A rejection needs a decision, not a close-out, and `/flow-triage`
is where that decision is made; the comment is what it reads.

## Confirm the content reached the default branch

`MERGED` describes the PR, not the branch's files. Read one file the branch
changed straight off the remote:

```bash
git fetch origin <default branch> -q
git show origin/<default branch>:<a path the branch changed>
```

A spot check is enough here: the close-out deletes nothing by default, and if
`/flow-worktree-close` is run later it reruns the exhaustive gate before it touches
anything. The `done` flip reports the work as finished, so it comes first.

## Check the GitHub issue closed itself

Only when a GitHub issue exists, which the ticket's `## Comments` records. A
project with `github.create_issue` false opens none, so skip this heading and
say nothing about it. When one exists, `Closes #<n>` in the PR body should have
closed it on merge:

```bash
gh issue view <n> --json state,stateReason
```

`CLOSED` with `COMPLETED` also proves the keyword survived into the body a user
pasted by hand, which is a possible failure only when `pr.create_mode` is
`manual`; under `gh` the body reached GitHub as the skill wrote it. Still
`OPEN` means the keyword did not arrive, so close the GitHub issue directly and
say why.

## Flip the ticket to `done`

The merge checks above are the proof the work landed, and merging was the user's
own decision to complete it, so flip the ticket to `done` without asking. Also
remove the `Session:` line if present.

`~/.flow-factory/tracker-contract.md` says `done` means any branch or worktree the
work created is dealt with, and the recorded decision below to leave them on disk
is how they are dealt with, so the flip never waits on a cleanup that may never
happen.

## Offer `/flow-jira-subtask`

Only when `jira.enabled` is true. Single-ticket mode, on the ticket just closed
out. When it is false this project has no Jira: skip this heading, say nothing
about Jira, and the sequence ends at the flip above.

## Stop here by default; `/flow-worktree-close` only on a specific reason

The close-out ends at the last heading that ran. Leave the worktree and branch on
disk: a merged branch costs nothing there, and the work often continues in the
worktree. Do not prompt `/flow-worktree-close`.

Offer it only for a specific reason: the user asks to clean up, worktree or disk
clutter is a stated problem, or a follow-up needs the worktree gone. When it
does run, `/flow-worktree-close` is a hard stop, never an auto-advance, and it owns
its own merge gate and the rest of its cleanup.

## Report what you observed

Put the checked value in every line, never the intended one.

Called from `/flow-ship-ticket`, the run ends at its Stage 8 table, not here. This
heading is that stage's input, so hand back and let it render the table.
