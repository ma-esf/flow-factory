---
name: flow-status
description: Session and git status snapshot. Reads session history and live git state to report what we've been working on, current worktree, branch, commits made this session, uncommitted changes, branch delta against the project's default branch, 3 next-step options, and one line when the Flow Factory checkout is behind its origin. Use when user types /flow-status or asks "what's our status", "where are we", "what have we done".
---

# flow-status - Session Status

When invoked, resolve the base ref and refresh remote state FIRST, then run the git commands below, read the conversation history, then produce the report. All comparisons in the report use `$BASE` (the freshly fetched remote tip), not the local branch of the same name, because the local one may be stale or absent.

## Step 0 - Resolve the base ref and refresh remote state (must run first, and must SUCCEED)

`$BASE` is `origin/` followed by the `git.default_branch` key in this project's settings, read as `~/.flow-factory/settings-contract.md` says. Never write a branch name into this skill: in a repository whose default branch is `master` the guessed remote ref does not exist, every comparison below compares against nothing, and the report prints anyway.

If `~/.flow-factory/settings-contract.md` is not readable, the factory was never installed on this machine. Say so and stop.

Check first that this project has a `flow-factory.toml` at its root. If it does not, stop as `~/.flow-factory/settings-contract.md` says.

```bash
BASE="origin/<the git.default_branch value>"

# Updates all remotes/<name>/* refs and prunes branches deleted on the server.
# Does not modify any local branch or working tree.
git fetch --all --prune && echo "FETCH_OK" || echo "FETCH_FAILED"
# --all succeeds with no remote at all, so FETCH_OK alone does not prove $BASE exists.
git rev-parse --verify -q "$BASE" >/dev/null && echo "BASE_OK" || echo "BASE_MISSING"
# Always show when we last actually reached the remote (freshness, even on success):
date -r "$(git rev-parse --git-common-dir)/FETCH_HEAD" 2>/dev/null
```

If the output contains `FETCH_FAILED` (an authentication failure, a network error, a proxy or firewall refusing the connection), **STOP. Do not run Step 1 and do not produce the report.** Every comparison would otherwise silently use a stale cached `$BASE` and mislead: it reports the tip as it was at the last successful fetch, which can be hours or days behind, and nothing in the report says so. Instead report only: the fetch error, the last successful fetch time (the `FETCH_HEAD` mtime above), and tell the user to resolve the fetch failure and re-run `/flow-status`. Continue to Step 1 only after the fetch succeeds.

If the output contains `BASE_MISSING`, stop the same way: there is no remote named `origin`, or it does not carry the default branch, so every comparison below would error and the report would be built from the errors. Report which ref is missing and that the factory compares against `origin`.

## Step 1 - Collect git state (run after the fetch completes)

```bash
# Set BASE again. Step 0 and Step 1 are separate runs, because the fetch has to be
# judged before this block is allowed to start, and a shell variable does not survive
# between runs. Left empty, `"$BASE"...HEAD` silently reads as `HEAD...HEAD` and every
# count below comes back zero, so the report says "in sync" about a branch that is not.
BASE="origin/<the git.default_branch value>"
DEFAULT="${BASE#origin/}"

# Current branch
cur=$(git branch --show-current); echo "${cur:-DETACHED}"

# Its upstream (origin/foo, origin/foo[ahead 1], origin/foo[gone]), or NO_UPSTREAM.
[ -n "$cur" ] && git for-each-ref --format='%(upstream:short)%(upstream:track)' "refs/heads/$cur" | grep . || echo "NO_UPSTREAM"

# Worktree path
git rev-parse --show-toplevel

# All worktrees
git worktree list

# Ahead/behind COUNTS. left = behind (on the base, not here); right = ahead-by-SHA (here, not on the base).
read -r behind ahead <<< "$(git rev-list --left-right --count "$BASE"...HEAD)"
echo "ahead_by_sha=$ahead behind=$behind"

# Commit subjects: ahead-by-SHA list, then behind list.
git log --oneline "$BASE"..HEAD
git log --oneline HEAD.."$BASE"

# SQUASH-MERGE DETECTION (the key check). Is the branch's ENTIRE diff-since-divergence
# already a single commit on the base? Compare the patch-id of the whole branch range against
# each commit the base added after the merge-base. Catches a squash-merge that git log,
# git cherry, and --is-ancestor all wrongly report as "ahead". It matches against the
# squash commit's OWN diff, so the base editing those files afterwards does not fool it.
mb=$(git merge-base "$BASE" HEAD)
squash=""
if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ] && [ "$behind" -lt 200 ]; then
  bpid=$(git diff $mb...HEAD | git patch-id --stable | cut -d' ' -f1)
  for c in $(git rev-list $mb.."$BASE"); do
    if [ "$(git show $c | git patch-id --stable | cut -d' ' -f1)" = "$bpid" ]; then squash=$c; break; fi
  done
fi
echo "merge_base=$mb squash_commit=${squash:-none}"
[ -n "$squash" ] && git log --oneline -1 "$squash"

# Uncommitted changes (the genuine not-on-base delta when squash_commit is set).
git status --short

# Genuinely-new committed work (use ONLY when squash_commit is none).
git diff --stat "$BASE"...HEAD

# Ancestor check: true after a fast-forward or a merge commit, never after a squash (a squash rewrites history).
# The default branch is the base, so it passes whenever it is not ahead: it gets its own marker.
if [ -z "$cur" ]; then echo "DETACHED"
elif [ "$cur" = "$DEFAULT" ]; then echo "DEFAULT_BRANCH"
elif git merge-base --is-ancestor HEAD "$BASE"; then echo "MERGED into $BASE"
else echo "NOT merged"; fi

# For every local branch, merged into the base or not. This is all of them, not only the
# ones a worktree has checked out; pair it with `git worktree list` above before calling
# one a worktree that can be removed. The default branch is never listed as merged,
# because it is the base.
git for-each-ref --merged="$BASE" --format='MERGED  %(refname:lstrip=2)' refs/heads/ | grep -vxF "MERGED  $DEFAULT"
git for-each-ref --no-merged="$BASE" --format='ACTIVE  %(refname:lstrip=2)' refs/heads/
```

Then check whether the factory checkout has an update. This check never stops the report: a factory that cannot be checked is no reason to withhold the project's status, and Step 0's two stops stay the only ones.

```bash
# Prints one FACTORY_LINE when the checkout is behind or cannot be checked, and
# nothing when it is level or the record names no checkout.
F=$(sed -n 's/^checkout //p' ~/.flow-factory/install-record.txt 2>/dev/null)
if [ -n "$F" ]; then
  n=
  if [ -e "$F/.git" ]; then
    # No credential prompt, and killed after 10 seconds, so no origin can hang the report.
    GIT_TERMINAL_PROMPT=0 git -C "$F" fetch -q >/dev/null 2>&1 & p=$!
    ( sleep 10; kill "$p" ) >/dev/null 2>&1 & t=$!
    wait "$p" && n=$(git -C "$F" rev-list --count HEAD..@{u} 2>/dev/null)
    kill "$t" 2>/dev/null
  fi
  if [ -z "$n" ]; then echo "FACTORY_LINE: I could not check for a Flow Factory update in $F."
  elif [ "$n" -gt 0 ]; then
    s=s; [ "$n" -eq 1 ] && s=
    echo "FACTORY_LINE: Flow Factory is $n commit$s behind origin: run ./install in $F"
  fi
fi
```

## Step 2 - Produce the report

Output exactly these 7 sections, in order, then the factory line when Step 1 printed one. Keep each section tight, no padding.

---

### 1. What we've been working on
One paragraph, plain English. Synthesise from the conversation history: what problem, what approach, what outcome so far.

### 2. Worktree
`<absolute path>`, and note if it is a secondary worktree (not the main clone) or the main repo.

### 3. Branch
`<branch name> -> <upstream>`, the upstream copied as Step 1 printed it (e.g. `feature/foo -> origin/feature/foo`, or `origin/feature/foo[gone]` once the remote branch is deleted). On `NO_UPSTREAM`, say the branch has no upstream; never print one Step 1 did not. On `DETACHED`, say only that HEAD is on no branch. Append `(already merged to <the base>, safe to delete)` only when the ancestor check printed `MERGED into`.

### 4. Commits ahead of the base
Read `ahead_by_sha` and `squash_commit` from Step 1.
- If `ahead_by_sha` is 0 -> "No commits ahead of `<the base>`."
- If `squash_commit` is set -> the SHA-ahead commits are already on the base, squash-merged. Report: "N commits ahead by SHA, but their content is already on `<the base>` (squash-merged as `<short-sha>` '<subject>'). Genuinely ahead: 0." Then list the `git log "$BASE"..HEAD` commits under that caveat, so it is clear they are not new work.
- If `squash_commit` is none and `ahead_by_sha` > 0 -> these are genuinely ahead; list each SHA + message as real work.

### 5. Uncommitted changes
List files from `git status --short`. If none, say "Working tree clean."

### 6. Branch delta vs the base
Lead with the genuine delta: what this branch has that `$BASE` does NOT.
- Committed: if `squash_commit` is set, say "none; all committed work is already on `<the base>` via `<short-sha>`." Otherwise summarise `git diff --stat "$BASE"...HEAD` (N files, +X/-Y, list files) as the genuinely-new committed work.
- Uncommitted: list `git status --short` (usually the real delta).
Never present `git diff --stat "$BASE"...HEAD` as the branch's delta when `squash_commit` is set; that diffstat is just the squashed content echoed back, not new work.

Then position vs `$BASE`:
- If `behind` > 0, say "Behind `<the base>` by `behind` commits" and list `git log HEAD.."$BASE"`. Flag as a rebase candidate.
- If `ahead_by_sha` is 0 and `behind` is 0, say "In sync with `<the base>`."

If local branches other than the current one are already merged into `$BASE` (per the per-branch loop in Step 1), list them in a sub-bullet as cleanup candidates. The loop covers every local branch, so say for each whether a worktree has it checked out, reading `git worktree list`: a merged branch with a worktree means a worktree to remove, a merged branch without one means only a branch to delete. Skip if none.

### 7. What's next
Offer exactly 3 options, lettered A / B / C. Derive them from the session context: what was in progress, what was blocked, what was mentioned as upcoming. Be specific (file names, feature names), not generic.

---

When the factory check in Step 1 printed a `FACTORY_LINE:`, end the report with the text after that prefix, as it stands, on its own line after section 7. When it printed none, add nothing about the factory. Never run the commands it names.

## Format rules
- Use `###` headers exactly as above
- Keep total output under 400 words
- No emoji
- Sections 4 and 5 use bullet lists; sections 1, 2, 3 use prose; section 7 uses A/B/C list
