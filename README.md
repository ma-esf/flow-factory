# Flow Factory

Flow Factory is an agentic software factory: a set of skills, a markdown issue
tracker and an installer that carry one piece of work from an unclear idea to a
merged, closed-out change.

It is for an engineer who builds with a coding agent and wants every piece of
work to take the same route: captured, triaged, built, verified, shipped,
closed out. It is project agnostic. An AI engineer on a retrieval system and a
software engineer on a dashboard install the same factory and use the same four
stages.

## Before you install

These stop the install:

- **Claude Code.** The skills are installed into `~/.claude/skills/`, and the
  installer stops when `~/.claude` is absent.
- **git.** Both this checkout and the project you install into have to be git
  repositories, this one cloned with its history so it can name its release,
  and the project carrying at least one commit.
- **A project that is not this checkout.** The argument you pass names the
  project, never the factory.

Nothing else stops it, and what is left is worth knowing before you judge what
the factory costs. The Deliver stage is built on `gh`, authenticated against
GitHub, and on `/code-review`, Claude Code's built-in review skill that the
factory does not ship. Without them it loses the proof that a squash merge
landed and its review step, while the rest of the factory carries on working.
Every skill that compares against the default branch needs a remote named
`origin` carrying it. `/flow-conductor` needs iTerm2 and macOS Automation
permission, and the other twenty-seven skills do not.

macOS is what the factory has been run on. The only pieces left that nothing
else has are the iTerm2 dispatch in `/flow-conductor` and the `pbcopy` step
two skills offer, but that is a fact about where it has been tried rather than
a claim that it travels: nobody has run the rest anywhere else.

`machine/requirements.md` holds all fifteen, in three tiers, with the probe
for each and what is lost without it.
`machine/dispatch-prerequisites.md` holds the four dispatch probes and what
each failure looks like.

## Install

Clone this repository. Then run the installer from the checkout, naming the
project to install into:

```bash
./install/install.sh <project-root>
```

The argument is the project, never the factory. Run it bare from this checkout
and it stops and tells you to pass the project.

The installer asks a short list of questions about the project and writes the
answers to `flow-factory.toml`: the default branch, the command that runs its
tests, where it keeps its docs and decision records, how pull requests get
opened and merged, and whether Jira is in play. A few more arrive with a
default, which you keep or replace.

Two of the answers behave differently from the rest. It detects your default
branch and asks you to confirm it, because a repository showing one branch is
the repository answering, not you. The test command has no default, so leaving
it empty means every skill that runs tests stops and names it. For several of
the remaining questions an empty answer is a real answer: it says the project
has no such thing.

The install leaves files in two places.

On the machine, once:

- `~/.claude/skills/flow-*`, one directory per skill.
- `~/.flow-factory/`, the tracker and settings contracts and the file templates
  the skills write against.

In the project, once per project:

- `flow-factory.toml` at the root, holding the answers. Installing into the
  same project again overwrites it, and the answers it held are gone.
- `.flow/issues/` and `.flow/candidates/`, where work items live.
- `.flow/README.md`, recording which version of the factory was installed and
  when.

Nothing else is installed. No service, no database, no state shared between
projects.

## Where to start

The everyday chain is `/flow-park` to capture something worth doing,
`/flow-triage` to turn a capture into a buildable ticket, and
`/flow-ship-issue` to build, verify and ship it. `/flow-backlog` answers what
there is to work on.

- `docs/4d-system.md` - the four stages work moves through.
- `docs/skills.md` - every skill and what it is for.
- `docs/glossary.md` - the vocabulary the skills use.
- `docs/roadmap.md` - what is coming next.

## What is in this repository

| Directory | Holds | Installed |
|---|---|---|
| `skills/` | the skill sources | on the machine, once |
| `machine/` | the requirements, the tracker rules and the file templates skills write against | on the machine, once |
| `project/` | the settings file and the pointer file | in each project, once |
| `install/` | the installer | not installed; it does the placing |
| `docs/` | the reference docs | not installed; read them here |
