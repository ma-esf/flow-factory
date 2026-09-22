---
name: flow-worktree-create
description: Create a new git worktree and branch for a parallel agent session, then mirror the repo's git-excluded agent context (project rules, skills, tracker, settings) and the project memory into it via symlinks so the worktree session has the same rules, skills, docs and memory as the main checkout. Bases on the project's default branch by default, or on a branch the user or the calling skill names when stacking on an open PR. Use when the user says "new worktree", "create a worktree", "spin up a worktree", "stack a branch on", or /flow-worktree-create.
---

# flow-worktree-create

Prepare a worktree for a *separate* parallel session: create it, base it on the
latest default branch, and symlink in the git-excluded context that a fresh
worktree would otherwise lack. Worktrees only check out tracked files, so anything
gitignored or in `.git/info/exclude` (rules, repo skills, issue tracker, context
docs) is missing until linked.

This does **not** enter the worktree. The point is to stage it for another agent
session whose cwd will be the worktree root. Pairs with `flow-worktree-close`.

## What gets mirrored

The list lives outside this skill, in two files read in this order:

1. `~/.flow-factory/worktree-share.txt`, the machine defaults, installed once per
   machine and serving every project.
2. `<main>/flow-worktree-share.txt`, this project's own additions. Optional: a
   project with no extra paths does not have the file, and that is the normal
   state, not an error.

Both use one repo-relative path per line (`#` comments and blanks ignored).
Folders link as folders (files added inside them stay covered); files link as
files.

If `~/.flow-factory/worktree-share.txt` is not readable, the factory was never
installed on this machine. Say so and stop. Do not create the worktree and link
nothing: a worktree with no rules, no skills and no tracker is the exact failure
this manifest exists to prevent, and it looks like a success.

Check first that this project has a `flow-factory.toml` at its root. If it does
not, stop as `~/.flow-factory/settings-contract.md` says.

The machine list is linked before any project line is judged. That order is
load-bearing, not cosmetic, and for a worse reason than the refusal below.
Measured: with a project entry `.cortex/foo` read first, `mkdir -p` creates a
**real** `.cortex` directory in the worktree, `.cortex` itself is then skipped
as existing, and the worktree ends up with no tracker at all while every line
reports success. Machine first is what prevents that.

Project memory is linked separately, because it lives outside the repo:
`~/.claude/projects/<key>/memory/`, where `<key>` is the absolute checkout path
with every `/` and `.` turned into `-`. A worktree has its own key and so, by
default, no memory at all.

## Steps

1. **Get the branch name.** The user supplies it, or you propose one. It must
   carry a type prefix from `branch.prefixes` in this project's settings, read the
   way `~/.flow-factory/settings-contract.md` says. After the prefix comes a
   reader-POV description (the observable effect, not the files touched), with a
   ticket id if there is one, e.g. `feat/feedback-record-status`,
   `fix/dropped-income-rows`. This matches the repo's existing branches; if unsure,
   run `git branch -r` and follow the pattern there. A bare, prefixless name is
   wrong: add the prefix before creating. The worktree directory name is the
   whole branch with every `/` turned into `-`, so `feat/foo` and `fix/foo` get
   different directories.

2. **Create and link.** Fill in the first two lines before running any of it:
   an unsubstituted `BASE` assigns without error and only fails three lines
   later, naming a ref nobody typed. Run from anywhere inside the repo:

   ```bash
   BRANCH="feat/foo"                     # <- the branch the user gave
   BASE="origin/<default branch>"        # <- origin/ + git.default_branch from
                                         #    this project's settings, unless the
                                         #    user or the calling skill named a
                                         #    base, then origin/<that branch>
   MAIN="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
   NAME="${BRANCH//\//-}"
   WT="$MAIN/.claude/worktrees/$NAME"

   git -C "$MAIN" fetch origin -p
   git -C "$MAIN" worktree add "$WT" -b "$BRANCH" "$BASE"

   # Local permission layer: the harness copies this when IT makes a worktree;
   # a raw `git worktree add` does not, so carry it over (a copy, not a symlink,
   # because it is the per-worktree local layer).
   if [ -f "$MAIN/.claude/settings.local.json" ]; then
     mkdir -p "$WT/.claude"
     cp "$MAIN/.claude/settings.local.json" "$WT/.claude/settings.local.json"
   fi

   # Mirror the shared, git-excluded context via absolute symlinks. Machine list
   # first, project list second; see "What gets mirrored" for why that order is
   # load-bearing.
   # Input redirection (not a pipe) keeps the loop in the current shell;
   # default-IFS `read` trims surrounding whitespace, so no external trim is
   # needed. Only full-line `#` comments and blank lines are skipped.
   # Loop var is `rel`, NOT `path`: in zsh `path` is tied to $PATH, so
   # `read path` wipes PATH and every command in the loop stops resolving.
   # `|| [ -n "$rel" ]` catches a final line with no trailing newline, which
   # plain `read` drops silently. `${rel%/}` strips a trailing slash, which
   # would make `ln -s` try to link *into* the target and fail.
   for LIST in "$HOME/.flow-factory/worktree-share.txt" "$MAIN/flow-worktree-share.txt"; do
     [ -f "$LIST" ] || continue
     while read -r rel || [ -n "$rel" ]; do
       [ -z "$rel" ] && continue
       case "$rel" in \#*) continue ;; esac
       rel="${rel%/}"
       src="$MAIN/$rel"; dest="$WT/$rel"
       if [ ! -e "$src" ]; then echo "skip (missing in main): $rel"; continue; fi
       # Refuse a path nested under one already linked as a folder. Through
       # that link the destination IS the source, so the entry can only ever
       # print `skip (exists)` or `skip (missing in main)`. Measured, not
       # assumed. Naming it `refused` is the point: a silent skip reads as a
       # link that worked.
       d="$(dirname "$dest")"; nested=""
       while [ "$d" != "$WT" ] && [ "$d" != "/" ]; do
         if [ -L "$d" ]; then nested="$d"; break; fi
         d="$(dirname "$d")"
       done
       if [ -n "$nested" ]; then echo "refused (nests under a linked path): $rel"; continue; fi
       if [ -e "$dest" ] || [ -L "$dest" ]; then echo "skip (exists): $rel"; continue; fi
       mkdir -p "$(dirname "$dest")"
       ln -s "$src" "$dest" && echo "linked: $rel"
     done < "$LIST"
   done

   # Project memory: link the worktree's memory folder to the main checkout's.
   # The main key is required to exist, so a wrong key rule shows up here as a
   # skip instead of as a session that silently starts without memory.
   PROJECTS="$HOME/.claude/projects"
   MAIN_KEY="$(printf '%s' "$MAIN" | sed 's#[/.]#-#g')"
   WT_KEY="$(printf '%s' "$WT" | sed 's#[/.]#-#g')"
   if [ ! -d "$PROJECTS/$MAIN_KEY/memory" ]; then
     echo "skip (no memory folder for main key $MAIN_KEY)"
   elif [ -e "$PROJECTS/$WT_KEY/memory" ] || [ -L "$PROJECTS/$WT_KEY/memory" ]; then
     echo "skip (exists): project memory"
   else
     mkdir -p "$PROJECTS/$WT_KEY"
     ln -s "$PROJECTS/$MAIN_KEY/memory" "$PROJECTS/$WT_KEY/memory" && echo "linked: project memory"
   fi
   ```

3. **Report.** One or two lines: the worktree path, the branch and what it is
   based on, and the list of linked paths. Name the base explicitly when it is not
   the default branch's remote-tracking ref, so a stacked branch is never mistaken
   for a fresh one. Report any `refused` line too: that path was not linked and the
   project file needs fixing. Tell the user to start their parallel session with
   cwd set to `$WT`.

## Stacking on another branch

The default base is the default branch's remote-tracking ref and stays that way
unless the user names a different one. Stacking is for work that genuinely builds
on an open, unmerged PR: set `BASE` to that branch, and the new PR targets it
rather than the default branch.

Two things to say out loud when you do it, because both bite later:

- The stacked PR's base is the parent branch, not the default branch. Most GitHub
  instances retarget it to the default branch when the parent merges, but confirm
  that on the first stack in a given repo rather than assume it.
- If the parent branch gets review changes, this branch needs a rebase. That is
  the cost of stacking, and it is worth paying only when the work is genuinely
  blocked on the parent.

Never infer a base from the branch the main checkout happens to be on. The user
names it, or it is the default branch's remote-tracking ref.

## Hard rules

- Base new branches on the default branch's remote-tracking ref (after fetch)
  unless the user explicitly named a different base. Never infer one from whatever
  branch the main checkout happens to be sitting on.
- Symlinks are **absolute** and point back into the main checkout, so `.cortex`
  (the issue tracker) is one shared source across all worktrees, not a fork.
- Writing through those symlinks gets blocked, always from a background session and
  often from a live one. It is a harness guard, so never weaken it with
  `worktree.bgIsolation: "none"`: that drops write isolation for the whole repo, and
  the blocked session cannot apply it anyway. Fall back to Bash as one single
  command. A compound command is refused, and a `cd` into the main checkout locks
  Bash out until `EnterWorktree` runs again.
- Never clobber: if a path already exists in the worktree, skip it and say so.
- The memory link points at the main checkout's real memory folder. Never
  `rm -rf` a worktree's memory path with a trailing slash; that follows the
  link and deletes the shared memory. Remove the link itself, or leave it.
- This skill creates and stages only. It does not enter, build, or run anything.
