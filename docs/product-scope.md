# Flow Factory

Flow Factory is an agentic software factory for AI engineers and software
engineers. This guide describes the project for the platform engineer and
gathers our expectations for the product and how we want to build it.

**Scope:** what we build and ship, and what we expect of it. Not how the work
is done (`4d-system.md`), and not how any one part gets built (an issue or a spec).

## Who this is for

Flow Factory is an internal tool for up to ten engineers in one company. We can
reach every user directly, so we find out what is wrong by asking them.

Build for that. Prefer the fastest thing that can fail in front of a real user
over the complete thing. Do not build machinery whose only job is to reach users
we cannot talk to, such as anonymised feedback pipelines, usage reporting, or an
install flow hardened for strangers. A written step beats a tool that automates
it.

## 4D system

Flow Factory is based on the 4D system defined in `4d-system.md`.

## Project agnostic

The factory must not assume a project type. An AI engineer working on a RAG
system and a software engineer working on a dashboard must both be able to set
up and use it.

The skills we have today were developed in this repo and carry its assumptions.
Each skill must be made project agnostic before it enters the factory. The
strategy for doing this shall be worked out before we start porting skills.

## MVPs

Flow Factory ships in numbered MVPs, not in one release. Each one must be useful
to an engineer on its own, so scope is never cut down to the least that passes
an acceptance run.

### MVP 1

Carries one flow through all four stages of `4d-system.md`. A flow is one idea,
from Discover to a closed-out Deliver.

MVP 1 is done when a user installs it on a clean machine and completes one
real flow with the factory's own skills, borrowing nothing from the repository
the skills came from, on the operating system and agentic system listed under
Installation.

## Repository

Flow Factory is its own git repository. The skills and the repository structure
they need both ship from it.

## Installation

Flow Factory must have an installation process that sets up the skills and the
repository structure they need.

Users may run Flow Factory on different machines and with different agentic
systems. MVP 1 must support:

- macOS; and
- Claude Code.

The installation process should detect configuration where possible and ask
the user to confirm what it found. It should ask the user only for
configuration that cannot be detected.

The installation process must check and configure everything required for a
smooth run of the factory, including agentic systems, terminal tools, and
other platform-specific prerequisites. For example, Claude Code on macOS may
require iTerm2.

The installation method shall be investigated before implementation.

## Feedback

We ask the users. There are ten of them and we work with all of them, so the
factory carries no feedback tooling.

## Initial components

The factory currently consists of:

- refined and isolated skills from `skills-by-stage.md`;
- the markdown issue tracker those skills read and write, described in
  `machine/tracker-contract.md`. `/flow-jira-subtask` is optional, for users who
  also keep work in Jira; and
- a skill that prints the tracker, which is how a user sees the current work.
