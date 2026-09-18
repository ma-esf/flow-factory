# Flow Factory

Flow Factory is an agentic software factory: a set of skills, a markdown issue
tracker and an installer that carry one piece of work from an unclear idea to a
merged, closed-out change.

It is project agnostic. An AI engineer on a retrieval system and a software
engineer on a dashboard install the same factory and use the same four stages.

## The four stages

Work moves through four stages. Each ends when its question is answered.

- **Discover.** Understand the problem, gather evidence, establish context.
  What is broken, missing or unclear, and what evidence do we have for it?
- **Define.** Set the domain language, intended behavior, boundaries and
  constraints. What exactly are we building, what is out of scope, and what
  result proves it correct?
- **Decompose.** Break the defined work into independent, executable pieces.
  How do we split this into pieces small enough to ship and verify one at a
  time?
- **Deliver.** Build, verify, ship and close out. Is it built, tested, merged
  and closed out, with nothing left dangling?

`docs/4d-system.md` holds the full definition.

## What is in this repository

An install leaves files in two places: once on the machine, and once in every
project that uses the factory. Each directory is named after where its contents
land.

| Directory | Holds | Installed |
|---|---|---|
| `skills/` | the skill sources | on the machine, once |
| `machine/` | the tracker rules and the file templates skills write against | on the machine, once |
| `project/` | the settings file and the pointer file | in each project, once |
| `install/` | the installer | not installed; it does the placing |
| `docs/` | the specification | not installed; read it here |

Nothing else is installed. No service, no database, no state shared between
projects.

## MVP 1

Flow Factory ships in numbered releases, each useful to an engineer on its own.

MVP 1 is done when a second engineer installs the factory on their own machine
and completes one real flow, through all four stages, in a repository that is
not the one the skills came from, borrowing nothing from it. That run must
include at least one intentionally invalid input, to prove the factory reports
a failure instead of producing a plausible fallback.

MVP 1 supports macOS and Claude Code. `docs/mvp-1-skills.md` names the
twenty-one skills it ships and why. `docs/mvp-plan.md` holds the scope, the
open decisions and what is deferred.
