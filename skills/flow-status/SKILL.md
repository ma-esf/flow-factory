---
name: flow-status
description: Session and git status snapshot. Reads session history and live git state to report what we've been working on, current worktree, branch, commits made this session, uncommitted changes, branch delta against the project's default branch, and 3 next-step options. Use when user types /flow-status or asks "what's our status", "where are we", "what have we done".
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
# Always show when we last actually reached the remote (freshness, even on success).
# Two spellings because BSD and GNU stat disagree on the flag; the second runs
# only when the first is not the stat this machine has.
stat -f '%Sm  %N' "$(git rev-parse --git-common-dir)/FETCH_HEAD" 2>/dev/null \
  || stat -c '%y  %n' "$(git rev-parse --git-common-dir)/FETCH_HEAD" 2>/dev/null
```

If the output contains `FETCH_FAILED` (an authentication failure, a network error, a proxy or firewall refusing the connection), **STOP. Do not run Step 1 and do not produce the report.** Every comparison would otherwise silently use a stale cached `$BASE` and mislead: it reports the tip as it was at the last successful fetch, which can be hours or days behind, and nothing in the report says so. Instead report only: the fetch error, the last successful fetch time (the `FETCH_HEAD` mtime above), and tell the user to resolve the fetch failure and re-run `/flow-status`. Continue to Step 1 only after the fetch succeeds.

## Step 1 - Collect git state (run after the fetch completes)

```bash
# Set BASE again. Step 0 and Step 1 are separate runs, because the fetch has to be
# judged before this block is allowed to start, and a shell variable does not survive
# between runs. Left empty, `"$BASE"...HEAD` silently reads as `HEAD...HEAD` and every
# count below comes back zero, so the report says "in sync" about a branch that is not.
BASE="origin/<the git.default_branch value>"

# Current branch
git branch --show-current

# Worktree path
git rev-parse --show-toplevel

# All worktrees
git worktree list

# Ahead/behind COUNTS. left = behind (on the base, not here); right = ahead-by-SHA (here, not on the base).
set -- $(git rev-list --left-right --count "$BASE"...HEAD); behind=$1; ahead=$2
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
  bpid=$(git diff $mb...HEAD | git patch-id --stable | awk '{print $1}')
  for c in $(git rev-list $mb.."$BASE"); do
    if [ "$(git show $c | git patch-id --stable | awk '{print $1}')" = "$bpid" ]; then squash=$c; break; fi
  done
fi
echo "merge_base=$mb squash_commit=${squash:-none}"
[ -n "$squash" ] && git log --oneline -1 "$squash"

# Uncommitted changes (the genuine not-on-base delta when squash_commit is set).
git status --short

# Genuinely-new committed work (use ONLY when squash_commit is none).
git diff --stat "$BASE"...HEAD

# Ancestor check: true only for fast-forward merges, NOT squashes (a squash rewrites history).
git merge-base --is-ancestor HEAD "$BASE" && echo "MERGED into $BASE" || echo "NOT merged"

# For every local branch, merged into the base or not. This is all of them, not only the
# ones a worktree has checked out; pair it with `git worktree list` above before calling
# one a worktree that can be removed.
git for-each-ref --format='%(refname:short)' refs/heads/ | while read b; do
  if git merge-base --is-ancestor "$b" "$BASE" 2>/dev/null; then
    echo "MERGED  $b"
  else
    echo "ACTIVE  $b"
  fi
done
```

## Step 2 - Produce the report

Output exactly these 7 sections, in order. Keep each section tight, no padding.

---

### 1. What we've been working on
One paragraph, plain English. Synthesise from the conversation history: what problem, what approach, what outcome so far.

### 2. Worktree
`<absolute path>`, and note if it is a secondary worktree (not the main clone) or the main repo.

### 3. Branch
`<branch name>` and its upstream if it has one (e.g. `feature/foo -> origin/feature/foo`). If the branch is already fully merged into `$BASE` (per the `--is-ancestor` check), append: `(already merged to <the base>, safe to delete)`.

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

## Format rules
- Use `###` headers exactly as above
- Keep total output under 400 words
- No emoji
- Sections 4 and 5 use bullet lists; sections 1, 2, 3 use prose; section 7 uses A/B/C list
