---
name: flow-release
description: "Cut a numbered release of Flow Factory itself: check the tree is releasable, show what changed since the last tag, update the roadmap, commit, tag and push the tag. Runs only in a factory checkout. Use when the user says to cut, tag or bump a release of the factory, names a version like 0.2 or v0.2.0, asks what changed since the last release, or invokes /flow-release."
---

# flow-release

The factory releasing itself. Every other skill acts on the project it is invoked
from; this one acts on the Flow Factory checkout, and it is the only one that
does. Run the headings below in order.

There is no version file. The tag **is** the version: `install.sh`'s
`factory_stamp` runs `git describe --tags --always`, so the moment a tag exists on
the default branch, every later install stamps the installed project's
`.flow/README.md` with it. That is the whole release mechanism, and it is why the
order of the last three headings cannot be rearranged.

## Refuse to run outside a factory checkout

This skill is installed on every machine that installs the factory, so it will be
invoked from ordinary projects by people who wanted something else. Check for the
markers `install.sh` itself checks before placing anything:

```bash
ls -d machine skills install/install.sh project/flow-factory.toml project/.flow/README.md
```

Any of them missing means this is not a factory checkout. Say that, say the skill
releases Flow Factory and not the project the session is standing in, and stop.
Do not offer to tag the current project instead: a tag named for a factory release
on somebody's application is worse than no tag.

Do not read `flow-factory.toml` from the root here. The factory checkout has no
settings file of its own, only the template at `project/flow-factory.toml` that
installs place elsewhere. Reading the template would answer with another project's
defaults.

## Check the tree is releasable

Three facts, each a stop:

```bash
git rev-parse --abbrev-ref HEAD      # must be the default branch
git status --porcelain               # must print nothing
git fetch origin -q && git log --oneline @{u}..HEAD   # must print nothing
```

- **On the default branch.** `git describe --tags` only finds a tag reachable from
  `HEAD`, so a tag laid on a side branch is invisible to an install made from the
  default branch. It does not fail loudly; it silently keeps reporting the previous
  release, which is the worst available outcome.
- **Clean.** A tag records a commit, and a dirty tree holds files no commit
  contains. Tag it anyway and `factory_stamp` prints `v0.2.0 plus uncommitted
  changes to 4 files` on your own machine, while everyone cloning gets a `v0.2.0`
  that never held those files.
- **Nothing unpushed.** A tag pointing at a commit the remote has never seen breaks
  every clone: `git describe` there falls back to an older tag or a bare hash.

## Show what changed since the last release

```bash
git describe --tags --abbrev=0        # the previous release, or nothing at all
git log --oneline <previous>..HEAD    # its commits
git diff --stat <previous>..HEAD
```

No previous tag means this is the first release; read the whole history instead.

Summarize it for the user in a few lines, grouped by what a user of the factory
would notice: skills added or changed, installer behaviour, contracts and
templates, docs. Say plainly which changes a user gets only by re-running the
installer, which is all of them — an installed project never updates itself.

## Decide the number

`docs/roadmap.md` holds the only criterion the factory has written down: each
release has to be useful to an engineer on its own, so scope is never cut down to
the least that passes a test. There is no semver policy beyond that. Propose a
number against the change summary above and let the user settle it; never pick one
silently.

Tag names are `v<major>.<minor>.<patch>`, matching the `v0.1.0` the stamp is
written against.

## Update the roadmap, then commit

`docs/roadmap.md` names the current release in prose, and nothing checks that the
prose agrees with the tags. It is the one thing in the repository that goes stale
at a release, so it is edited **before** the tag exists, not after:

- the heading that says what the current release gives you today
- anything under the deferred list that this release actually shipped
- `docs/glossary.md` if it names the current release by number

Show the diff and the exact commit message, and get an explicit go before
committing. Write no attribution in it. `~/.flow-factory/attribution-rule.md` makes
`none` the unset default, and a factory checkout has no settings file to set it to
anything else.

## Tag the commit

Only now, and only on the commit the previous heading made:

```bash
git tag -a v0.2.0 -m "<the release name and a line on what it gives>"
```

Annotated, not lightweight. `factory_stamp` passes `--tags`, so a lightweight tag
would be found too, but it carries no date, no author and no message, and a
release the factory cannot say anything about is not worth the ceremony.

Verify before going near a remote. On a clean tree at the tagged commit:

```bash
git describe --tags        # must print exactly v0.2.0, with no suffix
```

A `-1-g<hash>` suffix means the tag is one commit behind `HEAD`, so something was
committed after the tag. A bare hash means the tag did not take. Either way the
tag is still local and still free to move; fix it here.

## Push the tag, as its own step

A tag does not travel with a branch push. It needs its own, and it needs the
user's explicit go — a pushed tag is the release becoming real for everyone else.

```bash
git remote -v          # the factory may have more than one
git push <remote> v0.2.0
```

List the remotes and ask which of them this release goes to. Do not assume
`origin`, and do not quietly push to all of them: a second remote is often a
mirror under a different account, and whether a release appears there is a
decision, not a detail.

## Hard rules

- **Never move or delete a tag that has been pushed.** Not to fix a message, not
  to add a forgotten commit. Installs made against it stamped `v0.2.0` into a
  project's `.flow/README.md`, and moving the tag makes that record name a tree it
  never held. The fix for a bad release is the next tag, never a rewritten one.
- **Never tag a dirty or unpushed tree**, and never tag off the default branch.
  The three checks above are the single gate; no tag without all three.
- **The commit that updates the roadmap comes before the tag**, always. A tag laid
  first points at a release that still describes its predecessor, and the only
  repair for that is the one the rule above forbids.
