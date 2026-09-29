# Flow Factory

Flow Factory is an agentic software factory: a set of skills, a markdown ticket
tracker and an installer that carry one piece of work from an unclear idea to a
merged, closed-out change.

It is for an engineer who builds with a coding agent and wants every piece of
work to take the same route: captured, triaged, built, verified, shipped,
closed out. It is project agnostic. An AI engineer on a retrieval system and a
software engineer on a dashboard install the same factory and use the same four
stages.

## Before you install

- **macOS.** The installer and the skills use macOS tools.
- **Claude Code.** The skills are installed into `~/.claude/skills/`, and the
  installer stops when `~/.claude` is absent.
- **git.** Both this checkout and the project you install into have to be git
  repositories, and the project needs at least one commit.

The installer does not check three more, and the skills that ship work need
all of them:

- **`gh`, installed and authenticated.** `/flow-close-out` reads it as the
  proof that a pull request merged, and `/flow-new-github-issue` cannot run
  without it.
- **A remote named `origin` carrying the default branch.** Every skill that
  compares a branch with the default branch compares with `origin`'s copy.
- **`/code-review`**, Claude Code's built-in review skill, which the factory
  does not ship. `/flow-ship-ticket` reviews with it.

One skill needs more than that. `/flow-conductor` launches a session per ticket
by driving iTerm2, so it needs iTerm2 installed and macOS Automation permission
granted to the terminal the agent runs in.
`machine/dispatch-prerequisites.md` holds the probes and what each failure
looks like.

## Install

Clone this repository. Then run the installer from the checkout:

```bash
./install
```

It asks nothing. Before it writes outside the checkout, it names the only two
places it writes there:

- `~/.claude/skills/flow-*`, one directory per skill.
- `~/.flow-factory/`, the tracker and settings contracts, the file templates
  the skills write against, and `install-record.txt`, the list of every file
  it placed.

A `flow-*` skill directory it did not place is left alone and named.

Run it again to update. It pulls the checkout, fast-forward only, runs the
installer that pull brought, and removes every file it placed that the
factory no longer ships. A pull that fails leaves the checkout as it stands,
and that is what it installs.

Fitting a project, its settings and its tracker, arrives with `/flow-init`.

Nothing else is installed. No service, no database, no state shared between
projects.

## Where to start

The everyday chain is `/flow-park` to capture something worth doing,
`/flow-triage` to turn a capture into a buildable ticket, and
`/flow-ship-ticket` to build, verify and ship it. `/flow-backlog` answers what
there is to work on.

- `docs/4d-system.md` - the four stages work moves through.
- `docs/skills.md` - every skill and what it is for.
- `docs/glossary.md` - the vocabulary the skills use.
- `docs/roadmap.md` - what is coming next.

## What is in this repository

| Directory | Holds | Installed |
|---|---|---|
| `skills/` | the skill sources | on the machine, once |
| `machine/` | the tracker rules and the file templates skills write against | on the machine, once |
| `project/` | the settings file and the pointer file | in each project, once |
| `install` | the installer | not installed; it does the placing |
| `tests/` | the installer's regression test | not installed |
| `docs/` | the reference docs | not installed; read them here |
