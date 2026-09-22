# Requirements

What Flow Factory needs from a machine and a project, in three tiers: five
that stop the install, seven that cost one feature and leave the rest
working, and three the install only advises. Each entry gives the probe, what
is lost without it, and what the failure looks like to somebody who did not
check. The README's "Before you install" list is the stop tier of this file.

**Scope:** what has to be true of the machine and the project outside this
repository. Not the four iTerm2 dispatch probes, written once in
`dispatch-prerequisites.md` and pointed at here. Not what an unanswered
settings key does, which is `settings-contract.md`. Not what a skill does
with what it finds (that skill).

## The three tiers

A requirement earns its tier by what is lost when it is absent, never by how
hard it is to satisfy or how central the tool feels.

- **stop** - the install cannot place a correct set of files. Name the
  failure and exit non-zero.
- **degrade** - one feature is lost and everything else works. Finish, say
  what is missing and what it costs, and exit zero.
- **advise** - nothing is lost today. Print it once and never block on it.

Three tiers rather than two because of what a reading of this repository on
2026-09-22 found in the README. It named iTerm2, which one skill of the
twenty-eight uses, beside Claude Code and git, with nothing to tell them
apart; and it did not name `gh` or `/code-review` at all, which seven skills
and five skills respectively are built on. A flat list gets this exactly
backwards: it advertises the cost of the feature the factory can most do
without, and hides the two the Deliver stage cannot work without.

## Stop

The install cannot place a correct set of files without these.

- **Claude Code on the machine**, probed as `[ -d "$HOME/.claude" ]`. The
  skills are copied into `~/.claude/skills/`; without it there is nowhere to
  put them. Probed on `.claude` and not on `.claude/skills`, because somebody
  who has never added a skill has the first and not the second, and being
  told to install a tool you already have is worse than no check.
- **A complete factory checkout, cloned with git.** Two probes: `git -C
  <factory> describe --tags --always` for the version stamp the pointer file
  carries, and the presence of `machine/`, `skills/`,
  `project/flow-factory.toml` and `project/.flow/README.md`. A download of
  the source without its history cannot say which release it is.
- **The project is a git repository**, probed as `git -C <project> rev-parse
  --git-dir`. Every skill reads git state.
- **The project is not the factory checkout.** An install into the factory
  would place the product inside its own source.
- **The project has a commit on a named branch**, probed as `git -C
  <project> rev-parse --abbrev-ref HEAD`. An unborn branch has no ref to
  confirm, and `git.default_branch` is the key most of the mapped skill lines
  depend on.

## Degrade

Each of these costs the one feature named and nothing else. The install
finishes.

- **`gh`, installed and authenticated.** Seven skills call it. Without it
  `/flow-close-out` and `/flow-worktree-close` lose the reading that proves a
  squash merge landed, `/flow-pr-summary` loses the pull request's real base,
  and `/flow-new-issue` cannot run at all. `gh pr view` is the only proof
  under the default `squash` strategy, for the reason `flow-close-out` gives:
  the ancestry check cannot tell landed work from work that never diverged.
  `flow-factory.toml` says `gh` is needed under both values of
  `pr.create_mode`, so this is not a setting a project can answer its way out
  of.
- **A remote named `origin` carrying the default branch.** Every skill that
  compares against the default branch builds `origin/` plus
  `git.default_branch`. Measured on 2026-09-22 in a repository with no
  remote: `git fetch --all --prune` printed nothing and exited 0, so the
  freshness gate every such skill opens with reported `FETCH_OK`, and the
  comparison behind it then failed with `fatal: ambiguous argument
  'origin/main..HEAD'`. The gate passing is the danger, not the fatal: a
  report assembled from commands that all errored is still a report.
- **A reachable remote.** Network, credentials, and a proxy that allows the
  fetch. `/flow-status` and `/flow-reground` already stop on `FETCH_FAILED`
  and say when the last successful fetch was, which is the behaviour every
  other skill in this tier should copy.
- **iTerm2 dispatch**, four probes, written once in
  `dispatch-prerequisites.md`. Without them `/flow-conductor` cannot launch a
  session per issue; the other twenty-seven skills do not notice. Three of
  the four fail in ways the conductor cannot see, which is why they are
  probed rather than left to fail at the moment of use.
- **`/code-review` in Claude Code**, which five skills name and the factory
  does not ship. Without it `/flow-ship-issue` Stage 3 has no review step. It
  cannot be probed from a shell, so the skills name it instead.
- **`lsof`, for `/flow-run-app`.** The skill surveys listeners on the app's
  ports and resolves each process's working directory to tell its own
  worktree's servers from another session's. Without `lsof` it cannot see
  what is already running, which is the check that stops it killing somebody
  else's server.
- **`pbcopy`, for the copy offer.** `/flow-pr-summary` and `/flow-ship-issue`
  offer to put the pull request body on the clipboard, and now offer it only
  when `command -v pbcopy` succeeds, naming the file path otherwise. This is
  prose in a skill, not a shell guard: no run has yet confirmed a session
  obeys it.

## Advise

Nothing is lost today. These are printed once.

- **Run the installer again after pulling a new release.** Skills are copied
  into `~/.claude/skills/` and never linked, deliberately: `find` and `grep
  -r` do not descend into a symlinked directory, so a linked install would
  make every later check read nothing and report a pass. The cost of copying
  is that an updated checkout does not update the machine until the installer
  runs again.
- **Exclude `.claude/worktrees/` in the project's `.gitignore`.**
  `/flow-worktree-create` puts each worktree at
  `<main>/.claude/worktrees/<name>`. In a project that tracks `.claude/`,
  every worktree lands in the project's history.
- **Decide whether `.flow/` is committed.** Both answers work and the factory
  does not care: `worktree-share.txt` links it when it is excluded and skips
  it when the project commits it. It is named here so a team makes the
  decision rather than discovering it in a diff.

## What the installer checks today

As of 2026-09-22, read from `install/install.sh` and not from a run:

- every entry in the stop tier, each as a `fail` that exits non-zero;
- the four dispatch probes, reported and not enforced.

Not checked: `gh`, the `origin` remote, `/code-review` and `lsof`. The first
two are the only entries in this file whose absence is not announced by the
thing that fails, so they are the two worth adding first. `/code-review`
cannot be probed from a shell at all.

This file is placed on the machine by the installer's step that copies every
file under `machine/`, so it needs no installer change to arrive.
