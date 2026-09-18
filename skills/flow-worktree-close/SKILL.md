---
name: flow-worktree-close
description: Clean up a worktree and its branch after the PR merged. Verifies the merge landed on the project's default branch, stops processes running from the worktree, removes the worktree, and deletes the local (and leftover remote) branch. Use when the user says a worktree branch was merged and wants it closed, e.g. "merged, close the branch and worktree" or /flow-worktree-close.
---

# flow-worktree-close

Close out a merged worktree: verify, stop processes, remove worktree, delete branch.
Squash merges are common, so "is it merged?" is answered by content diff, never by
commit ancestry. That gate is correct under every merge strategy, so it is not
conditional on one.

`<default branch>` below is `git.default_branch` from this project's settings, read
the way `~/.flow-factory/settings-contract.md` says. Read it once, before step 1.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

## Identify the target

- If the session is inside a worktree (under `.claude/worktrees/`), that is the target.
- Otherwise resolve the argument against `git worktree list` to get the path and its
  checked-out branch (the branch may have been renamed; trust `git worktree list`,
  not the worktree directory name).

## Steps

1. **Verify the merge landed.** From the worktree:
   - `git fetch origin -p`
   - Diff **only the paths this branch changed**, in three separate commands. The
     guard refuses `$(...)`, so read each result and paste it into the next:

     ```bash
     git merge-base origin/<default branch> HEAD              # -> BASE
     git diff --name-only <BASE> HEAD                         # -> the changed paths
     git diff origin/<default branch> HEAD -- <those paths>   # must print nothing
     ```

   - No changed paths at all means the branch changed nothing versus the default
     branch. STOP: that is not a merge, and nothing gets deleted.
   - Empty output proves every file this branch touched is now identical on the
     default branch, which is what a squash merge leaves behind.
   - If it is non-empty: STOP. Show the diff and ask, nothing gets deleted.

   Do **not** gate on a bare `git diff origin/<default branch> HEAD`. That also
   reports commits which landed on the default branch after you branched, so it
   fails while your content is fully merged. A gate that cries wolf is worse than no
   gate: the next person forces past it out of habit and deletes a branch that
   really was unmerged.

2. **Stop processes running from the worktree.** A directory removal fails while a
   process is live inside it, whoever started that process:
   - Find them: `ps aux | grep "<worktree-path>"` and check listeners with
     `lsof -nP -iTCP -sTCP:LISTEN`.
   - Kill only PIDs whose command path or cwd is inside the target worktree.
   - Never touch processes from other worktrees; parallel sessions own those.

3. **Remove the worktree from outside it.** Never delete the directory the shell is
   standing in. The removal still succeeds and leaves the shell on a path that is
   gone, so `pwd` and every later git call fail with "Unable to read current
   working directory" and steps 4 and 5 cannot run. `git -C <main-checkout>` does
   not rescue that: the cwd is deleted either way.

   When this session created the worktree with `EnterWorktree({name})`,
   `ExitWorktree({action: "remove"})` does the whole step in one call. Refused as
   unmerged (squash) means re-invoking with `discard_changes: true`; refused on
   ownership means using git instead.

   Otherwise get the session out first, cheapest move first:
   - `ExitWorktree({action: "keep"})`. Either it returns the shell to wherever the
     session started, which is not guaranteed to be the main checkout, or it
     reports no active worktree session and changes nothing.
   - If that did not move you, one plain `cd <main-checkout>`. In a session Bash is
     isolating, this is refused, and so is the `cd` back until `EnterWorktree` runs
     again. A refusal deletes nothing.
   - Delegate before handing the job back. A subagent is not necessarily pinned to
     the parent's worktree, so spawn one and have it prove `cd <main-checkout>`
     runs before it touches anything. Give it the merge facts and tell it to verify
     each one rather than trust the brief: a wrong "its remote is already gone"
     is exactly what it will otherwise act on. Name the worktrees and branches it
     may not touch, because a shared checkout holds other sessions' work.
   - Only when the subagent is confined too: say this session cannot remove the
     worktree, and let the user run `/flow-worktree-close` from a main-checkout
     session.

   Confirm with `pwd` that the shell is outside the target, then
   `git -C <main-checkout> worktree remove <path>`, which works wherever the move
   landed. git refuses on a modified tracked file or on any untracked, non-ignored
   file, and names neither, so run `git status --porcelain` in the worktree first
   and show what it lists. Ignored files do not block it, so try without `--force`;
   `--force` only with step 1's justification. Removal never deletes the branch, so
   a commit that is not on the default branch survives into step 4's
   `git branch -d`, which is where that gate lives.

   Disposable: caches, build output, and the paths `flow-worktree-create` symlinked
   in, which are the ones its two manifests list. `.claude/settings.local.json` is a
   real copy, so diff it against the main checkout's first, once per worktree being
   removed. Each carries its own grants, and diffing only one loses the others. List and ask about any
   other untracked file.

4. **Clean up branches.** From the main checkout:
   - `git fetch origin -p`. Do not `git pull` without checking
     `git branch --show-current`: the shared checkout is often on another session's
     branch.
   - `git branch -d <branch>`; when it refuses with "not fully merged" (squash),
     use `-D`, again justified only by step 1.
   - `git ls-remote --heads origin <branch>`; GitHub usually auto-deletes on merge.
     If it still exists, confirm with the user before `git push origin --delete <branch>`.

5. **Report.** One or two lines: worktree removed, branch(es) deleted, and the merge
   commit still on the default branch per
   `git merge-base --is-ancestor <merge-commit> origin/<default branch>`. Do not
   report the default branch as being *at* that commit: parallel sessions merge too,
   so the tip has often moved on already. Read `origin/<default branch>`, never local
   `HEAD`, which in the shared checkout is usually behind.

## Hard rules

- The single gate for every destructive step is an empty
  `git diff origin/<default branch> HEAD -- <the paths this branch changed>`. No
  empty diff, no deletion. Never widen it to a bare
  `git diff origin/<default branch> HEAD`.
- Ask before deleting anything that holds content not on `origin/<default branch>`.
