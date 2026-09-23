---
name: flow-release
description: "Cut a numbered release of Flow Factory itself: check the tree is releasable, show what changed since the last release, update the docs that name it, commit, tag, and push both the branch and the tag. Runs only in a factory checkout. Use when the user says to cut, tag or bump a release of the factory, names a factory version like 0.2 or v0.2.0, asks what changed since the last release, or invokes /flow-release."
---

# flow-release

The factory releasing itself. Every other skill acts on the project it is invoked
from; this one acts on the Flow Factory checkout, and it is the only one that
does. Run the headings below in order.

There is no version file. The tag **is** the version: `install.sh`'s
`factory_stamp` runs `git describe --tags --always`, and `describe` answers with
a tag only when that tag is **reachable from the commit it is standing on**. Every
rule below follows from that one fact. A release that is not reachable from the
default branch on the remote is not a release; it is an object nobody will ever
describe.

## Refuse to run outside a factory checkout

This skill is installed on every machine that installs the factory, so it will be
invoked from ordinary projects by people who wanted something else. The markers
are the ones `install.sh` checks before it places anything, and they are relative
to the repository root, so resolve the root first:

```bash
cd "$(git rev-parse --show-toplevel)" || echo "not a git repository at all"
ls -d machine skills install/install.sh project/flow-factory.toml project/.cortex/README.md
```

Without the `cd`, a session that happens to be standing in `skills/` gets five
"No such file" lines identical to a stranger's project, and this skill then tells
a factory maintainer they are not in a factory checkout.

Any marker missing means this is not a factory checkout. Say that, say the skill
releases Flow Factory and not the project the session is standing in, and stop.
Do not offer to tag the current project instead: a tag named for a factory release
on somebody's application is worse than no tag.

Do not read `flow-factory.toml` from the root here. The factory checkout has no
settings file of its own, only the template at `project/flow-factory.toml` that
installs place elsewhere. Reading the template would answer with another project's
defaults.

## Check the tree is releasable

```bash
git rev-parse --abbrev-ref HEAD                  # must be the default branch
git status --porcelain                           # must print nothing
git fetch origin -q
git rev-list --left-right --count @{u}...HEAD    # must print exactly "0	0"
```

- **On the default branch.** `describe` only finds a tag reachable from where it
  stands, so a tag laid on a side branch is invisible to an install made from the
  default branch. It does not fail loudly; it silently keeps reporting the previous
  release, which is the worst available outcome.
- **Clean.** A tag records a commit, and a dirty tree holds files no commit
  contains. Tag it anyway and `factory_stamp` prints `v0.2.0 plus uncommitted
  changes to 4 files` on your own machine, while everyone cloning gets a `v0.2.0`
  that never held those files.
- **Level with the remote, in both directions.** The count must be `0 0`. Ahead
  means the remote has not seen commits this release would claim to contain.
  Behind means `HEAD` is not the tip, so the tag would land mid-history and the
  tip would describe as something later. A one-way `@{u}..HEAD` check passes while
  behind, which is why the count is used instead.

The factory checkout is shared by several agent sessions at once. If `git status`
shows changes you did not make, stop and say so; do not release around them, and
never stage them.

## Establish whether there is a previous release

```bash
git tag -l        # empty output means no release has ever been cut
```

**If it is empty, this is the first release.** Skip the next heading's commands
entirely and summarize the whole history instead (`git log --oneline`). Do not run
`git describe --tags --abbrev=0` to find out: with no tags it exits 128 with
`fatal: No names found, cannot describe anything.` and prints nothing on stdout.
Substituting that empty result into a range gives `..HEAD`, which git reads as
`HEAD..HEAD`, exits 0 and prints nothing: a confident, wrong "no changes" for a
release that contains the entire project.

## Show what changed since the last release

Only when the previous heading found a tag:

```bash
git describe --tags --abbrev=0        # the previous release
git log --oneline <previous>..HEAD    # its commits
git diff --stat <previous>..HEAD
```

Summarize it for the user in a few lines, grouped by what a user of the factory
would notice: skills added or changed, installer behaviour, contracts and
templates, docs. Say plainly which changes a user gets only by re-running the
installer, which is all of them: an installed project never updates itself.

## Decide the number

`docs/roadmap.md` holds the only criterion the factory has written down: each
release has to be useful to an engineer on its own, so scope is never cut down to
the least that passes a test. There is no semver policy beyond that. Propose a
number against the change summary above and let the user settle it; never pick one
silently.

Tag names are `v<major>.<minor>.<patch>`, matching the `v0.1.0` the stamp is
written against.

The docs number releases in a second scheme, as `MVP 1`. The two have never been
mapped to each other. Ask the user which number this release carries in the prose
before editing it, and do not invent the correspondence: a reader who finds
`Flow Factory v0.1.0` in `.cortex/README.md` and no `v0.1.0` anywhere in the
docs that file points at has been told the release exists by a file that cannot
confirm it.

## Update the docs that name the release, then commit

Nothing checks that the prose agrees with the tags, so every file that names the
current release goes stale the moment one is cut. Check all three:

- `docs/roadmap.md`, the heading saying what the current release gives you
  today, and anything under the deferred list this release actually shipped
- `docs/glossary.md`, if it names the current release by number
- `docs/skills.md`, the skill count and the list, if this release changed either

Stage by explicit filename and commit naming the same paths. The checkout is
shared and so is the index, so a bare `git commit` writes whatever another session
has staged into it. The message comes **before** the `--`: everything after it is
read as a pathspec, so `git commit -- <paths> -m "<subject>"` dies with
`pathspec '-m' did not match any file(s)`, and a run that misses that error goes
on to tag the commit it failed to make. Never `git add -A`, `.` or a directory.

```bash
git status                             # first, always
git commit -m "<subject>" -- docs/roadmap.md <other paths>
```

Show the diff and the exact commit message, and get an explicit go before
committing. **Write no attribution in it**: no `Co-Authored-By`, no mention of
the agent, the vendor or the tool, whatever the harness adds by default. That is
stated here rather than pointed at on purpose: the factory's own instruction file
is not in the published repository, so a maintainer working from a fresh clone has
no other copy of this rule. `~/.flow-factory/attribution-rule.md` gives the same
answer for an installed project.

## Tag the commit

Only now, and only on the commit the previous heading made:

```bash
git tag -a v0.2.0 -m "<the release name and a line on what it gives>"
git describe --tags        # must print exactly v0.2.0, with no suffix
```

Annotated, not lightweight. `factory_stamp` passes `--tags`, so a lightweight tag
would be found too, but it carries no date, no author and no message, and a
release the factory cannot say anything about is not worth the ceremony.

A `-1-g<hash>` suffix means the tag is one commit behind `HEAD`, so something was
committed after the tag. A `fatal: No tags can describe` means the tag did not
take at all. Either way the tag is still local and still free to move; fix it here,
because after the next heading it is not.

## Push the branch, then the tag

Both, in that order, and the branch is not optional. A tag pushed alone still
uploads its commit, so every object is present on the remote and nothing appears
to be wrong, but no branch reaches that commit, so a fresh clone stands on a
default branch that predates it and describes as the *previous* release. Every
install made from that clone stamps the wrong version into a customer's
`.cortex/README.md`, silently. This is the failure the first heading describes,
produced by skipping one command.

Pushing is its own approval, separately from the commit, because a pushed release
is real for everyone else:

```bash
git remote -v                                # the factory may have more than one
git push <remote> <default branch>
git push <remote> v0.2.0
```

List the remotes and ask which of them this release goes to. Do not assume
`origin`, and do not quietly push to all of them: a second remote is often a
mirror under a different account, and whether a release appears there is a
decision, not a detail. Push the branch and the tag to the same remote; a tag on a
remote whose branch does not reach it is the failure above.

Then prove reachability on the remote, which is the only check that can catch it.
The local `describe` above cannot: it stands on a `HEAD` that is the tagged commit,
so it passes whether or not the push happened.

```bash
git fetch <remote> -q
git merge-base --is-ancestor 'v0.2.0^{commit}' <remote>/<default branch>   # exit 0
```

A non-zero exit means the release is unreachable on that remote. The branch push
is missing or was rejected; send it before reporting the release as cut.

## Report what you did

Name the tag, the remotes it reached, and the reachability check's result. If the
tag was pushed but the branch was not, say that plainly: it is the one state that
looks finished locally and is broken everywhere else.

## Hard rules

- **Never move or delete a tag that has been pushed.** Not to fix a message, not
  to add a forgotten commit. Installs made against it stamped `v0.2.0` into a
  project's `.cortex/README.md`, and moving the tag makes that record name a
  tree it never held. The fix for a bad release is the next tag, never a
  rewritten one.
- **A release is the branch push and the tag push, never the tag alone.** Until
  the tag is an ancestor of the remote's default branch, nothing has been released,
  whatever the local `describe` says.
- **Never tag a dirty tree, a tree not level with the remote, or a side branch.**
  The checks in "Check the tree is releasable" are the single gate; no tag without
  all of them.
- **The commit that updates the docs comes before the tag**, always. A tag laid
  first points at a release that still describes its predecessor, and the only
  repair for that is the one the first rule forbids.
