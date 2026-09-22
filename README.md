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

- **macOS.** The installer and the skills use macOS tools.
- **Claude Code.** The skills are installed into `~/.claude/skills/`, and the
  installer stops when `~/.claude` is absent.
- **git.** Both this checkout and the project you install into have to be git
  repositories.

One skill needs more than that. `/flow-conductor` launches a session per issue
by driving iTerm2, so it needs iTerm2 installed and macOS Automation permission
granted to the terminal the agent runs in. The installer probes for both,
reports what failed and finishes anyway; only `/flow-conductor` is blocked.
`machine/dispatch-prerequisites.md` holds the probes and what each failure
looks like.

## Install

Clone this repository. Then run the installer from the checkout, naming the
project to install into:

```bash
./install/install.sh <project-root>
```

The argument is the project, never the factory. Run it bare inside a project
and it asks whether that is the one; run it bare from this checkout and it
stops and tells you to pass the project. `--machine` installs the skills on
this Mac without touching any project, `--help` lists the rest.

The install runs in three sections, each announced as it starts.

**1/3 This machine.** The skills, the contracts and the templates land in
`~/.claude/skills/` and `~/.flow-factory/`. No questions here, and running it
again refreshes what is there. It ends by probing the four things `/flow-conductor` needs and
saying which are missing; nothing else waits on them.

**2/3 Your project.** Six quick questions, then one that covers seven more,
then one that covers the four keys with a default. Enter takes the answer in
brackets and a menu takes a number. The installer puts forward what the
project can tell it, to confirm rather than accept: the default branch from
the repository, the test command from `package.json`, `pyproject.toml`,
`Cargo.toml` and the like, the test directory and the glossary from where
they usually sit. Nothing detected is written unconfirmed, because a
repository showing one branch is the repository answering, not you.

Two answers behave differently. The test command has no fallback, so left
empty every skill that runs tests stops and names it, and the install says so
at the end. The seven keys about docs, tests and decision records take empty
as a real answer meaning the project has no such thing, which is why they are
offered as a group rather than skipped.

Every answer is shown in one table before anything is written. Say no there,
or press Ctrl-C at any question, and the project is left as it was.

The questions are not in the installer. Each one lives in
`project/flow-factory.toml` beside the key it sets, as `ask:`, `hint:`,
`group:`, `choice:`, `detect:` and `verify:` lines, and the installer strips
them when it writes that file into a project. Edit a question there and the
installer asks it; add a key without one and the installer stops and says so.
The alternative was a second list, and a second list is the one that drifts.

**3/3 Check.** Every file and skill an installed skill refers to is looked up
on this machine. A miss is a factory bug and the install says so.

The install leaves files in two places.

On the machine, once:

- `~/.claude/skills/flow-*`, one directory per skill.
- `~/.flow-factory/`, the tracker and settings contracts and the file
  templates the skills write against.

In the project, once per project:

- `flow-factory.toml` at the root, holding the answers. Installing into the
  same project again reads it first, so its answers are the defaults and
  Enter keeps each one.
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
| `machine/` | the tracker rules and the file templates skills write against | on the machine, once |
| `project/` | the settings file and the pointer file | in each project, once |
| `install/` | the installer | not installed; it does the placing |
| `docs/` | the reference docs | not installed; read them here |
